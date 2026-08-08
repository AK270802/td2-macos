pub mod auth;
pub mod agent;
pub mod activity;
pub mod screenshots;
pub mod projects;
pub mod consent;

use anyhow::{anyhow, Result};
use reqwest::{Client, Response, StatusCode};
use crate::auth::session_store;

const AGENT_VERSION: &str = env!("CARGO_PKG_VERSION");

pub fn build_client() -> Result<Client> {
    Ok(Client::builder()
        .user_agent(format!("WorkPulse-Agent/{AGENT_VERSION}"))
        .timeout(std::time::Duration::from_secs(30))
        .build()?)
}

fn base_url() -> String {
    std::env::var("WORKPULSE_API_URL")
        .unwrap_or_else(|_| "https://dev-workpulse-api.baseel.com".into())
}

pub fn api(path: &str) -> String {
    format!("{}/api/v1{}", base_url(), path)
}

async fn send_get(client: &Client, path: &str) -> Result<Response> {
    let token = session_store::get_access_token().ok_or_else(|| anyhow!("not authenticated"))?;
    let res = client.get(api(path))
        .header("Authorization", format!("Bearer {token}"))
        .header("X-Agent-Version", AGENT_VERSION)
        .send().await?;
    Ok(res)
}

async fn send_post<B: serde::Serialize>(client: &Client, path: &str, body: &B) -> Result<Response> {
    let token = session_store::get_access_token().ok_or_else(|| anyhow!("not authenticated"))?;
    let res = client.post(api(path))
        .header("Authorization", format!("Bearer {token}"))
        .header("X-Agent-Version", AGENT_VERSION)
        .json(body)
        .send().await?;
    Ok(res)
}

/// GET with automatic one-shot token refresh on 401. Agent tokens are rotated
/// by the server on refresh, so the retried request uses the fresh token.
pub async fn authed_get(client: &Client, path: &str) -> Result<Response> {
    let res = send_get(client, path).await?;
    if res.status().as_u16() == 401 && auth::refresh(client).await.is_ok() {
        return send_get(client, path).await;
    }
    Ok(res)
}

/// POST with the same one-shot 401 → refresh → retry behavior.
pub async fn authed_post<B: serde::Serialize>(client: &Client, path: &str, body: &B) -> Result<Response> {
    let res = send_post(client, path, body).await?;
    if res.status().as_u16() == 401 && auth::refresh(client).await.is_ok() {
        return send_post(client, path, body).await;
    }
    Ok(res)
}

pub fn is_permanent_failure(status: StatusCode) -> bool {
    matches!(status.as_u16(), 400 | 401 | 403 | 404 | 422)
}

pub fn is_retryable(status: StatusCode) -> bool {
    status.as_u16() == 429 || status.is_server_error()
}
