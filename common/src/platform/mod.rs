//! OS-specific capture primitives behind one interface.
//!
//! Windows: native WinAPI (GetForegroundWindow / GetLastInputInfo / UIA).
//! macOS: subprocess best-effort (osascript, ioreg) — no native SDK bindings,
//!        so it degrades to None gracefully rather than failing to compile.
//! Linux: X11 tools (xdotool, xprintidle) best-effort; Wayland is a known gap.

#[cfg(windows)]
mod windows_impl;
// Always compiled on macOS: the native backend reuses its browser-URL table.
#[cfg(target_os = "macos")]
#[cfg_attr(feature = "macos-native", allow(dead_code))]
mod macos_impl;
#[cfg(all(target_os = "macos", feature = "macos-native"))]
mod macos_native;
#[cfg(all(unix, not(target_os = "macos")))]
mod linux_impl;

#[cfg(windows)]
use windows_impl as imp;
#[cfg(all(target_os = "macos", not(feature = "macos-native")))]
use macos_impl as imp;
#[cfg(all(target_os = "macos", feature = "macos-native"))]
use macos_native as imp;
#[cfg(all(unix, not(target_os = "macos")))]
use linux_impl as imp;

// Native-only capabilities used by idle.rs, screenshot.rs and agentd's IPC.
#[cfg(all(target_os = "macos", feature = "macos-native"))]
pub use macos_native::{capture_window, permissions, request_missing_permissions, take_input_counts, Permissions};

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct WindowRect {
    pub x: i32,
    pub y: i32,
    pub width: u32,
    pub height: u32,
}

#[derive(Debug, Clone)]
pub struct ForegroundWindow {
    pub app_name: String,
    pub process_name: String,
    pub exe_path: String,
    pub window_title: String,
    pub rect: Option<WindowRect>,
    /// Native window handle (HWND on Windows), for UIA browser-URL reads.
    pub native_handle: isize,
}

/// The focused window, or None when it can't be determined (lock screen,
/// excluded system process, missing OS tooling).
pub fn foreground_window() -> Option<ForegroundWindow> {
    imp::foreground_window()
}

/// Milliseconds since the last user input, 0 if unknown.
pub fn idle_ms() -> u64 {
    imp::idle_ms()
}

/// Full URL from the focused browser's address bar (caller extracts eTLD+1
/// immediately — the raw URL is never persisted).
pub fn browser_url(win: &ForegroundWindow) -> Option<String> {
    imp::browser_url(win)
}

/// A visible top-level window, tagged with its owning process's exe name.
/// Used by the meeting detector to spot call-in-progress titles (e.g. "Zoom
/// Meeting", "Meeting | Microsoft Teams") without depending on which window
/// currently has focus — a meeting can be running in the background while
/// the user works in another app.
#[derive(Debug, Clone)]
pub struct WindowInfo {
    /// Lowercased exe file name, e.g. "zoom.exe".
    pub process_name: String,
    pub title: String,
}

/// All visible top-level windows with a non-empty title. Best-effort: an
/// empty Vec on platforms/environments where enumeration isn't available
/// (macOS, Linux) rather than an error — meeting detection there degrades to
/// its other signals.
pub fn enumerate_windows() -> Vec<WindowInfo> {
    imp::enumerate_windows()
}
