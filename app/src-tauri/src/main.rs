#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    // Works around a persistent WebView2 blank-paint bug seen on some
    // GPU/driver configs, where secondary webviews (mini widget, idle
    // warning, and even the DevTools webview itself) never composite a
    // frame — all the resize-nudge tricks in windows.rs are a workaround
    // for the SAME underlying issue, kept as a second layer of defense.
    // Must be set before Tauri creates the WebView2 environment (i.e.
    // before `run()`), since WebView2 only reads this env var at
    // environment-creation time.
    #[cfg(target_os = "windows")]
    std::env::set_var("WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS", "--disable-gpu --disable-gpu-compositing");

    // Held for the whole process lifetime — dropping it stops log flushing.
    // Release builds run with no console (windows_subsystem = "windows"
    // above), so without this, tracing output would go nowhere and a crash
    // would leave no trace at all.
    let _logging_guard = common::logging::init("app");
    workpulse_app_lib::run();
}
