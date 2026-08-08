//! Tauri → agentd bridge. All traffic goes through the shared
//! common::ipc_transport client (named pipe on Windows, Unix socket
//! elsewhere) — one code path on every platform, and a real error when the
//! agent is unreachable instead of fabricated state.

use serde::{Deserialize, Serialize};
use tauri::{command, AppHandle};
use tauri_plugin_notification::NotificationExt;

#[derive(Serialize, Deserialize, Debug)]
pub struct TimerState {
    pub state: String,
    pub task: Option<serde_json::Value>,
    pub elapsed_secs: u64,
    pub break_type: Option<String>,
    pub break_remaining_secs: Option<u64>,
    pub idle_warning: Option<serde_json::Value>,
    pub idle_since_secs: Option<u64>,
    pub in_meeting: bool,
}

#[command]
pub async fn send_ipc(cmd: String, payload: Option<serde_json::Value>) -> Result<serde_json::Value, String> {
    common::ipc_transport::request(&cmd, payload).await.map_err(|e| e.to_string())
}

#[command]
pub async fn get_timer_state() -> Result<TimerState, String> {
    let res = common::ipc_transport::request("get_state", None).await.map_err(|e| e.to_string())?;
    serde_json::from_value(res).map_err(|e| e.to_string())
}

/// Fires a native OS notification (with the platform's default sound) for a
/// task start/pause — the in-app Toast component only ever reaches whichever
/// window happens to be focused and visible, so switching to a mini-widget
/// click or minimizing the main window left the user with no feedback at
/// all. Living here means both the mini widget's play/pause button and the
/// main window's task list go through the same notification, instead of
/// each window needing its own copy of this logic.
async fn notify_tracking_state(app: &AppHandle) {
    let Ok(state) = common::ipc_transport::request("get_state", None).await else { return };
    let status = state["state"].as_str().unwrap_or("idle");
    let task_name = state["task"]["task_name"].as_str();
    let (title, body) = match status {
        "running" => ("Tracking started", task_name.map(str::to_string).unwrap_or_else(|| "Timer running.".into())),
        "paused" => ("Tracking paused", task_name.map(str::to_string).unwrap_or_else(|| "Timer paused.".into())),
        _ => return, // idle/on_break aren't a task start/pause
    };
    let _ = app.notification().builder().title(title).body(body).show();
}

#[command]
pub async fn toggle_play_pause(app: AppHandle) -> Result<(), String> {
    common::ipc_transport::request("toggle_play_pause", None).await.map_err(|e| e.to_string())?;
    notify_tracking_state(&app).await;
    Ok(())
}

#[command(rename_all = "snake_case")]
pub async fn select_task(app: AppHandle, task_id: String, project_id: String, task_name: String, project_name: String) -> Result<(), String> {
    common::ipc_transport::request("select_task", Some(serde_json::json!({
        "task_id": task_id, "project_id": project_id,
        "task_name": task_name, "project_name": project_name
    }))).await.map_err(|e| e.to_string())?;
    let _ = app.notification().builder().title("Tracking started").body(task_name).show();
    Ok(())
}
