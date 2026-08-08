//! macOS backend via `osascript`/`ioreg` subprocesses — no native SDK
//! bindings. Requires the Accessibility permission (System Settings →
//! Privacy & Security) which the app requests during onboarding.

use super::ForegroundWindow;
use std::process::Command;

fn osascript(script: &str) -> Option<String> {
    let out = Command::new("osascript").args(["-e", script]).output().ok()?;
    if !out.status.success() { return None; }
    let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if s.is_empty() { None } else { Some(s) }
}

pub fn foreground_window() -> Option<ForegroundWindow> {
    let app_name = osascript(
        r#"tell application "System Events" to get name of first application process whose frontmost is true"#,
    )?;
    let window_title = osascript(
        r#"tell application "System Events" to try
            get name of front window of (first application process whose frontmost is true)
        on error
            ""
        end try"#,
    ).unwrap_or_default();
    let process_name = app_name.to_lowercase();
    Some(ForegroundWindow {
        app_name: app_name.clone(),
        process_name,
        exe_path: String::new(),
        window_title: window_title.chars().take(200).collect(),
        rect: None,
        native_handle: 0,
    })
}

pub fn idle_ms() -> u64 {
    // HIDIdleTime is reported in nanoseconds.
    let out = match Command::new("sh")
        .args(["-c", "ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print $NF; exit}'"])
        .output()
    {
        Ok(o) => o,
        Err(_) => return 0,
    };
    String::from_utf8_lossy(&out.stdout)
        .trim()
        .parse::<u64>()
        .map(|ns| ns / 1_000_000)
        .unwrap_or(0)
}

pub fn browser_url(win: &ForegroundWindow) -> Option<String> {
    // Scriptable browsers only; Firefox exposes no AppleScript URL API.
    let script = match win.process_name.as_str() {
        "google chrome" | "chrome" => r#"tell application "Google Chrome" to get URL of active tab of front window"#,
        "safari" => r#"tell application "Safari" to get URL of front document"#,
        "microsoft edge" | "edge" => r#"tell application "Microsoft Edge" to get URL of active tab of front window"#,
        "brave browser" | "brave" => r#"tell application "Brave Browser" to get URL of active tab of front window"#,
        "arc" => r#"tell application "Arc" to get URL of active tab of front window"#,
        _ => return None,
    };
    osascript(script)
}

pub fn enumerate_windows() -> Vec<super::WindowInfo> {
    // No native window-enumeration binding in v1; meeting detection on macOS
    // degrades to the foreground-app signal only.
    Vec::new()
}
