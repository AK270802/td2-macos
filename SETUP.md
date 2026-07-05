# WorkPulse Tauri Agent — Setup

## Prerequisites

1. **Rust toolchain** (if not installed):
   ```powershell
   # Run in terminal — installs stable MSVC toolchain
   winget install Rustlang.Rustup
   # Then restart terminal, then:
   rustup default stable-x86_64-pc-windows-msvc
   ```

2. **Node.js 18+**: Already installed (`node --version` confirmed)

3. **OpenSSL** (for SQLCipher bundled build):
   ```powershell
   winget install OpenSSL.OpenSSL
   # Or use the vendored variant (already selected in Cargo.toml: bundled-sqlcipher-vendored-openssl)
   # No manual OpenSSL install needed with the vendored feature.
   ```

4. **Tauri CLI v2**:
   ```powershell
   cargo install tauri-cli --version "^2"
   ```

## Build

```powershell
cd agent\tauri

# Build agentd (service binary)
cargo build -p agentd --release

# Build + run the Tauri UI in dev mode
cd app
npm install
cargo tauri dev
```

## Install service (development)

```powershell
# Run as Administrator
.\target\release\agentd.exe install

# Run service manually (or let it auto-start)
.\target\release\agentd.exe debug    # foreground/debug mode (no SCM)
```

## Run tests

```powershell
cargo test -p common
```

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `WORKPULSE_API_URL` | `https://workpulse-dev-api.baseel.com` | Backend API base URL |
| `RUST_LOG` | `info` | Log level (trace/debug/info/warn/error) |
