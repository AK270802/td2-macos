//! Batch sync (5 min), assignment/config sync (20 min), screenshot upload,
//! retry queue, and daily pruning.
//!
//! Resilience: each cycle is individually error-guarded — no HTTP status or
//! network failure can terminate the loop. 401s trigger a token refresh and
//! retry inside the API layer; a failed refresh surfaces as a permanent batch
//! failure, never a dead thread.

use anyhow::Result;
use tracing::{info, warn};
use common::{
    api::{self, activity, agent, screenshots},
    db::{self, queries, sync_queue},
    models::ActivityBatch,
};
use std::sync::{Mutex, OnceLock};
use tokio::sync::{mpsc, oneshot};

const AGENT_VERSION: &str = env!("CARGO_PKG_VERSION");

// ── Shared sync status (read by IPC get_sync_status) ─────────────────────────

#[derive(Default, Clone, serde::Serialize)]
pub struct SyncStatus {
    pub connected: bool,
    pub last_sync_ts: Option<i64>,
    pub last_result: String,
    pub pending_events: i64,
    pub next_sync_ts: Option<i64>,
    pub agent_version: String,
}

static STATUS: Mutex<Option<SyncStatus>> = Mutex::new(None);

// ── Manual "sync now" trigger ────────────────────────────────────────────────
//
// The IPC server's connection tasks run on the main multi-threaded runtime,
// where a spawned future must be `Send` — but `rusqlite::Connection` is not,
// so IPC can't open its own connection and await network calls inline. This
// loop already owns a `Connection` on its dedicated single-thread runtime, so
// "sync now" is delivered here as a request and executed on this thread; the
// caller awaits the reply over a oneshot channel instead.
static TRIGGER: OnceLock<mpsc::UnboundedSender<oneshot::Sender<Result<(), String>>>> = OnceLock::new();

/// Called from the IPC handler. Returns `None` if the sync loop hasn't
/// started yet (trigger channel not registered).
pub fn request_sync_now() -> Option<oneshot::Receiver<Result<(), String>>> {
    let (tx, rx) = oneshot::channel();
    TRIGGER.get()?.send(tx).ok()?;
    Some(rx)
}

pub fn status_json() -> serde_json::Value {
    let guard = STATUS.lock().unwrap();
    match &*guard {
        Some(s) => serde_json::to_value(s).unwrap_or_default(),
        None => serde_json::json!({
            "connected": false,
            "last_sync_ts": null,
            "last_result": "starting",
            "pending_events": 0,
            "next_sync_ts": null,
            "agent_version": AGENT_VERSION,
        }),
    }
}

fn update_status(conn: &rusqlite::Connection, connected: bool, result: &str, next_sync_ts: i64) {
    let pending: i64 = conn.query_row(
        "SELECT COUNT(*) FROM events WHERE synced=0", [], |r| r.get(0)).unwrap_or(0);
    let mut guard = STATUS.lock().unwrap();
    *guard = Some(SyncStatus {
        connected,
        last_sync_ts: Some(chrono::Utc::now().timestamp()),
        last_result: result.to_string(),
        pending_events: pending,
        next_sync_ts: Some(next_sync_ts),
        agent_version: AGENT_VERSION.to_string(),
    });
}

// ── Main loop ─────────────────────────────────────────────────────────────────

pub async fn run() {
    let (tx, mut rx) = mpsc::unbounded_channel();
    let _ = TRIGGER.set(tx);
    loop {
        if let Err(e) = run_inner(&mut rx).await {
            tracing::error!("Sync loop error, restarting in 30s: {e}");
        }
        tokio::time::sleep(std::time::Duration::from_secs(30)).await;
    }
}

async fn run_inner(trigger_rx: &mut mpsc::UnboundedReceiver<oneshot::Sender<Result<(), String>>>) -> Result<()> {
    let client = api::build_client()?;
    let conn = db::open()?;

    let mut last_batch: Option<std::time::Instant> = None;
    let mut last_assign: Option<std::time::Instant> = None;
    let mut last_prune: Option<std::time::Instant> = None;

    info!("Sync loop running");
    loop {
        // Intervals are re-read every cycle so server-pushed changes apply live.
        let batch_secs = queries::get_config_u64(&conn, "batch_sync_interval_min", 5).clamp(1, 60) * 60;
        let assign_secs = queries::get_config_u64(&conn, "assignment_sync_interval_min", 20).clamp(1, 240) * 60;

        // Batch sync + screenshots
        if last_batch.map_or(true, |t| t.elapsed().as_secs() >= batch_secs) {
            last_batch = Some(std::time::Instant::now());
            let next = chrono::Utc::now().timestamp() + batch_secs as i64;
            // Provisional flush of the in-progress session (if any) so an
            // active task's time shows on the dashboard without waiting for
            // it to stop — same cadence as the batch upload that follows.
            if let Ok(mut t) = crate::ipc::timer().lock() {
                t.flush_active(&conn);
            }
            match sync_batch(&client, &conn).await {
                Ok(()) => update_status(&conn, true, "ok", next),
                Err(e) => {
                    warn!("Batch sync error: {e}");
                    update_status(&conn, false, "error", next);
                }
            }
            if let Err(e) = upload_screenshots(&client, &conn).await {
                warn!("Screenshot upload error: {e}");
            }
        }

        // Assignment + config sync
        if last_assign.map_or(true, |t| t.elapsed().as_secs() >= assign_secs) {
            last_assign = Some(std::time::Instant::now());
            if let Err(e) = sync_config_and_assignments(&client, &conn).await {
                warn!("Assignment sync error: {e}");
            }
        }

        // Retry queue — every tick
        if let Err(e) = retry_pending(&client, &conn).await {
            warn!("Retry error: {e}");
        }

        // Daily prune of synced local data
        if last_prune.map_or(true, |t| t.elapsed().as_secs() >= 86_400) {
            last_prune = Some(std::time::Instant::now());
            let days = queries::get_config(&conn, "retention_days")
                .and_then(|s| s.parse().ok()).unwrap_or(7i64);
            if let Err(e) = queries::prune_old_data(&conn, days) {
                warn!("Prune error: {e}");
            }
        }

        tokio::select! {
            _ = tokio::time::sleep(std::time::Duration::from_secs(30)) => {}
            Some(reply) = trigger_rx.recv() => {
                let next = chrono::Utc::now().timestamp() + batch_secs as i64;
                if let Ok(mut t) = crate::ipc::timer().lock() {
                    t.flush_active(&conn);
                }
                let batch_result = sync_batch(&client, &conn).await;
                if let Err(e) = &batch_result { warn!("Manual sync batch error: {e}"); }
                if let Err(e) = upload_screenshots(&client, &conn).await { warn!("Screenshot upload error: {e}"); }
                let assign_result = sync_config_and_assignments(&client, &conn).await;
                if let Err(e) = &assign_result { warn!("Manual sync assign error: {e}"); }
                update_status(&conn, batch_result.is_ok(), if batch_result.is_ok() { "ok" } else { "error" }, next);
                last_batch = Some(std::time::Instant::now());
                last_assign = Some(std::time::Instant::now());
                let result = match (batch_result, assign_result) {
                    (Ok(()), Ok(())) => Ok(()),
                    (Err(e), _) | (_, Err(e)) => Err(e.to_string()),
                };
                let _ = reply.send(result);
            }
        }
    }
}

// ── Batch sync ────────────────────────────────────────────────────────────────

pub(crate) async fn sync_batch(client: &reqwest::Client, conn: &rusqlite::Connection) -> Result<()> {
    // In-flight guard: while queued batches await retry, don't create a new
    // overlapping batch over the same unsynced events.
    let queued: i64 = conn.query_row(
        "SELECT COUNT(*) FROM sync_queue WHERE status IN ('pending','retry')", [], |r| r.get(0)).unwrap_or(0);
    if queued > 0 {
        return Ok(());
    }

    let events = queries::get_unsynced_events(conn, 500)?;
    let logs = queries::get_unsynced_task_time_logs(conn)?;
    if events.is_empty() && logs.is_empty() { return Ok(()); }

    let event_uuids: Vec<_> = events.iter().map(|e| e.event_uuid).collect();
    let batch_id = uuid::Uuid::new_v4().to_string();
    sync_queue::enqueue(conn, &batch_id, &event_uuids)?;

    let tz_offset = chrono::Local::now().offset().local_minus_utc() / 60;
    let batch = ActivityBatch {
        events, task_time_logs: logs.clone(), agent_version: AGENT_VERSION.into(), tz_offset,
    };

    match activity::post_batch(client, &batch).await {
        Ok(activity::BatchResult::Accepted) => {
            sync_queue::mark_done(conn, &batch_id)?;
            queries::mark_events_synced(conn, &event_uuids)?;
            let log_ids: Vec<_> = logs.iter().map(|l| l.id).collect();
            queries::mark_task_time_logs_synced(conn, &log_ids)?;
            info!("Batch synced: {} events, {} logs", event_uuids.len(), log_ids.len());
        }
        Ok(activity::BatchResult::PermanentFailure) => {
            sync_queue::mark_done(conn, &batch_id)?;
            // Mark events synced so a poison batch can't wedge the queue; the
            // rejection is already server-logged.
            queries::mark_events_synced(conn, &event_uuids)?;
            warn!("Batch permanently rejected ({} events dropped)", event_uuids.len());
        }
        Ok(activity::BatchResult::Retryable) => {
            sync_queue::schedule_retry(conn, &batch_id, 0)?;
            warn!("Batch queued for retry");
        }
        Err(e) => {
            // Network-level failure — retry with backoff.
            sync_queue::schedule_retry(conn, &batch_id, 0)?;
            warn!("Batch send failed, queued for retry: {e}");
        }
    }
    Ok(())
}

async fn retry_pending(client: &reqwest::Client, conn: &rusqlite::Connection) -> Result<()> {
    for batch in sync_queue::get_due_batches(conn)? {
        // Resend THIS batch's still-unsynced events (not a fresh query).
        let events = queries::get_unsynced_events_by_uuids(conn, &batch.event_uuids)?;
        if events.is_empty() {
            sync_queue::mark_done(conn, &batch.batch_id)?;
            continue;
        }
        let uuids: Vec<_> = events.iter().map(|e| e.event_uuid).collect();
        let logs = queries::get_unsynced_task_time_logs(conn)?;
        let tz_offset = chrono::Local::now().offset().local_minus_utc() / 60;
        let payload = ActivityBatch { events, task_time_logs: logs.clone(), agent_version: AGENT_VERSION.into(), tz_offset };
        match activity::post_batch(client, &payload).await {
            Ok(activity::BatchResult::Accepted) => {
                sync_queue::mark_done(conn, &batch.batch_id)?;
                queries::mark_events_synced(conn, &uuids)?;
                let log_ids: Vec<_> = logs.iter().map(|l| l.id).collect();
                queries::mark_task_time_logs_synced(conn, &log_ids)?;
                info!("Retry batch synced: {} events", uuids.len());
            }
            Ok(activity::BatchResult::PermanentFailure) => {
                sync_queue::mark_done(conn, &batch.batch_id)?;
                queries::mark_events_synced(conn, &uuids)?;
            }
            Ok(activity::BatchResult::Retryable) | Err(_) => {
                sync_queue::schedule_retry(conn, &batch.batch_id, batch.retry_count)?;
            }
        }
    }
    Ok(())
}

// ── Screenshots ───────────────────────────────────────────────────────────────

async fn upload_screenshots(client: &reqwest::Client, conn: &rusqlite::Connection) -> Result<()> {
    let mut stmt = conn.prepare(
        "SELECT uuid,file_path,task_id,ts,app_name,window_title FROM screenshots WHERE uploaded=0 LIMIT 50"
    )?;
    let rows: Vec<(String, String, Option<String>, i64, Option<String>, Option<String>)> =
        stmt.query_map([], |r| {
            Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?))
        })?.filter_map(|r| r.ok()).collect();

    for (uuid, path, task_id, ts, app_name, window_title) in rows {
        let p = std::path::Path::new(&path);
        if !p.exists() {
            conn.execute("UPDATE screenshots SET uploaded=1 WHERE uuid=?1", rusqlite::params![uuid])?;
            continue;
        }
        let meta = screenshots::ScreenshotMeta {
            task_id: task_id.as_deref(),
            app_name: app_name.as_deref(),
            window_title: window_title.as_deref(),
            captured_at: ts,
        };
        match screenshots::upload(client, p, &meta).await {
            Ok(_) => { conn.execute("UPDATE screenshots SET uploaded=1 WHERE uuid=?1", rusqlite::params![uuid])?; }
            Err(e) => warn!("Screenshot upload failed {uuid}: {e}"),
        }
    }
    Ok(())
}

// ── Config + assignments ──────────────────────────────────────────────────────

pub(crate) async fn sync_config_and_assignments(client: &reqwest::Client, conn: &rusqlite::Connection) -> Result<()> {
    let (config, tasks, identity) = agent::get_config(client).await?;

    // Server-pushed operational config → agent_config (capture loop reloads
    // these every 30s).
    let _ = queries::set_config(conn, "idle_threshold_sec", &config.idle_threshold_sec.to_string());
    let _ = queries::set_config(conn, "screenshot_interval_sec", &config.screenshot_interval_sec.to_string());
    let _ = queries::set_config(conn, "screenshots_enabled", if config.screenshots_enabled { "true" } else { "false" });
    let _ = queries::set_config(conn, "blur_radius", &config.blur_radius.to_string());
    let _ = queries::set_config(conn, "capture_interval_sec", &config.capture_interval_sec.to_string());
    let _ = queries::set_config(conn, "batch_sync_interval_min", &config.batch_sync_interval_min.to_string());
    let _ = queries::set_config(conn, "assignment_sync_interval_min", &config.assignment_sync_interval_min.to_string());
    if let Some(uid) = &identity.user_id {
        let _ = queries::set_config(conn, "user_id", uid);
    }
    if let Some(tid) = &identity.tenant_id {
        let _ = queries::set_config(conn, "tenant_id", tid);
    }
    if let Some(days) = identity.retention_days {
        let _ = queries::set_config(conn, "retention_days", &days.to_string());
    }
    if let Some(gat) = &identity.general_activity_task_id {
        let _ = queries::set_config(conn, "general_activity_task_id", gat);
    }

    queries::upsert_assigned_tasks(conn, &tasks)?;
    let keep: Vec<_> = tasks.iter().map(|t| t.task_id).collect();
    let active = crate::ipc::active_task_id();
    queries::prune_stale_assignments(conn, &keep, active.as_ref())?;
    info!("Config + assignments synced: {} tasks", tasks.len());
    Ok(())
}
