use tauri::{
    App,
    menu::{Menu, MenuItem, PredefinedMenuItem},
    tray::{TrayIconBuilder, TrayIconEvent},
};

pub fn setup_tray(app: &mut App) -> tauri::Result<()> {
    let open = MenuItem::with_id(app, "open", "Open EffiLens", true, None::<&str>)?;
    let mini = MenuItem::with_id(app, "mini", "Show mini timer", true, None::<&str>)?;
    let mini_hide = MenuItem::with_id(app, "mini_hide", "Hide mini timer", true, None::<&str>)?;
    let pause = MenuItem::with_id(app, "pause_resume", "Play / pause tracking", true, None::<&str>)?;
    let break_ = MenuItem::with_id(app, "break", "Start a break", true, None::<&str>)?;
    let sep1 = PredefinedMenuItem::separator(app)?;
    let check_updates = MenuItem::with_id(app, "check_updates", "Check for updates", true, None::<&str>)?;
    let logs = MenuItem::with_id(app, "open_logs", "Open logs folder", true, None::<&str>)?;
    let sep2 = PredefinedMenuItem::separator(app)?;
    let sep3 = PredefinedMenuItem::separator(app)?;
    let quit = MenuItem::with_id(app, "quit", "Quit EffiLens", true, None::<&str>)?;

    let menu = Menu::with_items(app, &[&open, &mini, &mini_hide, &sep1, &pause, &break_, &sep2, &check_updates, &logs, &sep3, &quit])?;

    TrayIconBuilder::with_id("workpulse_tray")
        .icon(app.default_window_icon().unwrap().clone())
        .menu(&menu)
        .show_menu_on_left_click(false)
        .tooltip("EffiLens")
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click { button: tauri::tray::MouseButton::Left, .. } = event {
                let _ = crate::windows::show_main(tray.app_handle());
            }
        })
        .on_menu_event(|app, event| match event.id.as_ref() {
            "quit" => {
                // Stop the running session cleanly, then exit.
                let handle = app.clone();
                tauri::async_runtime::spawn(async move {
                    let _ = common::ipc_transport::request("stop_tracking", None).await;
                    handle.exit(0);
                });
            }
            "open" => { let _ = crate::windows::show_main(app); }
            "mini" => { let _ = crate::windows::show_mini_widget(app); }
            "mini_hide" => { let _ = crate::windows::hide_mini_widget(app); }
            "check_updates" => {
                let handle = app.clone();
                tauri::async_runtime::spawn(async move {
                    crate::updater::check_and_install(&handle, true).await;
                });
            }
            "open_logs" => {
                let _ = crate::commands::windows::open_logs_folder(app.clone());
            }
            "pause_resume" => {
                tauri::async_runtime::spawn(async move {
                    let _ = common::ipc_transport::request("toggle_play_pause", None).await;
                });
            }
            "break" => {
                tauri::async_runtime::spawn(async move {
                    let _ = common::ipc_transport::request("start_break",
                        Some(serde_json::json!({"break_type": "coffee"}))).await;
                });
            }
            _ => {}
        })
        .build(app)?;
    Ok(())
}
