//! 1-second capture tick.
//!
//! Privacy: nothing is recorded unless the timer is RUNNING (tracking is
//! user-initiated and capture stops the moment the session does), and browser
//! URLs are reduced to eTLD+1 in-memory before anything touches the database.

use anyhow::Result;
use tracing::info;
use common::{
    capture::{app_tracker, browser_tracker, meeting::MeetingDetector, screenshot::{self, ScreenshotOptions}},
    db::{self, queries},
    idle::IdleDetector,
    models::ActivityEvent,
    platform,
};
use std::sync::atomic::{AtomicBool, Ordering};
use uuid::Uuid;

static IN_MEETING: AtomicBool = AtomicBool::new(false);

/// Read by the IPC `get_state` handler so the UI can show a meeting badge.
pub fn is_in_meeting() -> bool {
    IN_MEETING.load(Ordering::Relaxed)
}

struct CaptureConfig {
    capture_interval: u64,
    screenshot_interval: u64,
    idle_threshold: u64,
    blur_radius: f32,
    screenshots_enabled: bool,
    track_apps: bool,
    track_input: bool,
}

fn load_config(conn: &rusqlite::Connection) -> CaptureConfig {
    CaptureConfig {
        capture_interval: queries::get_config_u64(conn, "capture_interval_sec", 30),
        screenshot_interval: queries::get_config_u64(conn, "screenshot_interval_sec", 600),
        idle_threshold: queries::get_config_u64(conn, "idle_threshold_sec", 300),
        blur_radius: queries::get_config(conn, "blur_radius")
            .and_then(|s| s.parse::<f32>().ok()).unwrap_or(8.0),
        screenshots_enabled: queries::get_config_bool(conn, "screenshots_enabled", true),
        track_apps: queries::get_config_bool(conn, "track_apps", true),
        track_input: queries::get_config_bool(conn, "track_input", true),
    }
}

pub async fn run() {
    loop {
        if let Err(e) = run_inner().await {
            tracing::error!("Capture loop error, restarting in 10s: {e}");
        }
        tokio::time::sleep(std::time::Duration::from_secs(10)).await;
    }
}

async fn run_inner() -> Result<()> {
    let conn = db::open()?;
    let mut cfg = load_config(&conn);
    let mut idle = IdleDetector::new(cfg.idle_threshold);
    let mut meeting = MeetingDetector::new();
    let mut in_meeting = false;

    let mut last_screenshot = std::time::Instant::now();
    let mut last_capture = std::time::Instant::now();
    let mut last_tick = std::time::Instant::now();
    let mut last_input_totals = (0u32, 0u32, 0f64);
    let mut tick_count: u64 = 0;

    info!("Capture loop running (interval={}s)", cfg.capture_interval);
    loop {
        tokio::time::sleep(std::time::Duration::from_secs(1)).await;
        tick_count += 1;

        // Sleep detection: >90s between 1-second ticks means the machine slept.
        if last_tick.elapsed().as_secs() > 90 {
            crate::ipc::pause_for_sleep();
        }
        last_tick = std::time::Instant::now();

        // Live-reload config every 30s (server pushes + settings changes).
        if tick_count.is_multiple_of(30) {
            cfg = load_config(&conn);
            idle.threshold_secs = cfg.idle_threshold;
        }

        let ids: Option<(Uuid, Uuid)> = (|| {
            Some((
                queries::get_config(&conn, "user_id")?.parse().ok()?,
                queries::get_config(&conn, "tenant_id")?.parse().ok()?,
            ))
        })();

        let sample = if cfg.track_input { idle.tick() } else {
            idle.reset_counts();
            common::idle::InputSample { keystroke_count: 0, mouse_click_count: 0, mouse_distance_px: 0.0 }
        };

        let running = crate::ipc::timer().lock().map(|t| t.is_running()).unwrap_or(false);
        let idle_ms = platform::idle_ms();

        // ── Meeting detection (5s cadence) ───────────────────────────────────
        if tick_count.is_multiple_of(5) {
            in_meeting = meeting.evaluate(running);
            IN_MEETING.store(in_meeting, Ordering::Relaxed);
            if running {
                let secs = meeting.session_meeting_secs();
                if secs > 0 {
                    meeting.reset_session_meeting_secs();
                    if let Ok(mut t) = crate::ipc::timer().lock() {
                        t.add_meeting_seconds(secs);
                    }
                }
            }
        }

        // ── Idle warning flow ────────────────────────────────────────────────
        // Suppressed while in a meeting — muting the mic / stepping away from
        // the keyboard during a call is not "idle", mirroring the Python
        // agent's meeting_tracker.is_in_meeting guard.
        {
            let mut t = crate::ipc::timer().lock().unwrap();
            if running && !in_meeting && idle_ms >= cfg.idle_threshold * 1000 {
                // Back-date idle start to when input actually stopped.
                let idle_started = chrono::Utc::now().timestamp() - (idle_ms / 1000) as i64;
                t.on_idle_threshold(idle_started);
            }
            if t.idle_warning().is_some() {
                if idle_ms < 2000 {
                    // User came back before responding — keep the span as
                    // attributed idle time rather than dropping the warning.
                    t.idle_keep_working(&conn);
                } else {
                    t.tick_idle_warning();
                }
            }
        }

        // Everything below records data — only while clocked in.
        let Some((user_id, tenant_id)) = ids else { continue };
        if !running { continue; }

        // ── App + browser + input events on the capture interval ────────────
        if last_capture.elapsed().as_secs() >= cfg.capture_interval {
            let elapsed = last_capture.elapsed().as_secs().min(cfg.capture_interval * 2) as i64;
            last_capture = std::time::Instant::now();

            let app = app_tracker::get_foreground_app();

            if cfg.track_apps {
                if let Some(ref app) = app {
                    let ev = ActivityEvent {
                        event_uuid: Uuid::new_v4(),
                        user_id,
                        tenant_id,
                        event_type: "app".into(),
                        ts: chrono::Utc::now().timestamp(),
                        duration_sec: elapsed,
                        payload: app_tracker::to_event_payload(app),
                    };
                    let _ = queries::insert_event(&conn, &ev);

                    // Browser domain (eTLD+1 only, extracted in-memory).
                    if browser_tracker::is_browser(&app.process_name) {
                        if let Some(url) = platform::browser_url(app) {
                            if let Some(domain) = browser_tracker::extract_domain(&url) {
                                let ev = ActivityEvent {
                                    event_uuid: Uuid::new_v4(),
                                    user_id,
                                    tenant_id,
                                    event_type: "browser".into(),
                                    ts: chrono::Utc::now().timestamp(),
                                    duration_sec: elapsed,
                                    payload: serde_json::json!({
                                        "domain": domain,
                                        "process_name": app.process_name,
                                    }),
                                };
                                let _ = queries::insert_event(&conn, &ev);
                                let _ = queries::touch_domain(&conn, &domain);
                            }
                        }
                    }
                }
            }

            // Input counts — only the delta since the last flush.
            if cfg.track_input {
                let (dk, dc, dd) = (
                    sample.keystroke_count.saturating_sub(last_input_totals.0),
                    sample.mouse_click_count.saturating_sub(last_input_totals.1),
                    (sample.mouse_distance_px - last_input_totals.2).max(0.0),
                );
                if dk > 0 || dc > 0 {
                    let ev = ActivityEvent {
                        event_uuid: Uuid::new_v4(),
                        user_id,
                        tenant_id,
                        event_type: "input".into(),
                        ts: chrono::Utc::now().timestamp(),
                        duration_sec: elapsed,
                        payload: serde_json::json!({
                            "keystroke_count": dk,
                            "mouse_click_count": dc,
                            "mouse_distance_px": dd as i64,
                        }),
                    };
                    let _ = queries::insert_event(&conn, &ev);
                }
                last_input_totals = (sample.keystroke_count, sample.mouse_click_count, sample.mouse_distance_px);
                if sample.keystroke_count > 100_000 {
                    idle.reset_counts();
                    last_input_totals = (0, 0, 0.0);
                }
            }
        }

        // ── Screenshot on its own interval ───────────────────────────────────
        if cfg.screenshots_enabled && last_screenshot.elapsed().as_secs() >= cfg.screenshot_interval {
            last_screenshot = std::time::Instant::now();
            let app = app_tracker::get_foreground_app();
            let opts = ScreenshotOptions { blur_radius: cfg.blur_radius, ..ScreenshotOptions::default() };
            let task_id = crate::ipc::active_task_id().map(|u| u.to_string());
            match screenshot::capture_and_save(
                &db::screenshots_dir(),
                app.as_ref().map(|a| a.app_name.clone()),
                app.as_ref().map(|a| a.window_title.clone()),
                app.as_ref().and_then(|a| a.rect),
                &opts,
                sample.keystroke_count,
                sample.mouse_click_count,
            ) {
                Ok(cap) => {
                    let _ = queries::insert_screenshot(
                        &conn, &cap.uuid, cap.ts,
                        &cap.path.to_string_lossy(),
                        cap.app_name.as_deref(), cap.window_title.as_deref(),
                        task_id.as_deref(),
                    );
                }
                Err(e) => tracing::warn!("Screenshot failed: {e}"),
            }
        }

        // ── Crash-recovery checkpoint every 60s ──────────────────────────────
        if tick_count.is_multiple_of(60) {
            if let Ok(t) = crate::ipc::timer().lock() {
                t.checkpoint(&conn);
            }
        }
    }
}
