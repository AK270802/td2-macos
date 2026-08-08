//! Consent endpoints — shapes match core-services `app/schemas/consent.py`:
//!   GET  /consent/status  → { consent_status, policy_version, policy_content }
//!   POST /consent/accept  { policy_version: int } → { status, accepted_at }

use anyhow::{anyhow, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use crate::api::{authed_get, authed_post};

#[derive(Deserialize, Serialize, Debug, Clone)]
pub struct ConsentStatus {
    /// "pending" | "accepted" | "withdrawn"
    pub consent_status: String,
    #[serde(default)]
    pub policy_version: Option<i64>,
    #[serde(default)]
    pub policy_content: Option<String>,
}

impl ConsentStatus {
    pub fn accepted(&self) -> bool {
        self.consent_status == "accepted"
    }
}

pub async fn get_status(client: &Client) -> Result<ConsentStatus> {
    let res = authed_get(client, "/consent/status").await?;
    if !res.status().is_success() {
        return Err(anyhow!("consent status failed: {}", res.status()));
    }
    Ok(res.json().await?)
}

#[derive(Serialize)]
struct AcceptRequest { policy_version: i64 }

pub async fn accept(client: &Client, policy_version: i64) -> Result<()> {
    let res = authed_post(client, "/consent/accept", &AcceptRequest { policy_version }).await?;
    if !res.status().is_success() {
        return Err(anyhow!("consent accept failed: {}", res.status()));
    }
    Ok(())
}
