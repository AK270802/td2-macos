# workpulse-agent (Rust + Tauri)

Rust workspace: background agent (`agentd`) + Tauri desktop UI (`app`).
Full architecture: `ARCHITECTURE.md`

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Agent backend | Rust 1.x · Tokio · rusqlite (SQLCipher) · reqwest |
| IPC | `interprocess` crate — named pipe (Windows) / Unix socket (macOS, Linux) |
| Tauri shell | Tauri v2 · plugins: shell, notification, autostart, global-shortcut |
| Frontend | React 18 · TypeScript 5 · Vite 5 (no CSS framework — tokens.css) |
| Platform capture | `common/src/platform/` — WinAPI (Windows), osascript/ioreg (macOS), xdotool/xprintidle (Linux X11) |

## Crate Responsibilities

- **`common/`** — shared library: db, capture, api client, auth, models, platform layer,
  `timer_state` (pure state machine) + `timer_service` (persistence glue), `ipc_transport`.
- **`agentd/`** — background binary. Runs in the USER SESSION on all
  platforms (never as a system service — session-0 can't capture the desktop
  and has the wrong keychain/AppData). Three loops: `capture_loop` (1s tick),
  `sync_loop` (5 min batches), `ipc` server. The Tauri app spawns it on
  demand; installers register per-login autostart.
- **`app/src-tauri/`** — Tauri binary. Proxies UI commands to agentd over IPC.
  Tray, window management (main / mini / idle_warning — all render the same
  SPA, selected by window label).
- **`app/src/`** — React frontend. Pages: Login, Consent, Main, Settings.
  Windows: MiniWidget, IdleWarning.

## Build & Run

```powershell
cargo build -p agentd
cd app && npm install && npm run dev        # frontend only
cd app && npm run tauri dev                  # full app
cd app && npm run tauri build                # production installer (NSIS)
cargo run -p agentd -- debug                 # agentd in foreground
```

## Test

```powershell
cargo test --workspace
cargo test -p common
```

## Design System ("Instrument", dark only)

- Fonts (Google Fonts, imported in `app/src/styles/tokens.css`):
  Fraunces (display serif, italic axis) · JetBrains Mono (timers, codes,
  overline labels — always `tabular-nums`) · Public Sans (UI).
- All colours from CSS variables in `tokens.css`. Never hardcode hex in components.
- Overline labels: `.wp-overline` (mono 10px, 0.18em tracking, rule above).
- Accents: gold `--gold` (actions/tracking), emerald (connected/active),
  coral (breaks), red (danger).

## Conventions

- Error handling: `anyhow::Result`; log at loop boundary; loops self-restart, never die.
- DB: fresh `Connection` per thread (`rusqlite::Connection` is `!Send`).
- IPC protocol: newline-delimited JSON `{cmd, payload?}` → `{ok, data, error}`.
- Timer logic lives ONLY in `common::timer_state` (tested) wrapped by
  `common::timer_service` (persistence). Never fork timer logic elsewhere.
- API contract mirrors core-services `/api/v1` exactly — field names in
  `common/src/api/*` are load-bearing; check `app/schemas/*.py` before changing.

## Privacy Rules (non-negotiable)

- Raw keystrokes: **never**. Integer counts only.
- URLs: **eTLD+1 domain only**, extracted in-memory; raw URL never persisted.
- Screenshots: **active window crop**, Gaussian-blurred BEFORE any disk write.
- Timer: **user-initiated only**; capture records nothing unless state == running.
- Consent: server-tracked; UI is gated on `GET /consent/status` after login.
