# WorkPulse Agent — Architecture

## Overview

Two co-operating processes built from a single Rust workspace:

| Process | Binary | Role |
|---------|--------|------|
| `agentd(.exe)` | `agentd/` crate | Background capture & sync — a USER-SESSION process on every platform (HKLM Run autostart on Windows, LaunchAgent on macOS, systemd --user on Linux). A session-0 service cannot see the interactive desktop, and the DB key + tokens live in the user's keychain. |
| `workpulse-app(.exe)` | `app/src-tauri/` + `app/src/` | Tauri desktop UI (React in the system WebView) |

Shared logic lives in `common/`. The two processes share one SQLCipher
database on disk and communicate over a local socket (`common::ipc_transport`
— named pipe on Windows, Unix domain socket on macOS/Linux).

## Workspace Layout

```
workpulse-rust/
├── Cargo.toml            # Workspace root (resolver = "2")
├── agentd/src/
│   ├── main.rs           # Service entry, crash recovery, loop spawning
│   ├── capture_loop.rs   # 1s tick: app/browser/input/idle/screenshot
│   ├── sync_loop.rs      # 5-min batches, retries, config pull, prune, SyncStatus
│   └── ipc.rs            # IPC server + TimerService singleton
├── common/src/
│   ├── timer_state.rs    # Pure timer state machine (fully unit-tested)
│   ├── timer_service.rs  # Persistence glue: StateEvents → DB rows, idle/break accounting
│   ├── ipc_transport.rs  # Cross-platform local socket, shared client/server
│   ├── idle.rs           # Input sampling (counts only) + idle_ms
│   ├── platform/         # OS backends: windows_impl / macos_impl / linux_impl
│   ├── api/              # HTTP client — mirrors core-services /api/v1 exactly
│   ├── auth/             # Keychain session store
│   ├── capture/          # app_tracker, browser_tracker (eTLD+1), screenshot
│   └── db/               # schema, queries, sync_queue (backoff), key_manager (CSPRNG)
└── app/
    ├── src/              # React (Vite): pages, windows, components, hooks
    └── src-tauri/        # Tauri shell: commands, tray, window mgmt, NSIS hooks
```

## Key Data Flows

### Capture (`capture_loop`, 1s tick)
1. Sleep detect: tick gap > 90s → pause timer via TimerService.
2. Config live-reload every 30s (server-pushed + local settings apply without restart).
3. **Nothing is recorded unless the timer is RUNNING** (user-initiated tracking).
4. Every `capture_interval_sec` (default 30): app event; browser-domain event
   (eTLD+1 extracted in-memory); input-count delta event.
5. Idle: `idle_ms ≥ idle_threshold` → back-dated idle warning on the
   TimerService → UI shows the idle window; keep-working attributes the span
   to `idle_sec`, break/expiry stops the session back-dated to idle start.
6. Every `screenshot_interval_sec` (default 600): active-window crop → scale
   → Gaussian blur → activity-count overlay → JPEG ladder (60/40/25, ≤150 KB).
7. Every 60s: crash-recovery checkpoint (`active_tracking_session`).

### Sync (`sync_loop`, 30s tick; every cycle error-guarded — the loop cannot die)
- Every `batch_sync_interval_min` (default 5): up to 500 events + unsynced
  task_time_logs → `POST /activity/batch`. 2xx → mark synced; 4xx → drop with
  warning; 429/5xx/network → retry queue with backoff `min(2^n·60, 1800)`s,
  max 10 retries. Retries resend **that batch's** still-unsynced events.
- 401 anywhere → one-shot token refresh + retry (built into the API layer).
- Screenshots: ≤50/cycle multipart upload (app_name, window_title, task_id,
  captured_at_client), local file deleted only after confirmed 200.
- Every `assignment_sync_interval_min` (default 20): `GET /agent/config` →
  persist operational config + identity, upsert assigned tasks, prune stale
  (never the actively tracked task).
- Daily: prune synced data older than `retention_days`.
- Publishes `SyncStatus` (connected, last/next sync, pending count) → IPC
  `get_sync_status` → status bar.

### Timer
- Single source of truth: `common::timer_state::TimerState`
  (idle ⇄ running ⇄ paused ⇄ on_break) — the exact code covered by
  `timer_state_tests.rs` runs in production, wrapped by
  `common::timer_service::TimerService` which:
  - writes `task_time_logs` on every stop/switch (duration = active − idle;
    idle_sec / break_sec carried separately, matching TaskTimeLogIn),
  - checkpoints `active_tracking_session` (crash recovery ≤60s loss),
  - persists last-task config for resume.

### IPC Protocol
Local socket, newline-delimited JSON: `{cmd, payload?}` → `{ok, data, error}`.
Commands: `ping · get_state · toggle_play_pause · select_task · start_break ·
stop_tracking · idle_keep_working · idle_auto_stop · get_assigned_tasks ·
get_time_stats · get_task_times_today · get_recent_events · get_sync_status ·
sync_now · get_consent_status · accept_consent`

### Single instance + reminder watcher (Tauri app)
- `tauri-plugin-single-instance` is the first plugin registered: a second
  launch focuses the running instance's main window and exits instead of
  spawning a duplicate window/webview/agentd-probe set.
- A background task started in `.setup()` (`start_reminder_watcher`) polls
  `get_state` every 20s for the app process's whole lifetime — independent
  of which window is visible, so it still works while the user is on the
  mini widget or the main window is hidden to tray:
  - tracking stopping (running/paused/on_break → idle) focuses the main
    window and fires an OS notification, so the user notices and can pick a
    new task;
  - idle with nothing tracked for ≥10 min (while the machine is in active
    use) nudges with an OS notification, cooling down for 10 min between
    repeats;
  - an in-app idle-warning (timer running, no input) is mirrored as an OS
    notification once per occurrence, in case the always-on-top window is
    missed.

## Database Schema (SQLCipher, key = 32 CSPRNG bytes in OS keychain)

| Table | Purpose |
|-------|---------|
| `events` | app/browser/input/idle/tracking_* events; `synced` flag |
| `screenshots` | metadata + path; `uploaded` flag; task_id |
| `sync_queue` | batch retry queue (pending/retry/done/failed) |
| `agent_config` | KV: server config, identity, last task, UI settings |
| `assigned_tasks` | denormalised task picker cache |
| `task_time_logs` | sessions: duration/idle/break seconds; `synced` flag |
| `active_tracking_session` | single-row crash-recovery checkpoint |
| `domain_cache` | seen browser domains |

## Platform Matrix

| Capability | Windows | macOS | Linux (X11) |
|---|---|---|---|
| Foreground app | WinAPI (native) | osascript (needs Accessibility) | xdotool |
| Idle ms | GetLastInputInfo | ioreg HIDIdleTime | xprintidle |
| Input counts | GetAsyncKeyState (counts only) | inferred from idle resets | inferred from idle resets |
| Browser domain | UI Automation | AppleScript (Chrome/Safari/Edge/Brave/Arc) | not in v1 |
| Screenshot | xcap + window crop | xcap (needs Screen Recording) | xcap |
| Background process | HKLM Run autostart (user session) | LaunchAgent (user) | systemd --user |
| Autostart | tauri-plugin-autostart | tauri-plugin-autostart | tauri-plugin-autostart |
| Installer | NSIS (.exe) | dmg (CI) | deb (CI; depends xdotool, xprintidle) |

Wayland foreground/idle capture is a documented v1 gap.

## Offline Resilience

The agent is designed to keep working with zero internet:
- **Login**: only the very first sign-in on a device needs the network
  (credentials must be verified server-side). Every subsequent launch reads
  the cached session from the OS keychain + local DB (`get_session`) with no
  network round-trip — offline restarts do not force a re-login.
- **Capture**: `capture_loop` never calls the network; app/browser/input
  events and the running timer's `task_time_logs` write to the local
  SQLCipher DB unconditionally once a session exists.
- **Sync**: `sync_loop` treats every network failure as retryable (backoff
  queue, never data loss) and reconnection is automatic — nothing needs to
  be manually re-triggered, though `sync_now` exists for an immediate flush.
- **UI honesty**: the status bar shows two independent indicators — `agent`
  (local IPC reachability) and `cloud sync` (backend/internet reachability)
  — so losing internet never reads as "tracking stopped."

## Window routing

Secondary windows (`mini`, `idle_warning`) load the same `index.html` as
`main` but with `?window=mini`/`?window=idle_warning` baked into the URL at
creation time (`windows.rs`). The frontend (`main.tsx`) reads that query
param synchronously before falling back to `getCurrentWindow().label` —
deliberately not relying on the Tauri JS bridge alone, since a window
silently defaulting to "main" would render the entire Login/Main app inside
a 264×50 widget frame instead of failing visibly.

## Privacy Constraints (non-negotiable)

- Keystrokes: integer counts only — never key identity or content.
- URLs: eTLD+1 only, reduced in-memory; the raw URL is never persisted.
- Screenshots: active-window crop, blurred before any disk write.
- Timer: user-initiated only; zero capture outside a running session.
- Consent: gated server-side (`/consent/status`) before the dashboard loads.
