use anyhow::Result;
use reqwest::Client;
use crate::api::{authed_post, is_permanent_failure};
use crate::models::ActivityBatch;

pub enum BatchResult { Accepted, PermanentFailure, Retryable }

/// POST /activity/batch. Every HTTP status maps to a BatchResult — an
/// unexpected status is treated as retryable rather than an error, so the
/// sync loop can never be killed by a surprise status code.
pub async fn post_batch(client: &Client, batch: &ActivityBatch) -> Result<BatchResult> {
    let res = authed_post(client, "/activity/batch", batch).await?;
    let status = res.status();
    if status.is_success() {
        return Ok(BatchResult::Accepted); // 202 expected
    }
    if is_permanent_failure(status) {
        tracing::warn!("Batch permanently rejected: {status}");
        return Ok(BatchResult::PermanentFailure);
    }
    Ok(BatchResult::Retryable)
}
