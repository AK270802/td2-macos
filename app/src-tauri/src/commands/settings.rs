#![allow(dead_code)]
use tauri::command;
use common::db::{self, queries};

const AUTOSTART_KEY: &str = "WorkPulse";
const RUN_REG: &str = r"HKCU\Software\Microsoft\Windows\CurrentVersion\Run";

#[command]
pub fn get_autostart() -> bool {
    std::process::Command::new("reg")
        .args(["query", RUN_REG, "/v", AUTOSTART_KEY])
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

#[command]
pub fn set_autostart(enabled: bool) -> Result<(), String> {
    if enabled {
        let exe = std::env::current_exe().map_err(|e| e.to_string())?;
        let exe_str = exe.to_string_lossy().to_string();
        std::process::Command::new("reg")
            .args(["add", RUN_REG, "/v", AUTOSTART_KEY, "/t", "REG_SZ", "/d", &exe_str, "/f"])
            .output().map_err(|e| e.to_string())?;
    } else {
        let _ = std::process::Command::new("reg")
            .args(["delete", RUN_REG, "/v", AUTOSTART_KEY, "/f"])
            .output();
    }
    Ok(())
}

#[command]
pub fn get_settings() -> Result<serde_json::Value, String> {
    let conn = db::open().map_err(|e| e.to_string())?;
    Ok(serde_json::json!({
        "screenshots_enabled": queries::get_config(&conn, "screenshots_enabled").unwrap_or("true".into()),
        "blur_radius": queries::get_config(&conn, "blur_radius").unwrap_or("8".into()),
        "idle_threshold_sec": queries::get_config(&conn, "idle_threshold_sec").unwrap_or("300".into()),
        "capture_interval_sec": queries::get_config(&conn, "capture_interval_sec").unwrap_or("30".into()),
    }))
}

#[command]
pub fn save_settings(key: String, value: String) -> Result<(), String> {
    let conn = db::open().map_err(|e| e.to_string())?;
    queries::set_config(&conn, &key, &value).map_err(|e| e.to_string())
}
