//! Browser domain tracking via UIAutomation (Chromium + Firefox).
//! Returns eTLD+1 only — never paths or query strings.

use addr::parse_domain_name;

const BROWSER_EXES: &[&str] = &[
    "chrome.exe","msedge.exe","firefox.exe","brave.exe","vivaldi.exe","opera.exe",
];

/// macOS app names as reported by the native backend (lowercased owner name).
#[cfg(feature = "macos-native")]
const BROWSER_APPS_MACOS: &[&str] = &[
    "google chrome", "safari", "microsoft edge", "brave browser", "arc",
    "firefox", "vivaldi", "opera", "chromium",
];

pub fn is_browser(process_name: &str) -> bool {
    let name = process_name.to_lowercase();
    #[cfg(feature = "macos-native")]
    if BROWSER_APPS_MACOS.contains(&name.as_str()) {
        return true;
    }
    BROWSER_EXES.contains(&name.as_str())
}

/// Extract eTLD+1 from a URL string. Returns None for non-domain URLs.
pub fn extract_domain(url: &str) -> Option<String> {
    let without_scheme = url
        .trim_start_matches("https://")
        .trim_start_matches("http://");
    let host = without_scheme.split(&['/', '?', '#', ' '][..]).next()?.trim();
    if host.is_empty() { return None; }
    match parse_domain_name(host) {
        Ok(domain) => Some(domain.root()?.to_string()),
        Err(_) => None,
    }
}

#[cfg(windows)]
pub fn read_browser_url(hwnd_ptr: isize) -> Option<String> {
    use windows::Win32::UI::Accessibility::{
        IUIAutomation, CUIAutomation, TreeScope_Descendants,
        UIA_EditControlTypeId, UIA_ValuePatternId, UIA_ControlTypePropertyId,
    };
    use windows::Win32::Foundation::HWND;
    use windows::Win32::System::Com::{CoCreateInstance, CLSCTX_INPROC_SERVER};
    use windows::core::{Interface, VARIANT};

    unsafe {
        let automation: IUIAutomation = CoCreateInstance(
            &CUIAutomation,
            None,
            CLSCTX_INPROC_SERVER,
        ).ok()?;
        let hwnd = HWND(hwnd_ptr as *mut _);
        let root = automation.ElementFromHandle(hwnd).ok()?;

        // UIA_EditControlTypeId is a UIA_CONTROLTYPE_ID (i32 wrapper); pass its i32 value
        let condition = automation.CreatePropertyCondition(
            UIA_ControlTypePropertyId,
            &VARIANT::from(UIA_EditControlTypeId.0),
        ).ok()?;
        let edit = root.FindFirst(TreeScope_Descendants, &condition).ok()?;

        let value_pattern: windows::Win32::UI::Accessibility::IUIAutomationValuePattern =
            edit.GetCurrentPattern(UIA_ValuePatternId).ok()?.cast().ok()?;
        let bstr = value_pattern.CurrentValue().ok()?;
        Some(bstr.to_string())
    }
}

#[cfg(not(windows))]
pub fn read_browser_url(_hwnd_ptr: isize) -> Option<String> { None }
