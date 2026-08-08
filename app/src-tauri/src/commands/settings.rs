use tauri::command;
use tauri_plugin_autostart::ManagerExt;
use common::db::{self, queries};

#[command]
pub fn get_autostart(app: tauri::AppHandle) -> bool {
    app.autolaunch().is_enabled().unwrap_or(false)
}

#[command]
pub fn set_autostart(app: tauri::AppHandle, enabled: bool) -> Result<(), String> {
    let autolaunch = app.autolaunch();
    if enabled {
        autolaunch.enable().map_err(|e| e.to_string())
    } else {
        autolaunch.disable().map_err(|e| e.to_string())
    }
}

#[command]
pub fn get_settings() -> Result<serde_json::Value, String> {
    let conn = db::open().map_err(|e| e.to_string())?;
    let get = |key: &str, default: &str| queries::get_config(&conn, key).unwrap_or_else(|| default.into());
    Ok(serde_json::json!({
        "screenshots_enabled": get("screenshots_enabled", "true"),
        "blur_radius": get("blur_radius", "8"),
        "idle_threshold_sec": get("idle_threshold_sec", "300"),
        "capture_interval_sec": get("capture_interval_sec", "30"),
        "screenshot_interval_sec": get("screenshot_interval_sec", "600"),
        "track_input": get("track_input", "true"),
        "track_apps": get("track_apps", "true"),
        "idle_alerts_enabled": get("idle_alerts_enabled", "true"),
        "break_reminders_enabled": get("break_reminders_enabled", "true"),
        "daily_summary_enabled": get("daily_summary_enabled", "false"),
        "sound_enabled": get("sound_enabled", "true"),
        "sync_errors_enabled": get("sync_errors_enabled", "true"),
        "theme": get("theme", "dark"),
        "portal_url": get("portal_url", "https://dev-workpulse.baseel.com"),
    }))
}

#[command]
pub fn save_settings(key: String, value: String) -> Result<(), String> {
    // Whitelist: only UI-owned settings keys may be written from the webview.
    const ALLOWED: &[&str] = &[
        "screenshots_enabled", "blur_radius", "idle_threshold_sec",
        "screenshot_interval_sec", "track_input", "track_apps",
        "idle_alerts_enabled", "break_reminders_enabled",
        "daily_summary_enabled", "sound_enabled", "sync_errors_enabled",
        "theme",
    ];
    if !ALLOWED.contains(&key.as_str()) {
        return Err(format!("setting not writable: {key}"));
    }
    let conn = db::open().map_err(|e| e.to_string())?;
    queries::set_config(&conn, &key, &value).map_err(|e| e.to_string())
}

/// Manual "Check for updates" from Settings — same path as the tray menu
/// item, just reachable from inside the main window too. Always notifies
/// (unlike the silent 6-hourly background loop) so clicking the button
/// gives feedback either way, including "you're already current".
#[command]
pub async fn check_for_updates(app: tauri::AppHandle) {
    crate::updater::check_and_install(&app, true).await;
}
