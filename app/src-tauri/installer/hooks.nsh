; WorkPulse NSIS installer hooks.
; agentd.exe is bundled as a resource and lands in $INSTDIR\agentd.exe.
;
; The installer runs in "currentUser" mode (installMode: currentUser in
; tauri.conf.json) specifically so it never triggers a UAC elevation prompt —
; required for users in orgs without local admin rights. That means every
; write this hook makes MUST stay under HKCU: an HKLM write here would
; silently fail (or, worse, force elevation back on) for non-admin installs.
; agentd itself already only ever runs in the user session (desktop capture
; is impossible from a session-0 service), so a per-user Run key is not a
; regression — it's the same effective behavior, just scoped correctly.

!macro NSIS_HOOK_POSTINSTALL
  ; Best-effort cleanup of the legacy Windows Service from older
  ; (admin-installed) builds. Requires admin to actually remove; for
  ; non-admin installs this just no-ops rather than blocking install.
  nsExec::Exec 'sc stop WorkPulseAgent'
  nsExec::Exec 'sc delete WorkPulseAgent'
  ; Best-effort cleanup of the old HKLM autostart entry from pre-per-user
  ; builds, in case this machine was previously admin-installed.
  DeleteRegValue HKLM "Software\Microsoft\Windows\CurrentVersion\Run" "WorkPulseAgentd"
  ; Per-login autostart of the capture agent for the current user only.
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "WorkPulseAgentd" '"$INSTDIR\agentd.exe" run'
!macroend

!macro NSIS_HOOK_PREUNINSTALL
  DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "WorkPulseAgentd"
  DeleteRegValue HKLM "Software\Microsoft\Windows\CurrentVersion\Run" "WorkPulseAgentd"
  ; Best-effort stop of a running agentd in the current session.
  nsExec::Exec 'taskkill /IM agentd.exe /F'
!macroend
