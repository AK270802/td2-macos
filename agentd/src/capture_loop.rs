use anyhow::Result;
use tracing::info;
use common::{
    capture::app_tracker,
    capture::screenshot::{self, ScreenshotOptions},
    db::{self, queries},
    idle::IdleDetector,
    models::ActivityEvent,
};
use uuid::Uuid;

pub async fn run() {
    if let Err(e) = run_inner().await {
        tracing::error!("Capture loop error: {e}");
    }
}

async fn run_inner() -> Result<()> {
    let conn = db::open()?;
    let user_id: Uuid = queries::get_config(&conn, "user_id")
        .and_then(|s| s.parse().ok()).unwrap_or_default();
    let tenant_id: Uuid = queries::get_config(&conn, "tenant_id")
        .and_then(|s| s.parse().ok()).unwrap_or_default();

    let capture_interval = queries::get_config(&conn, "capture_interval_sec")
        .and_then(|s| s.parse().ok()).unwrap_or(30u64);
    let screenshot_interval = queries::get_config(&conn, "screenshot_interval_sec")
        .and_then(|s| s.parse().ok()).unwrap_or(600u64);
    let idle_threshold = queries::get_config(&conn, "idle_threshold_sec")
        .and_then(|s| s.parse().ok()).unwrap_or(300u64);

    let mut idle = IdleDetector::new(idle_threshold);
    let mut last_screenshot = std::time::Instant::now();
    let mut last_capture = std::time::Instant::now();
    let mut last_tick = std::time::Instant::now();

    info!("Capture loop running (interval={}s)", capture_interval);
    loop {
        tokio::time::sleep(std::time::Duration::from_secs(1)).await;

        // Sleep detection: if more than 90s elapsed since last 1-second tick, system slept.
        let tick_gap = last_tick.elapsed().as_secs();
        if tick_gap > 90 {
            crate::ipc::pause_for_sleep();
        }
        last_tick = std::time::Instant::now();

        let sample = idle.tick();

        // App capture on interval
        if last_capture.elapsed().as_secs() >= capture_interval {
            last_capture = std::time::Instant::now();
            if let Some(app) = app_tracker::get_foreground_app() {
                let ev = ActivityEvent {
                    event_uuid: Uuid::new_v4(),
                    user_id,
                    tenant_id,
                    event_type: "app".into(),
                    ts: chrono::Utc::now().timestamp(),
                    duration_sec: capture_interval as i64,
                    payload: app_tracker::to_event_payload(&app),
                };
                let _ = queries::insert_event(&conn, &ev);
            }
            // Write input event if any activity
            if sample.keystroke_count > 0 || sample.mouse_click_count > 0 {
                let ev = ActivityEvent {
                    event_uuid: Uuid::new_v4(),
                    user_id, tenant_id,
                    event_type: "input".into(),
                    ts: chrono::Utc::now().timestamp(),
                    duration_sec: capture_interval as i64,
                    payload: serde_json::json!({
                        "keystroke_count": sample.keystroke_count,
                        "mouse_click_count": sample.mouse_click_count,
                        "mouse_distance_px": sample.mouse_distance_px as i64,
                    }),
                };
                let _ = queries::insert_event(&conn, &ev);
                idle.reset_counts();
            }
        }

        // Screenshot on interval
        if last_screenshot.elapsed().as_secs() >= screenshot_interval {
            last_screenshot = std::time::Instant::now();
            let screenshots_dir = db::screenshots_dir();
            let opts = ScreenshotOptions {
                blur_radius: queries::get_config(&conn, "blur_radius")
                    .and_then(|s| s.parse::<f32>().ok()).unwrap_or(8.0),
                ..ScreenshotOptions::default()
            };
            let app = app_tracker::get_foreground_app();
            match screenshot::capture_and_save(
                &screenshots_dir,
                app.as_ref().map(|a| a.app_name.clone()),
                app.as_ref().map(|a| a.window_title.clone()),
                &opts,
                sample.keystroke_count,
                sample.mouse_click_count,
            ) {
                Ok(cap) => {
                    conn.execute(
                        "INSERT OR IGNORE INTO screenshots (uuid,ts,file_path,app_name,window_title,uploaded) VALUES (?1,?2,?3,?4,?5,0)",
                        rusqlite::params![
                            cap.uuid.to_string(), cap.ts,
                            cap.path.to_string_lossy().to_string(),
                            cap.app_name, cap.window_title
                        ],
                    ).ok();
                }
                Err(e) => tracing::warn!("Screenshot failed: {e}"),
            }
        }
    }
}
