# Build & Release

> No macOS build has been run yet. Nothing here should be read as "builds successfully" until the `macos-native` workflow is green.

## Windows development workflow
1. Edit Swift/YAML on Windows (no Swift toolchain needed; none is installed).
2. Push a branch → `.github/workflows/macos-native.yml` runs on `macos-15`.
3. Read `kit-test-report-*` (JUnit XML) and `xcodebuild-log-*` artifacts; download `EffiLens-*-unsigned.zip` to test on a remote Mac.

## Project generation
- `project.yml` (XcodeGen) → `EffiLens.xcodeproj` generated in CI / on the Mac. The `.xcodeproj` is not committed (add `mac-os/EffiLens.xcodeproj/` to `.gitignore` when committing).
- `Package.swift` defines `EffiLensKit` (+ tests) — `swift build` / `swift test` headless.

## Commands (macOS)
```bash
cd workpulse-rust/mac-os
brew install xcodegen
swift test --parallel                     # EffiLensKit unit tests
./Scripts/build.sh Debug                  # generate + test + unsigned build
xcodebuild -project EffiLens.xcodeproj -scheme EffiLens -configuration Release \
  MACOSX_DEPLOYMENT_TARGET=15.0 build     # configurable deployment target
```

## Configurations
| | Debug | Release (CI default) | Release (signed) |
|---|---|---|---|
| Signing | ad-hoc `-` | ad-hoc `-` | Developer ID Application, hardened runtime, `--timestamp` |
| Archs | host | arm64 + x86_64 | arm64 + x86_64 |
| API origin | `EFFILENS_API_BASE_URL` (project.yml) | same | same — confirm prod URL |
| Artifact | — | `EffiLens-Release-unsigned.zip` | notarised, stapled DMG |

⚠️ Environment URLs disagree today: Rust default `https://dev-workpulse-api.baseel.com`, go-agent default `https://workpulse-dev-api.baseel.com`. Portal URL unknown. Confirm per environment.

## Rust agent (Milestone 3)
`cargo build -p agentd --release --features macos-native --target aarch64-apple-darwin` and `x86_64-apple-darwin` → `lipo -create` → `Contents/MacOS/effilens-agentd`; signed before the app bundle.

## Packaging
- **DMG** (default): `Scripts/release.sh` — drag-to-Applications, signed, notarised, stapled.
- **PKG** (optional, MDM/enterprise; needed only for the prototype's multi-step installer): `productbuild` + Developer ID Installer cert.

## Signing & notarisation secrets (GitHub → Settings → Secrets)
| Secret | Content |
|---|---|
| `APPLE_TEAM_ID` | 10-char Team ID |
| `MACOS_DEVELOPER_ID_APP_CERT_P12` | base64 Developer ID Application .p12 |
| `MACOS_DEVELOPER_ID_APP_CERT_PASSWORD` | .p12 password |
| `MACOS_DEVELOPER_ID_INSTALLER_CERT_P12` / `_PASSWORD` | only for PKG |
| `APPLE_NOTARY_API_KEY_P8` | App Store Connect API key (.p8 contents) |
| `APPLE_NOTARY_KEY_ID`, `APPLE_NOTARY_ISSUER_ID` | API key identifiers |

The release job fails fast with a clear message when secrets are absent. Unsigned builds never need them.

## CI matrix
- `macos-15` (Sequoia, Xcode 16) — required.
- `macos-26` (Tahoe) — add to `test-kit.matrix.os` when GitHub publishes the image; until then validate on a remote Tahoe Mac.
- Deployment target 14.0 (Sonoma). APIs used that need 14: `@Observable`, `ContentUnavailableView`, `onChange(of:_:)` two-arg, ScreenCaptureKit `SCScreenshotManager`. Tahoe's Liquid Glass styling is adopted automatically by native controls; no custom materials fight it.

## Release validation checklist
`codesign --verify --deep --strict` · `spctl --assess` · `stapler validate` · fresh-Mac install · TCC prompts appear once per permission · agent registers in Login Items · sign-in → consent → tracking → sync visible in portal · legacy-app conflict banner appears when Tauri app runs.
