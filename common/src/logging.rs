//! Shared logging + crash-log setup for `agentd` and the Tauri `app` binary.
//!
//! Both binaries build with `windows_subsystem = "windows"` in release (no
//! console window), which means stdout goes nowhere — writing tracing output
//! only to stdout would leave the user with zero visibility into what the
//! background process is doing, and zero record of why it crashed. This
//! mirrors the Python agent's `src/core/logger.py`: a rotating log file plus
//! a dedicated crash.log, both under the per-user log directory surfaced by
//! the tray's "Open Logs Folder" action.
//!
//! Rotation is daily (tracing-appender has no built-in size-based rotation);
//! the Python agent's log volume was low enough that size-based rotation was
//! mostly about avoiding an unbounded file, so daily rotation of a
//! comparably low-volume log serves the same purpose.

use std::io;
use std::path::Path;
use std::sync::Mutex;
use tracing_appender::non_blocking::WorkerGuard;

/// Must be kept alive for the process lifetime — dropping it stops the
/// background flush thread and the file writer silently goes idle.
pub struct LoggingGuard(#[allow(dead_code)] WorkerGuard);

/// Initialize tracing: rotating file under `common::db::logs_dir()`, plus
/// stdout in debug builds (so `cargo run` / `agentd debug` still work as
/// before). Also installs a panic hook that appends to `crash.log` so a
/// panic is never silently lost once the console window is gone.
pub fn init(component: &str) -> LoggingGuard {
    let dir = crate::db::logs_dir();
    let _ = std::fs::create_dir_all(&dir);

    let file_appender = tracing_appender::rolling::daily(&dir, format!("{component}.log"));
    let (non_blocking, guard) = tracing_appender::non_blocking(file_appender);

    use tracing_subscriber::prelude::*;
    let file_layer = tracing_subscriber::fmt::layer()
        .with_writer(non_blocking)
        .with_ansi(false);
    let filter = tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info"));

    let registry = tracing_subscriber::registry().with(filter).with(file_layer);

    #[cfg(debug_assertions)]
    {
        registry.with(tracing_subscriber::fmt::layer()).init();
    }
    #[cfg(not(debug_assertions))]
    {
        registry.init();
    }

    install_crash_hook(dir.join("crash.log"), component.to_string());

    LoggingGuard(guard)
}

fn install_crash_hook(crash_log_path: std::path::PathBuf, component: String) {
    let path = Mutex::new(crash_log_path);
    let default_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        if let Ok(p) = path.lock() {
            let _ = append_crash_entry(&p, &component, info);
        }
        default_hook(info);
    }));
}

fn append_crash_entry(path: &Path, component: &str, info: &std::panic::PanicHookInfo) -> io::Result<()> {
    use std::io::Write;
    let mut f = std::fs::OpenOptions::new().create(true).append(true).open(path)?;
    let ts = chrono::Utc::now().to_rfc3339();
    let location = info.location().map(|l| l.to_string()).unwrap_or_else(|| "unknown".into());
    let message = info.payload().downcast_ref::<&str>().map(|s| s.to_string())
        .or_else(|| info.payload().downcast_ref::<String>().cloned())
        .unwrap_or_else(|| "<non-string panic payload>".into());
    writeln!(f, "{ts} | {component} | PANIC at {location}: {message}")?;
    Ok(())
}
