use anyhow::Result;
use rusqlite::{Connection, params};
use uuid::Uuid;

const MAX_RETRIES: u32 = 10;

pub struct QueuedBatch {
    pub batch_id: String,
    pub event_uuids: Vec<Uuid>,
    pub retry_count: u32,
}

pub fn enqueue(conn: &Connection, batch_id: &str, event_uuids: &[Uuid]) -> Result<()> {
    let uuids_json = serde_json::to_string(&event_uuids.iter().map(|u| u.to_string()).collect::<Vec<_>>())?;
    conn.execute(
        "INSERT OR IGNORE INTO sync_queue (batch_id,event_uuids,status,retry_count,next_retry_at) VALUES (?1,?2,'pending',0,0)",
        params![batch_id, uuids_json],
    )?;
    Ok(())
}

pub fn mark_done(conn: &Connection, batch_id: &str) -> Result<()> {
    conn.execute("UPDATE sync_queue SET status='done' WHERE batch_id=?1", params![batch_id])?;
    Ok(())
}

pub fn schedule_retry(conn: &Connection, batch_id: &str, retry_count: u32) -> Result<()> {
    let delay = backoff_secs(retry_count);
    let next_retry = chrono::Utc::now().timestamp() + delay as i64;
    if retry_count >= MAX_RETRIES {
        conn.execute("UPDATE sync_queue SET status='failed' WHERE batch_id=?1", params![batch_id])?;
    } else {
        conn.execute(
            "UPDATE sync_queue SET status='retry', retry_count=?2, next_retry_at=?3 WHERE batch_id=?1",
            params![batch_id, retry_count + 1, next_retry],
        )?;
    }
    Ok(())
}

pub fn get_due_batches(conn: &Connection) -> Result<Vec<QueuedBatch>> {
    let now = chrono::Utc::now().timestamp();
    let mut stmt = conn.prepare(
        "SELECT batch_id,event_uuids,retry_count FROM sync_queue WHERE status IN ('pending','retry') AND next_retry_at <= ?1 LIMIT 10"
    )?;
    let rows = stmt.query_map(params![now], |row| {
        let uuids_json: String = row.get(1)?;
        Ok((row.get::<_,String>(0)?, uuids_json, row.get::<_,u32>(2)?))
    })?;
    let mut out = vec![];
    for r in rows {
        let (batch_id, uuids_json, retry_count) = r?;
        let uuids: Vec<String> = serde_json::from_str(&uuids_json).unwrap_or_default();
        out.push(QueuedBatch {
            batch_id,
            event_uuids: uuids.iter().filter_map(|s| s.parse().ok()).collect(),
            retry_count,
        });
    }
    Ok(out)
}

/// Exponential backoff: min(2^n * 60, 1800) seconds — matches Python agent exactly.
pub fn backoff_secs(retry_count: u32) -> u64 {
    let base = (2u64.pow(retry_count)).saturating_mul(60);
    base.min(1800)
}

