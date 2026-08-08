//! POST /screenshots/upload — multipart fields match core-services
//! `app/api/v1/screenshots.py`: file, app_name, window_title, task_id,
//! captured_at_client (ISO 8601).

use anyhow::{anyhow, Result};
use reqwest::Client;
use std::path::Path;
use crate::api::api;
use crate::auth::session_store;

pub struct ScreenshotMeta<'a> {
    pub task_id: Option<&'a str>,
    pub app_name: Option<&'a str>,
    pub window_title: Option<&'a str>,
    pub captured_at: i64,
}

pub async fn upload(client: &Client, path: &Path, meta: &ScreenshotMeta<'_>) -> Result<()> {
    let token = session_store::get_access_token().ok_or_else(|| anyhow!("not authenticated"))?;
    let bytes = std::fs::read(path)?;
    let part = reqwest::multipart::Part::bytes(bytes)
        .file_name("screenshot.jpg")
        .mime_str("image/jpeg")?;

    let captured_iso = chrono::DateTime::from_timestamp(meta.captured_at, 0)
        .unwrap_or_else(chrono::Utc::now)
        .to_rfc3339();

    let mut form = reqwest::multipart::Form::new()
        .part("file", part)
        .text("app_name", meta.app_name.unwrap_or("").to_string())
        .text("window_title", meta.window_title.unwrap_or("").to_string())
        .text("captured_at_client", captured_iso);
    if let Some(tid) = meta.task_id {
        form = form.text("task_id", tid.to_string());
    }

    let res = client.post(api("/screenshots/upload"))
        .header("Authorization", format!("Bearer {token}"))
        .header("X-Agent-Version", env!("CARGO_PKG_VERSION"))
        .multipart(form)
        .send().await?;

    if !res.status().is_success() {
        return Err(anyhow!("screenshot upload failed: {}", res.status()));
    }
    // Only delete the local file after a confirmed 200.
    std::fs::remove_file(path).ok();
    Ok(())
}
