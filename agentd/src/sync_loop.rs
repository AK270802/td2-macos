use anyhow::Result;
use tracing::{info, warn};
use common::{
    api::{self, activity, screenshots},
    db::{self, queries, sync_queue},
    models::ActivityBatch,
};

const AGENT_VERSION: &str = env!("CARGO_PKG_VERSION");

pub async fn run() {
    if let Err(e) = run_inner().await {
        tracing::error!("Sync loop error: {e}");
    }
}

async fn run_inner() -> Result<()> {
    let client = api::build_client()?;
    let conn = db::open()?;

    let batch_interval_secs = queries::get_config(&conn, "batch_sync_interval_min")
        .and_then(|s| s.parse::<u64>().ok())
        .unwrap_or(5) * 60;
    let assignment_interval_secs = queries::get_config(&conn, "assignment_sync_interval_min")
        .and_then(|s| s.parse::<u64>().ok())
        .unwrap_or(20) * 60;

    let mut last_batch = std::time::Instant::now()
        .checked_sub(std::time::Duration::from_secs(batch_interval_secs))
        .unwrap_or(std::time::Instant::now());
    let mut last_assign = std::time::Instant::now()
        .checked_sub(std::time::Duration::from_secs(assignment_interval_secs))
        .unwrap_or(std::time::Instant::now());

    info!("Sync loop running (batch={}s, assign={}s)", batch_interval_secs, assignment_interval_secs);
    loop {
        tokio::time::sleep(std::time::Duration::from_secs(30)).await;

        // 5-min batch sync
        if last_batch.elapsed().as_secs() >= batch_interval_secs {
            last_batch = std::time::Instant::now();
            if let Err(e) = sync_batch(&client, &conn).await {
                warn!("Batch sync error: {e}");
            }
            // Screenshots upload (within batch cycle, max 50)
            if let Err(e) = upload_screenshots(&client, &conn).await {
                warn!("Screenshot upload error: {e}");
            }
        }

        // 20-min assignment sync (decoupled from batch)
        if last_assign.elapsed().as_secs() >= assignment_interval_secs {
            last_assign = std::time::Instant::now();
            if let Err(e) = sync_assignments(&client, &conn).await {
                warn!("Assignment sync error: {e}");
            }
        }

        // Retry pending queue
        if let Err(e) = retry_pending(&client, &conn).await {
            warn!("Retry error: {e}");
        }
    }
}

async fn sync_batch(client: &reqwest::Client, conn: &rusqlite::Connection) -> Result<()> {
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

    match activity::post_batch(client, &batch).await? {
        activity::BatchResult::Accepted => {
            sync_queue::mark_done(conn, &batch_id)?;
            queries::mark_events_synced(conn, &event_uuids)?;
            let log_ids: Vec<_> = logs.iter().map(|l| l.id).collect();
            queries::mark_task_time_logs_synced(conn, &log_ids)?;
            info!("Batch synced: {} events, {} logs", event_uuids.len(), log_ids.len());
        }
        activity::BatchResult::PermanentFailure => {
            sync_queue::mark_done(conn, &batch_id)?;
            warn!("Batch permanently rejected");
        }
        activity::BatchResult::Retryable => {
            sync_queue::schedule_retry(conn, &batch_id, 0)?;
            warn!("Batch queued for retry");
        }
    }
    Ok(())
}

async fn retry_pending(client: &reqwest::Client, conn: &rusqlite::Connection) -> Result<()> {
    let batches = sync_queue::get_due_batches(conn)?;
    for batch in batches {
        let events = queries::get_unsynced_events(conn, 500)?;
        let logs = queries::get_unsynced_task_time_logs(conn)?;
        let tz_offset = chrono::Local::now().offset().local_minus_utc() / 60;
        let payload = ActivityBatch { events, task_time_logs: logs, agent_version: AGENT_VERSION.into(), tz_offset };
        match activity::post_batch(client, &payload).await? {
            activity::BatchResult::Accepted => { sync_queue::mark_done(conn, &batch.batch_id)?; }
            activity::BatchResult::Retryable => { sync_queue::schedule_retry(conn, &batch.batch_id, batch.retry_count)?; }
            activity::BatchResult::PermanentFailure => { sync_queue::mark_done(conn, &batch.batch_id)?; }
        }
    }
    Ok(())
}

async fn upload_screenshots(client: &reqwest::Client, conn: &rusqlite::Connection) -> Result<()> {
    let mut stmt = conn.prepare(
        "SELECT uuid,file_path,task_id,ts FROM screenshots WHERE uploaded=0 LIMIT 50"
    )?;
    let rows: Vec<(String, String, Option<String>, i64)> = stmt.query_map([], |r| {
        Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?))
    })?.filter_map(|r| r.ok()).collect();

    for (uuid, path, task_id, ts) in rows {
        let p = std::path::Path::new(&path);
        if !p.exists() { conn.execute("UPDATE screenshots SET uploaded=1 WHERE uuid=?1", rusqlite::params![uuid])?; continue; }
        match screenshots::upload(client, p, task_id.as_deref(), ts).await {
            Ok(_) => { conn.execute("UPDATE screenshots SET uploaded=1 WHERE uuid=?1", rusqlite::params![uuid])?; }
            Err(e) => warn!("Screenshot upload failed {uuid}: {e}"),
        }
    }
    Ok(())
}

async fn sync_assignments(client: &reqwest::Client, conn: &rusqlite::Connection) -> Result<()> {
    let tenant_id = queries::get_config(conn, "tenant_id").unwrap_or_default();
    match common::api::projects::get_assigned(client, &tenant_id).await {
        Ok(projects) => {
            let all_tasks: Vec<_> = projects.iter().flat_map(|p| p.tasks.iter().cloned()).collect();
            queries::upsert_assigned_tasks(conn, &all_tasks)?;
            info!("Assignments synced: {} tasks", all_tasks.len());
        }
        Err(e) => warn!("Assignment sync failed: {e}"),
    }
    Ok(())
}
