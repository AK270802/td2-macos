use anyhow::{anyhow, Result};
use reqwest::Client;
use crate::api::{authed_post, is_permanent_failure, is_retryable};
use crate::models::ActivityBatch;

pub enum BatchResult { Accepted, PermanentFailure, Retryable }

pub async fn post_batch(client: &Client, batch: &ActivityBatch) -> Result<BatchResult> {
    let res = authed_post(client, "/activity/batch", batch).await?;
    let status = res.status();
    if status.as_u16() == 202 || status.is_success() {
        return Ok(BatchResult::Accepted);
    }
    if is_permanent_failure(status) { return Ok(BatchResult::PermanentFailure); }
    if is_retryable(status) { return Ok(BatchResult::Retryable); }
    Err(anyhow!("Unexpected status: {status}"))
}
