; Tauri NSIS installer hook (see app/src-tauri/tauri.conf.json's
; bundle.windows.nsis.installerHooks). Runs as part of the Rust app's own
; installer.
;
; Migrating a user from the old Python-based agent to this one (see the
; RUST_AGENT_ENABLED backend rollout in core-services/app/api/v1/agent.py)
; leaves the Python install in place unless we clean it up here. The Python
; agent (../../agent/installer/workpulse.nsi):
;   - is per-user, no admin, no Windows service (despite service-sounding
;     naming in agent/src/updater/auto_updater.py -- that naming is legacy)
;   - installs to $LOCALAPPDATA\WorkPulse as WorkPulseAgent.exe
;   - autostarts via an HKCU "...\Run" value named "WorkPulse"
;   - ships its own uninstaller at $LOCALAPPDATA\WorkPulse\Uninstall.exe
;
; This Rust app's own autostart entry (tauri-plugin-autostart) may end up
; using that same HKCU Run value name, which would harmlessly overwrite the
; Python one -- but a registry write alone doesn't stop an already-running
; process or remove the old ~30-40MB install directory, so both are handled
; explicitly below. Every step here is best-effort and non-fatal: nsExec
; failures don't abort the Rust install, matching this project's existing
; philosophy (see agentd/common: "loops self-restart, never die").

!macro NSIS_HOOK_PREINSTALL
  StrCpy $0 "$LOCALAPPDATA\WorkPulse"

  ; Ask the Python agent to quit gracefully -- it already implements this
  ; command for its own self-update flow (workpulse.nsi calls the same
  ; `"$INSTDIR\WorkPulseAgent.exe" quit` before overwriting its own files).
  IfFileExists "$0\WorkPulseAgent.exe" 0 +2
    nsExec::ExecToLog '"$0\WorkPulseAgent.exe" quit'

  ; Force-kill a moment later in case "quit" isn't implemented in an older
  ; install, or the process is hung. No-op if it already exited above.
  nsExec::ExecToLog 'taskkill /IM WorkPulseAgent.exe /F'

  ; Prefer the Python installer's own uninstaller -- it knows precisely
  ; which registry keys and shortcuts it created, rather than us duplicating
  ; (and risking drift from) that logic. `_?=$0` keeps it from copying
  ; itself to a temp dir and returning immediately, so this blocks until the
  ; uninstall actually finishes and it's safe to clean up what's left.
  IfFileExists "$0\Uninstall.exe" 0 +2
    nsExec::ExecToLog '"$0\Uninstall.exe" /S _?=$0'

  ; Belt-and-suspenders for installs where the uninstaller is missing or
  ; failed to fully clean up -- harmless no-ops if already gone.
  DeleteRegValue HKCU "SOFTWARE\Microsoft\Windows\CurrentVersion\Run" "WorkPulse"
  RMDir /r "$0"
!macroend
