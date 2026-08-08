use anyhow::Result;
use rusqlite::{Connection, params};
use crate::models::{ActivityEvent, Task, TaskTimeLog};
use uuid::Uuid;

pub fn insert_event(conn: &Connection, ev: &ActivityEvent) -> Result<()> {
    conn.execute(
        "INSERT OR IGNORE INTO events (event_uuid, user_id, tenant_id, event_type, ts, duration_sec, payload)
         VALUES (?1,?2,?3,?4,?5,?6,?7)",
        params![
            ev.event_uuid.to_string(), ev.user_id.to_string(), ev.tenant_id.to_string(),
            ev.event_type, ev.ts, ev.duration_sec,
            serde_json::to_string(&ev.payload)?
        ],
    )?;
    Ok(())
}

fn row_to_event(row: &rusqlite::Row) -> rusqlite::Result<ActivityEvent> {
    Ok(ActivityEvent {
        event_uuid: row.get::<_,String>(0)?.parse().unwrap_or_default(),
        user_id: row.get::<_,String>(1)?.parse().unwrap_or_default(),
        tenant_id: row.get::<_,String>(2)?.parse().unwrap_or_default(),
        event_type: row.get(3)?,
        ts: row.get(4)?,
        duration_sec: row.get(5)?,
        payload: serde_json::from_str(&row.get::<_,String>(6)?).unwrap_or_default(),
    })
}

pub fn get_unsynced_events(conn: &Connection, limit: usize) -> Result<Vec<ActivityEvent>> {
    let mut stmt = conn.prepare(
        "SELECT event_uuid,user_id,tenant_id,event_type,ts,duration_sec,payload FROM events WHERE synced=0 ORDER BY ts LIMIT ?1"
    )?;
    let rows = stmt.query_map(params![limit as i64], row_to_event)?;
    Ok(rows.filter_map(|r| r.ok()).collect())
}

/// Fetch the still-unsynced subset of a specific batch's events — used by the
/// retry path so a retry resends *that batch*, not whatever happens to be
/// unsynced at the moment.
pub fn get_unsynced_events_by_uuids(conn: &Connection, uuids: &[Uuid]) -> Result<Vec<ActivityEvent>> {
    let mut out = Vec::with_capacity(uuids.len());
    let mut stmt = conn.prepare(
        "SELECT event_uuid,user_id,tenant_id,event_type,ts,duration_sec,payload FROM events WHERE event_uuid=?1 AND synced=0"
    )?;
    for id in uuids {
        if let Ok(ev) = stmt.query_row(params![id.to_string()], row_to_event) {
            out.push(ev);
        }
    }
    Ok(out)
}

/// Most recent events for the activity feed (any type), newest first.
pub fn get_recent_events(conn: &Connection, limit: usize) -> Result<Vec<ActivityEvent>> {
    let mut stmt = conn.prepare(
        "SELECT event_uuid,user_id,tenant_id,event_type,ts,duration_sec,payload FROM events ORDER BY ts DESC LIMIT ?1"
    )?;
    let rows = stmt.query_map(params![limit as i64], row_to_event)?;
    Ok(rows.filter_map(|r| r.ok()).collect())
}

pub fn mark_events_synced(conn: &Connection, uuids: &[Uuid]) -> Result<()> {
    for id in uuids {
        conn.execute("UPDATE events SET synced=1 WHERE event_uuid=?1", params![id.to_string()])?;
    }
    Ok(())
}

/// Upserts by id — a provisional flush of an in-progress session and its
/// eventual finalized write (same `id`, reused across the session) both go
/// through here, so later writes overwrite rather than get ignored.
pub fn insert_task_time_log(conn: &Connection, log: &TaskTimeLog) -> Result<()> {
    conn.execute(
        "INSERT OR REPLACE INTO task_time_logs (id,task_id,project_id,task_name,project_name,started_at,ended_at,duration_sec,idle_sec,break_sec,synced)
         VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,0)",
        params![
            log.id.to_string(), log.task_id.to_string(), log.project_id.to_string(),
            log.task_name, log.project_name, log.started_at, log.ended_at,
            log.duration_sec, log.idle_sec, log.break_sec
        ],
    )?;
    Ok(())
}

fn row_to_log(row: &rusqlite::Row) -> rusqlite::Result<TaskTimeLog> {
    Ok(TaskTimeLog {
        id: row.get::<_,String>(0)?.parse().unwrap_or_default(),
        task_id: row.get::<_,String>(1)?.parse().unwrap_or_default(),
        project_id: row.get::<_,String>(2)?.parse().unwrap_or_default(),
        task_name: row.get(3)?,
        project_name: row.get(4)?,
        started_at: row.get(5)?,
        ended_at: row.get(6)?,
        duration_sec: row.get(7)?,
        idle_sec: row.get(8)?,
        break_sec: row.get(9)?,
        meeting_sec: row.get(10).unwrap_or(0),
        synced: false,
    })
}

pub fn get_unsynced_task_time_logs(conn: &Connection) -> Result<Vec<TaskTimeLog>> {
    let mut stmt = conn.prepare(
        "SELECT id,task_id,project_id,task_name,project_name,started_at,ended_at,duration_sec,idle_sec,break_sec,meeting_sec FROM task_time_logs WHERE synced=0"
    )?;
    let rows = stmt.query_map([], row_to_log)?;
    Ok(rows.filter_map(|r| r.ok()).collect())
}

pub fn mark_task_time_logs_synced(conn: &Connection, ids: &[Uuid]) -> Result<()> {
    for id in ids {
        conn.execute("UPDATE task_time_logs SET synced=1 WHERE id=?1", params![id.to_string()])?;
    }
    Ok(())
}

/// Seconds already logged against a task today — lets a re-selected task
/// continue its daily total instead of restarting at zero.
pub fn get_today_accumulated_secs(conn: &Connection, task_id: &Uuid) -> i64 {
    use chrono::{Local, Datelike, TimeZone};
    let now = Local::now();
    let today_start = Local.with_ymd_and_hms(now.year(), now.month(), now.day(), 0, 0, 0)
        .unwrap().timestamp();
    conn.query_row(
        "SELECT COALESCE(SUM(duration_sec),0) FROM task_time_logs WHERE task_id=?1 AND started_at >= ?2",
        params![task_id.to_string(), today_start], |r| r.get(0)).unwrap_or(0)
}

pub fn get_assigned_tasks(conn: &Connection) -> Result<Vec<Task>> {
    let mut stmt = conn.prepare("SELECT task_id,project_id,task_name,project_name FROM assigned_tasks ORDER BY project_name, task_name")?;
    let rows = stmt.query_map([], |row| {
        Ok(Task {
            task_id: row.get::<_,String>(0)?.parse().unwrap_or_default(),
            project_id: row.get::<_,String>(1)?.parse().unwrap_or_default(),
            task_name: row.get(2)?,
            project_name: row.get(3)?,
        })
    })?;
    Ok(rows.filter_map(|r| r.ok()).collect())
}

pub fn upsert_assigned_tasks(conn: &Connection, tasks: &[Task]) -> Result<()> {
    let now = chrono::Utc::now().timestamp();
    for t in tasks {
        conn.execute(
            "INSERT OR REPLACE INTO assigned_tasks (task_id,project_id,task_name,project_name,last_synced)
             VALUES (?1,?2,?3,?4,?5)",
            params![t.task_id.to_string(), t.project_id.to_string(), t.task_name, t.project_name, now],
        )?;
    }
    Ok(())
}

/// Remove assignments not present in the latest sync — except the task that is
/// actively being tracked (guards against an empty/flaky API response wiping
/// the running session's task).
pub fn prune_stale_assignments(conn: &Connection, keep_ids: &[Uuid], active_task_id: Option<&Uuid>) -> Result<()> {
    let keep: std::collections::HashSet<String> = keep_ids.iter().map(|u| u.to_string()).collect();
    let mut stmt = conn.prepare("SELECT task_id FROM assigned_tasks")?;
    let existing: Vec<String> = stmt.query_map([], |r| r.get::<_,String>(0))?
        .filter_map(|r| r.ok()).collect();
    for id in existing {
        if keep.contains(&id) { continue; }
        if let Some(active) = active_task_id {
            if active.to_string() == id { continue; }
        }
        conn.execute("DELETE FROM assigned_tasks WHERE task_id=?1", params![id])?;
    }
    Ok(())
}

pub fn save_active_session(conn: &Connection, task: Option<&Task>, accumulated: u64) -> Result<()> {
    let now = chrono::Utc::now().timestamp();
    match task {
        Some(t) => {
            conn.execute(
                "INSERT OR REPLACE INTO active_tracking_session (id,task_id,project_id,task_name,project_name,session_start_ts,accumulated_seconds,saved_at)
                 VALUES (1,?1,?2,?3,?4,?5,?6,?7)",
                params![t.task_id.to_string(), t.project_id.to_string(), t.task_name, t.project_name, now, accumulated as i64, now],
            )?;
        }
        None => {
            conn.execute(
                "INSERT OR REPLACE INTO active_tracking_session (id,accumulated_seconds,saved_at) VALUES (1,0,?1)",
                params![now],
            )?;
        }
    }
    Ok(())
}

pub struct RecoveredSession {
    pub task: Task,
    pub session_start_ts: i64,
    pub accumulated_seconds: i64,
    pub saved_at: i64,
}

/// Read a checkpointed session left behind by a crash. Returns None when the
/// last shutdown was clean (task fields nulled out).
pub fn get_active_session(conn: &Connection) -> Option<RecoveredSession> {
    conn.query_row(
        "SELECT task_id,project_id,task_name,project_name,session_start_ts,accumulated_seconds,saved_at
         FROM active_tracking_session WHERE id=1 AND task_id IS NOT NULL AND task_id != ''",
        [],
        |row| {
            Ok(RecoveredSession {
                task: Task {
                    task_id: row.get::<_,String>(0)?.parse().unwrap_or_default(),
                    project_id: row.get::<_,String>(1)?.parse().unwrap_or_default(),
                    task_name: row.get(2)?,
                    project_name: row.get(3)?,
                },
                session_start_ts: row.get(4)?,
                accumulated_seconds: row.get(5)?,
                saved_at: row.get(6)?,
            })
        },
    ).ok()
}

pub fn insert_screenshot(conn: &Connection, uuid: &Uuid, ts: i64, file_path: &str,
                         app_name: Option<&str>, window_title: Option<&str>, task_id: Option<&str>) -> Result<()> {
    conn.execute(
        "INSERT OR IGNORE INTO screenshots (uuid,ts,file_path,app_name,window_title,uploaded,task_id) VALUES (?1,?2,?3,?4,?5,0,?6)",
        params![uuid.to_string(), ts, file_path, app_name, window_title, task_id],
    )?;
    Ok(())
}

pub fn touch_domain(conn: &Connection, domain: &str) -> Result<()> {
    let now = chrono::Utc::now().timestamp();
    conn.execute(
        "INSERT INTO domain_cache (domain, first_seen, last_seen) VALUES (?1,?2,?2)
         ON CONFLICT(domain) DO UPDATE SET last_seen=?2",
        params![domain, now],
    )?;
    Ok(())
}

/// Delete synced events, uploaded screenshot rows (and their files), and
/// synced logs older than `days`.
pub fn prune_old_data(conn: &Connection, days: i64) -> Result<()> {
    let cutoff = chrono::Utc::now().timestamp() - days * 86400;
    let mut stmt = conn.prepare("SELECT file_path FROM screenshots WHERE uploaded=1 AND ts < ?1")?;
    let paths: Vec<String> = stmt.query_map(params![cutoff], |r| r.get(0))?.filter_map(|r| r.ok()).collect();
    for p in paths {
        let _ = std::fs::remove_file(&p);
    }
    conn.execute("DELETE FROM screenshots WHERE uploaded=1 AND ts < ?1", params![cutoff])?;
    conn.execute("DELETE FROM events WHERE synced=1 AND ts < ?1", params![cutoff])?;
    conn.execute("DELETE FROM task_time_logs WHERE synced=1 AND ended_at < ?1", params![cutoff])?;
    conn.execute("DELETE FROM sync_queue WHERE status IN ('done','failed')", params![])?;
    Ok(())
}

pub fn get_config(conn: &Connection, key: &str) -> Option<String> {
    conn.query_row("SELECT value FROM agent_config WHERE key=?1", params![key], |r| r.get(0)).ok()
}

pub fn set_config(conn: &Connection, key: &str, value: &str) -> Result<()> {
    let now = chrono::Utc::now().timestamp();
    conn.execute("INSERT OR REPLACE INTO agent_config (key,value,last_synced) VALUES (?1,?2,?3)", params![key,value,now])?;
    Ok(())
}

pub fn get_config_bool(conn: &Connection, key: &str, default: bool) -> bool {
    get_config(conn, key).map(|v| v == "true" || v == "1").unwrap_or(default)
}

pub fn get_config_u64(conn: &Connection, key: &str, default: u64) -> u64 {
    get_config(conn, key).and_then(|s| s.parse().ok()).unwrap_or(default)
}

pub fn get_time_stats_local(conn: &Connection) -> Result<(i64, i64, i64, i32, i64)> {
    use chrono::{Local, Datelike, TimeZone};
    let now = Local::now();
    let today_start = Local.with_ymd_and_hms(now.year(), now.month(), now.day(), 0, 0, 0)
        .unwrap().timestamp();
    let week_start = today_start - (now.weekday().num_days_from_monday() as i64) * 86400;
    let month_start = Local.with_ymd_and_hms(now.year(), now.month(), 1, 0, 0, 0)
        .unwrap().timestamp();

    let worked_today: i64 = conn.query_row(
        "SELECT COALESCE(SUM(duration_sec),0) FROM task_time_logs WHERE started_at >= ?1",
        params![today_start], |r| r.get(0)).unwrap_or(0);
    let worked_week: i64 = conn.query_row(
        "SELECT COALESCE(SUM(duration_sec),0) FROM task_time_logs WHERE started_at >= ?1",
        params![week_start], |r| r.get(0)).unwrap_or(0);
    let worked_month: i64 = conn.query_row(
        "SELECT COALESCE(SUM(duration_sec),0) FROM task_time_logs WHERE started_at >= ?1",
        params![month_start], |r| r.get(0)).unwrap_or(0);
    let sessions_today: i32 = conn.query_row(
        "SELECT COUNT(*) FROM task_time_logs WHERE started_at >= ?1",
        params![today_start], |r| r.get(0)).unwrap_or(0);
    let meeting_today: i64 = conn.query_row(
        "SELECT COALESCE(SUM(meeting_sec),0) FROM task_time_logs WHERE started_at >= ?1",
        params![today_start], |r| r.get(0)).unwrap_or(0);

    Ok((worked_today, worked_week, worked_month, sessions_today, meeting_today))
}

/// Per-task seconds logged today — drives the per-row time column in the UI.
pub fn get_task_times_today(conn: &Connection) -> Result<Vec<(String, i64)>> {
    use chrono::{Local, Datelike, TimeZone};
    let now = Local::now();
    let today_start = Local.with_ymd_and_hms(now.year(), now.month(), now.day(), 0, 0, 0)
        .unwrap().timestamp();
    let mut stmt = conn.prepare(
        "SELECT task_id, COALESCE(SUM(duration_sec),0) FROM task_time_logs WHERE started_at >= ?1 GROUP BY task_id"
    )?;
    let rows = stmt.query_map(params![today_start], |r| Ok((r.get::<_,String>(0)?, r.get::<_,i64>(1)?)))?;
    Ok(rows.filter_map(|r| r.ok()).collect())
}
