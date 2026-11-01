#!/usr/bin/env bash
# Unsigned packaging for CI / dev: verifies the bundle, then produces
#   EffiLens-<config>.zip   (ditto, preserves bundle metadata)
#   EffiLens-<config>.dmg   (drag-to-Applications)
#   EffiLens-<config>.pkg   (managed install to /Applications, no scripts)
# Usage: package.sh <path/to/EffiLens.app> <out-dir> <configuration>
set -euo pipefail

APP="${1:?app path}"
OUT="${2:?output dir}"
CONFIG="${3:-Debug}"

[ -d "$APP" ] || { echo "App bundle not found: $APP" >&2; exit 1; }
mkdir -p "$OUT"

# Bundle sanity checks.
plutil -lint "$APP/Contents/Info.plist"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[ "$BUNDLE_ID" = "com.baseel.effilens.mac" ] || { echo "Unexpected bundle id: $BUNDLE_ID" >&2; exit 1; }
lipo -info "$APP/Contents/MacOS/EffiLens"
test -f "$APP/Contents/Resources/Assets.car" || { echo "Asset catalogue missing" >&2; exit 1; }
if [ -f "$APP/Contents/MacOS/effilens-agentd" ]; then lipo -info "$APP/Contents/MacOS/effilens-agentd"; fi

NAME="EffiLens-$VERSION-$CONFIG"
ditto -c -k --keepParent "$APP" "$OUT/$NAME.zip"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/dmg/EffiLens.app"
ln -s /Applications "$STAGE/dmg/Applications"
hdiutil create -volname "EffiLens" -srcfolder "$STAGE/dmg" -ov -format UDZO "$OUT/$NAME.dmg" >/dev/null

mkdir -p "$STAGE/pkgroot"
ditto "$APP" "$STAGE/pkgroot/EffiLens.app"
pkgbuild \
  --root "$STAGE/pkgroot" \
  --identifier "com.baseel.effilens.mac.pkg" \
  --version "$VERSION" \
  --install-location /Applications \
  "$OUT/$NAME.pkg" >/dev/null

ls -lh "$OUT"
