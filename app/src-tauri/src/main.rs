#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;
mod tray;
mod windows;
mod theme;

fn main() {
    tracing_subscriber::fmt::init();
    workpulse_app_lib::run();
}
