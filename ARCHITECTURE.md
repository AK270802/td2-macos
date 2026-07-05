# WorkPulse Agent — Architecture

## Overview

Two co-operating Windows processes built from a single Rust workspace:

| Process | Binary | Role |
|---------|--------|------|
| `agentd.exe` | `agentd/` crate | Windows Service — headless capture & sync |
| `workpulse-app.exe` | `app/src-tauri/` + `app/src/` | Tauri desktop UI (React in WebView2) |

Shared business logic lives in the `common/` crate. The two processes share a single SQLCipher database on disk and communicate via a Windows named pipe.

---

## Workspace Layout

```
tauri/
├── Cargo.toml          # Workspace root (resolver = "2")
├── agentd/             # Windows Service binary
│   └── src/
│       ├── main.rs         # Service install/remove/run entry + tokio runtime
│       ├── capture_loop.rs # 30s tick → app/input/screenshot events
│       ├── sync_loop.rs    # 5-min batch upload + screenshot upload + retry
│       └── ipc.rs          # Named pipe server (\\.\pipe\workpulse-agent)
├── common/             # Shared library (no binary)
│   └── src/
│       ├── models.rs       # ActivityEvent, Task, Project, AgentConfig, …
│       ├── idle.rs         # Idle detection (input device polling)
│       ├── timer_state.rs  # Timer persistence helpers
│       ├── api/            # HTTP client (reqwest) — activity, auth, projects, screenshots
│       ├── auth/           # JWT / session store
│       ├── capture/
│       │   ├── app_tracker.rs      # GetForegroundWindow → app + domain
│       │   ├── browser_tracker.rs  # eTLD+1 extraction (no paths/queries)
│       │   └── screenshot.rs       # mss capture → blur → JPEG
│       └── db/
│           ├── schema.rs    # CREATE TABLE IF NOT EXISTS (run on open)
│           ├── queries.rs   # All SQL helpers
│           ├── sync_queue.rs# Retry queue (pending/done, exponential back-off)
│           └── key_manager.rs # SQLCipher key derivation
└── app/                # Tauri + React frontend
    ├── src/            # TypeScript / React (Vite)
    │   ├── pages/      # Login, Consent, Main, Settings
    │   ├── windows/    # IdleWarning, MiniWidget, QuitDialog
    │   ├── components/ # HeroCard, Sidebar, StatRow, StatusBar, TaskList, …
    │   ├── hooks/      # useAuth, useTimerState
    │   └── styles/     # tokens.css (design tokens)
    └── src-tauri/
        └── src/
            ├── lib.rs      # Tauri builder, plugin init, invoke_handler
            ├── tray.rs     # System tray menu
            ├── windows.rs  # Window creation helpers
            ├── theme.rs    # DWM acrylic / dark mode
            └── commands/   # Tauri #[command] handlers
                ├── ipc.rs      # Proxy → agentd named pipe
                ├── auth.rs     # Login / logout / get_session
                └── settings.rs # Settings R/W + autostart toggle
```

---

## Process Architecture

```
┌─────────────────────────────────────────────┐
│  workpulse-app.exe  (Tauri + React/WebView2) │
│                                             │
│  React UI  ←→  Tauri commands  ──────────────┼──┐ named pipe
│                (ipc / auth / settings)       │  │  \\.\pipe\workpulse-agent
└─────────────────────────────────────────────┘  │
                                                  ▼
┌─────────────────────────────────────────────┐
│  agentd.exe  (Windows Service)              │
│                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌──────┐│
│  │ capture_loop│  │  sync_loop  │  │  IPC ││
│  │  (OS thread)│  │  (OS thread)│  │server││
│  └──────┬──────┘  └──────┬──────┘  └──────┘│
└─────────┼────────────────┼─────────────────┘
          │ INSERT          │ SELECT / UPDATE
          ▼                 ▼
   ┌─────────────────────────────┐
   │  SQLCipher DB (local disk)  │
   │  events · screenshots       │
   │  sync_queue · agent_config  │
   │  assigned_tasks · tasks     │
   │  task_time_logs             │
   └────────────────────────────┘
          ▲                 │ POST batch
          │ GET config/     ▼
   ┌──────┴─────────────────────────┐
   │  workpulse-core-services API   │
   └────────────────────────────────┘
```

---

## Key Data Flows

### Capture (every 30 s in `capture_loop`)
1. `IdleDetector::tick()` — samples input device state; accumulates keystroke/click counts.
2. `app_tracker::get_foreground_app()` → `ActivityEvent { event_type: "app" }` → `db::queries::insert_event`.
3. If any input counts exist → `ActivityEvent { event_type: "input" }` → insert.
4. Every 600 s: `screenshot::capture_and_save` → active window only → Gaussian blur → JPEG → insert into `screenshots` table.

### Sync (every 5 min in `sync_loop`)
1. Pull up to 500 unsynced events + all unsynced task_time_logs.
2. Wrap in `ActivityBatch` → POST to core API.
3. On `Accepted`: mark events + logs synced, mark `sync_queue` batch done.
4. On `Retryable`: enqueue in `sync_queue` with exponential back-off.
5. Screenshot upload: up to 50 pending screenshots per cycle → multipart POST.
6. Every 20 min: pull assigned tasks/projects from API → upsert locally.

### Timer (in-memory in `agentd`, queried by UI via IPC)
- State machine: `idle → running → paused → on_break → running`
- `OnceLock<Mutex<TimerInner>>` — single source of truth in agentd process.
- UI calls `toggle_play_pause` / `select_task` / `start_break` via IPC.
- Task selection persists `last_task_id` to `agent_config` for resume after restart.
- Sleep detection: if capture_loop tick gap > 90 s → `pause_for_sleep()`.

### IPC Protocol
Named pipe `\\.\pipe\workpulse-agent`, newline-delimited JSON.

```json
→ { "cmd": "select_task", "payload": { "task_id": "...", "task_name": "...", ... } }
← { "ok": true, "data": { "ok": true }, "error": null }
```

Commands: `ping` · `get_state` · `toggle_play_pause` · `select_task` · `start_break` · `get_assigned_tasks` · `get_time_stats`

---

## Database Schema (SQLCipher)

| Table | Purpose |
|-------|---------|
| `events` | App usage + input count events; `synced` flag |
| `screenshots` | Screenshot metadata + file path; `uploaded` flag |
| `sync_queue` | Retry-capable upload batch tracking |
| `agent_config` | Key/value store for remote config + last-used task |
| `assigned_tasks` | Tasks pulled from API (denormalised for speed) |
| `projects` / `tasks` | Local task/project cache |
| `task_time_logs` | Completed timer sessions; `synced` flag |
| `active_tracking_session` | Single-row in-progress timer persistence |
| `domain_cache` | Browser domain → favicon cache |

Schema is applied on every `db::open()` via `ensure_schema` (idempotent `CREATE TABLE IF NOT EXISTS`).

---

## Privacy Constraints (non-negotiable)

- **Keystrokes**: integer counts only — raw keys are never captured or stored.
- **URLs**: eTLD+1 domain only — no path, query string, or fragment.
- **Screenshots**: active window only; Gaussian blur applied before saving to disk.
- **Timer**: user-initiated only — no automatic time attribution.
