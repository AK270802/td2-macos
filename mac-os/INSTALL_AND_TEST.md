# EffiLens for macOS: Install and Test (development build)

> **Unsigned development build.** The installers are **ad-hoc signed only**. They are not signed with a Developer ID and are **not notarised**. macOS Gatekeeper blocks the first launch until you approve it (see §4). Do not distribute these builds to end users.

Backend: **development** API `https://dev-workpulse-api.baseel.com` (`/api/v1`). Web portal: `https://dev-workpulse.baseel.com`. Use a **development account only**. Never use a production account.

Requirements: macOS 14 Sonoma or later. Works on Apple Silicon and Intel (universal binaries).

---

## 1. Download the CI artifacts

1. Open GitHub → `AK270802/td2-macos` → **Actions** → workflow **macos-native**.
2. Open the latest green run on `feature/macos-native`.
3. Under **Artifacts**, download **EffiLens-macOS-universal-unsigned** (kept 30 days). It contains:

| File | Purpose |
|---|---|
| `EffiLens-macOS-universal.dmg` | Drag-and-drop install |
| `EffiLens-macOS-universal.pkg` | Installer package (installs to `/Applications`) |
| `EffiLens.app.zip` | Raw app bundle |
| `SHA256SUMS-universal.txt` | Checksums |
| `build-metadata-universal.txt` | Commit, run URL, Xcode/macOS versions |
| `RELEASE_NOTES.md`, `INSTALL_AND_TEST.md` | Notes and this guide |

`EffiLens-macOS-universal-debug-unsigned` is the same app built in Debug, with extra logging. Use it only when diagnosing a problem.

4. Verify the checksums in Terminal:

```bash
cd ~/Downloads/EffiLens-macOS-universal-unsigned
shasum -a 256 -c SHA256SUMS-universal.txt
```

## 2. Choose DMG or PKG

- **DMG**: open it and drag EffiLens onto the Applications shortcut (window styled like the prototype's installer). The guided installer is the separate `EffiLens-macOS-universal.pkg`.
- **PKG**: Installer.app puts `EffiLens.app` in `/Applications`. The package contains no scripts and writes nothing outside `/Applications/EffiLens.app`, and installing again upgrades in place. The tracking agent and its LaunchAgent plist live inside the app bundle.

Install only one of them. Both produce the same app.

## 3. Install

**DMG:** double-click the DMG and drag **EffiLens** onto **Applications**, then eject the disk image.

**PKG:** right-click the PKG and choose **Open**. macOS warns that the package is from an unidentified developer; click **Open**, then follow the installer. If macOS refuses, go to **System Settings › Privacy & Security** and click **Open Anyway** next to the package message.

If an older WorkPulse (Tauri) app is installed, **quit it first**: menu bar icon › Quit. EffiLens refuses to track while the old agent runs, so time is never recorded twice.

## 4. Open the unsigned app safely

1. In Finder, open **Applications**, **right-click EffiLens › Open**, and then click **Open** again.
2. If macOS only offers *Move to Trash* or *Done*, open **System Settings › Privacy & Security**, scroll to *“EffiLens” was blocked…*, click **Open Anyway** and authenticate.
3. Last resort, for testing builds you downloaded yourself from CI only: `xattr -dr com.apple.quarantine /Applications/EffiLens.app`

> Ad-hoc signatures change with every build, so macOS treats each new build as a new app. After installing a new build you may need to **re-grant** Accessibility, Screen Recording and Input Monitoring: remove the old EffiLens entry with `–`, then add the new one.

## 5. First-run onboarding (six steps, inside the app)

1. **Welcome**: overview and privacy summary.
2. **Sign in**: development account email and password.
3. **Consent**: the server-tracked monitoring policy. You must accept it to continue.
4. **Permissions**: Accessibility, Screen Recording, Input Monitoring, Notifications and Automation (§6).
5. **Background agent**: approve EffiLens in Login Items (§6).
6. **Ready**.

## 6. Grant permissions

Each permission is optional. If you deny one, EffiLens keeps running with reduced capability, and the banner at the top of the main window lists what's missing.

| Permission | Where | Without it |
|---|---|---|
| Accessibility | Privacy & Security › Accessibility | Window titles are blank |
| Screen Recording | Privacy & Security › Screen & System Audio Recording | Screenshots are **skipped** (never full-screen) |
| Input Monitoring | Privacy & Security › Input Monitoring | Keyboard/mouse activity counts stay 0 (typed content is never read) |
| Automation | Prompted per browser the first time a browser is frontmost while tracking | Website domain is omitted |
| Notifications | Prompted from onboarding or Settings › Notifications | No reminders or idle alerts |
| Login Items (“Allow in the Background”) | General › Login Items | The tracking agent cannot run, and the app shows **Agent offline** |

After changing a setting, switch back to EffiLens. Status refreshes automatically, or click **Refresh**. macOS may ask you to quit and reopen EffiLens after granting Screen Recording.

## 7. Sign in with the development account

Use your **development** account on `dev-workpulse-api.baseel.com`. The sign-in screen shows the server host under the form, so check it says `dev-workpulse-api.baseel.com`.

Note: signing in revokes the account's previous desktop agent token (backend behaviour), so the old Tauri agent signed in with the same account is signed out.

## 8. Verify the Dashboard

- The KPIs (today, week, utilisation) match the web portal for the same account and date.
- The weekly chart and recent sessions load, and empty states appear for a new account. No sample data is ever shown.
- Press **⌘R** or reopen the screen to refresh.

## 9. Verify Leave

- **Leave Overview / Balance**: the paid and comp-off figures match the portal.
- **Apply for Leave**: submit a **future, harmless** request (for example a half day). It appears in **My Requests** as *Pending*.
- **Details › Withdraw**: the status becomes *Cancelled*. Clean up any test requests you create.
- **Calendar** and **Holidays** match the portal.
- A manager account sees the request under **Approvals**. **Only approve or reject test requests.**

## 10. Verify tracking

1. Open **Time Tracker**. The status pill shows **Connected** (or *Synced · …*).
2. Click **Track** next to a task. The timer starts, and the menu-bar timer shows the elapsed time.
3. Test **Pause / Resume**, **Take a Break…** and **Stop**.
4. Open **Settings › Diagnostics**. *Queued events* grows while you track and drops after a sync. **Sync Now** forces a sync.
5. After about 5 minutes (or Sync Now), **History** and the portal show the session.
6. **Idle**: stop using the Mac for longer than the organisation's idle threshold. You get an idle prompt or notification.
7. **Reminder**: in Settings › General, set *Reminder Notification Interval (When Inactive)* to 5 minutes and click **Save Settings**. Leave tracking stopped; you get the “Effilens Tracker Inactive” notification after 5 minutes.

## 11. Verify screenshots

Screenshots are only taken if the organisation has enabled them (Settings › Screenshots shows the policy) and Screen Recording is allowed.

- While tracking, wait one screenshot interval. In the portal, the screenshot shows **only the active window**, blurred.
- Revoke Screen Recording. No screenshots are taken, and EffiLens never falls back to a full-screen capture.

## 12. Verify browser detection

Track a task with Safari or Chrome in front and approve the Automation prompt. In the portal's activity view (or **Activity** in the app, after a sync), only the **domain** appears, for example `github.com`. Full URLs are never stored.

## 13. Verify menu-bar controls

- Click the menu-bar timer. The popover shows the timer, task, **Start/Pause**, **Stop**, **Open Dashboard**, **Show Mini Timer**, **Settings…** and **Quit**.
- **Show Mini Timer** opens a small floating window that stays on top of other windows.
- The keyboard shortcuts **⌃⌥Space** (start/pause), **⌃⌥S** (stop) and **⇧⌘M** (mini timer) work from the menu bar's Tracking menu.
- **Quit while tracking** offers *Keep Tracking & Quit* (the agent keeps running) or *Stop Tracking & Quit*.

## 14. Verify agent restart and recovery

```bash
launchctl print gui/$(id -u)/com.baseel.effilens.mac.agent | head -20   # agent registered/running
pkill -f effilens-agentd                                                 # simulate a crash
```

- launchd restarts the agent within a few seconds. The app briefly shows **Agent offline**, then reconnects and hands the session back automatically.
- Quit and reopen the app. Tracking state is preserved.
- Restart the Mac. The agent starts at login. If you saved **Launch at Mac Startup**, the app starts too.
- Turn Wi-Fi off while tracking. The **Offline** banner appears and events are queued. Turn Wi-Fi back on; the queue drains (watch Diagnostics).

## 15. Verify logout

1. Account menu (sidebar, bottom) › **Sign Out**, or Settings › Account › **Sign Out…**.
2. The dialog warns how many unsynced records will be removed. Confirm.
3. Tracking stops, and the agent clears this account's local unsynced activity (approved logout contract).
4. Sign in with a **second** development account. None of the first account's activity is uploaded under the second account.
5. Repeat the logout while offline (Wi-Fi off). Logout still completes locally.

## 16. Remove EffiLens safely

1. In EffiLens, choose **Sign Out**, then **Quit EffiLens**.
2. Open **System Settings › General › Login Items** and remove EffiLens if it's listed.
3. Delete the app: drag `/Applications/EffiLens.app` to the Trash.
4. Optionally, remove local data and preferences:

```bash
launchctl bootout gui/$(id -u)/com.baseel.effilens.mac.agent 2>/dev/null || true
rm -rf ~/Library/Application\ Support/EffiLens
defaults delete com.baseel.effilens.mac 2>/dev/null || true
security delete-generic-password -s com.baseel.effilens.mac 2>/dev/null || true   # repeat until "could not be found"
pkgutil --forget com.baseel.effilens.mac.pkg 2>/dev/null || true                  # PKG installs only
tccutil reset All com.baseel.effilens.mac                                          # privacy permissions
```

The legacy WorkPulse data in `~/Library/Application Support/WorkPulseAgentRust` is **not** touched.

---

## Switching environment (developers)

The API host is fixed per build in `project.yml` (`EFFILENS_API_BASE_URL`, development by default). The UI can be pointed at another **non-production** HTTPS server with:

```bash
defaults write com.baseel.effilens.mac effilens.serverOverride https://your-test-host.example
defaults delete com.baseel.effilens.mac effilens.serverOverride   # back to default
```

The background agent's API comes from its LaunchAgent plist and must be the same. `set_session` refuses a mismatched host.

## Manual test checklist

Record each item as PASS / FAIL / BLOCKED, with the macOS version and the chip (Apple Silicon or Intel).

- [ ] DMG install opens on Apple Silicon
- [ ] DMG install opens on Intel
- [ ] PKG install, and upgrade by reinstalling
- [ ] Gatekeeper “Open Anyway” flow
- [ ] Onboarding steps 1–6
- [ ] Each permission granted, and each denied (reduced mode, no crash)
- [ ] Login Items approval → agent runs (`launchctl print …`)
- [ ] Sign-in (dev), consent
- [ ] Dashboard figures match the portal
- [ ] Leave: overview, apply, withdraw, calendar, holidays, balance
- [ ] Approvals (manager account, test requests only)
- [ ] Team, Reports, Activity, Notifications load for the right roles
- [ ] Tracking start/pause/break/stop, and History after sync
- [ ] Idle warning and inactive reminder
- [ ] Window-only blurred screenshot, and skipped without permission
- [ ] Browser domain only
- [ ] Menu bar, mini timer, shortcuts, quit-while-tracking
- [ ] Agent crash → auto restart → session restored
- [ ] Offline queue → recovery
- [ ] Logout clears unsynced data, and account B never uploads account A's data
- [ ] Uninstall per §16

## Permissions: two identities (macOS 14 and later)

EffiLens has two processes that macOS checks for permission separately:

| Process | Shown in System Settings as | Used for |
|---|---|---|
| EffiLens.app | **EffiLens** | UI and notifications |
| Tracking agent (launchd LaunchAgent) | **effilens-agentd** | Accessibility, Screen Recording and Input Monitoring capture |

launchd starts the agent as its own *responsible process*. When the agent captures, macOS checks the agent's code identity, not the app's. Before this fix, turning on "EffiLens" alone left capture blocked while the UI showed `Allow…`.

What happens now:
- **Allow… / Enable agent…** asks both the app and the agent to register in that Privacy & Security list, then opens the pane.
- A row shows **Allowed** only when the agent can capture.
- **Enable agent…** means EffiLens is allowed but `effilens-agentd` is not yet.
- If the agent can't be reached, the state is unknown, and the row falls back to the app's own check. It never shows "denied" just because the agent didn't answer.
- Status refreshes when the list appears, every 2 s while it is visible, when the app becomes active (for example after returning from System Settings), on **Recheck**, and when tracking starts.

### Permissions after an update (unsigned / ad-hoc builds)

Ad-hoc signatures are pinned to the binary's hash (cdhash), so every new build is a "different app" to macOS. An old switch can stay **on** in System Settings but no longer apply. If a row says `Allow…` while the switch is already on:
1. Select the entry (EffiLens or effilens-agentd) and remove it with **−**.
2. Click **Allow… / Enable agent…** in EffiLens again and turn the new entry on.
3. Restart tracking. For Screen Recording, macOS may ask you to quit and reopen the app.

**Permanent fix:** sign with a **Developer ID** certificate (`Scripts/release.sh`) and notarise. macOS then keys the grants to Team ID + bundle identifier (`com.baseel.effilens.mac`, agent `com.baseel.effilens.mac.agent`), so they survive updates. For managed fleets, a PPPC (MDM) profile can pre-approve Accessibility and Input Monitoring. Screen Recording can only be pre-set to "allow standard users to approve".

### Manual test checklist
1. Fresh install → onboarding: every capture row shows `Allow…`.
2. Click Allow… on Screen Recording: System Settings opens, and both EffiLens and effilens-agentd are listed.
3. Turn on only EffiLens → within about 2 s the row shows **Enable agent…**, and the footnote explains why.
4. Turn on effilens-agentd → the row shows **Allowed** without restarting the app.
5. Turn it off → the row goes back to Allow…, and the dashboard banner lists the permission.
6. Quit the agent (`launchctl bootout gui/$UID/com.baseel.effilens.mac.agent`) → rows fall back to the app's status (no false "denied"). Click Recheck after the agent restarts.
7. Start tracking with everything allowed → no banner, screenshots upload, and activity counts are above zero.
8. Repeat on macOS 14, 15 and 26.
