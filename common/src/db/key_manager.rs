use anyhow::Result;
use keyring::Entry;

const SERVICE: &str = "WorkPulse";
const ACCOUNT: &str = "db_key";

pub fn get_or_create_db_key() -> Result<String> {
    let entry = Entry::new(SERVICE, ACCOUNT)?;
    match entry.get_password() {
        Ok(key) => Ok(key),
        Err(_) => {
            let key = generate_key();
            entry.set_password(&key)?;
            Ok(key)
        }
    }
}

fn generate_key() -> String {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    use std::time::SystemTime;
    // 32 random-ish bytes encoded as 64 hex chars
    let mut bytes = [0u8; 32];
    for i in 0..32 {
        let mut h = DefaultHasher::new();
        SystemTime::now().hash(&mut h);
        i.hash(&mut h);
        bytes[i] = (h.finish() & 0xff) as u8;
    }
    hex::encode(bytes)
}
