use anyhow::{anyhow, Result};
use reqwest::Client;
use serde::Deserialize;
use semver::Version;
use crate::api::authed_get;
use crate::models::{AgentConfig, Task, TimeStats};

#[derive(Deserialize)]
struct ConfigResponse {
    user_id: Option<String>,
    tenant_id: Option<String>,
    idle_threshold_sec: Option<u64>,
    screenshot_interval_sec: Option<u64>,
    screenshots_enabled: Option<bool>,
    blur_radius: Option<u32>,
    capture_interval_sec: Option<u64>,
    batch_sync_interval_min: Option<u64>,
    assignment_sync_interval_min: Option<u64>,
    retention_days: Option<i64>,
    assigned_tasks: Option<Vec<TaskResponse>>,
    general_activity_task_id: Option<String>,
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

/// Field names match core-services `app/schemas/agent.py` TimeStatsResponse.
#[derive(Deserialize)]
struct TimeStatsResponse {
    today_logged_sec: Option<i64>,
    week_logged_sec: Option<i64>,
    month_logged_sec: Option<i64>,
    #[allow(dead_code)]
    tasks_today: Option<serde_json::Value>,
}

pub struct RemoteIdentity {
    pub user_id: Option<String>,
    pub tenant_id: Option<String>,
    pub retention_days: Option<i64>,
    pub general_activity_task_id: Option<String>,
}

pub async fn get_config(client: &Client) -> Result<(AgentConfig, Vec<Task>, RemoteIdentity)> {
    let res = authed_get(client, "/agent/config").await?;
    if !res.status().is_success() {
        return Err(anyhow!("agent config failed: {}", res.status()));
    }
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
    let identity = RemoteIdentity {
        user_id: body.user_id,
        tenant_id: body.tenant_id,
        retention_days: body.retention_days,
        general_activity_task_id: body.general_activity_task_id,
    };
    Ok((config, tasks, identity))
}

/// Returns (update_available, download_url) using semver comparison.
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
    if !res.status().is_success() {
        return Err(anyhow!("time stats failed: {}", res.status()));
    }
    let body: TimeStatsResponse = res.json().await?;
    Ok(TimeStats {
        worked_today_sec: body.today_logged_sec.unwrap_or(0),
        worked_week_sec: body.week_logged_sec.unwrap_or(0),
        worked_month_sec: body.month_logged_sec.unwrap_or(0),
        sessions_today: 0, // server does not report session count; local DB does
    })
}
