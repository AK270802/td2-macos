# Implementation Plan

Each milestone is independently buildable and testable on `macos-15` CI. "Done" = CI green + design review (5 dimensions ≥ 7/10, swiftui-design-skill) for UI milestones.

| M | Scope | Deliverables | Exit criteria | Status |
|---|---|---|---|---|
| 1 | Foundation | `project.yml`, `Package.swift`, app lifecycle, `AppEnvironment` DI, `Route`/sidebar, design tokens & components, asset catalogue with official logo, logging, tests skeleton, CI workflow, build/release scripts | `xcodegen generate` + `xcodebuild` Debug/Release succeed; `swift test` passes | **Code written — awaiting first CI run** |
| 2 | Backend integration | `APIClient` (401 refresh, retry, error mapping), `SessionManager` (portal + agent tokens, Keychain), Codable models for auth/user/agent/projects/task-time/dashboard/analytics/leave/notifications/consent, services, sign-in, consent gate, Dashboard + Leave Overview vertical slices | Sign-in against dev backend; dashboard and leave overview show real data; unit tests for decoding/refresh | **Code written — awaiting CI + live verification**. Remaining: change-password + forgot-password forms (M2b) |
| 3 | Rust agent | Feature `macos-native` (files in RUST_AGENT_INTEGRATION.md §2), native capture backend, authenticated IPC, `set_session`/`clear_session`/`get_permissions`, LaunchAgent + `SMAppService`, universal binary embedded in app | Default `cargo test --workspace` unchanged & green; feature build on macOS; tracked session appears in portal; no screenshot when Screen Recording denied | Blocked on D2 approval |
| 4 | Core screens | Tracker, Projects, Assigned Tasks, History (+CSV), Manual Entry (admin), Notifications, Activity, Team, Member, sidebar search | All per SCREEN_INVENTORY §C/§E with L/E/Err states | — |
| 5 | Leave | Apply, My Requests, Detail (+edit/withdraw), Calendar, Holidays (comp-off / holiday leave), Balance, Approvals (single + bulk, manager/admin stage), admin policy | Role matrix verified with user/manager/admin test accounts | — |
| 6 | Reports | Productivity / Time / Attendance / Leave tabs, ranges, `/reports/generate` export + download | Manager+ export works; employees see self analytics only | — |
| 7 | macOS experience | Mini timer panel, popover completion, Dock badge, notifications, shortcuts, quit-while-tracking, idle dialog, Settings panes, About & Diagnostics, update UX, offline banner | Manual QA checklist | — |
| 8 | Installer & onboarding | DMG (and PKG if approved), onboarding steps 2–4, permission flows, agent start, initial sync, failure/recovery paths | Fresh-Mac install by non-developer | — |
| 9 | Hardening | Crash/session recovery UI, supervision, CPU/memory budget (< 1 % CPU idle tracking, < 150 MB app), accessibility audit, release signing & notarisation, legacy→native migration runbook | Signed notarised DMG; Sequoia + Tahoe validation | — |

## Next milestone
Run CI for M1–2, fix compiler findings, verify sign-in + Dashboard + Leave Overview against the dev backend; in parallel, obtain approval of the D2 Rust file list to start M3.
