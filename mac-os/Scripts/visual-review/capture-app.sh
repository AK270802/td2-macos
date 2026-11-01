#!/usr/bin/env bash
# Captures every screen of a DEBUG EffiLens.app in light and dark mode using
# the app's built-in review mode (Sources/App/ReviewMode.swift). The app is
# not signed in: screens show their real loading/empty/error states.
# Usage: capture-app.sh <EffiLens.app> <out-dir>
set -uo pipefail

APP="${1:?app path}"
OUT="${2:?output dir}"
BIN="$APP/Contents/MacOS/EffiLens"
mkdir -p "$OUT"

SCREENS=(signin onboarding-setup onboarding-privacy onboarding-permissions
  dashboard tracker projects tasks history manualEntry
  leaveOverview applyLeave myRequests leaveCalendar leaveBalance holidays
  team approvals reports notifications activity settings about menubar mini)

failures=0
for theme in light dark; do
  for screen in "${SCREENS[@]}"; do
    file="$OUT/$screen-$theme.png"
    "$BIN" -EffiLensReview "$screen" -EffiLensReviewAppearance "$theme" -EffiLensReviewOutput "$file" \
      -ApplePersistenceIgnoreState YES >/dev/null 2>&1 &
    pid=$!
    for _ in $(seq 1 40); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null
      echo "timeout: $screen ($theme)"
    fi
    if [ -s "$file" ]; then
      echo "captured $screen-$theme.png"
    else
      echo "::warning::no capture for $screen ($theme)"
      failures=$((failures + 1))
    fi
  done
done
echo "capture failures: $failures"
