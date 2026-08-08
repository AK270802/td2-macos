//! Linux/X11 backend via `xdotool` and `xprintidle` (declared as package
//! dependencies of the .deb). Wayland compositors that don't expose global
//! window info are a documented limitation for v1.

use super::ForegroundWindow;
use std::process::Command;

fn run(cmd: &str, args: &[&str]) -> Option<String> {
    let out = Command::new(cmd).args(args).output().ok()?;
    if !out.status.success() { return None; }
    let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if s.is_empty() { None } else { Some(s) }
}

pub fn foreground_window() -> Option<ForegroundWindow> {
    let wid = run("xdotool", &["getactivewindow"])?;
    let window_title = run("xdotool", &["getwindowname", &wid]).unwrap_or_default();
    let pid = run("xdotool", &["getwindowpid", &wid])?;
    let exe_path = std::fs::read_link(format!("/proc/{pid}/exe"))
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_default();
    let process_name = std::fs::read_to_string(format!("/proc/{pid}/comm"))
        .map(|s| s.trim().to_lowercase())
        .unwrap_or_default();
    if process_name.is_empty() { return None; }
    Some(ForegroundWindow {
        app_name: process_name.clone(),
        process_name,
        exe_path,
        window_title: window_title.chars().take(200).collect(),
        rect: None,
        native_handle: 0,
    })
}

pub fn idle_ms() -> u64 {
    run("xprintidle", &[])
        .and_then(|s| s.parse::<u64>().ok())
        .unwrap_or(0)
}

pub fn browser_url(_win: &ForegroundWindow) -> Option<String> {
    // AT-SPI2 URL reads are not implemented in v1 — domain tracking is
    // Windows/macOS only on Linux for now.
    None
}

pub fn enumerate_windows() -> Vec<super::WindowInfo> {
    // No native window-enumeration binding in v1; meeting detection on Linux
    // degrades to the foreground-app signal only.
    Vec::new()
}
