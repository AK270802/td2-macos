use anyhow::Result;
use rusqlite::Connection;

pub fn ensure_schema(conn: &Connection) -> Result<()> {
    conn.execute_batch("
        CREATE TABLE IF NOT EXISTS events (
            event_uuid  TEXT PRIMARY KEY,
            user_id     TEXT NOT NULL,
            tenant_id   TEXT NOT NULL,
            event_type  TEXT NOT NULL,
            ts          INTEGER NOT NULL,
            duration_sec INTEGER NOT NULL DEFAULT 0,
            payload     TEXT NOT NULL DEFAULT '{}',
            synced      INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS ix_events_synced ON events(synced);
        CREATE INDEX IF NOT EXISTS ix_events_ts ON events(ts);

        CREATE TABLE IF NOT EXISTS screenshots (
            uuid         TEXT PRIMARY KEY,
            ts           INTEGER NOT NULL,
            file_path    TEXT NOT NULL,
            app_name     TEXT,
            window_title TEXT,
            uploaded     INTEGER NOT NULL DEFAULT 0,
            task_id      TEXT
        );

        CREATE TABLE IF NOT EXISTS domain_cache (
            domain      TEXT PRIMARY KEY,
            favicon_b64 TEXT,
            first_seen  INTEGER NOT NULL,
            last_seen   INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS sync_queue (
            batch_id     TEXT PRIMARY KEY,
            event_uuids  TEXT NOT NULL,
            status       TEXT NOT NULL DEFAULT 'pending',
            retry_count  INTEGER NOT NULL DEFAULT 0,
            next_retry_at INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS agent_config (
            key         TEXT PRIMARY KEY,
            value       TEXT NOT NULL,
            last_synced INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS assigned_tasks (
            task_id      TEXT PRIMARY KEY,
            project_id   TEXT NOT NULL,
            task_name    TEXT NOT NULL,
            project_name TEXT NOT NULL,
            last_synced  INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS task_time_logs (
            id           TEXT PRIMARY KEY,
            task_id      TEXT NOT NULL,
            project_id   TEXT NOT NULL,
            task_name    TEXT NOT NULL,
            project_name TEXT NOT NULL,
            started_at   INTEGER NOT NULL,
            ended_at     INTEGER NOT NULL,
            duration_sec INTEGER NOT NULL,
            idle_sec     INTEGER NOT NULL DEFAULT 0,
            break_sec    INTEGER NOT NULL DEFAULT 0,
            meeting_sec  INTEGER NOT NULL DEFAULT 0,
            synced       INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS active_tracking_session (
            id                  INTEGER PRIMARY KEY DEFAULT 1,
            task_id             TEXT,
            project_id          TEXT,
            task_name           TEXT,
            project_name        TEXT,
            session_start_ts    INTEGER,
            accumulated_seconds INTEGER NOT NULL DEFAULT 0,
            saved_at            INTEGER NOT NULL DEFAULT 0
        );
    ")?;
    run_migrations(conn);
    Ok(())
}

/// Idempotent column additions for databases created before these columns
/// existed. "duplicate column name" errors are expected and swallowed.
fn run_migrations(conn: &Connection) {
    for ddl in [
        "ALTER TABLE task_time_logs ADD COLUMN idle_sec INTEGER NOT NULL DEFAULT 0",
        "ALTER TABLE task_time_logs ADD COLUMN break_sec INTEGER NOT NULL DEFAULT 0",
        "ALTER TABLE task_time_logs ADD COLUMN meeting_sec INTEGER NOT NULL DEFAULT 0",
    ] {
        let _ = conn.execute_batch(ddl);
    }
}
