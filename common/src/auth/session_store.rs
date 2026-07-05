use anyhow::Result;
use keyring::Entry;
use uuid::Uuid;

const SERVICE: &str = "WorkPulse";

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
