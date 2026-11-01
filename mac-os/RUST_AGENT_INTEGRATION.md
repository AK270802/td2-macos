# Rust Agent Integration

Goal: one tracking engine. Reuse `common` + `agentd` as-is; add native macOS capture and the native-app IPC contract **behind a non-default Cargo feature `macos-native`**, so default builds (Tauri DMG, Windows NSIS, Linux DEB) are byte-for-byte unchanged.

## 1. Reuse (unchanged)

| Module | Role |
|---|---|
| `common::api::{auth, agent, activity, screenshots, consent}` | Agent endpoints, 401 refresh-retry |
| `common::db::{schema, queries, sync_queue, key_manager}` | SQLCipher store, batch queue, backoff `min(2^n·60,1800)` s, 10 retries |
| `common::timer_state`, `common::timer_service` | The only timer logic (tested), crash recovery, idle/meeting accounting |
| `common::capture::screenshot` | xcap → crop → 0.5× → Gaussian blur r=8 → JPEG ≤150 KB ladder |
| `common::capture::browser_tracker::extract_domain` | eTLD+1 via `addr` (raw URL never persisted) |
| `common::capture::meeting` (scoring) | Meeting detector |
| `common::logging`, `common::ipc_transport` (protocol) | Logs, NDJSON framing |
| `agentd::{capture_loop, sync_loop, ipc}` | Loops; built with `--features macos-native` |

## 2. Required changes (more than one file — impact assessed)

Decision 2 allowed one new file; the existing architecture needs feature-gated edits in a few more. **All are `#[cfg(feature = "macos-native")]`; default-feature code paths are untouched.**

| File | Change | Default-build impact |
|---|---|---|
| `common/Cargo.toml` | `[features] macos-native = [objc2, objc2-app-kit, objc2-foundation, core-graphics, core-foundation, security-framework]` (optional, macOS-target only) | None (optional deps not compiled) |
| `common/src/platform/macos_native.rs` (**new**) | Native backend (below) | None |
| `common/src/platform/mod.rs` | `#[cfg(all(target_os="macos", feature="macos-native"))] use macos_native as imp;` else existing `macos_impl` | None |
| `common/src/ipc_transport.rs` | Feature-gated socket path `~/Library/Application Support/EffiLens/agent.sock`, 0600 umask, `getpeereid` UID check, `auth` token verification | None |
| `common/src/db/mod.rs` + `key_manager.rs` | Feature-gated data dir `EffiLens/`, DB key in Keychain (signed builds) | None |
| `common/src/capture/browser_tracker.rs`, `meeting.rs` | Feature-gated macOS bundle-ID lists (Safari, Chrome, Edge, Brave, Arc, Firefox; zoom.us, Teams, Webex, FaceTime, Meet-in-browser) | None (fixes the Tauri macOS bug only if later enabled there — separate approval) |
| `agentd/Cargo.toml` | `macos-native = ["common/macos-native"]` | None |
| `agentd/src/ipc.rs` | Feature-gated `set_session`, `clear_session`, `get_permissions`; reject requests without valid `auth` | None |

⚠️ `agentd/src/ipc.rs` and `common/src/db/queries.rs` currently have **uncommitted local modifications** in the working tree. Milestone 3 edits must be rebased onto whatever the owner commits; they were not touched in Milestones 1–2.

Verification gate for Milestone 3: `cargo test --workspace` (default features, Linux + macOS) **and** `cargo build -p agentd --features macos-native --target {aarch64,x86_64}-apple-darwin` on macOS runners; Tauri `main.yml` must stay green.

## 3. Native macOS backend (`macos_native.rs`)

| Capability | API | Permission | Fallback when denied |
|---|---|---|---|
| Frontmost app (name, bundle id, pid, path) | `NSWorkspace.frontmostApplication` | none | — |
| Focused window title + frame | `AXUIElementCreateApplication(pid)` → `kAXFocusedWindowAttribute` → `kAXTitleAttribute` / position+size | Accessibility | title = "" , rect = None |
| Idle time | `CGEventSourceSecondsSinceLastEventType(.combinedSessionState, kCGAnyInputEventType)` | none | — |
| Input counts (integers only) | `CGEventTap` listen-only on keyDown/mouseDown/mouseMoved; increments counters, **never reads key codes/characters** | Input Monitoring (macOS prompts for listen-only taps) | counts = 0 (not synthetic) |
| Window list (meetings) | `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` owner name + title | Screen Recording for titles | owner names only |
| Browser URL → eTLD+1 | Apple Events per bundle id (`NSAppleScript`), parsed in memory | Automation (per browser) | domain omitted |
| Screenshot (active window only) | ScreenCaptureKit `SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow:))` (macOS 14+) → existing blur/JPEG pipeline | Screen Recording | **skip capture** (no full-monitor fallback) |

CPU: no subprocesses (removes the per-second `sh`/`ioreg` and 2× `osascript` per 30 s of `macos_impl.rs`).

## 4. IPC protocol

Transport: Unix domain socket, NDJSON, one request per connection, 3 s client timeout, 4 MiB max line.

```json
→ {"cmd":"get_state","payload":null,"auth":"<64 hex>"}
← {"ok":true,"data":{"state":"running","task":{…},"elapsed_secs":3725,…},"error":null}
```

Commands: existing `ping, get_state, toggle_play_pause, select_task, start_break, stop_tracking, clear_local_data, idle_keep_working, idle_auto_stop, get_assigned_tasks, get_time_stats, get_task_times_today, get_recent_events, get_sync_status, sync_now, get_consent_status, accept_consent` + native `set_session{access_token,user_id,tenant_id,api_base_url}`, `clear_session`, `get_permissions → {accessibility, screen_recording, input_monitoring}`. Swift mirror: `Sources/EffiLensKit/Agent/AgentProtocol.swift`.

### Socket authentication

1. Daemon creates `EffiLens/` (0700), binds socket with umask 077 (0600).
2. On start, writes 32 random bytes hex to `ipc.token` (0600, `O_NOFOLLOW`), rotated every start.
3. Every connection: `getpeereid` must equal daemon UID; `auth` compared in constant time; failure → `{"ok":false,"error":"unauthorized"}` + close; rate-limited logging.
4. Swift client refuses token files that are symlinks, group/world-readable, or owned by another UID.

## 5. Lifecycle & process management

- Binary: `EffiLens.app/Contents/MacOS/effilens-agentd` (universal, lipo arm64+x86_64), signed inside-out with hardened runtime.
- LaunchAgent: `Contents/Library/LaunchAgents/com.baseel.effilens.mac.agent.plist` (`BundleProgram`, `KeepAlive{SuccessfulExit=false}`, `ProcessType=Interactive`), registered via `SMAppService.agent(plistName:)`; user approves in System Settings › Login Items.
- Single instance: IPC `ping` + exclusive `flock` on `EffiLens/agentd.lock` (closes the stale-socket race noted in the audit).
- Sign-out: app sends `stop_tracking` → `clear_session`; daemon idles without a session.

## 6. Database separation

| | Legacy Tauri | Native |
|---|---|---|
| Data dir | `~/Library/Application Support/WorkPulseAgentRust/` | `~/Library/Application Support/EffiLens/` |
| Socket | `$TMPDIR/workpulse-agent.sock` | `EffiLens/agent.sock` |
| DB key | `db.key` file (0600) | Keychain item `com.baseel.effilens.mac / agent.dbkey` |
| Bundle / LaunchAgent | `com.baseel.workpulse` / `com.baseel.workpulse.agentd` | `com.baseel.effilens.mac` / `com.baseel.effilens.mac.agent` |

No data migration from the legacy DB: unsynced legacy events must be flushed by the legacy app before switching (migration runbook, M9).

## 7. Legacy coexistence safeguards

1. App detects legacy app (`NSRunningApplication` bundle id) or legacy socket → UI state `legacyConflict`; tracking controls disabled; banner explains.
2. Daemon refuses `select_task`/`toggle_play_pause` while the legacy socket answers `ping` (defence in depth).
3. Native sign-in warns that it will sign the legacy agent out (backend revokes `workpulse-agent` device on login).

## 8. Offline sync

Unchanged agentd behaviour: 500-event batches, `task_time_logs` included, permanent 4xx dropped / transient retried. ⚠️ Audit risk: 401 during a batch is classified permanent → events marked synced. Native build fixes this under the feature flag by treating 401 as retryable after token refresh.

## 9. Implementation status & deviations (Milestone 3, commit dbd4585+)

Implemented behind `macos-native` (off by default). Files touched exactly as §2, plus:
- `common/src/idle.rs` — native `tick()` reads event-tap counts (§3 "Input counts").
- `common/src/capture/screenshot.rs` — split into `capture_active_window` (backend-specific) + shared `process_and_write`; default path unchanged in behaviour.
- `agentd/src/main.rs`, `capture_loop.rs`, `sync_loop.rs` — **not modified**.

Deviations from the plan (honest list):
| Plan | Implemented | Reason |
|---|---|---|
| ScreenCaptureKit window capture | `CGWindowListCreateImage` for a single CGWindowID (window-only, still never full-screen) | ScreenCaptureKit is async Objective-C; calling it from Rust needs objc2 + blocks crates. Deprecated API works on macOS 14/15; migration to SCK tracked for M9 |
| DB key in Keychain | 0600 file in `EffiLens/` (existing key_manager) | Same reason as the existing code comment: Keychain ACLs bind to code signature; daemon and app are separate binaries; revisit after Developer ID signing |
| No subprocesses | Browser URL still via `osascript`, but only when a browser is frontmost and once per capture interval (30 s), not per second | Native Apple Events from Rust need objc; per-second `ioreg`/`osascript` calls are gone |
| `getpeereid` | `tokio::net::UnixStream::peer_cred()` (uses getpeereid on macOS) | — |
| flock | `std::fs::File::try_lock` (Rust ≥ 1.89) | No extra crates |

IPC commands added: `set_session` (validates UUIDs, refuses an `api_base_url` different from the agent's own API, wipes the previous account's local data on account switch), `clear_session` (stop → `clear_local_activity_data` → forget token), `get_permissions`. The pre-existing `clear_local_data` command is unchanged.
