#!/usr/bin/env bash
# Xcode build phase: embeds the universal Rust agent and its LaunchAgent plist.
# The agent is produced by `cargo build -p agentd --features macos-native`
# (see BUILD_AND_RELEASE.md) and placed at mac-os/build/agent/effilens-agentd.
set -euo pipefail

DEST="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}"
AGENT="${SRCROOT}/build/agent/effilens-agentd"
mkdir -p "${DEST}/MacOS" "${DEST}/Library/LaunchAgents"

if [ -f "${AGENT}" ]; then
  install -m 0755 "${AGENT}" "${DEST}/MacOS/effilens-agentd"
  echo "Embedded effilens-agentd"
else
  echo "warning: ${AGENT} not found — the app will run without the tracking agent (UI shows 'Agent offline')."
fi

sed -e "s|__API_URL__|${EFFILENS_API_BASE_URL}|g" \
  "${SRCROOT}/Resources/LaunchAgent.plist.in" \
  > "${DEST}/Library/LaunchAgents/com.baseel.effilens.mac.agent.plist"
plutil -lint "${DEST}/Library/LaunchAgents/com.baseel.effilens.mac.agent.plist"
