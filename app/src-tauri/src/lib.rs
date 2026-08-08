mod commands;
mod tray;
mod updater;
mod windows;

use tauri_plugin_notification::NotificationExt;

/// agentd lives in the user session (desktop capture is impossible from a
/// service). If it isn't answering, spawn the copy that ships next to this
/// executable (installed layout) or the workspace build (dev layout).
fn ensure_agentd_running() {
    tauri::async_runtime::spawn(async {
        if common::ipc_transport::request("ping", None).await.is_ok() {
            return;
        }
        let exe_name = if cfg!(windows) { "agentd.exe" } else { "agentd" };
        let candidates: Vec<std::path::PathBuf> = std::env::current_exe()
            .ok()
            .and_then(|p| p.parent().map(|d| d.to_path_buf()))
            .map(|dir| vec![
                dir.join(exe_name),                                   // installed
                dir.join("resources").join(exe_name),                 // installed (resource dir)
                dir.join("../../../target/release").join(exe_name),   // dev
                dir.join("../../../target/debug").join(exe_name),     // dev
            ])
            .unwrap_or_default();
        for path in candidates {
            if path.exists() {
                match std::process::Command::new(&path).arg("run").spawn() {
                    Ok(_) => {
                        tracing::info!("spawned agentd from {}", path.display());
                        return;
                    }
                    Err(e) => tracing::warn!("failed to spawn agentd at {}: {e}", path.display()),
                }
            }
        }
        tracing::warn!("agentd binary not found — timer will show as offline");
    });
}

const NOT_TRACKING_THRESHOLD_SECS: u64 = 600; // nudge after 10 min idle
const REMINDER_COOLDOWN_SECS: u64 = 600; // don't repeat more than every 10 min

/// Background watcher — lives for the app process's whole lifetime,
/// independent of which window (if any) is currently visible, so it still
/// works while the user is on the mini widget or the main window is hidden
/// to tray. Polls agentd's timer state and:
///   - focuses the main window the moment tracking stops, so the user
///     notices and can pick a new task;
///   - nudges with an OS notification if nothing has been tracked for a
///     while even though the machine is in active use;
///   - mirrors an in-app idle warning (timer running, no input) as an OS
///     notification too, in case the always-on-top window isn't noticed.
fn start_reminder_watcher(app: tauri::AppHandle) {
    tauri::async_runtime::spawn(async move {
        let mut prev_state: Option<String> = None;
        let mut last_not_tracking_reminder: Option<std::time::Instant> = None;
        let mut idle_warning_notified = false;

        loop {
            tokio::time::sleep(std::time::Duration::from_secs(20)).await;

            let Ok(data) = common::ipc_transport::request("get_state", None).await else {
                prev_state = None; // agentd unreachable — re-arm cleanly once it's back
                continue;
            };
            let state = data["state"].as_str().unwrap_or("idle").to_string();
            let idle_since_secs = data["idle_since_secs"].as_u64();
            let has_idle_warning = !data["idle_warning"].is_null();

            // Tracking just stopped (running/paused/on_break → idle): surface
            // the app so the user notices and can start a new task.
            if let Some(prev) = &prev_state {
                if prev != "idle" && state == "idle" {
                    let _ = crate::windows::show_main(&app);
                    let _ = app.notification().builder()
                        .title("Tracking stopped")
                        .body("Pick a task in EffiLens to keep your hours accurate.")
                        .show();
                    last_not_tracking_reminder = Some(std::time::Instant::now());
                }
            }

            // Periodic "you're not tracking anything" nudge while idle.
            if state == "idle" {
                if let Some(secs) = idle_since_secs {
                    let due = secs >= NOT_TRACKING_THRESHOLD_SECS
                        && last_not_tracking_reminder
                            .is_none_or(|t| t.elapsed().as_secs() >= REMINDER_COOLDOWN_SECS);
                    if due {
                        let _ = app.notification().builder()
                            .title("Still there?")
                            .body("You're not tracking any task right now.")
                            .show();
                        last_not_tracking_reminder = Some(std::time::Instant::now());
                    }
                }
            } else {
                last_not_tracking_reminder = None;
            }

            // Idle-while-running: the in-app idle_warning window already
            // shows (useTimerState drives it), but mirror it as an OS
            // notification once per occurrence in case that window is
            // missed (other monitor, alt-tabbed away, etc).
            if has_idle_warning && !idle_warning_notified {
                let _ = app.notification().builder()
                    .title("Are you still working?")
                    .body("No input detected — this session may pause soon.")
                    .show();
            }
            idle_warning_notified = has_idle_warning;

            prev_state = Some(state);
        }
    });
}

pub fn run() {
    tauri::Builder::default()
        // Must be the first plugin registered: when a second instance is
        // launched (double-click, autostart racing a manual launch, etc.)
        // this callback fires in the ALREADY-RUNNING process and the new
        // process exits immediately — otherwise every launch spawns its own
        // window set and its own agentd-spawn attempt, which is exactly the
        // "multiple EffiLens instances" duplication this prevents.
        .plugin(tauri_plugin_single_instance::init(|app, _argv, _cwd| {
            let _ = crate::windows::show_main(app);
        }))
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None,
        ))
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .setup(|app| {
            tray::setup_tray(app)?;
            ensure_agentd_running();
            start_reminder_watcher(app.handle().clone());
            updater::spawn_background_checks(app.handle().clone());

            #[cfg(debug_assertions)]
            if std::env::var("WORKPULSE_DEBUG_OPEN_MINI").is_ok() {
                let handle = app.handle().clone();
                tauri::async_runtime::spawn(async move {
                    tokio::time::sleep(std::time::Duration::from_secs(3)).await;
                    let _ = crate::windows::show_mini_widget(&handle);
                });
            }

            // CmdOrCtrl+Shift+K: summon EffiLens with the task switcher open.
            use tauri_plugin_global_shortcut::{GlobalShortcutExt, ShortcutState};
            let handle = app.handle().clone();
            let _ = app.global_shortcut().on_shortcut("CommandOrControl+Shift+K", move |_app, _sc, event| {
                if event.state() == ShortcutState::Pressed {
                    let _ = crate::windows::show_main(&handle);
                    let _ = tauri::Emitter::emit(&handle, "open-task-switcher", ());
                }
            });
            Ok(())
        })
        .on_window_event(|window, event| {
            // Closing the main window hides to tray — tracking continues in
            // agentd. Quit is explicit via tray menu or the in-app dialog.
            if window.label() == "main" {
                if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                    api.prevent_close();
                    let _ = window.hide();
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            commands::ipc::send_ipc,
            commands::ipc::get_timer_state,
            commands::ipc::toggle_play_pause,
            commands::ipc::select_task,
            commands::auth::login,
            commands::auth::logout,
            commands::auth::get_session,
            commands::auth::get_consent_status,
            commands::auth::accept_consent,
            commands::settings::get_settings,
            commands::settings::save_settings,
            commands::settings::check_for_updates,
            commands::settings::get_autostart,
            commands::settings::set_autostart,
            commands::windows::show_mini_widget,
            commands::windows::hide_mini_widget,
            commands::windows::minimize_to_mini_widget,
            commands::windows::show_idle_warning,
            commands::windows::close_idle_warning,
            commands::windows::show_main_window,
            commands::windows::hide_main_window,
            commands::windows::quit_app,
            commands::windows::open_logs_folder,
            commands::windows::log_frontend_error,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
