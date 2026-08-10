use anyhow::{anyhow, Result};
use std::path::PathBuf;

// Deliberately a plain file under the same per-user data root the SQLCipher
// db itself lives in — NOT the OS keychain. `agentd` and `workpulse-app` are
// two separate binaries; on macOS, Keychain access is scoped to the calling
// process's code signature, so an unsigned/ad-hoc-signed build gives each
// binary its own isolated view of the "same" keychain entry. Worse, the old
// keyring-based version here treated ANY read failure (including "wrong
// process, access denied") as "no key yet" and silently minted a fresh one —
// meaning agentd and workpulse-app could each be encrypting/decrypting the
// same db file with two different keys. A file under `data_dir()` has no
// such per-binary ambiguity: both processes resolve the same path the same
// way, matching how db_path()/screenshots_dir()/logs_dir() already work.
fn key_file_path() -> PathBuf {
    crate::db::data_dir().join("db.key")
}

pub fn get_or_create_db_key() -> Result<String> {
    let path = key_file_path();
    if let Ok(existing) = std::fs::read_to_string(&path) {
        let key = existing.trim();
        if key.len() == 64 && key.chars().all(|c| c.is_ascii_hexdigit()) {
            return Ok(key.to_string());
        }
        // Present but malformed (partial write, corruption) — fall through
        // and regenerate rather than handing SQLCipher a bad key.
    }
    let key = generate_key()?;
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(&path, &key)?;
    restrict_permissions(&path)?;
    Ok(key)
}

/// Owner-only file permissions — this file IS the database's encryption key,
/// so it needs the same "other users on this machine can't read it"
/// guarantee the OS keychain gave for free. Windows already gets this from
/// `data_dir()` living under the per-user profile (NTFS ACLs default to
/// owner-only there); Unix needs it set explicitly since a freshly created
/// file inherits the process umask, not owner-only by default.
#[cfg(unix)]
fn restrict_permissions(path: &std::path::Path) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))?;
    Ok(())
}

#[cfg(not(unix))]
fn restrict_permissions(_path: &std::path::Path) -> Result<()> {
    Ok(())
}

/// 32 bytes from the OS CSPRNG, hex-encoded for `PRAGMA key="x'…'"`.
fn generate_key() -> Result<String> {
    let mut bytes = [0u8; 32];
    getrandom::getrandom(&mut bytes).map_err(|e| anyhow!("os rng failed: {e}"))?;
    Ok(hex::encode(bytes))
}

#[cfg(test)]
mod tests {
    use super::generate_key;

    #[test]
    fn key_is_64_hex_chars() {
        let k = generate_key().unwrap();
        assert_eq!(k.len(), 64);
        assert!(k.chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[test]
    fn keys_are_unique() {
        assert_ne!(generate_key().unwrap(), generate_key().unwrap());
    }
}
