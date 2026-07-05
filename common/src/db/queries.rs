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

pub fn get_unsynced_events(conn: &Connection, limit: usize) -> Result<Vec<ActivityEvent>> {
    let mut stmt = conn.prepare(
        "SELECT event_uuid,user_id,tenant_id,event_type,ts,duration_sec,payload FROM events WHERE synced=0 LIMIT ?1"
    )?;
    let rows = stmt.query_map(params![limit as i64], |row| {
        Ok(ActivityEvent {
            event_uuid: row.get::<_,String>(0)?.parse().unwrap_or_default(),
            user_id: row.get::<_,String>(1)?.parse().unwrap_or_default(),
            tenant_id: row.get::<_,String>(2)?.parse().unwrap_or_default(),
            event_type: row.get(3)?,
            ts: row.get(4)?,
            duration_sec: row.get(5)?,
            payload: serde_json::from_str(&row.get::<_,String>(6)?).unwrap_or_default(),
        })
    })?;
    Ok(rows.filter_map(|r| r.ok()).collect())
}

pub fn mark_events_synced(conn: &Connection, uuids: &[Uuid]) -> Result<()> {
    for id in uuids {
        conn.execute("UPDATE events SET synced=1 WHERE event_uuid=?1", params![id.to_string()])?;
    }
    Ok(())
}

pub fn insert_task_time_log(conn: &Connection, log: &TaskTimeLog) -> Result<()> {
    conn.execute(
        "INSERT OR IGNORE INTO task_time_logs (id,task_id,project_id,task_name,project_name,started_at,ended_at,duration_sec,synced)
         VALUES (?1,?2,?3,?4,?5,?6,?7,?8,0)",
        params![
            log.id.to_string(), log.task_id.to_string(), log.project_id.to_string(),
            log.task_name, log.project_name, log.started_at, log.ended_at, log.duration_sec
        ],
    )?;
    Ok(())
}

pub fn get_unsynced_task_time_logs(conn: &Connection) -> Result<Vec<TaskTimeLog>> {
    let mut stmt = conn.prepare(
        "SELECT id,task_id,project_id,task_name,project_name,started_at,ended_at,duration_sec FROM task_time_logs WHERE synced=0"
    )?;
    let rows = stmt.query_map([], |row| {
        Ok(TaskTimeLog {
            id: row.get::<_,String>(0)?.parse().unwrap_or_default(),
            task_id: row.get::<_,String>(1)?.parse().unwrap_or_default(),
            project_id: row.get::<_,String>(2)?.parse().unwrap_or_default(),
            task_name: row.get(3)?,
            project_name: row.get(4)?,
            started_at: row.get(5)?,
            ended_at: row.get(6)?,
            duration_sec: row.get(7)?,
            synced: false,
        })
    })?;
    Ok(rows.filter_map(|r| r.ok()).collect())
}

pub fn mark_task_time_logs_synced(conn: &Connection, ids: &[Uuid]) -> Result<()> {
    for id in ids {
        conn.execute("UPDATE task_time_logs SET synced=1 WHERE id=?1", params![id.to_string()])?;
    }
    Ok(())
}

pub fn get_assigned_tasks(conn: &Connection) -> Result<Vec<Task>> {
    let mut stmt = conn.prepare("SELECT task_id,project_id,task_name,project_name FROM assigned_tasks")?;
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

pub fn get_config(conn: &Connection, key: &str) -> Option<String> {
    conn.query_row("SELECT value FROM agent_config WHERE key=?1", params![key], |r| r.get(0)).ok()
}

pub fn set_config(conn: &Connection, key: &str, value: &str) -> Result<()> {
    let now = chrono::Utc::now().timestamp();
    conn.execute("INSERT OR REPLACE INTO agent_config (key,value,last_synced) VALUES (?1,?2,?3)", params![key,value,now])?;
    Ok(())
}

pub fn get_time_stats_local(conn: &Connection) -> Result<(i64, i64, i32)> {
    use chrono::{Local, Datelike, TimeZone};
    let now = Local::now();
    let today_start = Local.with_ymd_and_hms(now.year(), now.month(), now.day(), 0, 0, 0)
        .unwrap().timestamp();
    let week_start = today_start - (now.weekday().num_days_from_monday() as i64) * 86400;

    let worked_today: i64 = conn.query_row(
        "SELECT COALESCE(SUM(duration_sec),0) FROM task_time_logs WHERE started_at >= ?1",
        params![today_start], |r| r.get(0)).unwrap_or(0);
    let worked_week: i64 = conn.query_row(
        "SELECT COALESCE(SUM(duration_sec),0) FROM task_time_logs WHERE started_at >= ?1",
        params![week_start], |r| r.get(0)).unwrap_or(0);
    let sessions_today: i32 = conn.query_row(
        "SELECT COUNT(*) FROM task_time_logs WHERE started_at >= ?1",
        params![today_start], |r| r.get(0)).unwrap_or(0);

    Ok((worked_today, worked_week, sessions_today))
}

