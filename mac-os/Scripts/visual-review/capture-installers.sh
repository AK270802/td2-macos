#!/usr/bin/env bash
# Captures the real installation screens for comparison with the prototype's
# #dmg / #installer windows: the mounted DMG's Finder window and Installer.app
# steps for the PKG (advanced with System Events up to — never past — the
# Install button). Uses `screencapture` of the whole display; failures are
# reported as warnings (CI runners may lack the needed GUI permissions).
# Usage: capture-installers.sh <dmg> <pkg> <out-dir>
set -uo pipefail
DMG="${1:?dmg}"; PKG="${2:?pkg}"; OUT="${3:?out}"
mkdir -p "$OUT"

shot() {
  if screencapture -x -o "$1" 2>/dev/null && [ -s "$1" ]; then
    echo "captured $(basename "$1")"
  else
    echo "::warning::could not capture $(basename "$1")"
  fi
}

# ── DMG window (Finder follows the system appearance — light on runners)
open "$DMG"
sleep 10
osascript -e 'tell application "Finder" to activate' >/dev/null 2>&1 || true
shot "$OUT/dmg-light.png"
osascript -e 'tell application "Finder" to close every window' >/dev/null 2>&1 || true
VOL="$(hdiutil info | awk -F'\t' '/\/Volumes\/EffiLens/ {print $NF}' | tail -1)"
if [ -n "$VOL" ]; then hdiutil detach "$VOL" -quiet -force || true; fi

# ── Installer.app steps: Introduction, then Continue (Destination / Type).
open "$PKG"
sleep 10
shot "$OUT/installer-0-light.png"
for step in 1 2 3; do
  if ! osascript >/dev/null 2>&1 <<'OSA'
tell application "System Events" to tell process "Installer"
  set frontmost to true
  click (first button of window 1 whose name is "Continue")
end tell
OSA
  then
    echo "::warning::could not press Continue (System Events lacks Accessibility on this runner)"
  fi
  sleep 3
  shot "$OUT/installer-$step-light.png"
done
osascript -e 'tell application "Installer" to quit' >/dev/null 2>&1 || pkill -x Installer || true
