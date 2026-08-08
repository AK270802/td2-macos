//! WorkPulse agentd — user-session background process.
//!
//! Capture APIs (foreground window, last-input, screen) are only valid inside
//! the interactive user session, and the SQLCipher key + auth tokens live in
//! the *user's* keychain — so agentd must run per-user on every platform:
//! Windows Run-key autostart, macOS LaunchAgent, Linux systemd --user.
//! (A session-0 SYSTEM service cannot see the user desktop at all.)
//!
//! No console window in release builds — agentd is spawned silently by the
//! Tauri app (and by the autostart Run-key entry) and must never flash a
//! visible cmd.exe window at the user. `cargo run -p agentd -- debug` from an
//! existing terminal is unaffected: `windows_subsystem = "windows"` only
//! suppresses allocation of a NEW console, it doesn't detach from one that's
//! already there.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod capture_loop;
mod ipc;
mod sync_loop;

use anyhow::Result;
use tracing::info;

async fn run_agent_loops(shutdown: std::sync::Arc<std::sync::atomic::AtomicBool>) -> Result<()> {
    info!("WorkPulse agentd starting");

    // Single-instance guard: if another agentd already answers, exit quietly.
    if common::ipc_transport::request("ping", None).await.is_ok() {
        info!("agentd already running — exiting duplicate instance");
        return Ok(());
    }

    let db = common::db::open()?;
    let client = common::api::build_client()?;

    // Crash recovery: persist any checkpointed session from an unclean stop
    // as an "interrupted" time log (≤60s of loss), then clear the checkpoint.
    common::timer_service::TimerService::recover_crashed_session(&db);

    // Startup: fetch config before UI is shown
    if let Ok((_config, tasks, identity)) = common::api::agent::get_config(&client).await {
        common::db::queries::upsert_assigned_tasks(&db, &tasks)?;
        if let Some(uid) = &identity.user_id {
            let _ = common::db::queries::set_config(&db, "user_id", uid);
        }
        if let Some(tid) = &identity.tenant_id {
            let _ = common::db::queries::set_config(&db, "tenant_id", tid);
        }
        info!("Startup config fetched, {} tasks", tasks.len());
    }

    // Spawn IPC server (Send-safe, stays on tokio)
    let ipc_handle = tokio::spawn(ipc::run_ipc_server());

    // rusqlite::Connection is !Send; run each loop on its own OS thread
    // with a single-threaded runtime so the connection never crosses threads.
    std::thread::Builder::new().name("capture".into()).spawn(move || {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all().build().expect("capture rt");
        rt.block_on(capture_loop::run());
    })?;
    std::thread::Builder::new().name("sync".into()).spawn(move || {
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all().build().expect("sync rt");
        rt.block_on(sync_loop::run());
    })?;

    // Heartbeat until shutdown
    while !shutdown.load(std::sync::atomic::Ordering::SeqCst) {
        tokio::time::sleep(std::time::Duration::from_secs(5)).await;
    }

    // Clean stop: close the running session so no checkpoint is left behind.
    if let Ok(mut t) = ipc::timer().lock() {
        t.stop(&db);
    }
    ipc_handle.abort();
    info!("WorkPulse agentd stopped");
    Ok(())
}

fn run_foreground() -> Result<()> {
    let rt = tokio::runtime::Runtime::new()?;
    let shutdown = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    let s2 = shutdown.clone();
    ctrlc::set_handler(move || { s2.store(true, std::sync::atomic::Ordering::SeqCst); })?;
    rt.block_on(run_agent_loops(shutdown))
}

/// Register agentd in the per-user autostart (HKCU Run key on Windows).
#[cfg(windows)]
fn install_autostart() -> Result<()> {
    let exe = std::env::current_exe()?;
    std::process::Command::new("reg")
        .args([
            "add", r"HKCU\Software\Microsoft\Windows\CurrentVersion\Run",
            "/v", "WorkPulseAgentd", "/t", "REG_SZ",
            "/d", &format!("\"{}\" run", exe.display()),
            "/f",
        ])
        .output()?;
    println!("agentd autostart registered for the current user");
    Ok(())
}

#[cfg(windows)]
fn remove_autostart() -> Result<()> {
    let _ = std::process::Command::new("reg")
        .args(["delete", r"HKCU\Software\Microsoft\Windows\CurrentVersion\Run",
               "/v", "WorkPulseAgentd", "/f"])
        .output();
    println!("agentd autostart removed");
    Ok(())
}

fn main() -> Result<()> {
    // Held for the whole process lifetime — dropping it stops log flushing.
    let _logging_guard = common::logging::init("agentd");

    let args: Vec<String> = std::env::args().collect();
    let cmd = args.get(1).map(|s| s.as_str()).unwrap_or("run");

    match cmd {
        // "run" (default) and legacy "debug" both run in the foreground of
        // the user session — the only place desktop capture works.
        "run" | "debug" => run_foreground()?,
        #[cfg(windows)]
        "install" => install_autostart()?,
        #[cfg(windows)]
        "remove" => remove_autostart()?,
        _ => eprintln!("Usage: agentd [run|install|remove]"),
    }
    Ok(())
}
