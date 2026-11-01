# Decisions & Assumptions

## Decisions applied (Phase 2 proposed defaults)

| # | Decision | Applied as | Evidence |
|---|---|---|---|
| D1 | SwiftUI app + Rust agent + UDS IPC; backend is source of truth | Implemented in M1–2 (Swift side) | ARCHITECTURE.md |
| D2 | Rust native module behind non-default feature | **Needs more than one file** (8 feature-gated edits + 1 new file) — listed with impact | RUST_AGENT_INTEGRATION.md §2 — awaiting approval |
| D3 | Single sign-in | Verified `get_current_user` rejects agent tokens → app performs portal + agent login with one form; **no backend change**. Exchange endpoint proposed only for SSO (B2) | `core-services/app/core/auth.py` |
| D4 | Existing leave backend only | Fixed types paid/unpaid/comp-off; type server-derived; two-stage approval | `app/schemas/leave.py`, `app/models/leave.py` |
| D5 | macOS 14 minimum; CI Sequoia (+Tahoe when available) | `project.yml`, `Package.swift`, workflow | BUILD_AND_RELEASE.md |
| D6 | `com.baseel.effilens.mac`, separate dirs/socket/LaunchAgent | Applied | RUST_AGENT_INTEGRATION.md §6 |
| D7 | Unsigned dev / signed release; secrets documented | Workflow + `release.sh` | BUILD_AND_RELEASE.md |

## Engineering decisions
- XcodeGen + local Swift package instead of a committed `.xcodeproj` (cannot be edited reliably on Windows).
- No third-party Swift dependencies in M1–2 (Swift Charts, Network.framework, Security are system).
- Agent IPC client in Swift via Network.framework (no FFI).
- Manual refresh-cookie handling (no shared cookie jar) to keep the token in the Keychain.
- Prototype "Simulate …" diagnostics rows and runtime accent picker are excluded (prototype affordances, conflict with fixed brand accent).

## Assumptions (to confirm)
1. Brand: dark accent `#FCAC04`, SF Pro instead of Inter, native vibrancy sidebar (BRAND_SPEC.md §8).
2. API origin per environment; portal URL unknown (left blank).
3. Consent statuses are exactly `accepted|pending|withdrawn`.
4. Distribution as DMG first; PKG only if MDM/enterprise needs it (the prototype's 6-step installer implies PKG).
5. Users run either the legacy Tauri app or the native app — never both (enforced by detection).
6. Signing in natively signs out the user's other agent logins (existing backend behaviour, not changed).

## Scope reductions (documented, need your approval)
| Prototype element | Reason |
|---|---|
| Annual/Sick/Casual leave buckets, leave-type picker, accrual chart, comments, reminders, notify-HR, holiday categories | Not in backend (B8) |
| Task priority, due date, estimate; project client & progress % | Not in backend (B4) |
| Employee manual-entry submission + approval rules | Backend allows admins only (B5) |
| Live "Working now / Idle / In meeting" presence | No endpoint (B3) |
| "▲12% vs avg"-style deltas | No baseline endpoint; omitted rather than computed client-side |
| SSO button | Disabled until B2 |

## Blockers
- **Apple Developer ID + notary credentials** (release signing, stable TCC/Keychain identity).
- **Approval of D2 file list** before Milestone 3.
- **Uncommitted changes** in `workpulse-rust` (`agentd/src/ipc.rs`, `app/src-tauri/src/commands/auth.rs`, `common/src/db/queries.rs`) — owner should commit or stash before Rust work; no branch was created and nothing was committed (per instruction).
- **Missing alembic revisions** (only matters if a backend proposal is approved).
- **First macOS CI run** — Swift sources are unverified by a compiler.
