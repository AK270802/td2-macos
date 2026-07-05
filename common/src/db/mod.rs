pub mod key_manager;
pub mod queries;
pub mod schema;
pub mod sync_queue;

use anyhow::Result;
use rusqlite::Connection;
use std::path::PathBuf;
use crate::db::key_manager::get_or_create_db_key;

pub fn open() -> Result<Connection> {
    let path = db_path();
    std::fs::create_dir_all(path.parent().unwrap())?;
    let conn = Connection::open(&path)?;
    let key = get_or_create_db_key()?;
    conn.execute_batch(&format!("PRAGMA key=\"x'{key}'\"; PRAGMA cipher_compatibility = 4; PRAGMA journal_mode=WAL;"))?;
    schema::ensure_schema(&conn)?;
    Ok(conn)
}

pub fn db_path() -> PathBuf {
    let appdata = std::env::var("APPDATA").unwrap_or_else(|_| ".".into());
    PathBuf::from(appdata).join("WorkPulse").join("workpulse.db")
}

pub fn screenshots_dir() -> PathBuf {
    let appdata = std::env::var("APPDATA").unwrap_or_else(|_| ".".into());
    PathBuf::from(appdata).join("WorkPulse").join("screenshots")
}
