#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    // Held for the whole process lifetime — dropping it stops log flushing.
    // Release builds run with no console (windows_subsystem = "windows"
    // above), so without this, tracing output would go nowhere and a crash
    // would leave no trace at all.
    let _logging_guard = common::logging::init("app");
    workpulse_app_lib::run();
}
