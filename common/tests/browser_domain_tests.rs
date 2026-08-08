//! eTLD+1 extraction — privacy-critical: no path, query, fragment, or
//! subdomain may ever survive extraction.

use common::capture::browser_tracker::{extract_domain, is_browser};

#[test]
fn extracts_etld_plus_one() {
    assert_eq!(extract_domain("https://github.com/baseel/workpulse/pull/42").as_deref(), Some("github.com"));
    assert_eq!(extract_domain("http://www.google.com/search?q=secret+query").as_deref(), Some("google.com"));
    assert_eq!(extract_domain("https://mail.google.com/mail/u/0/#inbox").as_deref(), Some("google.com"));
    assert_eq!(extract_domain("docs.rs/rusqlite/latest").as_deref(), Some("docs.rs"));
}

#[test]
fn respects_public_suffix_list() {
    // co.uk is a public suffix — eTLD+1 must keep the registrable label.
    assert_eq!(extract_domain("https://news.bbc.co.uk/article").as_deref(), Some("bbc.co.uk"));
    assert_eq!(extract_domain("https://foo.github.io/page").as_deref(), Some("foo.github.io"));
}

#[test]
fn never_leaks_paths_queries_or_fragments() {
    for url in [
        "https://bank.example.com/account/1234?token=SECRET",
        "https://example.com/reset-password#code=abc",
        "http://sub.deep.example.com/p?q=x&y=z",
    ] {
        let d = extract_domain(url).unwrap();
        assert!(!d.contains('/'), "path leaked: {d}");
        assert!(!d.contains('?'), "query leaked: {d}");
        assert!(!d.contains('#'), "fragment leaked: {d}");
        assert!(!d.contains("SECRET") && !d.contains("token") && !d.contains("abc"));
        assert_eq!(d, "example.com");
    }
}

#[test]
fn rejects_non_domains() {
    assert_eq!(extract_domain("localhost"), None);
    assert_eq!(extract_domain("about:blank"), None);
    assert_eq!(extract_domain(""), None);
    assert_eq!(extract_domain("chrome://settings"), None);
}

#[test]
fn browser_detection() {
    for b in ["chrome.exe", "MSEDGE.EXE", "firefox.exe", "brave.exe", "vivaldi.exe", "opera.exe"] {
        assert!(is_browser(b), "{b} should be a browser");
    }
    assert!(!is_browser("code.exe"));
    assert!(!is_browser("explorer.exe"));
}
