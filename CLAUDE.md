# workpulse-agent/tauri

Rust workspace: Windows Service (`agentd`) + Tauri desktop UI (`app`).
Full architecture: `ARCHITECTURE.md`

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Service backend | Rust 1.x · Tokio · rusqlite (SQLCipher) · reqwest |
| Tauri shell | Tauri v2 · tauri-plugin-shell · tauri-plugin-notification |
| Frontend | React 18 · TypeScript 5 · React Router v6 · Tailwind CSS v3 · Vite 5 |
| Windows integration | windows-service · windows-sys (WinAPI) |

## Crate Responsibilities

- **`common/`** — all shared types and logic (db, capture, api, auth, models). No binary.
- **`agentd/`** — Windows Service binary. Three long-running loops: `capture_loop`, `sync_loop`, `ipc` server.
- **`app/src-tauri/`** — Tauri binary. Proxies UI commands to agentd via named pipe. Manages tray, windows, theme.
- **`app/src/`** — React frontend (Vite). Pages: Login, Consent, Main, Settings. Windows: MiniWidget, IdleWarning, QuitDialog.

## Build & Run

```powershell
# Rust (agentd or common)
cargo build -p agentd
cargo build -p common

# Frontend dev (hot reload)
cd app && npm run dev

# Full Tauri dev (launches WebView2 + Rust hot rebuild)
cd app && npm run tauri dev

# Production build
cd app && npm run tauri build
```

## Test

```powershell
# All workspace tests
cargo test --workspace

# Specific crate
cargo test -p common

# agentd debug mode (no Windows Service registration needed)
cargo run -p agentd -- debug
```

## Key Files

| File | Role |
|------|------|
| `agentd/src/ipc.rs` | Named pipe server + timer state machine |
| `agentd/src/capture_loop.rs` | 30 s capture tick (app, input, screenshot) |
| `agentd/src/sync_loop.rs` | 5 min batch upload + retry |
| `common/src/db/schema.rs` | All table definitions |
| `common/src/db/queries.rs` | All SQL helpers |
| `common/src/models.rs` | Shared data types |
| `app/src-tauri/src/commands/ipc.rs` | Tauri → agentd IPC bridge |

## Conventions

- Error handling: `anyhow::Result` in binaries; return `Err` up the call stack, log at loop boundary.
- Logging: `tracing` macros (`info!`, `warn!`, `error!`). Filter via `RUST_LOG` env var.
- DB access: always open a fresh `Connection` per thread — `rusqlite::Connection` is `!Send`.
- `rusqlite` is not `Send` — capture and sync loops each run on their own OS thread with a `current_thread` Tokio runtime.
- IPC protocol: newline-delimited JSON `{ cmd, payload? }` → `{ ok, data, error }`.
- Frontend types mirror Rust models — keep `common/src/models.rs` and TypeScript interfaces in sync.
- Design tokens: all colours from `app/src/styles/tokens.css`. Dark mode only. No hardcoded hex values.

## Privacy Rules (non-negotiable)

- Raw keystrokes: **never**. Integer counts only.
- URLs: **eTLD+1 domain only**. No path, query string, or fragment.
- Screenshots: **active window only**. Gaussian blur before writing to disk.
- Timer: **user-initiated only**. No automatic time attribution.
