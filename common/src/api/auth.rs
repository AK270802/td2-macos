use anyhow::{anyhow, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use crate::api::api;
use crate::auth::session_store::{self, Session};

#[derive(Serialize)]
struct LoginRequest { email: String, password: String }

#[derive(Deserialize)]
struct LoginResponse {
    access_token: Option<String>,
    token: Option<String>,
    refresh_token: Option<String>,
    user_id: Option<String>,
    tenant_id: Option<String>,
    email: Option<String>,
}

pub async fn login(client: &Client, email: &str, password: &str) -> Result<Session> {
    let res = client.post(api("/auth/agent/login"))
        .json(&LoginRequest { email: email.into(), password: password.into() })
        .send().await?;
    if !res.status().is_success() {
        return Err(anyhow!("Login failed: {}", res.status()));
    }
    let body: LoginResponse = res.json().await?;
    let access_token = body.access_token.or(body.token)
        .ok_or_else(|| anyhow!("No token in login response"))?;
    let session = Session {
        user_id: body.user_id.unwrap_or_default().parse().unwrap_or_default(),
        tenant_id: body.tenant_id.unwrap_or_default().parse().unwrap_or_default(),
        email: body.email.unwrap_or_else(|| email.to_string()),
        access_token,
        refresh_token: body.refresh_token.unwrap_or_default(),
    };
    session_store::save(&session)?;
    Ok(session)
}

pub async fn refresh(client: &Client) -> Result<String> {
    let token = session_store::get_refresh_token()
        .or_else(session_store::get_access_token)
        .ok_or_else(|| anyhow!("no token to refresh"))?;
    let res = client.post(api("/auth/agent/refresh"))
        .header("Authorization", format!("Bearer {token}"))
        .send().await?;
    if res.status().as_u16() == 401 {
        return Err(anyhow!("session_expired"));
    }
    let body: LoginResponse = res.json().await?;
    let new_token = body.access_token.or(body.token)
        .ok_or_else(|| anyhow!("No token in refresh response"))?;
    // Update stored access token
    if let Some(rt) = body.refresh_token {
        let _ = keyring::Entry::new("WorkPulse", "agent_refresh_token").map(|e| e.set_password(&rt));
    }
    let _ = keyring::Entry::new("WorkPulse", "agent_token").map(|e| e.set_password(&new_token));
    Ok(new_token)
}

