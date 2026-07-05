use anyhow::Result;
use reqwest::Client;
use serde::Deserialize;
use semver::Version;
use crate::api::authed_get;
use crate::models::{AgentConfig, Task, TimeStats};

#[derive(Deserialize)]
struct ConfigResponse {
    idle_threshold_sec: Option<u64>,
    screenshot_interval_sec: Option<u64>,
    screenshots_enabled: Option<bool>,
    blur_radius: Option<u32>,
    capture_interval_sec: Option<u64>,
    batch_sync_interval_min: Option<u64>,
    assignment_sync_interval_min: Option<u64>,
    assigned_tasks: Option<Vec<TaskResponse>>,
}

#[derive(Deserialize)]
struct TaskResponse {
    task_id: String,
    project_id: String,
    task_name: String,
    project_name: String,
}

#[derive(Deserialize)]
struct VersionResponse {
    version: Option<String>,
    latest_version: Option<String>,
    #[allow(dead_code)]
    min_supported_version: Option<String>,
    download_url: Option<String>,
}

#[derive(Deserialize)]
struct TimeStatsResponse {
    worked_today_sec: Option<i64>,
    worked_week_sec: Option<i64>,
    sessions_today: Option<i32>,
}

pub async fn get_config(client: &Client) -> Result<(AgentConfig, Vec<Task>)> {
    let res = authed_get(client, "/agent/config").await?;
    let body: ConfigResponse = res.json().await?;
    let config = AgentConfig {
        idle_threshold_sec: body.idle_threshold_sec.unwrap_or(300),
        screenshot_interval_sec: body.screenshot_interval_sec.unwrap_or(600),
        screenshots_enabled: body.screenshots_enabled.unwrap_or(true),
        blur_radius: body.blur_radius.unwrap_or(8),
        capture_interval_sec: body.capture_interval_sec.unwrap_or(30),
        batch_sync_interval_min: body.batch_sync_interval_min.unwrap_or(5),
        assignment_sync_interval_min: body.assignment_sync_interval_min.unwrap_or(20),
        ..AgentConfig::default()
    };
    let tasks = body.assigned_tasks.unwrap_or_default().into_iter().map(|t| Task {
        task_id: t.task_id.parse().unwrap_or_default(),
        project_id: t.project_id.parse().unwrap_or_default(),
        task_name: t.task_name,
        project_name: t.project_name,
    }).collect();
    Ok((config, tasks))
}

/// Returns (update_available, download_url) using semver comparison.
/// Fixes the false-positive bug caused by lexicographic version comparison.
pub async fn check_version(client: &Client, current: &str) -> Result<(bool, Option<String>)> {
    let res = authed_get(client, "/agent/version").await?;
    let body: VersionResponse = res.json().await?;
    let server_ver_str = body.latest_version.or(body.version).unwrap_or_default();
    let current_v = Version::parse(current).unwrap_or_else(|_| Version::new(0,0,0));
    let server_v = Version::parse(&server_ver_str).unwrap_or_else(|_| Version::new(0,0,0));
    Ok((server_v > current_v, body.download_url))
}

pub async fn get_time_stats(client: &Client) -> Result<TimeStats> {
    let res = authed_get(client, "/agent/time-stats").await?;
    let body: TimeStatsResponse = res.json().await?;
    Ok(TimeStats {
        worked_today_sec: body.worked_today_sec.unwrap_or(0),
        worked_week_sec: body.worked_week_sec.unwrap_or(0),
        sessions_today: body.sessions_today.unwrap_or(0),
    })
}
