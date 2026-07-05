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
        .build()?)
}

fn base_url() -> String {
    std::env::var("WORKPULSE_API_URL")
        .unwrap_or_else(|_| "https://workpulse-dev-api.baseel.com".into())
}

pub fn api(path: &str) -> String {
    format!("{}/api/v1{}", base_url(), path)
}

pub async fn authed_get(client: &Client, path: &str) -> Result<Response> {
    let token = session_store::get_access_token().ok_or_else(|| anyhow!("not authenticated"))?;
    let res = client.get(api(path))
        .header("Authorization", format!("Bearer {token}"))
        .header("X-Agent-Version", AGENT_VERSION)
        .send().await?;
    Ok(res)
}

pub async fn authed_post<B: serde::Serialize>(client: &Client, path: &str, body: &B) -> Result<Response> {
    let token = session_store::get_access_token().ok_or_else(|| anyhow!("not authenticated"))?;
    let res = client.post(api(path))
        .header("Authorization", format!("Bearer {token}"))
        .header("X-Agent-Version", AGENT_VERSION)
        .json(body)
        .send().await?;
    Ok(res)
}

pub fn is_permanent_failure(status: StatusCode) -> bool {
    matches!(status.as_u16(), 400 | 403 | 404 | 422)
}

pub fn is_retryable(status: StatusCode) -> bool {
    matches!(status.as_u16(), 429 | 500 | 502 | 503 | 504)
}
