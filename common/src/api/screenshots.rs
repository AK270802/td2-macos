use anyhow::Result;
use reqwest::Client;
use std::path::Path;
use crate::api::api;
use crate::auth::session_store;

pub async fn upload(client: &Client, path: &Path, task_id: Option<&str>, ts: i64) -> Result<()> {
    let token = session_store::get_access_token().ok_or_else(|| anyhow::anyhow!("not authenticated"))?;
    let bytes = std::fs::read(path)?;
    let part = reqwest::multipart::Part::bytes(bytes)
        .file_name("screenshot.jpg")
        .mime_str("image/jpeg")?;
    let mut form = reqwest::multipart::Form::new()
        .part("file", part)
        .text("ts", ts.to_string());
    if let Some(tid) = task_id { form = form.text("task_id", tid.to_string()); }
    let res = client.post(api("/screenshots/upload"))
        .header("Authorization", format!("Bearer {token}"))
        .multipart(form)
        .send().await?;
    if res.status().is_success() {
        std::fs::remove_file(path).ok();
    }
    Ok(())
}
