#!/usr/bin/env bash
# Unsigned (ad-hoc) development packaging. Verifies the bundle, then produces
#   EffiLens.app.zip                     (ditto, preserves bundle metadata)
#   EffiLens-macOS-universal.dmg         (drag-to-Applications)
#   EffiLens-macOS-universal.pkg         (installs to /Applications, no scripts)
#   SHA256SUMS.txt, build-metadata.txt
# and validates the DMG/PKG structure. Not notarised — see INSTALL_AND_TEST.md.
#
# Usage: package.sh <path/to/EffiLens.app> <out-dir> [suffix]
#   suffix defaults to "universal"; Debug builds pass e.g. "universal-debug".
set -euo pipefail

APP_IN="${1:?app path}"
OUT="${2:?output dir}"
SUFFIX="${3:-universal}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ENTITLEMENTS="$HERE/../Resources/EffiLens.entitlements"

[ -d "$APP_IN" ] || { echo "App bundle not found: $APP_IN" >&2; exit 1; }
mkdir -p "$OUT"
STAGE="$(mktemp -d)"
trap 'hdiutil detach "$STAGE/mnt" -quiet >/dev/null 2>&1 || true; hdiutil detach "$STAGE/rwmnt" -force -quiet >/dev/null 2>&1 || true; rm -rf "$STAGE"' EXIT

APP="$STAGE/EffiLens.app"
ditto "$APP_IN" "$APP"
# Never ship local state.
find "$APP" \( -name "*.db" -o -name "*.sqlite*" -o -name "ipc.token" -o -name ".DS_Store" \) -print -delete

fail() { echo "::error::$*" >&2; exit 1; }

# ── Bundle validation ─────────────────────────────────────────────────
plutil -lint "$APP/Contents/Info.plist"
pb() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist"; }
BUNDLE_ID="$(pb CFBundleIdentifier)"
VERSION="$(pb CFBundleShortVersionString)"
BUILD="$(pb CFBundleVersion)"
MIN_OS="$(pb LSMinimumSystemVersion)"
[ "$BUNDLE_ID" = "com.baseel.effilens.mac" ] || fail "Unexpected bundle id: $BUNDLE_ID"
[ "$MIN_OS" = "14.0" ] || fail "Unexpected deployment target: $MIN_OS"

require_universal() {
  local bin="$1"
  [ -x "$bin" ] || fail "Missing or non-executable: $bin"
  local archs; archs="$(lipo -archs "$bin")"
  echo "$(basename "$bin"): $archs"
  [[ "$archs" == *arm64* && "$archs" == *x86_64* ]] || fail "$bin is not universal ($archs)"
}
require_universal "$APP/Contents/MacOS/EffiLens"
file "$APP/Contents/MacOS/EffiLens"

AGENT="$APP/Contents/MacOS/effilens-agentd"
PLIST="$APP/Contents/Library/LaunchAgents/com.baseel.effilens.mac.agent.plist"
if [ -f "$AGENT" ]; then
  require_universal "$AGENT"
  AGENT_STATUS="embedded"
else
  [ "${ALLOW_MISSING_AGENT:-0}" = "1" ] || fail "effilens-agentd is not embedded"
  AGENT_STATUS="missing"
fi
[ -f "$PLIST" ] || fail "LaunchAgent plist missing"
plutil -lint "$PLIST"
[ "$(/usr/libexec/PlistBuddy -c 'Print :Label' "$PLIST")" = "com.baseel.effilens.mac.agent" ] || fail "LaunchAgent label mismatch"
[ "$(/usr/libexec/PlistBuddy -c 'Print :BundleProgram' "$PLIST")" = "Contents/MacOS/effilens-agentd" ] || fail "LaunchAgent BundleProgram mismatch"
if grep -q "__API_URL__" "$PLIST"; then fail "LaunchAgent API URL placeholder not substituted"; fi
test -f "$APP/Contents/Resources/Assets.car" || fail "Asset catalogue missing"
test -f "$APP/Contents/Resources/AppIcon.icns" || /usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$APP/Contents/Info.plist" >/dev/null || fail "App icon missing"
# No credentials in the bundle.
if grep -rIl -E "(BEGIN (RSA|EC|OPENSSH) PRIVATE KEY|wp_refresh_token=[A-Za-z0-9])" "$APP" 2>/dev/null; then fail "Possible secret in bundle"; fi

# ── Ad-hoc signature (inside-out) ─────────────────────────────────────
# Unsigned arm64 code will not launch; an ad-hoc signature lets the
# development build run after the user approves it in Privacy & Security.
# This is NOT a Developer ID signature and the app is NOT notarised.
# Nested code first: Debug builds carry EffiLens.debug.dylib / __preview.dylib
# (Xcode 16 debug-dylib mode); any embedded frameworks/dylibs are signed too.
while IFS= read -r -d '' nested; do
  codesign --force --sign - --timestamp=none "$nested"
done < <(find "$APP/Contents" \( -name "*.dylib" -o -name "*.framework" \) -print0)
if [ -f "$AGENT" ]; then
  codesign --force --sign - --options runtime --timestamp=none "$AGENT"
fi
codesign --force --sign - --options runtime --timestamp=none --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# ── Outputs ───────────────────────────────────────────────────────────
DMG="$OUT/EffiLens-macOS-$SUFFIX.dmg"
PKG="$OUT/EffiLens-macOS-$SUFFIX.pkg"
ZIP="$OUT/EffiLens.app.zip"
[ "$SUFFIX" = "universal" ] || ZIP="$OUT/EffiLens-$SUFFIX.app.zip"

ditto -c -k --keepParent "$APP" "$ZIP"

retry() {
  local n=1
  until "$@"; do
    [ "$n" -ge 5 ] && return 1
    echo "retry $n: $*" >&2
    n=$((n + 1)); sleep $((n * 3))
  done
}

# Installer artwork rendered by Scripts/installer/render-assets.mjs (optional;
# plain installers are produced when it is absent).
ASSETS="${INSTALLER_ASSETS:-}"
RES_DIR="$HERE/../Resources/Installer"

# ── PKG (guided installer) ────────────────────────────────────────────
# Component package: the app bundle only (agent + LaunchAgent live inside it,
# so no files outside /Applications/EffiLens.app are ever written).
# BundleIsRelocatable=false keeps upgrades at /Applications/EffiLens.app.
mkdir -p "$STAGE/pkgroot"
ditto "$APP" "$STAGE/pkgroot/EffiLens.app"
pkgbuild --analyze --root "$STAGE/pkgroot" "$STAGE/components.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$STAGE/components.plist"
/usr/libexec/PlistBuddy -c "Set :0:BundleIsVersionChecked true" "$STAGE/components.plist"
mkdir -p "$STAGE/pkgs"
pkgbuild \
  --root "$STAGE/pkgroot" \
  --component-plist "$STAGE/components.plist" \
  --identifier "com.baseel.effilens.mac.pkg" \
  --version "$VERSION.$BUILD" \
  --install-location /Applications \
  "$STAGE/pkgs/EffiLens-component.pkg" >/dev/null

# Distribution: branded welcome / summary + background (prototype #installer).
# Installer.app's own steps (Introduction · Destination · Installation Type ·
# Installation · Summary) match the prototype's step list. No license step:
# no legal agreement text has been provided for the native app.
mkdir -p "$STAGE/pkgres"
cp "$RES_DIR/welcome.html" "$RES_DIR/conclusion.html" "$STAGE/pkgres/"
BG_XML=""
if [ -n "$ASSETS" ] && [ -f "$ASSETS/pkg-background.png" ]; then
  cp "$ASSETS/pkg-background.png" "$ASSETS/pkg-background-dark.png" "$STAGE/pkgres/"
  BG_XML='<background file="pkg-background.png" alignment="bottomleft" scaling="none"/>
    <background-darkAqua file="pkg-background-dark.png" alignment="bottomleft" scaling="none"/>'
fi
cat > "$STAGE/distribution.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>EffiLens</title>
    <welcome file="welcome.html" mime-type="text/html"/>
    <conclusion file="conclusion.html" mime-type="text/html"/>
    $BG_XML
    <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
    <volume-check><allowed-os-versions><os-version min="14.0"/></allowed-os-versions></volume-check>
    <choices-outline><line choice="default"><line choice="com.baseel.effilens.mac.pkg"/></line></choices-outline>
    <choice id="default"/>
    <choice id="com.baseel.effilens.mac.pkg" visible="false"><pkg-ref id="com.baseel.effilens.mac.pkg"/></choice>
    <pkg-ref id="com.baseel.effilens.mac.pkg" version="$VERSION.$BUILD" onConclusion="none">EffiLens-component.pkg</pkg-ref>
</installer-gui-script>
XML
productbuild --distribution "$STAGE/distribution.xml" --resources "$STAGE/pkgres" \
  --package-path "$STAGE/pkgs" "$PKG" >/dev/null

# ── DMG (prototype #dmg: 620×400, app → Applications, guided installer) ──
DMG_DONE=0
if [ -n "$ASSETS" ] && [ -f "$ASSETS/dmg-background.png" ] && command -v create-dmg >/dev/null; then
  mkdir -p "$STAGE/dmgsrc"
  ditto "$APP" "$STAGE/dmgsrc/EffiLens.app"
  tiffutil -cathidpicheck "$ASSETS/dmg-background.png" "$ASSETS/dmg-background@2x.png" -out "$STAGE/dmg-background.tiff" >/dev/null 2>&1 \
    || cp "$ASSETS/dmg-background.png" "$STAGE/dmg-background.tiff"
  rm -f "$DMG"
  if create-dmg \
      --volname "EffiLens $VERSION" \
      --background "$STAGE/dmg-background.tiff" \
      --window-pos 200 120 --window-size 620 428 \
      --icon-size 96 --text-size 13 \
      --icon "EffiLens.app" 170 215 \
      --app-drop-link 450 215 \
      --hide-extension "EffiLens.app" \
      --no-internet-enable \
      "$DMG" "$STAGE/dmgsrc" >/dev/null; then
    DMG_DONE=1
    echo "Branded DMG created (create-dmg)"
  else
    echo "::warning::create-dmg failed — falling back to a plain DMG"
  fi
fi
if [ "$DMG_DONE" = 0 ]; then
  # GitHub macOS runners intermittently fail `hdiutil create -srcfolder` with
  # "Resource busy". Build a blank writable image, copy in, convert; retry.
  mkdir -p "$STAGE/dmg"
  ditto "$APP" "$STAGE/dmg/EffiLens.app"
  SIZE_MB=$(( $(du -sm "$STAGE/dmg" | cut -f1) + 40 ))
  RW="$STAGE/rw.dmg"
  retry hdiutil create -size "${SIZE_MB}m" -fs HFS+ -volname "EffiLens $VERSION" -ov "$RW" >/dev/null
  mkdir -p "$STAGE/rwmnt"
  retry hdiutil attach "$RW" -nobrowse -noverify -mountpoint "$STAGE/rwmnt" -quiet
  ditto "$STAGE/dmg/EffiLens.app" "$STAGE/rwmnt/EffiLens.app"
  ln -s /Applications "$STAGE/rwmnt/Applications"
  sync
  retry hdiutil detach "$STAGE/rwmnt" -quiet || retry hdiutil detach "$STAGE/rwmnt" -force -quiet
  rm -f "$DMG"
  retry hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
fi

# ── Installer validation ──────────────────────────────────────────────
echo "Validating DMG…"
hdiutil verify "$DMG" >/dev/null
mkdir -p "$STAGE/mnt"
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$STAGE/mnt" -quiet
test -d "$STAGE/mnt/EffiLens.app" || fail "DMG: EffiLens.app missing"
[ -L "$STAGE/mnt/Applications" ] || fail "DMG: Applications shortcut missing"
require_universal "$STAGE/mnt/EffiLens.app/Contents/MacOS/EffiLens"
[ "$AGENT_STATUS" = "missing" ] || require_universal "$STAGE/mnt/EffiLens.app/Contents/MacOS/effilens-agentd"
codesign --verify --strict "$STAGE/mnt/EffiLens.app"
hdiutil detach "$STAGE/mnt" -quiet

echo "Validating PKG…"
pkgutil --check-signature "$PKG" || true   # expected: unsigned
pkgutil --expand-full "$PKG" "$STAGE/pkgx"
PAYLOAD_APP="$(find "$STAGE/pkgx" -maxdepth 3 -type d -name EffiLens.app | head -1)"
[ -n "$PAYLOAD_APP" ] || fail "PKG: EffiLens.app not in payload"
require_universal "$PAYLOAD_APP/Contents/MacOS/EffiLens"
[ "$AGENT_STATUS" = "missing" ] || require_universal "$PAYLOAD_APP/Contents/MacOS/effilens-agentd"
test -f "$PAYLOAD_APP/Contents/Library/LaunchAgents/com.baseel.effilens.mac.agent.plist" || fail "PKG: LaunchAgent plist missing"
grep -q 'install-location="/Applications"\|<pkg-info[^>]*install-location="/Applications"' "$STAGE"/pkgx/*/PackageInfo || fail "PKG: install location is not /Applications"
OUTSIDE="$(find "$STAGE"/pkgx/*/Payload -mindepth 1 -maxdepth 1 ! -name EffiLens.app)"
[ -z "$OUTSIDE" ] || fail "PKG installs files outside EffiLens.app: $OUTSIDE"
if find "$STAGE"/pkgx -name "Scripts" -mindepth 2 -maxdepth 2 | grep -q .; then fail "PKG contains install scripts"; fi

# ── Metadata & checksums ──────────────────────────────────────────────
{
  echo "EffiLens $VERSION ($BUILD) — $SUFFIX"
  echo "bundle_id=$BUNDLE_ID"
  echo "minimum_macos=$MIN_OS"
  echo "agent=$AGENT_STATUS"
  echo "signature=ad-hoc (NOT Developer ID, NOT notarised)"
  echo "commit=${GITHUB_SHA:-local}"
  echo "run=${GITHUB_SERVER_URL:-}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}"
  echo "built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  sw_vers | sed 's/^/runner_/'
  xcodebuild -version | tr '\n' ' ' | sed 's/^/xcode=/'; echo
} > "$OUT/build-metadata-$SUFFIX.txt"

( cd "$OUT" && shasum -a 256 "$(basename "$DMG")" "$(basename "$PKG")" "$(basename "$ZIP")" > "SHA256SUMS-$SUFFIX.txt" )
cat "$OUT/SHA256SUMS-$SUFFIX.txt"
ls -lh "$OUT"
