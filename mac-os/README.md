# EffiLens for macOS (native SwiftUI)

Native macOS client for EffiLens/WorkPulse. Coexists with — and does not modify — the Tauri app (`../app`), the Rust agent (`../agentd`, `../common`), the Windows go-agent, the portal and core-services.

```
mac-os/
├── project.yml              XcodeGen spec (generates EffiLens.xcodeproj on macOS)
├── Package.swift            EffiLensKit package (UI-free core + tests)
├── Sources/
│   ├── EffiLensKit/         Core · Networking · Models · Auth · Storage · Services · Agent
│   ├── App/                 EffiLensApp, AppEnvironment (DI), AppModel, Route, RootView
│   ├── DesignSystem/        Tokens (brand), Formatting, Components
│   └── Features/            Onboarding · Shell · Dashboard · Leave · MenuBar
├── Resources/               Info.plist, entitlements, Assets.xcassets (official logo)
├── Tests/EffiLensKitTests/  Decoding, API client, fixtures
├── Scripts/                 build.sh, release.sh
└── *.md                     Architecture & plan documents
```

Docs: [ARCHITECTURE](ARCHITECTURE.md) · [IMPLEMENTATION_PLAN](IMPLEMENTATION_PLAN.md) · [BRAND_SPEC](BRAND_SPEC.md) · [SCREEN_INVENTORY](SCREEN_INVENTORY.md) · [API_INTEGRATION](API_INTEGRATION.md) · [RUST_AGENT_INTEGRATION](RUST_AGENT_INTEGRATION.md) · [SECURITY_AND_PRIVACY](SECURITY_AND_PRIVACY.md) · [BUILD_AND_RELEASE](BUILD_AND_RELEASE.md) · [DECISIONS_AND_ASSUMPTIONS](DECISIONS_AND_ASSUMPTIONS.md)

Build: see BUILD_AND_RELEASE.md. **Not yet compiled** — first verification happens on the `macos-native` GitHub Actions workflow.

## Status (development release)

- All sidebar screens are implemented against the real `/api/v1` endpoints (no mock data): Dashboard, Time Tracker, Projects, Assigned Tasks, History, Manual Entry (admin), Leave Overview / Apply / My Requests + detail / Calendar / Balance / Holidays, Team + member detail and Approvals (manager+), Reports (Productivity, Time, Attendance, Leave), Notifications, Activity, Settings (General, Tracking, Screenshots, Notifications, Appearance, Account, About, Diagnostics).
- Settings › General mirrors the go-agent Settings modal: *Reminder Notification Interval (When Inactive)* (Never/5/10/15/30/60 min, default 15) and *Launch at Startup*, applied with **Save Settings** / **Cancel**.
- Native: menu-bar extra, floating mini timer, Dock badge, local notifications, keyboard shortcuts, quit-while-tracking confirmation, offline banner, agent-error alerts with Reconnect, update dialog (no native feed yet, gap B7), six-step in-app onboarding.
- Installers: CI job 6 builds `EffiLens-macOS-universal.dmg` / `.pkg` / `EffiLens.app.zip` (ad-hoc signed, **not notarised**). Install/test: [INSTALL_AND_TEST.md](INSTALL_AND_TEST.md).
- Not supported by the backend (shown disabled or explained, never faked): desktop SSO (B2), live presence (B3), employee manual entries (B5), report export from the app (links to the portal), native auto-update (B7).

## Unified behaviour with go-agent, the web portal and core-services

| Area | Source of truth | Native implementation |
|---|---|---|
| Idle warning | go-agent `OnIdleWarning`, Tauri `IdleWarning.tsx` | Window restored and floated; 60 s countdown; *Still working* → `idle_keep_working`; *On a break* or timeout → `idle_auto_stop` (back-dated), plus a "Tracking Stopped" notification |
| Inactive reminder | go-agent `notifier.go` | Same interval setting (0/5/10/15/30/60), same text; also restores the window |
| Sleep / wake | go-agent `OnSystemWake` | Agent pauses at sleep (`pause_for_sleep`); on wake the app restores the window, refreshes the session after 10 s, re-hands it to the agent and syncs |
| Stay signed in | go-agent token refresh on start/resume | Session re-handed to the agent before start/resume; single-flight refresh in `SessionManager` |
| Tray / menu bar | go-agent tray | 15-min Coffee Break, End Break, Open Dashboard, Open Web Portal, Quit (stop + final sync) |
| Activity | core-services `GET /analytics/timeline` (same as the portal) | Synced events with app, domain, window title, idle, category; plus the local unsynced count |
| Team presence | core-services `GET /users/{id}.last_device_seen`, `/dashboard/team.activity_level` | "Active · 3 min ago" / "Last seen …" plus activity level |
| Leave rules | frontend `lib/leave-utils.ts` (mirrors the backend) | Status labels (Awaiting manager / admin); edit and cancel rules; approver level; payment labels (Paid / Unpaid / Paid + Unpaid / At approval); Full / Half Day; portal filter chips; balance rows; Edit request with `client_updated_at` |

Not available in core-services (not shown, never faked): project progress or client, task priority / due date / estimate, Annual / Sick / Casual leave types.
