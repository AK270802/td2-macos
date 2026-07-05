; WorkPulse Agent — NSIS service installation helper
; Called by the main Tauri-generated installer via ExecWait or as a custom action.
; Handles: service registration, recovery config, firewall exception.

!define SERVICE_NAME    "WorkPulseAgent"
!define DISPLAY_NAME    "WorkPulse Agent"
!define AGENTD_EXE      "$INSTDIR\agentd.exe"

Section "Service Install" SEC_SERVICE
    ; Install agentd as a Windows Service
    ExecWait '"$AGENTD_EXE" install' $0
    DetailPrint "agentd install exited with code $0"

    ; Set service to auto-start (already done by agentd.exe install, belt-and-suspenders)
    ExecWait 'sc config "$SERVICE_NAME" start= auto' $1

    ; Service recovery: restart on 1st and 2nd failure, 60s delay, reset counter after 24h
    ExecWait 'sc failure "$SERVICE_NAME" reset= 86400 actions= restart/60000/restart/60000////'

    ; Start the service immediately after install
    ExecWait 'sc start "$SERVICE_NAME"' $2
    DetailPrint "Service start exited with code $2"
SectionEnd

; Silent install support (/S flag) — Tauri NSIS supports this out of the box.
; For Group Policy / MDM deployment, use: WorkPulse_Setup.exe /S /D=C:\Program Files\WorkPulse
