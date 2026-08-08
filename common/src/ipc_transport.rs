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
pub async fn request(cmd: &str, payload: Option<serde_json::Value>) -> Result<serde_json::Value> {
    let fut = async {
        let conn = Stream::connect(socket_name()?).await
            .map_err(|e| anyhow!("agent not reachable: {e}"))?;
        let (reader, mut writer) = conn.split();
        let msg = serde_json::to_string(&IpcRequest { cmd: cmd.into(), payload })?;
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
