use anyhow::Result;
use uuid::Uuid;
use crate::db::{self, queries};

// Stored as rows in the local SQLCipher-encrypted `agent_config` table
// (same table user_id/tenant_id already live in) rather than the OS
// keychain. `agentd` and `workpulse-app` are separate binaries; on macOS,
// Keychain access is scoped to the calling process's code signature, so an
// unsigned/ad-hoc-signed build gives each binary its own isolated view of
// the "same" keychain entry — agentd's sync loop could silently see no
// token at all even right after a successful login in workpulse-app. The
// encrypted db file both processes already share doesn't have that
// per-binary ambiguity, and reusing it here (instead of a new plaintext
// file) keeps these tokens under the same encryption-at-rest the rest of
// local data gets.
const ACCESS_TOKEN_KEY: &str = "session_access_token";
const REFRESH_TOKEN_KEY: &str = "session_refresh_token";

pub struct Session {
    pub user_id: Uuid,
    pub tenant_id: Uuid,
    pub email: String,
    pub access_token: String,
    pub refresh_token: String,
}

pub fn save(session: &Session) -> Result<()> {
    let conn = db::open()?;
    queries::set_config(&conn, ACCESS_TOKEN_KEY, &session.access_token)?;
    queries::set_config(&conn, REFRESH_TOKEN_KEY, &session.refresh_token)?;
    Ok(())
}

pub fn get_access_token() -> Option<String> {
    let conn = db::open().ok()?;
    queries::get_config(&conn, ACCESS_TOKEN_KEY).filter(|s| !s.is_empty())
}

pub fn get_refresh_token() -> Option<String> {
    let conn = db::open().ok()?;
    queries::get_config(&conn, REFRESH_TOKEN_KEY).filter(|s| !s.is_empty())
}

pub fn clear() -> Result<()> {
    let conn = db::open()?;
    queries::set_config(&conn, ACCESS_TOKEN_KEY, "")?;
    queries::set_config(&conn, REFRESH_TOKEN_KEY, "")?;
    Ok(())
}

/// Used by api::auth::refresh() so both write paths share one storage
/// helper instead of duplicating the key names.
pub fn save_tokens(access_token: &str, refresh_token: Option<&str>) -> Result<()> {
    let conn = db::open()?;
    queries::set_config(&conn, ACCESS_TOKEN_KEY, access_token)?;
    if let Some(rt) = refresh_token {
        queries::set_config(&conn, REFRESH_TOKEN_KEY, rt)?;
    }
    Ok(())
}
