# WorkPulse Tauri Agent — Setup

## Prerequisites (Windows dev machine)

1. **Rust toolchain**
   ```powershell
   winget install Rustlang.Rustup
   rustup default stable-x86_64-pc-windows-msvc
   ```
2. **Node.js 18+**
3. **Perl** — required by the vendored OpenSSL build inside SQLCipher
   (`bundled-sqlcipher-vendored-openssl`). Strawberry Perl:
   ```powershell
   winget install StrawberryPerl.StrawberryPerl
   ```
4. **Tauri CLI v2** comes via the app's npm devDependencies (`npm install`).

macOS additionally: Xcode CLT. The agent needs the user to grant
Accessibility + Screen Recording (System Settings → Privacy & Security).
Linux additionally: `libwebkit2gtk-4.1-dev libayatana-appindicator3-dev
librsvg2-dev libxdo-dev`, and at runtime `xdotool xprintidle` (declared as
.deb dependencies).

## Build

```powershell
cd workpulse-rust

# Agent service binary
cargo build -p agentd --release

# Desktop app, dev mode (hot reload)
cd app
npm install
npm run tauri dev

# Production installer — .exe on Windows (NSIS), per-user install (no
# admin/UAC prompt), also builds agentd and bundles it as a resource.
.\build-release.ps1
```

The installer lands in `target/release/bundle/nsis/`. Linux `.deb` /
macOS `.dmg` are produced by CI (see `.gitlab-ci.yml`) with
`npm run tauri build -- --bundles deb|dmg`.

### Auto-updater signing

`tauri.conf.json`'s `bundle.createUpdaterArtifacts: true` makes every build
also produce a signed `.sig` alongside the installer, which the running app
verifies before installing an update (`tauri-plugin-updater`, checked in
`app/src-tauri/src/updater.rs`). Signing needs the private half of the
keypair generated once via:

```powershell
npx tauri signer generate -w src-tauri\keys\workpulse-updater.key --ci
```

The private key (`src-tauri/keys/workpulse-updater.key`, gitignored — never
commit it) never leaves your machine / CI secret store; the public half is
already baked into `tauri.conf.json`'s `plugins.updater.pubkey`. Plain
`npm run tauri build` will fail with "public key has been found, but no
private key" unless `TAURI_SIGNING_PRIVATE_KEY` is set to the *contents* of
that file (not its path) — use `.\build-release.ps1` instead of calling
`npm run tauri build` directly so that's handled for you.

For a real release, someone with the signed installer also needs to run:

```powershell
npx tauri signer sign target\release\bundle\nsis\WorkPulse_<version>_x64-setup.exe -k src-tauri\keys\workpulse-updater.key
```

and set `AGENT_LATEST_VERSION` / `AGENT_DOWNLOAD_URL` / `AGENT_SHA256` /
`AGENT_UPDATE_SIGNATURE` in core-services to the new version, a real HTTPS
URL the installer is hosted at, and this signature — the app polls
`GET /api/v1/agent/update/{target}/{arch}/{current_version}` for these.

## Run the agent manually (development)

```powershell
# Foreground, no Windows Service registration needed:
cargo run -p agentd -- debug

# As a Windows Service (run terminal as Administrator):
.\target\release\agentd.exe install
sc start WorkPulseAgent
```

## Tests

```powershell
cargo test --workspace
```

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `WORKPULSE_API_URL` | `https://dev-workpulse-api.baseel.com` | Backend base URL |
| `RUST_LOG` | `info` | Log level (trace/debug/info/warn/error) |
