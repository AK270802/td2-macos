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
    match try_open(&path) {
        Ok(conn) => Ok(conn),
        Err(e) if is_unreadable_db(&e) => {
            // Wrong key or corrupt file (e.g. a database left behind by an
            // older build). Local data is a re-syncable cache — back the file
            // up and start fresh rather than failing to launch.
            let backup = path.with_extension(format!("corrupt.{}", chrono::Utc::now().timestamp()));
            tracing::warn!("Local DB unreadable ({e}); moving to {} and recreating", backup.display());
            let _ = std::fs::rename(&path, &backup);
            let _ = std::fs::remove_file(path.with_extension("db-wal"));
            let _ = std::fs::remove_file(path.with_extension("db-shm"));
            try_open(&path)
        }
        Err(e) => Err(e),
    }
}

fn try_open(path: &std::path::Path) -> Result<Connection> {
    let conn = Connection::open(path)?;
    let key = get_or_create_db_key()?;
    conn.execute_batch(&format!("PRAGMA key=\"x'{key}'\"; PRAGMA cipher_compatibility = 4; PRAGMA journal_mode=WAL;"))?;
    schema::ensure_schema(&conn)?;
    Ok(conn)
}

fn is_unreadable_db(e: &anyhow::Error) -> bool {
    let msg = e.to_string().to_lowercase();
    msg.contains("not a database") || msg.contains("file is encrypted") || msg.contains("malformed")
}

/// Per-user data root. Deliberately named "WorkPulseAgentRust", not
/// "WorkPulse" — the legacy Python agent uses %APPDATA%\WorkPulse\workpulse.db
/// with the exact same filename, so sharing the folder would mean opening a
/// file written by the other agent's SQLCipher KDF settings, which fails as
/// SQLITE_NOTADB even with the correct raw key. Both agents can safely
/// coexist on a machine during migration this way.
pub fn data_dir() -> PathBuf {
    dirs::data_dir()
        .unwrap_or_else(|| dirs::home_dir().unwrap_or_else(|| PathBuf::from(".")))
        .join(DATA_DIR_NAME)
}

/// The native EffiLens macOS agent keeps a fully separate store
/// (`~/Library/Application Support/EffiLens/`) so it never shares
/// account-sensitive data, keys or sockets with the legacy Tauri agent.
#[cfg(feature = "macos-native")]
const DATA_DIR_NAME: &str = "EffiLens";
#[cfg(not(feature = "macos-native"))]
const DATA_DIR_NAME: &str = "WorkPulseAgentRust";

pub fn db_path() -> PathBuf {
    data_dir().join("workpulse.db")
}

pub fn screenshots_dir() -> PathBuf {
    data_dir().join("screenshots")
}

/// Where agentd/app write rotating logs and crash.log — surfaced to the user
/// via the tray "Open Logs Folder" action, matching the Python agent's
/// %APPDATA%\WorkPulse\logs convention (different root dir, same idea; see
/// `data_dir()`'s doc comment for why the roots can't be shared).
pub fn logs_dir() -> PathBuf {
    data_dir().join("logs")
}
