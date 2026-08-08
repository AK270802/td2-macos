# Builds the WorkPulse installer with updater-artifact signing enabled.
#
# `tauri build` does NOT read a .env file for signing -- it only reads the
# TAURI_SIGNING_PRIVATE_KEY environment variable directly, and it wants the
# *contents* of the key file (a two-line minisign blob), not a path. This
# script reads that file and exports it correctly so you don't have to
# copy/paste the key by hand.
#
# One-time setup, if src-tauri/keys/workpulse-updater.key doesn't exist yet:
#   npx tauri signer generate -w src-tauri/keys/workpulse-updater.key --ci
# --ci generates it without a password. If you generate one WITH a password
# instead, also set $env:TAURI_SIGNING_PRIVATE_KEY_PASSWORD below.
#
# Usage (from workpulse-rust/app):
#   .\build-release.ps1

$keyPath = Join-Path $PSScriptRoot "src-tauri\keys\workpulse-updater.key"
if (-not (Test-Path $keyPath)) {
    Write-Error "Signing key not found at $keyPath. Generate one first with:`n  npx tauri signer generate -w src-tauri\keys\workpulse-updater.key --ci"
    exit 1
}

$env:TAURI_SIGNING_PRIVATE_KEY = Get-Content -Raw $keyPath
$env:TAURI_SIGNING_PRIVATE_KEY_PASSWORD = ""

npm run tauri build
