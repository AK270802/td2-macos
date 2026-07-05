#![allow(dead_code)]
use tauri::command;
use common::api::{auth as api_auth, build_client};
use common::db::{self, queries};

#[command]
pub async fn login(email: String, password: String) -> Result<serde_json::Value, String> {
    let client = build_client().map_err(|e| e.to_string())?;
    let session = api_auth::login(&client, &email, &password).await.map_err(|e| e.to_string())?;
    // Persist identity so get_session can restore it after reload
    if let Ok(conn) = db::open() {
        let _ = queries::set_config(&conn, "user_id", &session.user_id.to_string());
        let _ = queries::set_config(&conn, "user_email", &session.email);
    }
    Ok(serde_json::json!({ "user_id": session.user_id.to_string(), "email": session.email }))
}

#[command]
pub async fn logout() -> Result<(), String> {
    if let Ok(conn) = db::open() {
        let _ = queries::set_config(&conn, "user_id", "");
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
