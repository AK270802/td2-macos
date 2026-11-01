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

/// Default builds: unchanged behaviour (401 after a failed refresh is final).
#[cfg(not(feature = "macos-native"))]
pub fn is_permanent_failure(status: StatusCode) -> bool {
    matches!(status.as_u16(), 400 | 401 | 403 | 404 | 422)
}

/// Native macOS build: a 401 that survives the one-shot refresh means the
/// session is missing/expired (e.g. the app has not handed over a fresh token
/// yet), not that the batch is bad. Treating it as permanent would mark the
/// events synced and lose them, so it is retried with backoff instead.
#[cfg(feature = "macos-native")]
pub fn is_permanent_failure(status: StatusCode) -> bool {
    matches!(status.as_u16(), 400 | 403 | 404 | 422)
}

pub fn is_retryable(status: StatusCode) -> bool {
    status.as_u16() == 429 || status.is_server_error()
}

#[cfg(test)]
mod failure_class_tests {
    use super::*;

    #[test]
    fn server_errors_and_429_are_retryable() {
        assert!(is_retryable(StatusCode::INTERNAL_SERVER_ERROR));
        assert!(is_retryable(StatusCode::TOO_MANY_REQUESTS));
        assert!(!is_retryable(StatusCode::BAD_REQUEST));
    }

    #[test]
    fn validation_errors_are_permanent() {
        assert!(is_permanent_failure(StatusCode::BAD_REQUEST));
        assert!(is_permanent_failure(StatusCode::UNPROCESSABLE_ENTITY));
    }

    #[cfg(not(feature = "macos-native"))]
    #[test]
    fn default_build_keeps_401_permanent() {
        assert!(is_permanent_failure(StatusCode::UNAUTHORIZED));
    }

    #[cfg(feature = "macos-native")]
    #[test]
    fn native_build_never_drops_events_on_401() {
        assert!(!is_permanent_failure(StatusCode::UNAUTHORIZED));
    }
}
