#!/usr/bin/env bash
# Signed + notarised release build. Run by .github/workflows/macos-native.yml
# (release job) or on a Mac holding the same environment variables.
# Never echoes secrets. See BUILD_AND_RELEASE.md for the required secrets.
set -euo pipefail

: "${APPLE_TEAM_ID:?}"
: "${MACOS_DEVELOPER_ID_APP_CERT_P12:?}"
: "${MACOS_DEVELOPER_ID_APP_CERT_PASSWORD:?}"
: "${APPLE_NOTARY_API_KEY_P8:?}"
: "${APPLE_NOTARY_KEY_ID:?}"
: "${APPLE_NOTARY_ISSUER_ID:?}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/release"
WORK="$(mktemp -d)"
KEYCHAIN="$WORK/effilens-signing.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"
mkdir -p "$OUT"

cleanup() {
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# 1. Ephemeral keychain with the Developer ID Application certificate.
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 3600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
echo "$MACOS_DEVELOPER_ID_APP_CERT_P12" | base64 --decode > "$WORK/app.p12"
security import "$WORK/app.p12" -k "$KEYCHAIN" -P "$MACOS_DEVELOPER_ID_APP_CERT_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
IDENTITY="Developer ID Application"

# 2. Archive (universal) with hardened runtime + secure timestamp.
cd "$ROOT"
xcodegen generate --spec project.yml
xcodebuild archive \
  -project EffiLens.xcodeproj \
  -scheme EffiLens \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$WORK/EffiLens.xcarchive" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN --timestamp --options runtime"

APP="$WORK/EffiLens.xcarchive/Products/Applications/EffiLens.app"
# Milestone 3: the Rust agent binary + LaunchAgent plist are embedded and signed
# here, inside-out, before the app bundle signature is re-applied.

codesign --verify --deep --strict --verbose=2 "$APP"

# 3. DMG.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$OUT/EffiLens-$VERSION.dmg"
STAGE="$WORK/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/EffiLens.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "EffiLens" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --sign "$IDENTITY" --keychain "$KEYCHAIN" --timestamp "$DMG"

# 4. Notarise + staple.
echo "$APPLE_NOTARY_API_KEY_P8" > "$WORK/notary.p8"
xcrun notarytool submit "$DMG" \
  --key "$WORK/notary.p8" --key-id "$APPLE_NOTARY_KEY_ID" --issuer "$APPLE_NOTARY_ISSUER_ID" \
  --wait --timeout 30m
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

echo "Release artifact: $DMG"
