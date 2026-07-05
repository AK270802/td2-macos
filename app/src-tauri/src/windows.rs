use tauri::{AppHandle, Manager, WebviewUrl, WebviewWindowBuilder};

#[allow(dead_code)]
pub fn show_main(app: &AppHandle) -> tauri::Result<()> {
    if let Some(win) = app.get_webview_window("main") {
        win.show()?;
        win.set_focus()?;
    } else {
        WebviewWindowBuilder::new(app, "main", WebviewUrl::App("index.html".into()))
            .title("WorkPulse")
            .inner_size(980.0, 660.0)
            .min_inner_size(900.0, 560.0)
            .decorations(false)
            .build()?;
    }
    Ok(())
}

#[allow(dead_code)]
pub fn show_mini_widget(app: &AppHandle) -> tauri::Result<()> {
    if let Some(win) = app.get_webview_window("mini") {
        win.show()?;
    } else {
        WebviewWindowBuilder::new(app, "mini", WebviewUrl::App("mini.html".into()))
            .title("WorkPulse Mini")
            .inner_size(320.0, 52.0)
            .decorations(false)
            .always_on_top(true)
            .skip_taskbar(true)
            .build()?;
    }
    Ok(())
}

#[allow(dead_code)]
pub fn show_idle_warning(app: &AppHandle) -> tauri::Result<()> {
    if app.get_webview_window("idle_warning").is_none() {
        WebviewWindowBuilder::new(app, "idle_warning", WebviewUrl::App("idle_warning.html".into()))
            .title("Idle Warning")
            .inner_size(420.0, 260.0)
            .decorations(false)
            .always_on_top(true)
            .build()?;
    }
    Ok(())
}
