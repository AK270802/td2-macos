use serde_json::json;

const EXCLUDED: &[&str] = &[
    "dwm.exe","winlogon.exe","csrss.exe","svchost.exe","services.exe","lsass.exe",
    "smss.exe","taskhostw.exe","searchhost.exe","sihost.exe","runtimebroker.exe",
    "shellexperiencehost.exe","startmenuexperiencehost.exe","textinputhost.exe",
    "applicationframehost.exe","lockapp.exe",
];
const WINDOW_TITLE_MAX: usize = 200;

pub struct ForegroundApp {
    pub app_name: String,
    pub process_name: String,
    pub exe_path: String,
    pub window_title: String,
}

#[cfg(windows)]
pub fn get_foreground_app() -> Option<ForegroundApp> {
    use windows::Win32::UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowTextW, GetWindowThreadProcessId};
    use windows::Win32::System::Threading::{OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32, PROCESS_QUERY_LIMITED_INFORMATION};
    use windows::core::PWSTR;
    use std::ffi::OsString;
    use std::os::windows::ffi::OsStringExt;

    unsafe {
        let hwnd = GetForegroundWindow();
        if hwnd.0.is_null() { return None; }

        let mut title_buf = [0u16; 512];
        let title_len = GetWindowTextW(hwnd, &mut title_buf) as usize;
        let window_title: String = OsString::from_wide(&title_buf[..title_len])
            .to_string_lossy()
            .chars().take(WINDOW_TITLE_MAX).collect();

        let mut pid = 0u32;
        GetWindowThreadProcessId(hwnd, Some(&mut pid));
        if pid == 0 { return None; }

        let handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid).ok()?;
        let mut path_buf = [0u16; 1024];
        let mut len = path_buf.len() as u32;
        QueryFullProcessImageNameW(handle, PROCESS_NAME_WIN32, PWSTR(path_buf.as_mut_ptr()), &mut len).ok()?;
        let exe_path: String = OsString::from_wide(&path_buf[..len as usize]).to_string_lossy().into_owned();
        let process_name = std::path::Path::new(&exe_path)
            .file_name()?.to_string_lossy().to_lowercase();

        if EXCLUDED.contains(&process_name.as_str()) { return None; }

        let app_name = process_name.trim_end_matches(".exe").to_string();
        Some(ForegroundApp { app_name, process_name, exe_path, window_title })
    }
}

#[cfg(not(windows))]
pub fn get_foreground_app() -> Option<ForegroundApp> { None }

pub fn to_event_payload(app: &ForegroundApp) -> serde_json::Value {
    json!({
        "app_name": app.app_name,
        "process_name": app.process_name,
        "exe_path": app.exe_path,
        "window_title": app.window_title,
    })
}
