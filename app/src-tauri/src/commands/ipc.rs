#![allow(dead_code)]
use serde::{Deserialize, Serialize};
use tauri::command;

const PIPE_NAME: &str = r"\\.\pipe\workpulse-agent";

#[derive(Serialize, Deserialize, Debug)]
pub struct TimerState {
    pub state: String,
    pub task: Option<serde_json::Value>,
    pub elapsed_secs: u64,
    pub break_type: Option<String>,
}

#[command]
pub async fn send_ipc(cmd: String, payload: Option<serde_json::Value>) -> Result<serde_json::Value, String> {
    ipc_call(&cmd, payload).await.map_err(|e| e.to_string())
}

#[command]
pub async fn get_timer_state() -> Result<TimerState, String> {
    let res = ipc_call("get_state", None).await.map_err(|e| e.to_string())?;
    serde_json::from_value(res).map_err(|e| e.to_string())
}

#[command]
pub async fn toggle_play_pause() -> Result<(), String> {
    ipc_call("toggle_play_pause", None).await.map(|_| ()).map_err(|e| e.to_string())
}

#[command]
pub async fn select_task(task_id: String, project_id: String, task_name: String, project_name: String) -> Result<(), String> {
    ipc_call("select_task", Some(serde_json::json!({
        "task_id": task_id, "project_id": project_id,
        "task_name": task_name, "project_name": project_name
    }))).await.map(|_| ()).map_err(|e| e.to_string())
}

#[cfg(windows)]
async fn ipc_call(cmd: &str, payload: Option<serde_json::Value>) -> anyhow::Result<serde_json::Value> {
    use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
    use tokio::net::windows::named_pipe::ClientOptions;

    let pipe = ClientOptions::new().open(PIPE_NAME)?;
    let (reader, mut writer) = tokio::io::split(pipe);
    let msg = serde_json::to_string(&serde_json::json!({"cmd": cmd, "payload": payload}))?;
    writer.write_all(format!("{msg}\n").as_bytes()).await?;
    let mut lines = BufReader::new(reader).lines();
    let line = lines.next_line().await?.ok_or_else(|| anyhow::anyhow!("no response"))?;
    let resp: serde_json::Value = serde_json::from_str(&line)?;
    Ok(resp["data"].clone())
}

#[cfg(not(windows))]
async fn ipc_call(_cmd: &str, _payload: Option<serde_json::Value>) -> anyhow::Result<serde_json::Value> {
    Ok(serde_json::json!({ "state": "idle", "task": null, "elapsed_secs": 0 }))
}
