//! Window-control commands invoked from the webview (the main window's React
//! app watches timer state and drives the idle-warning / mini-widget windows).

use tauri::command;

#[command]
pub fn show_mini_widget(app: tauri::AppHandle) -> Result<(), String> {
    crate::windows::show_mini_widget(&app).map_err(|e| e.to_string())
}

#[command]
pub fn hide_mini_widget(app: tauri::AppHandle) -> Result<(), String> {
    crate::windows::hide_mini_widget(&app).map_err(|e| e.to_string())
}

/// What the title bar's minimize button actually calls. Plain `hide_main_window`
/// + `show_mini_widget` (the old behaviour) always brought the mini widget back
/// even if the user had just explicitly hidden it — this respects that choice
/// instead, only showing the widget again if the user hasn't hidden it since.
#[command]
pub fn minimize_to_mini_widget(app: tauri::AppHandle) -> Result<(), String> {
    crate::windows::hide_main(&app).map_err(|e| e.to_string())?;
    if !crate::windows::mini_widget_user_hidden() {
        crate::windows::show_mini_widget(&app).map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[command]
pub fn show_idle_warning(app: tauri::AppHandle) -> Result<(), String> {
    crate::windows::show_idle_warning(&app).map_err(|e| e.to_string())
}

#[command]
pub fn close_idle_warning(app: tauri::AppHandle) -> Result<(), String> {
    crate::windows::close_idle_warning(&app).map_err(|e| e.to_string())
}

#[command]
pub fn show_main_window(app: tauri::AppHandle) -> Result<(), String> {
    crate::windows::show_main(&app).map_err(|e| e.to_string())
}

#[command]
pub fn hide_main_window(app: tauri::AppHandle) -> Result<(), String> {
    crate::windows::hide_main(&app).map_err(|e| e.to_string())
}

#[command]
pub fn quit_app(app: tauri::AppHandle) {
    app.exit(0);
}

/// Lets the webview report a JS-side crash (React error boundary, unhandled
/// rejection, window "error" event) straight to stdout/stderr — the only
/// place a dev running `tauri dev` is actually watching. Secondary windows
/// (mini widget, idle warning) render blank on a JS crash with no other way
/// to surface the reason short of manually opening devtools on that specific
/// window at the right moment.
#[command]
pub fn log_frontend_error(window: String, message: String) {
    eprintln!("[frontend error] window={window}: {message}");
}

/// Opens the shared logs directory (agentd.log / app.log / crash.log) in the
/// OS file browser — the only way a user can see these once release builds
/// stopped printing to a console window.
#[command]
pub fn open_logs_folder(app: tauri::AppHandle) -> Result<(), String> {
    use tauri_plugin_shell::ShellExt;
    let dir = common::db::logs_dir();
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    app.shell().open(dir.to_string_lossy().to_string(), None).map_err(|e| e.to_string())
}
