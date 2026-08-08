//! Background/manual auto-update checks via `tauri-plugin-updater`.
//!
//! The endpoint is built from the same `WORKPULSE_API_URL` the rest of the
//! app already resolves through `common::api::api` — pointing the app at a
//! local backend for testing also redirects update checks there, with no
//! separate env var to keep in sync. `{{target}}`/`{{arch}}`/
//! `{{current_version}}` are substituted by the plugin itself before the
//! request goes out; core-services' `/agent/update/...` route consumes them.

use tauri::AppHandle;
use tauri_plugin_notification::NotificationExt;
use tauri_plugin_updater::UpdaterExt;
use url::Url;

const BACKGROUND_CHECK_INTERVAL: std::time::Duration = std::time::Duration::from_secs(6 * 60 * 60);
// Give the UI a moment to paint before the first check's network I/O and
// (on the happy path) a download competes for bandwidth/CPU.
const STARTUP_DELAY: std::time::Duration = std::time::Duration::from_secs(30);

pub fn spawn_background_checks(app: AppHandle) {
    tauri::async_runtime::spawn(async move {
        tokio::time::sleep(STARTUP_DELAY).await;
        loop {
            check_and_install(&app, false).await;
            tokio::time::sleep(BACKGROUND_CHECK_INTERVAL).await;
        }
    });
}

/// Checks for an update and, if one exists, downloads, verifies (Ed25519
/// signature against the pubkey baked into `tauri.conf.json`), installs it,
/// and restarts the app. `notify_if_up_to_date` gates a "you're current"
/// notification — on for a manual tray click (so it gives feedback), off
/// for the silent background loop (so it doesn't nag every few hours).
pub async fn check_and_install(app: &AppHandle, notify_if_up_to_date: bool) {
    let endpoint = common::api::api("/agent/update/{{target}}/{{arch}}/{{current_version}}");
    let url: Url = match endpoint.parse() {
        Ok(u) => u,
        Err(e) => {
            tracing::warn!("updater endpoint invalid ({endpoint}): {e}");
            return;
        }
    };

    let builder = match app.updater_builder().endpoints(vec![url]) {
        Ok(b) => b,
        Err(e) => {
            tracing::warn!("updater endpoint config failed: {e}");
            return;
        }
    };
    let updater = match builder.build() {
        Ok(u) => u,
        Err(e) => {
            tracing::warn!("updater init failed: {e}");
            return;
        }
    };

    let update = match updater.check().await {
        Ok(u) => u,
        Err(e) => {
            tracing::warn!("update check failed: {e}");
            return;
        }
    };

    let Some(update) = update else {
        tracing::debug!("no update available");
        if notify_if_up_to_date {
            let _ = app.notification().builder()
                .title("EffiLens")
                .body("You're on the latest version.")
                .show();
        }
        return;
    };

    tracing::info!("update available: {}", update.version);
    let _ = app.notification().builder()
        .title("EffiLens update available")
        .body(format!(
            "Downloading version {} — EffiLens will restart shortly to install it.",
            update.version
        ))
        .show();

    // agentd is a separate process from this one and keeps tracking/syncing
    // through the restart below — only the UI shell briefly disappears and
    // reopens, exactly like a manual relaunch.
    if let Err(e) = update.download_and_install(|_chunk, _total| {}, || {}).await {
        tracing::warn!("update install failed: {e}");
        let _ = app.notification().builder()
            .title("EffiLens update failed")
            .body("Couldn't install the update. It'll retry automatically later.")
            .show();
        return;
    }

    tracing::info!("update installed — restarting");
    app.request_restart();
}
