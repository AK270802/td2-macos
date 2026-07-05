/// Read Windows registry to determine system theme (light=1, dark=0).
#[cfg(windows)]
#[allow(dead_code)]
pub fn system_prefers_dark() -> bool {
    use std::process::Command;
    // reg query returns AppsUseLightTheme; 0x0 = dark, 0x1 = light
    let out = Command::new("reg")
        .args(["query",
               r"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
               "/v", "AppsUseLightTheme"])
        .output()
        .ok();
    if let Some(output) = out {
        let text = String::from_utf8_lossy(&output.stdout);
        return text.contains("0x0");
    }
    false
}

#[cfg(not(windows))]
pub fn system_prefers_dark() -> bool { false }

/// Apply Mica/Acrylic vibrancy to a window (Windows 11+).
#[cfg(windows)]
#[allow(dead_code)]
pub fn apply_vibrancy(window: &tauri::WebviewWindow) {
    use window_vibrancy::apply_mica;
    let _ = apply_mica(window, Some(true));
}

#[cfg(not(windows))]
pub fn apply_vibrancy(_window: &tauri::WebviewWindow) {}
