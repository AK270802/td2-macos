//! IPC server — cross-platform local socket (named pipe on Windows, Unix
//! socket elsewhere) via common::ipc_transport. One spawn per connection.
//!
//! The timer is a `common::timer_service::TimerService` wrapping the tested
//! `TimerState` machine — the exact logic covered by timer_state_tests.rs is
//! what runs in production.

use common::db::{self, queries};
use common::ipc_transport::{self, IpcRequest, IpcResponse};
use interprocess::local_socket::traits::tokio::{Listener as _, Stream as _};
use common::models::{ActivityEvent, Task};
use common::timer_service::TimerService;
use common::timer_state::{BreakKind, TimerState};
use std::sync::{Mutex, OnceLock};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tracing::{error, info};
use uuid::Uuid;

static TIMER: OnceLock<Mutex<TimerService>> = OnceLock::new();

pub fn timer() -> &'static Mutex<TimerService> {
    TIMER.get_or_init(|| Mutex::new(TimerService::new()))
}

/// Task id currently being tracked (used by sync_loop's prune guard).
pub fn active_task_id() -> Option<Uuid> {
    timer().lock().ok()?.state().active_task().map(|t| t.task_id)
}

/// Called by capture_loop when a sleep gap is detected.
pub fn pause_for_sleep() {
    if let Ok(conn) = db::open() {
        if let Ok(mut t) = timer().lock() {
            t.pause_for_sleep(&conn);
        }
    }
}

// ── Server ────────────────────────────────────────────────────────────────────

pub async fn run_ipc_server() {
    info!("IPC server starting");
    let listener = match ipc_transport::bind_listener() {
        Ok(l) => l,
        Err(e) => {
            error!("IPC bind failed (is another agentd running?): {e}");
            return;
        }
    };
    loop {
        match listener.accept().await {
            Ok(conn) => { tokio::spawn(serve_conn(conn)); }
            Err(e) => {
                error!("IPC accept: {e}");
                tokio::time::sleep(std::time::Duration::from_millis(200)).await;
            }
        }
    }
}

async fn serve_conn(conn: interprocess::local_socket::tokio::Stream) {
    let (reader, mut writer) = conn.split();
    let mut lines = BufReader::new(reader).lines();
    while let Ok(Some(line)) = lines.next_line().await {
        let resp = handle_request(&line).await;
        let out = serde_json::to_string(&resp).unwrap_or_default();
        if writer.write_all(format!("{out}\n").as_bytes()).await.is_err() {
            break;
        }
    }
}

// ── Command handlers ──────────────────────────────────────────────────────────

async fn handle_request(line: &str) -> IpcResponse {
    let req: IpcRequest = match serde_json::from_str(line) {
        Ok(r) => r,
        Err(e) => return IpcResponse::err(e.to_string()),
    };
    match req.cmd.as_str() {
        "ping" => IpcResponse::ok(serde_json::json!("pong")),
        "get_state" => get_state(),
        "toggle_play_pause" => with_conn(|conn| {
            timer().lock().unwrap().resume_last_task(conn);
            Ok(serde_json::json!({"ok": true}))
        }),
        "select_task" => select_task(req.payload),
        "start_break" => start_break(req.payload),
        "stop_tracking" => with_conn(|conn| {
            timer().lock().unwrap().stop(conn);
            Ok(serde_json::json!({"ok": true}))
        }),
        // Called on logout, after stop_tracking: the local DB is a single
        // file per OS-user profile shared by whichever WorkPulse account is
        // currently logged in, so leftover rows here would otherwise leak
        // into (and get synced under) the next account that logs in.
        "clear_local_data" => with_conn(|conn| {
            queries::clear_local_activity_data(conn)?;
            *timer().lock().unwrap() = TimerService::new();
            Ok(serde_json::json!({"ok": true}))
        }),
        "idle_keep_working" => idle_response(false),
        "idle_auto_stop" => idle_response(true),
        "get_assigned_tasks" => with_conn(|conn| {
            let tasks = queries::get_assigned_tasks(conn)?;
            Ok(serde_json::to_value(&tasks)?)
        }),
        "get_time_stats" => with_conn(|conn| {
            let (today, week, month, sessions, meeting_today) = queries::get_time_stats_local(conn)?;
            // Add the current in-progress session's not-yet-flushed meeting
            // seconds so the KPI updates live rather than waiting for the
            // next ~5-minute flush_active() cycle to persist it.
            let live_meeting = timer().lock().map(|t| t.meeting_secs() as i64).unwrap_or(0);
            Ok(serde_json::json!({
                "worked_today_sec": today,
                "worked_week_sec": week,
                "worked_month_sec": month,
                "sessions_today": sessions,
                "meeting_today_sec": meeting_today + live_meeting,
            }))
        }),
        "get_task_times_today" => with_conn(|conn| {
            let rows = queries::get_task_times_today(conn)?;
            Ok(serde_json::to_value(rows.into_iter().collect::<std::collections::HashMap<_,_>>())?)
        }),
        "get_recent_events" => {
            let limit = req.payload.as_ref()
                .and_then(|p| p["limit"].as_u64()).unwrap_or(12) as usize;
            with_conn(move |conn| {
                let events = queries::get_recent_events(conn, limit)?;
                Ok(serde_json::to_value(&events)?)
            })
        }
        "get_sync_status" => IpcResponse::ok(crate::sync_loop::status_json()),
        "sync_now" => sync_now().await,
        "get_consent_status" => get_consent_status().await,
        "accept_consent" => accept_consent(req.payload).await,
        _ => IpcResponse::err(format!("unknown command: {}", req.cmd)),
    }
}

fn with_conn<F>(f: F) -> IpcResponse
where F: FnOnce(&rusqlite::Connection) -> anyhow::Result<serde_json::Value> {
    match db::open() {
        Ok(conn) => match f(&conn) {
            Ok(v) => IpcResponse::ok(v),
            Err(e) => IpcResponse::err(e.to_string()),
        },
        Err(e) => IpcResponse::err(e.to_string()),
    }
}

fn get_state() -> IpcResponse {
    let t = timer().lock().unwrap();
    let state = t.state();
    let task = state.active_task().map(|task| serde_json::json!({
        "task_id": task.task_id,
        "project_id": task.project_id,
        "task_name": task.task_name,
        "project_name": task.project_name,
    }));
    let (break_type, break_remaining) = match state {
        TimerState::OnBreak { kind, break_started, .. } => {
            let used = break_started.elapsed().as_secs();
            (Some(kind.display().to_string()),
             Some(kind.duration_secs().saturating_sub(used)))
        }
        _ => (None, None),
    };
    IpcResponse::ok(serde_json::json!({
        "state": state.state_name(),
        "task": task,
        "elapsed_secs": t.display_elapsed(),
        "break_type": break_type,
        "break_remaining_secs": break_remaining,
        "idle_warning": t.idle_warning(),
        "idle_since_secs": t.idle_since_secs(),
        "in_meeting": crate::capture_loop::is_in_meeting(),
    }))
}

fn select_task(payload: Option<serde_json::Value>) -> IpcResponse {
    let p = payload.unwrap_or_default();
    let task = (|| {
        Some(Task {
            task_id: p["task_id"].as_str()?.parse().ok()?,
            project_id: p["project_id"].as_str()?.parse().ok()?,
            task_name: p["task_name"].as_str()?.to_string(),
            project_name: p["project_name"].as_str()?.to_string(),
        })
    })();
    let Some(task) = task else {
        return IpcResponse::err("select_task requires task_id, project_id, task_name, project_name");
    };
    with_conn(|conn| {
        timer().lock().unwrap().select_task(conn, task);
        Ok(serde_json::json!({"ok": true}))
    })
}

fn start_break(payload: Option<serde_json::Value>) -> IpcResponse {
    let p = payload.unwrap_or_default();
    let kind = match p["break_type"].as_str().unwrap_or("coffee") {
        "coffee" => BreakKind::Coffee,
        "lunch" => BreakKind::Lunch,
        other => BreakKind::Custom(
            other.to_string(),
            p["duration_secs"].as_u64().unwrap_or(600),
        ),
    };
    with_conn(|conn| {
        timer().lock().unwrap().start_break(conn, kind);
        Ok(serde_json::json!({"ok": true}))
    })
}

/// Shared idle-warning resolution. Records an `idle` activity event covering
/// the span, then either keeps working (idle deducted) or stops back-dated.
fn idle_response(auto_stop: bool) -> IpcResponse {
    with_conn(|conn| {
        let mut t = timer().lock().unwrap();
        if let Some(w) = t.idle_warning() {
            record_idle_event(conn, w.started_ts);
        }
        if auto_stop {
            t.idle_auto_stop(conn);
        } else {
            t.idle_keep_working(conn);
        }
        Ok(serde_json::json!({"ok": true}))
    })
}

fn record_idle_event(conn: &rusqlite::Connection, idle_start: i64) {
    let (Some(user_id), Some(tenant_id)) = (
        queries::get_config(conn, "user_id").and_then(|s| s.parse::<Uuid>().ok()),
        queries::get_config(conn, "tenant_id").and_then(|s| s.parse::<Uuid>().ok()),
    ) else { return };
    let now = chrono::Utc::now().timestamp();
    let ev = ActivityEvent {
        event_uuid: Uuid::new_v4(),
        user_id,
        tenant_id,
        event_type: "idle".into(),
        ts: idle_start,
        duration_sec: (now - idle_start).max(0),
        payload: serde_json::json!({ "idle_start": idle_start, "idle_end": now }),
    };
    let _ = queries::insert_event(conn, &ev);
}

async fn sync_now() -> IpcResponse {
    // Delegate to the sync loop's own thread — it already owns a `Connection`
    // (which is `!Send` and can't be opened/awaited-across here, since this
    // handler runs on the IPC server's multi-threaded runtime).
    match crate::sync_loop::request_sync_now() {
        Some(rx) => match rx.await {
            Ok(Ok(())) => IpcResponse::ok(serde_json::json!({"ok": true})),
            Ok(Err(e)) => IpcResponse::err(e),
            Err(_) => IpcResponse::err("sync loop did not respond"),
        },
        None => IpcResponse::err("sync loop not ready yet"),
    }
}

async fn get_consent_status() -> IpcResponse {
    let client = match common::api::build_client() {
        Ok(c) => c,
        Err(e) => return IpcResponse::err(e.to_string()),
    };
    match common::api::consent::get_status(&client).await {
        Ok(status) => IpcResponse::ok(serde_json::to_value(&status).unwrap_or_default()),
        Err(e) => IpcResponse::err(e.to_string()),
    }
}

async fn accept_consent(payload: Option<serde_json::Value>) -> IpcResponse {
    let version = payload.as_ref()
        .and_then(|p| p["policy_version"].as_i64())
        .unwrap_or(1);
    let client = match common::api::build_client() {
        Ok(c) => c,
        Err(e) => return IpcResponse::err(e.to_string()),
    };
    match common::api::consent::accept(&client, version).await {
        Ok(()) => {
            if let Ok(conn) = db::open() {
                let _ = queries::set_config(&conn, "consent_accepted_version", &version.to_string());
            }
            IpcResponse::ok(serde_json::json!({"ok": true}))
        }
        Err(e) => IpcResponse::err(e.to_string()),
    }
}
