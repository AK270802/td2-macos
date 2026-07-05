use tauri::{
    App,
    menu::{Menu, MenuItem, PredefinedMenuItem},
    tray::TrayIconBuilder,
};

#[allow(dead_code)]
pub fn setup_tray(app: &mut App) -> tauri::Result<()> {
    let quit = MenuItem::with_id(app, "quit", "Quit WorkPulse", true, None::<&str>)?;
    let open = MenuItem::with_id(app, "open", "Open WorkPulse", true, None::<&str>)?;
    let pause = MenuItem::with_id(app, "pause_resume", "Pause Tracking", true, None::<&str>)?;
    let sep = PredefinedMenuItem::separator(app)?;
    let settings = MenuItem::with_id(app, "settings", "Settings", true, None::<&str>)?;

    let menu = Menu::with_items(app, &[&open, &sep, &pause, &settings, &sep, &quit])?;

    TrayIconBuilder::new()
        .menu(&menu)
        .tooltip("WorkPulse")
        .on_menu_event(|app, event| match event.id.as_ref() {
            "quit" => app.exit(0),
            "open" => { let _ = crate::windows::show_main(app); }
            "pause_resume" => {
                tauri::async_runtime::spawn(async move {
                    let _ = crate::commands::ipc::toggle_play_pause().await;
                });
            }
            "settings" => { let _ = crate::windows::show_main(app); }
            _ => {}
        })
        .build(app)?;
    Ok(())
}
