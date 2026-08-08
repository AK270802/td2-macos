use anyhow::Result;
use keyring::Entry;
use uuid::Uuid;

// Distinct from the legacy Python agent's "WorkPulse" keyring service so a
// machine with both agents installed never mixes up auth tokens.
const SERVICE: &str = "WorkPulseAgentRust";

pub struct Session {
    pub user_id: Uuid,
    pub tenant_id: Uuid,
    pub email: String,
    pub access_token: String,
    pub refresh_token: String,
}

pub fn save(session: &Session) -> Result<()> {
    Entry::new(SERVICE, "agent_token")?.set_password(&session.access_token)?;
    Entry::new(SERVICE, "agent_refresh_token")?.set_password(&session.refresh_token)?;
    Ok(())
}

pub fn get_access_token() -> Option<String> {
    Entry::new(SERVICE, "agent_token").ok()?.get_password().ok()
}

pub fn get_refresh_token() -> Option<String> {
    Entry::new(SERVICE, "agent_refresh_token").ok()?.get_password().ok()
}

pub fn clear() -> Result<()> {
    let _ = Entry::new(SERVICE, "agent_token")?.delete_credential();
    let _ = Entry::new(SERVICE, "agent_refresh_token")?.delete_credential();
    Ok(())
}

/// Used by api::auth::refresh() so both write paths share one keyring
/// service/account naming source instead of duplicating string literals.
pub fn save_tokens(access_token: &str, refresh_token: Option<&str>) -> Result<()> {
    Entry::new(SERVICE, "agent_token")?.set_password(access_token)?;
    if let Some(rt) = refresh_token {
        Entry::new(SERVICE, "agent_refresh_token")?.set_password(rt)?;
    }
    Ok(())
}
