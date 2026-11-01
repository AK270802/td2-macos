#!/usr/bin/env bash
# Local / remote-Mac developer build of the native EffiLens app (unsigned).
#   ./Scripts/build.sh [Debug|Release]
set -euo pipefail

CONFIGURATION="${1:-Debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

command -v xcodegen >/dev/null || { echo "xcodegen not found: brew install xcodegen" >&2; exit 1; }

xcodegen generate --spec project.yml
swift test --parallel

xcodebuild \
  -project EffiLens.xcodeproj \
  -scheme EffiLens \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$ROOT/build/dd" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
  build

echo "Built: $ROOT/build/dd/Build/Products/$CONFIGURATION/EffiLens.app"
