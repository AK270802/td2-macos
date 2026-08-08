use super::{ForegroundWindow, WindowRect};

const EXCLUDED: &[&str] = &[
    "dwm.exe","winlogon.exe","csrss.exe","svchost.exe","services.exe","lsass.exe",
    "smss.exe","taskhostw.exe","searchhost.exe","sihost.exe","runtimebroker.exe",
    "shellexperiencehost.exe","startmenuexperiencehost.exe","textinputhost.exe",
    "applicationframehost.exe","lockapp.exe",
];
const WINDOW_TITLE_MAX: usize = 200;

pub fn foreground_window() -> Option<ForegroundWindow> {
    use windows::Win32::Foundation::RECT;
    use windows::Win32::UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowRect, GetWindowTextW, GetWindowThreadProcessId};
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

        let mut r = RECT::default();
        let rect = GetWindowRect(hwnd, &mut r).ok().map(|_| WindowRect {
            x: r.left,
            y: r.top,
            width: (r.right - r.left).max(0) as u32,
            height: (r.bottom - r.top).max(0) as u32,
        });

        let app_name = process_name.trim_end_matches(".exe").to_string();
        Some(ForegroundWindow {
            app_name,
            process_name,
            exe_path,
            window_title,
            rect,
            native_handle: hwnd.0 as isize,
        })
    }
}

pub fn idle_ms() -> u64 {
    use windows::Win32::UI::Input::KeyboardAndMouse::{GetLastInputInfo, LASTINPUTINFO};
    use windows::Win32::System::SystemInformation::GetTickCount;
    unsafe {
        let mut info = LASTINPUTINFO {
            cbSize: std::mem::size_of::<LASTINPUTINFO>() as u32,
            dwTime: 0,
        };
        let _ = GetLastInputInfo(&mut info);
        let tick = GetTickCount();
        tick.saturating_sub(info.dwTime) as u64
    }
}

pub fn browser_url(win: &ForegroundWindow) -> Option<String> {
    crate::capture::browser_tracker::read_browser_url(win.native_handle)
}

pub fn enumerate_windows() -> Vec<super::WindowInfo> {
    use windows::Win32::Foundation::{BOOL, HWND, LPARAM};
    use windows::Win32::UI::WindowsAndMessaging::{EnumWindows, GetWindowTextW, GetWindowThreadProcessId, IsWindowVisible};
    use windows::Win32::System::Threading::{OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32, PROCESS_QUERY_LIMITED_INFORMATION};
    use windows::core::PWSTR;
    use std::ffi::OsString;
    use std::os::windows::ffi::OsStringExt;

    unsafe extern "system" fn enum_cb(hwnd: HWND, lparam: LPARAM) -> BOOL {
        let out = &mut *(lparam.0 as *mut Vec<super::WindowInfo>);
        if !IsWindowVisible(hwnd).as_bool() {
            return true.into();
        }

        let mut title_buf = [0u16; 256];
        let title_len = GetWindowTextW(hwnd, &mut title_buf) as usize;
        if title_len == 0 {
            return true.into();
        }
        let title = OsString::from_wide(&title_buf[..title_len]).to_string_lossy().into_owned();

        let mut pid = 0u32;
        GetWindowThreadProcessId(hwnd, Some(&mut pid));
        if pid == 0 {
            return true.into();
        }
        let Ok(handle) = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) else {
            return true.into();
        };
        let mut path_buf = [0u16; 512];
        let mut path_len = path_buf.len() as u32;
        if QueryFullProcessImageNameW(handle, PROCESS_NAME_WIN32, PWSTR(path_buf.as_mut_ptr()), &mut path_len).is_err() {
            return true.into();
        }
        let exe_path = OsString::from_wide(&path_buf[..path_len as usize]).to_string_lossy().into_owned();
        let process_name = match std::path::Path::new(&exe_path).file_name() {
            Some(f) => f.to_string_lossy().to_lowercase(),
            None => return true.into(),
        };

        out.push(super::WindowInfo { process_name, title });
        true.into()
    }

    let mut out: Vec<super::WindowInfo> = Vec::new();
    unsafe {
        let _ = EnumWindows(Some(enum_cb), LPARAM(&mut out as *mut _ as isize));
    }
    out
}
