//! IPC server — cross-platform local socket (named pipe on Windows, Unix
//! socket elsewhere) via common::ipc_transport. One spawn per connection.
//!
//! The timer is a `common::timer_service::TimerService` wrapping the tested
//! `TimerState` machine — the exact logic covered by timer_state_tests.rs is
//! what runs in production.

use common::db::{self, queries};
use common::ipc_transport::{self, IpcRequest, IpcResponse};
#[cfg(not(feature = "macos-native"))]
use interprocess::local_socket::traits::tokio::{Listener as _, Stream as _};
use common::models::{ActivityEvent, Task};
use common::timer_service::TimerService;
use common::timer_state::{BreakKind, TimerState};
use std::sync::{Mutex, OnceLock};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tracing::{error, info};
use uuid::Uuid;

static TIMER: OnceLock<Mutex<TimerService>> = OnceLock::new();

pub fn timer() -> &'static Mutex<TimerService> {
    TIMER.get_or_init(|| Mutex::new(TimerService::new()))
}

/// Task id currently being tracked (used by sync_loop's prune guard).
pub fn active_task_id() -> Option<Uuid> {
    timer().lock().ok()?.state().active_task().map(|t| t.task_id)
}

/// Called by capture_loop when a sleep gap is detected.
pub fn pause_for_sleep() {
    if let Ok(conn) = db::open() {
        if let Ok(mut t) = timer().lock() {
            t.pause_for_sleep(&conn);
        }
    }
}

// ── Server ────────────────────────────────────────────────────────────────────

#[cfg(not(feature = "macos-native"))]
pub async fn run_ipc_server() {
    info!("IPC server starting");
    let listener = match ipc_transport::bind_listener() {
        Ok(l) => l,
        Err(e) => {
            error!("IPC bind failed (is another agentd running?): {e}");
            return;
        }
    };
    loop {
        match listener.accept().await {
            Ok(conn) => { tokio::spawn(serve_conn(conn)); }
            Err(e) => {
                error!("IPC accept: {e}");
                tokio::time::sleep(std::time::Duration::from_millis(200)).await;
            }
        }
    }
}

#[cfg(not(feature = "macos-native"))]
async fn serve_conn(conn: interprocess::local_socket::tokio::Stream) {
    let (reader, mut writer) = conn.split();
    let mut lines = BufReader::new(reader).lines();
    while let Ok(Some(line)) = lines.next_line().await {
        let resp = handle_request(&line).await;
        let out = serde_json::to_string(&resp).unwrap_or_default();
        if writer.write_all(format!("{out}\n").as_bytes()).await.is_err() {
            break;
        }
    }
}

/// Native EffiLens macOS agent: authenticated Unix-socket server.
#[cfg(feature = "macos-native")]
pub async fn run_ipc_server() {
    #[cfg(unix)]
    native_server::run().await;
    #[cfg(not(unix))]
    error!("the native EffiLens agent IPC server is only available on macOS");
}

#[cfg(all(feature = "macos-native", unix))]
mod native_server {
    use super::handle_request;
    use common::ipc_transport::{native, IpcRequest, IpcResponse};
    use std::sync::Arc;
    use tokio::io::{AsyncWriteExt, BufReader};
    use tracing::{error, info, warn};

    /// Holds the single-instance lock; removes socket + token on drop
    /// (graceful shutdown aborts the server future, which drops this).
    struct ServerGuard {
        _lock: std::fs::File,
    }

    impl Drop for ServerGuard {
        fn drop(&mut self) {
            native::cleanup();
            info!("native IPC server stopped; socket removed");
        }
    }

    pub async fn run() {
        if let Err(e) = native::ensure_private_dir() {
            error!("IPC: cannot prepare data dir: {e}");
            return;
        }
        let lock = match std::fs::OpenOptions::new()
            .create(true)
            .truncate(false)
            .write(true)
            .open(native::lock_path())
        {
            Ok(f) => f,
            Err(e) => {
                error!("IPC: cannot open lock file: {e}");
                return;
            }
        };
        if lock.try_lock().is_err() {
            error!("another EffiLens agent holds the lock — exiting duplicate instance");
            std::process::exit(0);
        }
        let listener = match native::bind_listener() {
            Ok(l) => l,
            Err(e) => {
                error!("IPC bind failed: {e}");
                return;
            }
        };
        let token = match native::rotate_token() {
            Ok(t) => Arc::new(t),
            Err(e) => {
                error!("IPC token creation failed: {e}");
                native::cleanup();
                return;
            }
        };
        let uid = match native::owner_uid() {
            Ok(u) => u,
            Err(e) => {
                error!("IPC: cannot resolve owner uid: {e}");
                native::cleanup();
                return;
            }
        };
        let _guard = ServerGuard { _lock: lock };
        info!("native IPC server listening");

        loop {
            match listener.accept().await {
                Ok((stream, _)) => {
                    // Peer identity: only processes of the same user may talk to us.
                    let same_user = stream.peer_cred().map(|c| c.uid() == uid).unwrap_or(false);
                    if !same_user {
                        warn!("IPC: rejected connection from a different user");
                        continue;
                    }
                    tokio::spawn(serve(stream, token.clone()));
                }
                Err(e) => {
                    error!("IPC accept: {e}");
                    tokio::time::sleep(std::time::Duration::from_millis(200)).await;
                }
            }
        }
    }

    async fn serve(stream: tokio::net::UnixStream, token: Arc<String>) {
        let (reader, mut writer) = stream.into_split();
        let mut reader = BufReader::new(reader);
        loop {
            let line = match native::read_bounded_line(&mut reader, native::MAX_LINE_BYTES).await {
                Ok(Some(line)) => line,
                Ok(None) => break,
                Err(e) => {
                    let _ = respond(&mut writer, &IpcResponse::err(e.to_string())).await;
                    break;
                }
            };
            let authorized = serde_json::from_str::<IpcRequest>(&line)
                .map(|r| native::token_matches(&token, r.auth.as_deref()))
                .unwrap_or(false);
            if !authorized {
                warn!("IPC: rejected unauthenticated request");
                let _ = respond(&mut writer, &IpcResponse::err("unauthorized")).await;
                break;
            }
            let resp = handle_request(&line).await;
            if respond(&mut writer, &resp).await.is_err() {
                break;
            }
        }
    }

    async fn respond(writer: &mut tokio::net::unix::OwnedWriteHalf, resp: &IpcResponse) -> std::io::Result<()> {
        let out = serde_json::to_string(resp).unwrap_or_default();
        writer.write_all(format!("{out}\n").as_bytes()).await
    }
}

/// Native-agent commands: session hand-off from the SwiftUI app and
/// permission preflight. The account-isolation semantics of the existing
/// `clear_local_data` command are reused, not re-implemented.
#[cfg(feature = "macos-native")]
mod native_cmds {
    use super::{timer, with_conn};
    use common::db::{self, queries};
    use common::ipc_transport::IpcResponse;
    use common::timer_service::TimerService;

    #[derive(serde::Deserialize)]
    struct SessionPayload {
        access_token: String,
        user_id: String,
        tenant_id: String,
        api_base_url: String,
    }

    pub async fn set_session(payload: Option<serde_json::Value>) -> IpcResponse {
        let Some(p) = payload.and_then(|v| serde_json::from_value::<SessionPayload>(v).ok()) else {
            return IpcResponse::err("invalid set_session payload");
        };
        if p.access_token.trim().is_empty()
            || uuid::Uuid::parse_str(&p.user_id).is_err()
            || uuid::Uuid::parse_str(&p.tenant_id).is_err()
        {
            return IpcResponse::err("invalid set_session payload");
        }
        // Never send the token anywhere except the API this agent is built for.
        let expected = common::api::api("");
        let expected_origin = expected.trim_end_matches("/api/v1").trim_end_matches('/');
        if p.api_base_url.trim_end_matches('/') != expected_origin {
            return IpcResponse::err("api_base_url does not match the agent's configured API");
        }

        let conn = match db::open() {
            Ok(c) => c,
            Err(e) => return IpcResponse::err(e.to_string()),
        };
        // A different account signing in: wipe the previous account's local
        // cache first (same rule as the logout path).
        let previous = queries::get_config(&conn, "user_id").unwrap_or_default();
        if !previous.is_empty() && previous != p.user_id {
            timer().lock().unwrap().stop(&conn);
            if let Err(e) = queries::clear_local_activity_data(&conn) {
                return IpcResponse::err(e.to_string());
            }
            *timer().lock().unwrap() = TimerService::new();
        }
        // Agent refresh rotates the bearer itself, so no separate refresh token.
        if let Err(e) = common::auth::session_store::save_tokens(&p.access_token, Some("")) {
            return IpcResponse::err(e.to_string());
        }
        let _ = queries::set_config(&conn, "user_id", &p.user_id);
        let _ = queries::set_config(&conn, "tenant_id", &p.tenant_id);
        drop(conn);

        // Pull config + assignments now instead of waiting for the sync cadence.
        // Uses the sync loop's own routine so the organisation's policy
        // (screenshots on/off + interval, blur, idle threshold, sync
        // intervals, retention) applies immediately after sign-in — not only
        // the task list.
        // rusqlite::Connection is !Sync, so the sync runs on a blocking
        // thread with its own runtime (this handler's future must be Send).
        let synced = tokio::task::spawn_blocking(|| -> anyhow::Result<()> {
            let rt = tokio::runtime::Builder::new_current_thread().enable_all().build()?;
            rt.block_on(async {
                let client = common::api::build_client()?;
                let conn = db::open()?;
                crate::sync_loop::sync_config_and_assignments(&client, &conn).await
            })
        })
        .await;
        match synced {
            Ok(Ok(())) => {}
            Ok(Err(e)) => tracing::warn!("set_session: config sync deferred to the sync loop: {e}"),
            Err(e) => tracing::warn!("set_session: config sync task failed: {e}"),
        }
        // go-agent parity: upload anything queued right after authentication
        // instead of waiting up to one batch interval (default 5 min).
        let _ = crate::sync_loop::request_sync_now();
        IpcResponse::ok(serde_json::json!({"ok": true}))
    }

    /// Sign-out: stop tracking, wipe local activity (the existing
    /// clear_local_data semantics), and forget the agent token.
    pub fn clear_session() -> IpcResponse {
        with_conn(|conn| {
            timer().lock().unwrap().stop(conn);
            queries::clear_local_activity_data(conn)?;
            *timer().lock().unwrap() = TimerService::new();
            common::auth::session_store::clear()?;
            queries::set_config(conn, "user_id", "")?;
            queries::set_config(conn, "tenant_id", "")?;
            Ok(serde_json::json!({"ok": true}))
        })
    }

    /// Registers the agent in the missing Privacy & Security lists (it is
    /// the capturing process and has its own TCC identity), then returns a
    /// fresh preflight.
    pub fn request_permissions() -> IpcResponse {
        #[cfg(target_os = "macos")]
        {
            match serde_json::to_value(common::platform::request_missing_permissions()) {
                Ok(v) => IpcResponse::ok(v),
                Err(e) => IpcResponse::err(e.to_string()),
            }
        }
        #[cfg(not(target_os = "macos"))]
        {
            IpcResponse::err("permissions are only available on macOS")
        }
    }

    pub fn get_permissions() -> IpcResponse {
        #[cfg(target_os = "macos")]
        {
            match serde_json::to_value(common::platform::permissions()) {
                Ok(v) => IpcResponse::ok(v),
                Err(e) => IpcResponse::err(e.to_string()),
            }
        }
        #[cfg(not(target_os = "macos"))]
        {
            IpcResponse::err("permissions are only available on macOS")
        }
    }
}

// ── Command handlers ──────────────────────────────────────────────────────────

async fn handle_request(line: &str) -> IpcResponse {
    let req: IpcRequest = match serde_json::from_str(line) {
        Ok(r) => r,
        Err(e) => return IpcResponse::err(e.to_string()),
    };
    // Never let the native agent and the legacy Tauri agent track at once.
    #[cfg(all(feature = "macos-native", unix))]
    if matches!(req.cmd.as_str(), "toggle_play_pause" | "select_task")
        && common::ipc_transport::native::legacy_agent_running()
    {
        return IpcResponse::err("legacy_agent_running: quit the older EffiLens app before tracking here");
    }
    match req.cmd.as_str() {
        "ping" => IpcResponse::ok(serde_json::json!("pong")),
        "get_state" => get_state(),
        "toggle_play_pause" => with_conn(|conn| {
            timer().lock().unwrap().resume_last_task(conn);
            Ok(serde_json::json!({"ok": true}))
        }),
        "select_task" => select_task(req.payload),
        "start_break" => start_break(req.payload),
        "stop_tracking" => with_conn(|conn| {
            timer().lock().unwrap().stop(conn);
            Ok(serde_json::json!({"ok": true}))
        }),
        // Called on logout, after stop_tracking: the local DB is a single
        // file per OS-user profile shared by whichever WorkPulse account is
        // currently logged in, so leftover rows here would otherwise leak
        // into (and get synced under) the next account that logs in.
        "clear_local_data" => with_conn(|conn| {
            queries::clear_local_activity_data(conn)?;
            *timer().lock().unwrap() = TimerService::new();
            Ok(serde_json::json!({"ok": true}))
        }),
        "idle_keep_working" => idle_response(false),
        "idle_auto_stop" => idle_response(true),
        "get_assigned_tasks" => with_conn(|conn| {
            let tasks = queries::get_assigned_tasks(conn)?;
            Ok(serde_json::to_value(&tasks)?)
        }),
        "get_time_stats" => with_conn(|conn| {
            let (today, week, month, sessions, meeting_today) = queries::get_time_stats_local(conn)?;
            // Add the current in-progress session's not-yet-flushed meeting
            // seconds so the KPI updates live rather than waiting for the
            // next ~5-minute flush_active() cycle to persist it.
            let live_meeting = timer().lock().map(|t| t.meeting_secs() as i64).unwrap_or(0);
            Ok(serde_json::json!({
                "worked_today_sec": today,
                "worked_week_sec": week,
                "worked_month_sec": month,
                "sessions_today": sessions,
                "meeting_today_sec": meeting_today + live_meeting,
            }))
        }),
        "get_task_times_today" => with_conn(|conn| {
            let rows = queries::get_task_times_today(conn)?;
            Ok(serde_json::to_value(rows.into_iter().collect::<std::collections::HashMap<_,_>>())?)
        }),
        "get_recent_events" => {
            let limit = req.payload.as_ref()
                .and_then(|p| p["limit"].as_u64()).unwrap_or(12) as usize;
            with_conn(move |conn| {
                let events = queries::get_recent_events(conn, limit)?;
                Ok(serde_json::to_value(&events)?)
            })
        }
        "get_sync_status" => IpcResponse::ok(crate::sync_loop::status_json()),
        "sync_now" => sync_now().await,
        "get_consent_status" => get_consent_status().await,
        "accept_consent" => accept_consent(req.payload).await,
        #[cfg(feature = "macos-native")]
        "set_session" => native_cmds::set_session(req.payload).await,
        #[cfg(feature = "macos-native")]
        "clear_session" => native_cmds::clear_session(),
        #[cfg(feature = "macos-native")]
        "get_permissions" => native_cmds::get_permissions(),
        #[cfg(feature = "macos-native")]
        "request_permissions" => native_cmds::request_permissions(),
        _ => IpcResponse::err(format!("unknown command: {}", req.cmd)),
    }
}

fn with_conn<F>(f: F) -> IpcResponse
where F: FnOnce(&rusqlite::Connection) -> anyhow::Result<serde_json::Value> {
    match db::open() {
        Ok(conn) => match f(&conn) {
            Ok(v) => IpcResponse::ok(v),
            Err(e) => IpcResponse::err(e.to_string()),
        },
        Err(e) => IpcResponse::err(e.to_string()),
    }
}

fn get_state() -> IpcResponse {
    let t = timer().lock().unwrap();
    let state = t.state();
    let task = state.active_task().map(|task| serde_json::json!({
        "task_id": task.task_id,
        "project_id": task.project_id,
        "task_name": task.task_name,
        "project_name": task.project_name,
    }));
    let (break_type, break_remaining) = match state {
        TimerState::OnBreak { kind, break_started, .. } => {
            let used = break_started.elapsed().as_secs();
            (Some(kind.display().to_string()),
             Some(kind.duration_secs().saturating_sub(used)))
        }
        _ => (None, None),
    };
    IpcResponse::ok(serde_json::json!({
        "state": state.state_name(),
        "task": task,
        "elapsed_secs": t.display_elapsed(),
        "break_type": break_type,
        "break_remaining_secs": break_remaining,
        "idle_warning": t.idle_warning(),
        "idle_since_secs": t.idle_since_secs(),
        "in_meeting": crate::capture_loop::is_in_meeting(),
    }))
}

fn select_task(payload: Option<serde_json::Value>) -> IpcResponse {
    let p = payload.unwrap_or_default();
    let task = (|| {
        Some(Task {
            task_id: p["task_id"].as_str()?.parse().ok()?,
            project_id: p["project_id"].as_str()?.parse().ok()?,
            task_name: p["task_name"].as_str()?.to_string(),
            project_name: p["project_name"].as_str()?.to_string(),
        })
    })();
    let Some(task) = task else {
        return IpcResponse::err("select_task requires task_id, project_id, task_name, project_name");
    };
    with_conn(|conn| {
        timer().lock().unwrap().select_task(conn, task);
        Ok(serde_json::json!({"ok": true}))
    })
}

fn start_break(payload: Option<serde_json::Value>) -> IpcResponse {
    let p = payload.unwrap_or_default();
    let kind = match p["break_type"].as_str().unwrap_or("coffee") {
        "coffee" => BreakKind::Coffee,
        "lunch" => BreakKind::Lunch,
        other => BreakKind::Custom(
            other.to_string(),
            p["duration_secs"].as_u64().unwrap_or(600),
        ),
    };
    with_conn(|conn| {
        timer().lock().unwrap().start_break(conn, kind);
        Ok(serde_json::json!({"ok": true}))
    })
}

/// Shared idle-warning resolution. Records an `idle` activity event covering
/// the span, then either keeps working (idle deducted) or stops back-dated.
fn idle_response(auto_stop: bool) -> IpcResponse {
    with_conn(|conn| {
        let mut t = timer().lock().unwrap();
        if let Some(w) = t.idle_warning() {
            record_idle_event(conn, w.started_ts);
        }
        if auto_stop {
            t.idle_auto_stop(conn);
        } else {
            t.idle_keep_working(conn);
        }
        Ok(serde_json::json!({"ok": true}))
    })
}

fn record_idle_event(conn: &rusqlite::Connection, idle_start: i64) {
    let (Some(user_id), Some(tenant_id)) = (
        queries::get_config(conn, "user_id").and_then(|s| s.parse::<Uuid>().ok()),
        queries::get_config(conn, "tenant_id").and_then(|s| s.parse::<Uuid>().ok()),
    ) else { return };
    let now = chrono::Utc::now().timestamp();
    let ev = ActivityEvent {
        event_uuid: Uuid::new_v4(),
        user_id,
        tenant_id,
        event_type: "idle".into(),
        ts: idle_start,
        duration_sec: (now - idle_start).max(0),
        payload: serde_json::json!({ "idle_start": idle_start, "idle_end": now }),
    };
    let _ = queries::insert_event(conn, &ev);
}

async fn sync_now() -> IpcResponse {
    // Delegate to the sync loop's own thread — it already owns a `Connection`
    // (which is `!Send` and can't be opened/awaited-across here, since this
    // handler runs on the IPC server's multi-threaded runtime).
    match crate::sync_loop::request_sync_now() {
        Some(rx) => match rx.await {
            Ok(Ok(())) => IpcResponse::ok(serde_json::json!({"ok": true})),
            Ok(Err(e)) => IpcResponse::err(e),
            Err(_) => IpcResponse::err("sync loop did not respond"),
        },
        None => IpcResponse::err("sync loop not ready yet"),
    }
}

async fn get_consent_status() -> IpcResponse {
    let client = match common::api::build_client() {
        Ok(c) => c,
        Err(e) => return IpcResponse::err(e.to_string()),
    };
    match common::api::consent::get_status(&client).await {
        Ok(status) => IpcResponse::ok(serde_json::to_value(&status).unwrap_or_default()),
        Err(e) => IpcResponse::err(e.to_string()),
    }
}

async fn accept_consent(payload: Option<serde_json::Value>) -> IpcResponse {
    let version = payload.as_ref()
        .and_then(|p| p["policy_version"].as_i64())
        .unwrap_or(1);
    let client = match common::api::build_client() {
        Ok(c) => c,
        Err(e) => return IpcResponse::err(e.to_string()),
    };
    match common::api::consent::accept(&client, version).await {
        Ok(()) => {
            if let Ok(conn) = db::open() {
                let _ = queries::set_config(&conn, "consent_accepted_version", &version.to_string());
            }
            IpcResponse::ok(serde_json::json!({"ok": true}))
        }
        Err(e) => IpcResponse::err(e.to_string()),
    }
}
