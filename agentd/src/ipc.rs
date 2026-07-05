//! Named pipe IPC server — concurrent, one spawn per connection.
//! JSON protocol: {cmd, payload} → {ok, data, error}

use serde::{Deserialize, Serialize};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tracing::{error, info};

const PIPE_NAME: &str = r"\\.\pipe\workpulse-agent";

// ── Shared timer state ────────────────────────────────────────────────────────

pub struct TimerInner {
    pub state: &'static str, // "idle" | "running" | "paused" | "on_break"
    pub task_id: Option<String>,
    pub project_id: Option<String>,
    pub task_name: Option<String>,
    pub project_name: Option<String>,
    pub started_at: Option<Instant>,
    pub accumulated: u64,
    pub break_type: Option<String>,
    pub break_started_at: Option<Instant>,
    pub break_duration_secs: u64,
}

static TIMER: OnceLock<Mutex<TimerInner>> = OnceLock::new();

pub fn timer() -> &'static Mutex<TimerInner> {
    TIMER.get_or_init(|| {
        Mutex::new(TimerInner {
            state: "idle",
            task_id: None,
            project_id: None,
            task_name: None,
            project_name: None,
            started_at: None,
            accumulated: 0,
            break_type: None,
            break_started_at: None,
            break_duration_secs: 0,
        })
    })
}

fn elapsed_secs(t: &TimerInner) -> u64 {
    let live = match t.started_at {
        Some(s) if t.state == "running" => s.elapsed().as_secs(),
        _ => 0,
    };
    t.accumulated + live
}

fn break_remaining(t: &TimerInner) -> Option<u64> {
    if t.state != "on_break" { return None; }
    let used = t.break_started_at.map(|s| s.elapsed().as_secs()).unwrap_or(0);
    Some(t.break_duration_secs.saturating_sub(used))
}

/// Called by capture_loop when sleep is detected — pauses running timer.
pub fn pause_for_sleep() {
    let mut t = timer().lock().unwrap();
    if t.state == "running" {
        t.accumulated = elapsed_secs(&t);
        t.started_at = None;
        t.state = "paused";
        info!("Timer paused: system sleep detected");
    }
}

// ── Wire types ────────────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct IpcRequest {
    cmd: String,
    payload: Option<serde_json::Value>,
}

#[derive(Serialize)]
struct IpcResponse {
    ok: bool,
    data: serde_json::Value,
    error: Option<String>,
}

// ── Server — one spawn per connection ────────────────────────────────────────

pub async fn run_ipc_server() {
    info!("IPC server starting on {PIPE_NAME}");
    #[cfg(windows)]
    loop {
        use tokio::net::windows::named_pipe::ServerOptions;
        let server = match ServerOptions::new().first_pipe_instance(false).create(PIPE_NAME) {
            Ok(s) => s,
            Err(e) => {
                error!("pipe create: {e}");
                tokio::time::sleep(Duration::from_millis(100)).await;
                continue;
            }
        };
        match server.connect().await {
            Ok(_) => { tokio::spawn(serve_conn(server)); }
            Err(e) => error!("pipe connect: {e}"),
        }
    }
    #[cfg(not(windows))]
    loop {
        tokio::time::sleep(Duration::from_secs(60)).await;
    }
}

#[cfg(windows)]
async fn serve_conn(server: tokio::net::windows::named_pipe::NamedPipeServer) {
    let (reader, mut writer) = tokio::io::split(server);
    let mut lines = BufReader::new(reader).lines();
    while let Ok(Some(line)) = lines.next_line().await {
        let resp = handle_request(&line).await;
        let out = serde_json::to_string(&resp).unwrap_or_default();
        if writer.write_all(format!("{out}\n").as_bytes()).await.is_err() {
            break;
        }
    }
}

// ── Command handlers ──────────────────────────────────────────────────────────

async fn handle_request(line: &str) -> IpcResponse {
    let req: IpcRequest = match serde_json::from_str(line) {
        Ok(r) => r,
        Err(e) => return err_resp(e.to_string()),
    };
    match req.cmd.as_str() {
        "ping" => ok_resp(serde_json::json!("pong")),

        "get_state" => {
            let t = timer().lock().unwrap();
            let task = t.task_id.as_ref().map(|id| serde_json::json!({
                "task_id": id,
                "task_name": t.task_name,
                "project_name": t.project_name,
            }));
            ok_resp(serde_json::json!({
                "state": t.state,
                "task": task,
                "elapsed_secs": elapsed_secs(&t),
                "break_type": t.break_type,
                "break_remaining_secs": break_remaining(&t),
            }))
        }

        "toggle_play_pause" => {
            let mut t = timer().lock().unwrap();
            match t.state {
                "running" => {
                    t.accumulated = elapsed_secs(&t);
                    t.started_at = None;
                    t.state = "paused";
                }
                "paused" | "on_break" => {
                    t.started_at = Some(Instant::now());
                    t.break_type = None;
                    t.break_started_at = None;
                    t.state = "running";
                }
                "idle" => {
                    // Resume last task from DB if available
                    drop(t);
                    if let Ok(conn) = common::db::open() {
                        if let Some(task_id) = common::db::queries::get_config(&conn, "last_task_id") {
                            let project_id = common::db::queries::get_config(&conn, "last_project_id").unwrap_or_default();
                            let task_name = common::db::queries::get_config(&conn, "last_task_name").unwrap_or_default();
                            let project_name = common::db::queries::get_config(&conn, "last_project_name").unwrap_or_default();
                            let mut t2 = timer().lock().unwrap();
                            t2.task_id = Some(task_id);
                            t2.project_id = Some(project_id);
                            t2.task_name = Some(task_name);
                            t2.project_name = Some(project_name);
                            t2.accumulated = 0;
                            t2.started_at = Some(Instant::now());
                            t2.break_type = None;
                            t2.state = "running";
                        }
                    }
                }
                _ => {}
            }
            ok_resp(serde_json::json!({"ok": true}))
        }

        "select_task" => {
            let payload = req.payload.unwrap_or_default();
            let task_id = payload["task_id"].as_str().map(String::from);
            let project_id = payload["project_id"].as_str().map(String::from);
            let task_name = payload["task_name"].as_str().map(String::from);
            let project_name = payload["project_name"].as_str().map(String::from);

            // Persist as last-used task for hero play resume
            if let (Some(ref tid), Some(ref pid), Some(ref tn), Some(ref pn)) =
                (&task_id, &project_id, &task_name, &project_name)
            {
                if let Ok(conn) = common::db::open() {
                    let _ = common::db::queries::set_config(&conn, "last_task_id", tid);
                    let _ = common::db::queries::set_config(&conn, "last_project_id", pid);
                    let _ = common::db::queries::set_config(&conn, "last_task_name", tn);
                    let _ = common::db::queries::set_config(&conn, "last_project_name", pn);
                }
            }

            let mut t = timer().lock().unwrap();
            if t.state == "running" {
                t.accumulated = elapsed_secs(&t);
            }
            t.task_id = task_id;
            t.project_id = project_id;
            t.task_name = task_name;
            t.project_name = project_name;
            t.accumulated = 0;
            t.started_at = Some(Instant::now());
            t.break_type = None;
            t.break_started_at = None;
            t.state = "running";
            ok_resp(serde_json::json!({"ok": true}))
        }

        "start_break" => {
            let payload = req.payload.unwrap_or_default();
            let break_type = payload["break_type"].as_str().unwrap_or("short").to_string();
            let duration_secs = payload["duration_secs"].as_u64().unwrap_or(600);
            let mut t = timer().lock().unwrap();
            if t.state == "running" {
                t.accumulated = elapsed_secs(&t);
                t.started_at = None;
            }
            t.break_type = Some(break_type);
            t.break_started_at = Some(Instant::now());
            t.break_duration_secs = duration_secs;
            t.state = "on_break";
            ok_resp(serde_json::json!({"ok": true}))
        }

        "get_assigned_tasks" => {
            let result = common::db::open()
                .and_then(|conn| common::db::queries::get_assigned_tasks(&conn));
            match result {
                Ok(tasks) => ok_resp(serde_json::to_value(&tasks).unwrap_or_default()),
                Err(e) => err_resp(e.to_string()),
            }
        }

        "get_time_stats" => {
            let result = common::db::open()
                .and_then(|conn| common::db::queries::get_time_stats_local(&conn));
            match result {
                Ok((today, week, sessions)) => ok_resp(serde_json::json!({
                    "worked_today_sec": today,
                    "worked_week_sec": week,
                    "sessions_today": sessions,
                })),
                Err(e) => err_resp(e.to_string()),
            }
        }

        _ => err_resp(format!("unknown command: {}", req.cmd)),
    }
}

fn ok_resp(data: serde_json::Value) -> IpcResponse {
    IpcResponse { ok: true, data, error: None }
}
fn err_resp(msg: String) -> IpcResponse {
    IpcResponse { ok: false, data: serde_json::Value::Null, error: Some(msg) }
}
