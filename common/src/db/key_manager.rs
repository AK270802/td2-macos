use anyhow::{anyhow, Result};
use keyring::Entry;

// Deliberately distinct from the legacy Python agent's keyring service
// ("WorkPulse") — both agents can coexist on a machine during migration, and
// sharing a service name means the Rust agent would try to decrypt a
// SQLCipher file written with the Python agent's KDF settings using its raw
// key bytes, which fails as SQLITE_NOTADB even though the "key" is correct.
const SERVICE: &str = "WorkPulseAgentRust";
const ACCOUNT: &str = "db_key";

pub fn get_or_create_db_key() -> Result<String> {
    let entry = Entry::new(SERVICE, ACCOUNT)?;
    match entry.get_password() {
        Ok(key) => Ok(key),
        Err(_) => {
            let key = generate_key()?;
            entry.set_password(&key)?;
            Ok(key)
        }
    }
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
