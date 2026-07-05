use anyhow::Result;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use crate::api::{authed_get, authed_post};

#[derive(Deserialize)]
pub struct ConsentStatus {
    pub required: bool,
    pub policy_version: Option<String>,
    pub accepted: bool,
}

pub async fn get_status(client: &Client) -> Result<ConsentStatus> {
    let res = authed_get(client, "/consent/status").await?;
    Ok(res.json().await?)
}

#[derive(Serialize)]
struct AcceptRequest { policy_version: String }

pub async fn accept(client: &Client, policy_version: &str) -> Result<()> {
    authed_post(client, "/consent/accept", &AcceptRequest { policy_version: policy_version.into() }).await?;
    Ok(())
}
