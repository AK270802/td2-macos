# Screen & Interaction Inventory

Source: full read of `EffiLens-macOS-Prototype.html` (820 lines; view ids, dialogs, menus, flows). **Total: 52 surfaces** — 26 primary screens/sub-views, 8 installer/onboarding steps, 6 system surfaces (menu bar, popover, mini timer, notifications, Dock, app menus), 6 settings panes, 6 dialogs/alerts.

Conventions for every screen unless noted: **Loading** = `ProgressView`/redacted placeholders (never fake numbers) · **Error** = `ErrorStateView` with retry; offline → offline variant · **Empty** = `ContentUnavailableView` with guidance · Auth = portal JWT unless marked *agent* (IPC/agent token).
Status: ✅ implemented (M1–2) · ⏳ scheduled (milestone) · ⚠️ gap (backend lacks data — shown as unavailable, never faked).

## A. Installer & first launch

| # | Surface | Purpose / components | Data · endpoint | Actions · validation | Perms | Status |
|---|---|---|---|---|---|---|
| A1 | DMG window | Drag EffiLens → Applications, background art | — | Drag/copy | — | ⏳ M8 (`release.sh` DMG) |
| A2 | Installer: Introduction | Universal, macOS 14+, notarised | — | Continue | — | ⏳ M8 — only if PKG chosen; DMG has no wizard |
| A3 | Installer: License | EULA, agree required | — | Agree gate | — | ⏳ M8 (PKG) |
| A4 | Installer: Destination | All users / only me | — | — | admin pw | ⏳ M8 (PKG) |
| A5 | Installer: Type | Components (App, Menu Bar Agent, Mini Timer, Login helper) | — | Toggles | — | ⏳ M8 — agent is mandatory in native design |
| A6 | Installer: Install/Summary | Progress, success | — | — | — | ⏳ M8 |
| A7 | Onboarding 1 — Sign in | Brand panel + email/password, remember, forgot, SSO, server status | `POST /auth/login`, `POST /auth/agent/login`; forgot → `POST /auth/forgot-password` | Email contains @, password non-empty; Enter submits | — | ✅ (SSO disabled ⚠️ B2; forgot ⏳ M2b) |
| A8 | Onboarding 2 — Device setup checklist | Verify org, register device, download policy, sync tasks, fetch balances | `/users/me`, `/agent/config` (*agent*), `/projects/assigned`, `/leave/balance` | Each row live status, retry on failure | — | ⏳ M8 (device model/OS shown locally; no device registration endpoint ⚠️ B6) |
| A9 | Onboarding 3 — Privacy consent | Recorded / never recorded lists + tenant policy text + checkbox | `GET /consent/status`, `POST /consent/accept {policy_version}` | Accept disabled until checked; no policy → blocked | — | ✅ (`ConsentView`) |
| A10 | Onboarding 4 — Permissions | Notifications, Accessibility, Screen Recording, Open at Login with Allow buttons | Local: `UNUserNotificationCenter`, `AXIsProcessTrustedWithOptions`, `CGRequestScreenCaptureAccess`, `SMAppService` | Each opens system prompt/Settings; re-check on focus | All four | ⏳ M8 |

## B. Shell & system surfaces

| # | Surface | Components | Data | Actions | Status |
|---|---|---|---|---|---|
| B1 | Main window chrome | Unified toolbar: title, sync pill, mini-timer, bell+badge, "+ Apply Leave" | agent `get_sync_status`; `/notifications/unread-count` | ⌘N apply leave | ✅ (mini-timer button ⏳ M7) |
| B2 | Sidebar | Search, Dashboard · Time Tracking (5) · Leave (6) · Workspace (7), badges, user card | `/users/me`; role from `UserOut.role` | Role-filtered (Route.minimumRole) | ✅ (search ⏳ M4) |
| B3 | Menu-bar extra | Mono timer + state dot | agent `get_state` (1 Hz IPC) | Click → popover | ✅ |
| B4 | Menu-bar popover (330 pt) | Connected pill, timer card, Start/Pause/Stop, Today, Leave left, recent tasks, actions | agent `get_state`, `get_time_stats`; `/leave/balance` | Start/Pause, Stop, start recent task, Open Dashboard, Apply Leave, Quit | ✅ partial (Today/Leave/recent ⏳ M7) |
| B5 | Floating mini timer (300 pt NSPanel) | Ring, time, task, play/pause/stop/close, draggable, always-on-top | agent `get_state` | ⌥⌘M toggle | ⏳ M7 |
| B6 | Native notifications | Banner: title, body | Agent events + `/notifications` | Click → route | ⏳ M7 (UNUserNotificationCenter) |
| B7 | Dock badge | Unread count | `/notifications/unread-count` | — | ⏳ M7 |
| B8 | App menus | File (New Leave ⌘N, Manual Entry ⇧⌘N), View (Mini Timer ⌥⌘M, Appearance ⌥⌘L), Tracking (Start/Pause ⌃⌥Space, Stop ⌃⌥S), Help (Updates, Diagnostics) | — | — | ✅ Tracking menu; rest ⏳ M7 |

## C. Dashboard & time tracking

| # | Screen | Components | Data · endpoint | Actions · validation | Role | Status |
|---|---|---|---|---|---|---|
| C1 | Dashboard | Date eyebrow, greeting, Start/Pause; KPIs Today / This week (of required) / Productivity / Leave left; Active session ring; Weekly bar chart; Recent sessions; Leave balance rings; Upcoming | `/dashboard/individual` (today, week) · `/leave/policy/me` (weekly_required_hours) · `/analytics/utilisation` · `/task-time` (7 d) · `/leave/balance` · `/leave/holidays` · `/leave/applications` · agent `get_state` | Start/Pause/Stop via IPC; links to Tracker/History/Leave | user | ✅ — "▲12% vs avg" deltas ⚠️ no baseline endpoint (omitted) |
| C2 | Time Tracker | 250 pt ring, 56 pt timer, Recording/Paused/Ready, Start/Resume, Stop & Save, shortcut hints, Quick-switch task list + search | agent `get_state`, `get_assigned_tasks`, `get_task_times_today`; `select_task`, `toggle_play_pause`, `stop_tracking`, `start_break` | Task required to start; switching flushes segment (agent) | user | ⏳ M4 |
| C3 | Projects | 2-col cards: name, task count, hours logged, View Tasks | `/projects/assigned`, `/task-time/project-summary` | Open tasks | user | ⏳ M4 — client name, progress % ⚠️ no fields |
| C4 | Assigned Tasks | Search, project filter, rows: project colour, name, hours, Start | `/projects/assigned`, `/task-time/summary` | Start → `select_task` | user | ⏳ M4 — priority, due date, estimate ⚠️ (TaskOut has none; filter hidden) |
| C5 | Time History | Day/Week/Month, Export CSV, KPIs Total/Sessions/Avg, day-grouped table Task·Project·Start·End·Duration | `/task-time?date_from&date_to&page` | CSV export generated locally from fetched rows | user | ⏳ M4 |
| C6 | Manual Entry | Task, date, start, end, reason, submit | `POST /task-time/manual` | end > start; **admin/super_admin only** (backend) | admin | ⏳ M4 — employee self-entry & approval rules (≤2 h, 7-day) ⚠️ B5 |

## D. Leave management

| # | Screen | Components | Data · endpoint | Actions · validation | Role | Status |
|---|---|---|---|---|---|---|
| D1 | Leave Overview | Balance rings (Paid, Comp-off), carried forward, unpaid, pending & recent list, upcoming holidays | `/leave/balance` (server `paid_remaining`, `comp_off_remaining`), `/leave/applications`, `/leave/holidays` | Withdraw pending (confirm) → `DELETE /leave/applications/{id}` | user | ✅ — Annual/Sick/Casual ⚠️ fixed backend types |
| D2 | Apply for Leave | Date range, Full / half day, reason, summary ring (available → after) | `POST /leave/applications {start_date,end_date,half_day,reason}`; `/leave/balance`; `/leave/policy/me` | end ≥ start; half_day only single day 🔶 verify; server returns paid/unpaid split + `message` | user | ⏳ M5 — leave-type selector ⚠️ type is server-derived; "Notify HR" ⚠️ |
| D3 | My Requests | Filter All/Pending/Approved/Rejected/Cancelled, table ID·Type·Dates·Days·Applied·Status | `/leave/applications?status&page` | Open detail | user | ⏳ M5 |
| D4 | Request detail | Header, From/To/Duration/Reason, Withdraw, approval timeline (submitted → manager → admin) | `/leave/applications/{id}` (manager/admin *_at, *_by, rejection reasons) | Withdraw; edit pending → `PATCH` with `client_updated_at` | user | ⏳ M5 — comments, Send Reminder ⚠️ |
| D5 | Leave Calendar | Month grid, prev/today/next, legend, chips | `/leave/calendar?year&month&user_id` | Navigate months | user (team view manager+) | ⏳ M5 — team-wide multi-user overlay uses per-user calls 🔶 |
| D6 | Holidays | List (date, name) + holiday-only calendar; claim comp-off / apply leave on holiday | `/leave/holidays?year`; `POST …/claim-compoff`, `…/apply-leave` | — | user; create/delete admin | ⏳ M5 — Public/Regional/Company type ⚠️ |
| D7 | Leave Balance | Table Entitled·Used·Pending·Available·Utilisation; policy notes | `/leave/balance`, `/leave/policy/me`, `/leave/applications?status=pending_*` | — | user | ⏳ M5 — accrual chart ⚠️ (no accrual model) |
| D8 | Approvals | Manager banner, request cards, Approve/Reject (reason), bulk | `/leave/applications?status=pending_manager|pending_admin`; `manager-approve|reject`, `admin-approve|reject`, `bulk-*` | Reject requires reason | manager+ | ⏳ M5 |
| D9 | Leave policy (admin) | Policy form, user/group overrides | `/leave/policy`, `/leave/policy/users|groups` | Server validation | admin | ⏳ M5 (not in prototype; required by brief) |

## E. Workspace

| # | Screen | Components | Data · endpoint | Role | Status |
|---|---|---|---|---|---|
| E1 | Team | KPIs Working now / On leave / Team hours; member cards with status | `/dashboard/team`, `/managers/me/users`, `/leave/calendar` per user | manager+ | ⏳ M4 — live presence ⚠️ B3 |
| E2 | Member detail | Avatar, role, KPIs week/productivity/leave | `/dashboard/individual?user_id`, `/leave/balance?user_id` | manager+ | ⏳ M4 |
| E3 | Reports | Tabs Productivity / Time / Attendance / Leave, Export PDF | `/analytics/*`, `/task-time/project-summary`, `/working-hours/stats|compliance`, `/leave/balance/all`; export `POST /reports/generate` → status → download | manager+ (backend) | ⏳ M6 — employee self-reports via analytics only |
| E4 | Notifications | Unread count, mark all read, list, preferences | `/notifications`, `PATCH …/read`, `POST /mark-all-read` | user | ⏳ M4 |
| E5 | Activity | Local timeline (sync, start/stop, idle, sign-in) | agent `get_recent_events` | user | ⏳ M4 |
| E6 | About & Diagnostics | Version, check updates, export logs, health rows (agent PID, backend latency, queue, permissions, last sync) | agent `ping`/`get_sync_status`/`get_permissions`; `/health` | user | ⏳ M7 — "Simulate …" rows are prototype-only, excluded |

## F. Settings (Settings scene, ⌘,)

| # | Pane | Fields | Backing | Status |
|---|---|---|---|---|
| F1 | General | Open at login, menu bar, Dock badge, mini timer when tracking, week start | `SMAppService`, UserDefaults | ⏳ M7 |
| F2 | Tracking | Idle detection, threshold, break reminders, global shortcut | **Read-only** from `/agent/config` (tenant policy; not user-editable) | ⏳ M7 |
| F3 | Screenshots | Capture, blur, frequency, retention | **Read-only** from `/agent/config` | ⏳ M7 |
| F4 | Notifications | Sounds, breaks, leave updates, idle alerts, style, test | local | ⏳ M7 |
| F5 | Appearance | System / Light / Dark | `NSApp.appearance` | ⏳ M7 (accent swatches ⚠️ dropped — brand accent fixed) |
| F6 | Account | Avatar, name, role, email, org, manager, device, Sign out | `/users/me`, `/users/profile` | ✅ minimal |

## G. Dialogs & recovery flows

| # | Dialog | Trigger | Actions | Status |
|---|---|---|---|---|
| G1 | Quit while tracking | ⌘Q / close with timer running | Stop & Quit · Keep in Menu Bar · Cancel | ⏳ M7 |
| G2 | Idle warning | agent `idle_warning=true` | Keep working (`idle_keep_working`) · Stop (`idle_auto_stop`) · Break | ⏳ M7 |
| G3 | Session recovery | agent recovered crashed session at start | Recover & Resume · Save Without Resuming · Discard | ⏳ M9 (agent already has `recover_crashed_session`) |
| G4 | Update available | update feed | What's new, download, verify, relaunch | ⏳ M7 (feed decision B7) |
| G5 | API error | `AppError.server` | Retry · Diagnostics · OK | ✅ inline (`ErrorStateView`); modal ⏳ M7 |
| G6 | Offline banner | `sync.connected == false` | Reconnect (`sync_now`) | ✅ pill; banner ⏳ M7 |
| G7 | Withdraw leave confirm | Withdraw | Withdraw · Cancel | ✅ |
