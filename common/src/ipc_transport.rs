//! Cross-platform local IPC between agentd (server) and the Tauri app (client).
//!
//! One code path everywhere via the `interprocess` crate: a named pipe on
//! Windows, an abstract-namespace socket on Linux, and a filesystem socket on
//! macOS. Protocol is newline-delimited JSON: {cmd, payload?} → {ok, data, error}.

use anyhow::{anyhow, Result};
use interprocess::local_socket::{
    tokio::{prelude::*, Listener, Stream},
    GenericFilePath, GenericNamespaced, ListenerOptions, Name, NameType, ToFsName, ToNsName,
};
use serde::{Deserialize, Serialize};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

const NS_NAME: &str = "workpulse-agent.sock";

#[derive(Serialize, Deserialize)]
pub struct IpcRequest {
    pub cmd: String,
    #[serde(default)]
    pub payload: Option<serde_json::Value>,
    /// Per-boot IPC secret (native macOS agent only). Absent on the legacy
    /// transport, so the wire format there is unchanged.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub auth: Option<String>,
}

#[derive(Serialize, Deserialize)]
pub struct IpcResponse {
    pub ok: bool,
    pub data: serde_json::Value,
    pub error: Option<String>,
}

impl IpcResponse {
    pub fn ok(data: serde_json::Value) -> Self {
        Self { ok: true, data, error: None }
    }
    pub fn err(msg: impl Into<String>) -> Self {
        Self { ok: false, data: serde_json::Value::Null, error: Some(msg.into()) }
    }
}

fn fs_socket_path() -> std::path::PathBuf {
    dirs::runtime_dir()
        .unwrap_or_else(std::env::temp_dir)
        .join(NS_NAME)
}

fn socket_name() -> Result<Name<'static>> {
    if GenericNamespaced::is_supported() {
        Ok(NS_NAME.to_ns_name::<GenericNamespaced>()?)
    } else {
        Ok(fs_socket_path().to_fs_name::<GenericFilePath>()?.into_owned())
    }
}

/// Bind the server listener. On filesystem-socket platforms a stale socket
/// file from a crashed process is removed and the bind retried once.
pub fn bind_listener() -> Result<Listener> {
    let name = socket_name()?;
    match ListenerOptions::new().name(name.clone()).create_tokio() {
        Ok(l) => Ok(l),
        Err(e) if e.kind() == std::io::ErrorKind::AddrInUse && !GenericNamespaced::is_supported() => {
            let _ = std::fs::remove_file(fs_socket_path());
            Ok(ListenerOptions::new().name(name).create_tokio()?)
        }
        Err(e) => Err(e.into()),
    }
}

/// One-shot client request with a 3-second overall timeout. Returns the
/// server's `data` field, or Err carrying the server-reported error.
#[cfg(feature = "macos-native")]
pub async fn request(cmd: &str, payload: Option<serde_json::Value>) -> Result<serde_json::Value> {
    native::request(cmd, payload).await
}

#[cfg(not(feature = "macos-native"))]
pub async fn request(cmd: &str, payload: Option<serde_json::Value>) -> Result<serde_json::Value> {
    let fut = async {
        let conn = Stream::connect(socket_name()?).await
            .map_err(|e| anyhow!("agent not reachable: {e}"))?;
        let (reader, mut writer) = conn.split();
        let msg = serde_json::to_string(&IpcRequest { cmd: cmd.into(), payload, auth: None })?;
        writer.write_all(format!("{msg}\n").as_bytes()).await?;
        let mut lines = BufReader::new(reader).lines();
        let line = lines.next_line().await?.ok_or_else(|| anyhow!("no response from agent"))?;
        let resp: IpcResponse = serde_json::from_str(&line)?;
        if resp.ok {
            Ok(resp.data)
        } else {
            Err(anyhow!(resp.error.unwrap_or_else(|| "unknown agent error".into())))
        }
    };
    tokio::time::timeout(std::time::Duration::from_secs(3), fut)
        .await
        .map_err(|_| anyhow!("agent request timed out"))?
}

/// Native EffiLens macOS transport: a filesystem Unix socket inside the
/// app's private data directory, authenticated three ways:
///   1. directory 0700 + socket 0600 (only the owner can connect),
///   2. peer UID check on every connection (`getpeereid` via tokio),
///   3. per-boot random secret in `ipc.token` (0600) sent as `auth`.
/// Requests are size-bounded; the legacy Tauri socket is never touched.
#[cfg(feature = "macos-native")]
#[cfg_attr(not(unix), allow(unused_imports, dead_code))]
pub mod native {
    use super::{IpcRequest, IpcResponse};
    use anyhow::{anyhow, Context, Result};
    use std::path::PathBuf;
    use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};

    /// Maximum accepted request line (bytes, including the newline).
    pub const MAX_LINE_BYTES: u64 = 64 * 1024;
    /// Maximum response line read by the Rust client.
    const MAX_RESPONSE_BYTES: u64 = 4 * 1024 * 1024;

    pub fn socket_path() -> PathBuf {
        crate::db::data_dir().join("agent.sock")
    }

    pub fn token_path() -> PathBuf {
        crate::db::data_dir().join("ipc.token")
    }

    pub fn lock_path() -> PathBuf {
        crate::db::data_dir().join("agentd.lock")
    }

    /// Creates the private data directory with owner-only permissions.
    #[cfg(unix)]
    pub fn ensure_private_dir() -> Result<PathBuf> {
        use std::os::unix::fs::PermissionsExt;
        let dir = crate::db::data_dir();
        std::fs::create_dir_all(&dir)?;
        std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o700))?;
        Ok(dir)
    }

    /// UID owning the private data directory (= the agent's own user).
    #[cfg(unix)]
    pub fn owner_uid() -> Result<u32> {
        use std::os::unix::fs::MetadataExt;
        Ok(std::fs::metadata(crate::db::data_dir())?.uid())
    }

    /// Writes a fresh 256-bit secret (0600, refusing to follow symlinks).
    #[cfg(unix)]
    pub fn rotate_token() -> Result<String> {
        use std::io::Write;
        use std::os::unix::fs::OpenOptionsExt;
        let mut bytes = [0u8; 32];
        getrandom::getrandom(&mut bytes).map_err(|e| anyhow!("os rng failed: {e}"))?;
        let token = hex::encode(bytes);
        let path = token_path();
        let _ = std::fs::remove_file(&path);
        let mut f = std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .custom_flags(0x0100) // O_NOFOLLOW on Darwin
            .open(&path)
            .context("create ipc.token")?;
        f.write_all(token.as_bytes())?;
        f.sync_all()?;
        Ok(token)
    }

    pub fn read_token() -> Option<String> {
        let t = std::fs::read_to_string(token_path()).ok()?;
        let t = t.trim().to_string();
        (t.len() == 64 && t.chars().all(|c| c.is_ascii_hexdigit())).then_some(t)
    }

    /// Constant-time comparison of the presented secret.
    pub fn token_matches(expected: &str, presented: Option<&str>) -> bool {
        let Some(presented) = presented else { return false };
        let (a, b) = (expected.as_bytes(), presented.as_bytes());
        if a.len() != b.len() {
            return false;
        }
        a.iter().zip(b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
    }

    /// Binds the socket (0600). A stale file from a crashed agent is removed
    /// only if nothing answers on it.
    #[cfg(unix)]
    pub fn bind_listener() -> Result<tokio::net::UnixListener> {
        use std::os::unix::fs::PermissionsExt;
        ensure_private_dir()?;
        let path = socket_path();
        if path.exists() {
            if std::os::unix::net::UnixStream::connect(&path).is_ok() {
                return Err(anyhow!("another EffiLens agent is listening"));
            }
            std::fs::remove_file(&path)?;
        }
        let listener = tokio::net::UnixListener::bind(&path)?;
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600))?;
        Ok(listener)
    }

    /// Removes the socket and token on graceful shutdown.
    pub fn cleanup() {
        let _ = std::fs::remove_file(socket_path());
        let _ = std::fs::remove_file(token_path());
    }

    /// Reads one newline-terminated line, failing if it exceeds `limit`.
    pub async fn read_bounded_line<R>(reader: &mut BufReader<R>, limit: u64) -> Result<Option<String>>
    where
        R: tokio::io::AsyncRead + Unpin,
    {
        let mut buf = Vec::new();
        let n = (&mut *reader).take(limit).read_until(b'\n', &mut buf).await?;
        if n == 0 {
            return Ok(None);
        }
        if buf.last() != Some(&b'\n') && n as u64 >= limit {
            return Err(anyhow!("ipc message exceeds {limit} bytes"));
        }
        Ok(Some(String::from_utf8(buf).map_err(|_| anyhow!("ipc message is not UTF-8"))?))
    }

    /// Rust-side client (used by agentd's own single-instance ping).
    #[cfg(unix)]
    pub async fn request(cmd: &str, payload: Option<serde_json::Value>) -> Result<serde_json::Value> {
        let fut = async {
            let token = read_token().ok_or_else(|| anyhow!("agent not running (no ipc token)"))?;
            let stream = tokio::net::UnixStream::connect(socket_path())
                .await
                .map_err(|e| anyhow!("agent not reachable: {e}"))?;
            let (reader, mut writer) = stream.into_split();
            let msg = serde_json::to_string(&IpcRequest { cmd: cmd.into(), payload, auth: Some(token) })?;
            writer.write_all(format!("{msg}\n").as_bytes()).await?;
            let mut reader = BufReader::new(reader);
            let line = read_bounded_line(&mut reader, MAX_RESPONSE_BYTES)
                .await?
                .ok_or_else(|| anyhow!("no response from agent"))?;
            let resp: IpcResponse = serde_json::from_str(&line)?;
            if resp.ok {
                Ok(resp.data)
            } else {
                Err(anyhow!(resp.error.unwrap_or_else(|| "unknown agent error".into())))
            }
        };
        tokio::time::timeout(std::time::Duration::from_secs(3), fut)
            .await
            .map_err(|_| anyhow!("agent request timed out"))?
    }

    /// Non-Unix hosts (a Windows dev machine checking the feature): the native
    /// agent only exists on macOS.
    #[cfg(not(unix))]
    pub async fn request(_cmd: &str, _payload: Option<serde_json::Value>) -> Result<serde_json::Value> {
        Err(anyhow!("the native EffiLens agent is only available on macOS"))
    }

    /// True if the legacy Tauri agent answers on its socket. Used to refuse
    /// tracking so both agents never record the same time twice.
    #[cfg(unix)]
    pub fn legacy_agent_running() -> bool {
        let candidates = [
            std::env::temp_dir().join("workpulse-agent.sock"),
            dirs::runtime_dir().unwrap_or_else(std::env::temp_dir).join("workpulse-agent.sock"),
        ];
        candidates.iter().any(|p| std::os::unix::net::UnixStream::connect(p).is_ok())
    }

    #[cfg(test)]
    mod tests {
        use super::token_matches;

        #[test]
        fn token_comparison() {
            let t = "a".repeat(64);
            assert!(token_matches(&t, Some(&t)));
            assert!(!token_matches(&t, Some(&"b".repeat(64))));
            assert!(!token_matches(&t, Some("short")));
            assert!(!token_matches(&t, None));
        }
    }
}
