//! Foreground-app capture — thin wrapper over the platform layer.

use serde_json::json;
pub use crate::platform::ForegroundWindow as ForegroundApp;

pub fn get_foreground_app() -> Option<ForegroundApp> {
    crate::platform::foreground_window()
}

pub fn to_event_payload(app: &ForegroundApp) -> serde_json::Value {
    json!({
        "app_name": app.app_name,
        "process_name": app.process_name,
        "exe_path": app.exe_path,
        "window_title": app.window_title,
    })
}
