; WorkPulse Agent — NSIS service uninstall helper

!define SERVICE_NAME    "WorkPulseAgent"
!define AGENTD_EXE      "$INSTDIR\agentd.exe"

Section "Service Uninstall" SEC_SERVICE_REMOVE
    ; Stop the service first
    ExecWait 'sc stop "$SERVICE_NAME"'
    Sleep 2000

    ; Remove the service registration
    ExecWait '"$AGENTD_EXE" remove' $0
    DetailPrint "agentd remove exited with code $0"

    ; Fallback: if agentd.exe is already gone, use sc directly
    ExecWait 'sc delete "$SERVICE_NAME"' $1
SectionEnd
