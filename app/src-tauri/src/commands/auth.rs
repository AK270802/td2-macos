use tauri::command;
use common::api::{auth as api_auth, build_client};
use common::db::{self, queries};

#[command]
pub async fn login(email: String, password: String) -> Result<serde_json::Value, String> {
    let client = build_client().map_err(|e| e.to_string())?;
    let session = api_auth::login(&client, &email, &password).await.map_err(|e| e.to_string())?;
    // Persist full identity — tenant_id is required by the capture loop for
    // every event it records.
    if let Ok(conn) = db::open() {
        let _ = queries::set_config(&conn, "user_id", &session.user_id.to_string());
        let _ = queries::set_config(&conn, "tenant_id", &session.tenant_id.to_string());
        let _ = queries::set_config(&conn, "user_email", &session.email);
    }
    Ok(serde_json::json!({
        "user_id": session.user_id.to_string(),
        "tenant_id": session.tenant_id.to_string(),
        "email": session.email,
    }))
}

#[command]
pub async fn logout() -> Result<(), String> {
    // Stop any running session first so the time log is written, then wipe
    // the local activity cache -- it's a single DB file per OS-user profile,
    // not per WorkPulse account, so leftover rows would otherwise leak into
    // whichever account logs in next on this machine.
    let _ = common::ipc_transport::request("stop_tracking", None).await;
    let _ = common::ipc_transport::request("clear_local_data", None).await;
    if let Ok(conn) = db::open() {
        let _ = queries::set_config(&conn, "user_id", "");
        let _ = queries::set_config(&conn, "tenant_id", "");
        let _ = queries::set_config(&conn, "user_email", "");
    }
    common::auth::session_store::clear().map_err(|e| e.to_string())
}

#[command]
pub fn get_session() -> Result<Option<serde_json::Value>, String> {
    if common::auth::session_store::get_access_token().is_none() {
        return Ok(None);
    }
    let conn = db::open().map_err(|e| e.to_string())?;
    let user_id = queries::get_config(&conn, "user_id").unwrap_or_default();
    let email = queries::get_config(&conn, "user_email").unwrap_or_default();
    if user_id.is_empty() || email.is_empty() {
        return Ok(None);
    }
    Ok(Some(serde_json::json!({ "user_id": user_id, "email": email })))
}

/// Consent gate for startup routing: returns the server's consent state when
/// reachable, caching it locally (agent_config) so a later offline launch
/// can answer from that cache instead of guessing. A brand new install that
/// has never once reached the server has no cache to fall back on — that
/// case fails CLOSED (consent required) rather than silently bypassing the
/// gate, since consent is a non-negotiable privacy requirement, not a nice
/// to have that's safe to skip on a network hiccup.
#[command]
pub async fn get_consent_status() -> Result<serde_json::Value, String> {
    let client = build_client().map_err(|e| e.to_string())?;
    let conn = db::open().map_err(|e| e.to_string())?;

    match common::api::consent::get_status(&client).await {
        Ok(s) => {
            let _ = queries::set_config(&conn, "consent_status_cache", &s.consent_status);
            let _ = queries::set_config(
                &conn,
                "consent_policy_version_cache",
                &s.policy_version.map(|v| v.to_string()).unwrap_or_default(),
            );
            if let Some(content) = &s.policy_content {
                let _ = queries::set_config(&conn, "consent_policy_content_cache", content);
            }
            Ok(serde_json::to_value(&s).map_err(|e| e.to_string())?)
        }
        Err(_) => match queries::get_config(&conn, "consent_status_cache") {
            Some(status) => Ok(serde_json::json!({
                "consent_status": status,
                "policy_version": queries::get_config(&conn, "consent_policy_version_cache")
                    .and_then(|v| v.parse::<i64>().ok()),
                "policy_content": queries::get_config(&conn, "consent_policy_content_cache"),
            })),
            None => Ok(serde_json::json!({
                "consent_status": "required",
                "policy_version": 1,
                "policy_content": null,
            })),
        },
    }
}

#[command]
pub async fn accept_consent(policy_version: i64) -> Result<(), String> {
    let client = build_client().map_err(|e| e.to_string())?;
    common::api::consent::accept(&client, policy_version).await.map_err(|e| e.to_string())
}
