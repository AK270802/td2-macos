use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Task {
    pub task_id: Uuid,
    pub project_id: Uuid,
    pub task_name: String,
    pub project_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Project {
    pub id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub tasks: Vec<Task>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimerSnapshot {
    pub state: String,
    pub task: Option<Task>,
    pub elapsed_secs: u64,
    pub break_type: Option<String>,
    pub synced_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActivityEvent {
    pub event_uuid: Uuid,
    pub user_id: Uuid,
    pub tenant_id: Uuid,
    pub event_type: String,
    pub ts: i64,
    pub duration_sec: i64,
    pub payload: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskTimeLog {
    pub id: Uuid,
    pub task_id: Uuid,
    pub project_id: Uuid,
    pub task_name: String,
    pub project_name: String,
    pub started_at: i64,
    pub ended_at: i64,
    pub duration_sec: i64,
    #[serde(default)]
    pub idle_sec: i64,
    #[serde(default)]
    pub break_sec: i64,
    #[serde(default)]
    pub meeting_sec: i64,
    #[serde(skip_serializing, default)]
    pub synced: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ActivityBatch {
    pub events: Vec<ActivityEvent>,
    pub task_time_logs: Vec<TaskTimeLog>,
    pub agent_version: String,
    pub tz_offset: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentConfig {
    pub idle_threshold_sec: u64,
    pub screenshot_interval_sec: u64,
    pub screenshots_enabled: bool,
    pub blur_radius: u32,
    pub capture_interval_sec: u64,
    pub batch_sync_interval_min: u64,
    pub assignment_sync_interval_min: u64,
    pub jpeg_quality: u8,
    pub max_screenshot_kb: u32,
    pub screenshot_scale: f32,
}

impl Default for AgentConfig {
    fn default() -> Self {
        Self {
            idle_threshold_sec: 300,
            screenshot_interval_sec: 600,
            screenshots_enabled: true,
            blur_radius: 8,
            capture_interval_sec: 30,
            batch_sync_interval_min: 5,
            assignment_sync_interval_min: 20,
            jpeg_quality: 60,
            max_screenshot_kb: 150,
            screenshot_scale: 0.5,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimeStats {
    pub worked_today_sec: i64,
    pub worked_week_sec: i64,
    pub worked_month_sec: i64,
    pub sessions_today: i32,
}
