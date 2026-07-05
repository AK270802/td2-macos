mod commands;
mod tray;
mod windows;
mod theme;

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_notification::init())
        .setup(|app| {
            tray::setup_tray(app)?;
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::ipc::send_ipc,
            commands::ipc::get_timer_state,
            commands::ipc::toggle_play_pause,
            commands::ipc::select_task,
            commands::auth::login,
            commands::auth::logout,
            commands::auth::get_session,
            commands::settings::get_settings,
            commands::settings::save_settings,
            commands::settings::get_autostart,
            commands::settings::set_autostart,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
