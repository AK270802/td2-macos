# API Integration

Base: `{origin}/api/v1` · JSON · snake_case. Verified against `core-services/app/api/v1/*.py` and `app/schemas/*.py` on 2026-11-01. Swift: `Sources/EffiLensKit/Services/*`, models in `Models/*`.

**Auth legend:** P = portal JWT (`get_current_user` / `require_*_role`) · A = agent token (`get_current_agent_user`) · P|A = `get_current_user_or_agent` · — = none.
**Common errors:** 400/422 `{"detail": str | [{loc,msg}]}` → `AppError.validation` · 401 → one refresh + retry, then sign-out · 403 + `X-Password-Change-Required: true` → password flow · 403 → forbidden · 404 · 409 conflict · 429 `Retry-After` · 5xx.
**Retry:** UI client retries idempotent requests (GET/PUT/DELETE + flagged POSTs) on offline/429/5xx — 2 retries, 0.8 s base, ≤6 s, jitter. Non-idempotent writes are never auto-retried. Background sync retry belongs to the Rust agent.

## Environments

| Environment | Portal (web) | Backend API (native app + Rust agent) | Prefix |
|---|---|---|---|
| Development (default) | `https://dev-workpulse.baseel.com` | `https://dev-workpulse-api.baseel.com` | `/api/v1` (`app/api/v1/__init__.py`) |
| Production | not configured — must stay separate; never used for development testing | | |

Configured in `project.yml` (`EFFILENS_API_BASE_URL`, `EFFILENS_PORTAL_URL` → Info.plist), overridable via `UserDefaults` key `effilens.serverOverride` (HTTPS only, loopback HTTP for local dev). The Rust agent receives the same API origin through `WORKPULSE_API_URL` in its LaunchAgent plist (`Scripts/embed-agent.sh`) — the same variable and default (`common/src/api/mod.rs`) the existing agent uses. API requests are never sent to the portal URL. No credentials are stored in source.

## Authentication

| Method · path | Auth | Request | Response | Notes |
|---|---|---|---|---|
| POST `/auth/login` | — | `{email, password}` | `TokenResponse{access_token, token_type, expires_in}` + `Set-Cookie: wp_refresh_token` (HttpOnly, path `/`, 7 d) | Cookie captured manually, stored in Keychain |
| POST `/auth/refresh` | cookie | `Cookie: wp_refresh_token=…` | `TokenResponse` + rotated cookie | Single-flight; old token revoked |
| POST `/auth/logout` | cookie | — | — | Best-effort on sign-out |
| POST `/auth/agent/login` | — | `{email, password}` | `AgentLoginResponse{access_token, user_id, tenant_id, email, expires_in, refresh_token_expires_in, password_changed}` | **Revokes prior `workpulse-agent` device** |
| POST `/auth/agent/refresh` | A | — | `AgentTokenResponse{token, device_id, expires_at, refresh_token_expires_in}` | Old device revoked |
| PATCH `/auth/change-password` | P | `{current_password, new_password}` | `TokenResponse` | Strength rules server-side |
| POST `/auth/forgot-password` | — | `{email}` | `{message}` | |

## Screen → endpoint map

| Screen | Method · path | Auth | Query / body | Response | Refresh |
|---|---|---|---|---|---|
| Shell / account | GET `/users/me` | P | — | `UserOut` (role, display_name, organization_name, timezone) | on launch, sign-in |
| Account / member | GET `/users/profile`, `/users/{id}/profile` | P | — | `UserProfileOut` (manager_name, leave section) | on open |
| Consent | GET `/consent/status` · POST `/consent/accept` | P\|A | `{policy_version}` | `{status, policy_version, policy_content}` · `{status, accepted_at}` | after sign-in |
| Dashboard KPIs | GET `/dashboard/individual` | P (min user) | `date_from,date_to,timezone[,user_id]` | `IndividualDashboardResponse{summary, timeline, top_*_apps, top_projects, activity_level}` | on open / ⌘R |
| Dashboard week target | GET `/leave/policy/me` | P | — | `EffectivePolicyOut.weekly_required_hours` | on open |
| Weekly chart | GET `/analytics/utilisation` | P | `date_from,date_to,timezone` | `{days[{date,active_sec,idle_sec,break_sec,utilisation_pct}], avg_utilisation_pct}` | on open |
| Productivity report | GET `/analytics/productivity-score` | P | same | `{days[{date,score,band,…}], avg_score}` | on open |
| App / domain usage | GET `/analytics/app-usage`, `/analytics/domain-usage` | P | `+page,page_size` | `{items, total_sec, total, page, page_size}` | on open |
| Team | GET `/dashboard/team` | P (manager+) | `date_from,date_to,timezone,group_id,user_ids` | `TeamDashboardResponse` | on open, 5 min |
| Team members | GET `/managers/me/users` | P (manager) | — | users | on open |
| Projects / tasks | GET `/projects/assigned` | P\|A | — | `[AssignedProjectOut{id,name,description,tasks[{id,name,description}]}]` | on open |
| | GET `/projects/{id}/tasks` | P | `page,page_size` | `TaskListResponse` | |
| History | GET `/task-time` | P | `user_id,task_id,project_id,date_from,date_to,timezone,is_manual,page,page_size(≤?)` | `{items[TaskTimeLogOut], total, page, page_size}` | on range change |
| Summaries | GET `/task-time/summary`, `/task-time/project-summary` | P | `date_from,date_to,timezone` | `{items, total_duration_sec}` | |
| Manual entry | POST `/task-time/manual` | P (**admin+**) | `{user_id, task_id, project_id?, started_at, ended_at, timezone?}` | `ManualTimeLogOut` | |
| Leave balance | GET `/leave/balance` | P | `user_id?,year?` | `LeaveBalanceOut` incl. computed `paid_remaining`, `comp_off_remaining`, `total_leave_taken` | after any leave action |
| Leave list | GET `/leave/applications` | P (scoped by role) | `user_id,status,source,start_from,start_to,page(≥1),page_size(1–200)` | `{items[LeaveApplicationOut], total, page, page_size}` | |
| Leave detail | GET `/leave/applications/{id}` | P | — | `LeaveApplicationOut` | |
| Apply | POST `/leave/applications` | P | `{user_id?, start_date, end_date, half_day, reason?}` | `LeaveApplicationOut` (+`message`) | |
| Edit | PATCH `/leave/applications/{id}` | P | `{start_date?, end_date?, half_day?, reason?, client_updated_at?}` | | |
| Withdraw | DELETE `/leave/applications/{id}` | P | — | `LeaveApplicationOut` (cancelled) | |
| Approve / reject | POST `…/{id}/manager-approve` · `manager-reject` | P manager+ | `{client_updated_at?}` · `{rejection_reason}` | `LeaveApplicationOut` | |
| | POST `…/{id}/admin-approve` · `admin-reject` | P admin+ | — · `{rejection_reason}` | | |
| Bulk | POST `/leave/applications/bulk-approve` · `bulk-reject` | P manager+ | `{application_ids}` · `+rejection_reason` | `BulkLeaveActionResponse` | |
| Calendar | GET `/leave/calendar` | P | `year,month(required),user_id?` | `{year,month,month_leave_count,holiday_count,days[CalendarDay]}` | per month |
| Holidays | GET `/leave/holidays` | P | `year?,user_id?` | `[HolidayOut]` | |
| | POST `/leave/holidays/{id}/claim-compoff` · `/apply-leave` | P | `{holiday_id?, reason?}` | `LeaveApplicationOut` | |
| | POST · DELETE `/leave/holidays[/{id}]` | P admin | `{date,name,description?}` | `HolidayOut` | |
| Policy (admin) | GET · PUT `/leave/policy`; GET `/leave/balance/all?year` | P admin | `LeavePolicyUpsert` | | |
| Notifications | GET `/notifications` | P | `skip,limit(1–200),unread_only` | `{items[NotificationOut], total, unread_count}` | 60 s while visible |
| | GET `/notifications/unread-count` · PATCH `/{id}/read` · POST `/mark-all-read` | P | | `{count}` · `NotificationOut` · `{updated}` | |
| Reports export | POST `/reports/generate` → GET `/reports/{id}/status` → GET `/reports/{id}/download` | P manager+ | `timezone` + body | job → presigned download | poll 2 s, max 2 min |
| Agent (via daemon) | GET `/agent/config`, `/agent/time-stats`; POST `/activity/batch`, `/screenshots/upload` | A | see RUST_AGENT_INTEGRATION.md | | agent schedule |
| Updates | GET `/agent/version` | — | — | `{version, download_url, sha256, min_supported_version}` (Windows/Tauri feed) | not used for native |

## Gaps (documented — no endpoints invented)

| # | Need | Current backend | Proposal (additive, needs approval) |
|---|---|---|---|
| B2 | Desktop SSO | SAML ACS returns to portal only | `effilens://auth/callback?code=` one-time code + `POST /auth/native/exchange` (PKCE, 60 s single-use code, issues portal session + agent token, audited) |
| B3 | Live team presence | None (`agent_devices.last_seen` exists) | `GET /managers/me/presence` derived from `last_seen` + latest event type |
| B4 | Task priority / due / estimate, project client / progress | Not in `tasks`/`projects` | Hide in UI; propose columns only if product wants them |
| B5 | Employee manual entries + approval (≤2 h auto, 7-day window) | Manual entry admin-only, no approval | Hide for non-admins |
| B6 | Device identity / platform | `agent_devices` has no platform; login fixed name `workpulse-agent` | Optional `device_name`, `platform` on `AgentLoginRequest`; nullable column (migration) |
| B7 | Native update feed | Tauri-format `/agent/update/{target}/…` | Sparkle appcast (static, CDN) or `GET /agent/appcast/macos-native.xml` |
| B8 | Configurable leave types, comments, reminders, notify-HR, holiday types, accrual | Fixed enums | Separate approval (affects portal) |
| B9 | Alembic revisions missing from repo | `schema_validator` expects `20260710_008` | Recover before any migration |
