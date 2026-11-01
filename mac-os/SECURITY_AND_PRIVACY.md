# Security & Privacy

## Credentials
- **Keychain** (`KeychainStore`): generic-password items, service = bundle id, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (no iCloud sync, no migration). Items: portal refresh token, agent token, last email.
- Portal access token (15 min) lives only in memory (`SessionManager` actor).
- Passwords are never persisted; cleared from the view model after sign-in.
- URLSession is ephemeral: no disk cache, cookie jar disabled; the refresh cookie is handled explicitly.
- Data-protection keychain is enabled only once Developer ID signing provides a keychain access group (unsigned dev builds would fail with `errSecMissingEntitlement`).

## Token lifecycle & revocation
- Portal: rotation on every refresh; refresh rejected → credentials wiped, UI returns to sign-in (`SessionEvent.expired`). Offline refresh failures keep credentials.
- Agent: 90-day token, rotated by `/auth/agent/refresh`; admins can revoke via `DELETE /users/{id}/devices/{device_id}` → next agent call 401 → refresh fails → session cleared.
- Sign-out: `stop_tracking` → `clear_session` (daemon forgets token) → `POST /auth/logout` → Keychain wipe.

## IPC
Per-boot 256-bit token (0600, no symlinks), socket 0600 inside a 0700 directory, peer-UID check, constant-time compare, bounded message size, 3 s timeouts. Unauthenticated sockets are prohibited (fixes audit finding on `$TMPDIR/workpulse-agent.sock`).

## Local data
SQLCipher DB (agent), key in Keychain (native daemon). Screenshots blurred **before** any disk write; deleted after successful upload. Local retention = `retention_days` from `/agent/config` (agent prune loop).

## Capture privacy (non-negotiable, CLAUDE.md)
- Keystrokes: integer counts only; event tap never reads key codes or characters.
- URLs: eTLD+1 in memory; raw URL never stored or logged.
- Screenshots: **active window only** via ScreenCaptureKit window filter; if Screen Recording is denied or the window can't be resolved the capture is skipped — never a full-monitor fallback.
- Nothing is captured unless the user has started the timer (`state == running`) and consent is `accepted`.
- Tracking pause/resume is user-initiated.

## Permissions
Requested only from onboarding/settings with explanatory copy; never bypassed. Info.plist: `NSAppleEventsUsageDescription`. TCC prompts: Accessibility, Screen Recording, Input Monitoring, Automation (per browser), Notifications. App Sandbox off (AX + LaunchAgent), Hardened Runtime on.

## Consent
Server-tracked (`/consent/status`); the UI is gated on `status == "accepted"` (fails closed for `pending`, `withdrawn`, unknown). Policy text comes from the tenant.

## Logging
`os.Logger`, subsystem `com.baseel.effilens.mac`. Dynamic values private by default; only paths, status codes and counts marked public. Never log tokens, cookies, passwords, window titles, domains or screenshot data. Exported diagnostics are redacted.

## Transport
HTTPS only (HTTP allowed solely for loopback dev origins). Server override validated by `AppConfiguration.validatedOrigin`. No secrets in Info.plist, source or CI logs.

## Updates
Signed + notarised builds; update feed signatures verified (Sparkle EdDSA or SHA-256 + code-signature check) before install — decision B7.
