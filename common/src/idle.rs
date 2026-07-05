pub struct InputSample {
    pub keystroke_count: u32,
    pub mouse_click_count: u32,
    pub mouse_distance_px: f64,
}

pub struct IdleDetector {
    pub threshold_secs: u64,
    last_cursor_x: i32,
    last_cursor_y: i32,
    prev_vk_states: [bool; 256],
    pub keystroke_count: u32,
    pub mouse_click_count: u32,
    pub mouse_distance_px: f64,
}

impl IdleDetector {
    pub fn new(threshold_secs: u64) -> Self {
        Self {
            threshold_secs,
            last_cursor_x: 0, last_cursor_y: 0,
            prev_vk_states: [false; 256],
            keystroke_count: 0, mouse_click_count: 0, mouse_distance_px: 0.0,
        }
    }

    /// Returns idle duration in ms via GetLastInputInfo (Windows only).
    #[cfg(windows)]
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

    #[cfg(not(windows))]
    pub fn idle_ms() -> u64 { 0 }

    pub fn is_idle(&self) -> bool {
        Self::idle_ms() >= self.threshold_secs * 1000
    }

    /// Sample key/mouse state. Call at ~1s intervals.
    #[cfg(windows)]
    pub fn tick(&mut self) -> InputSample {
        use windows::Win32::UI::Input::KeyboardAndMouse::GetAsyncKeyState;
        use windows::Win32::UI::WindowsAndMessaging::GetCursorPos;
        use windows::Win32::Foundation::POINT;

        // ~40 common VKs — counts only, never content
        const SAMPLED_VKS: &[i32] = &[
            0x08, 0x09, 0x0D, 0x10, 0x11, 0x12,
            0x1B, 0x20, 0x2E,
            0x41,0x42,0x43,0x44,0x45,0x46,0x47,0x48,0x49,0x4A,
            0x4B,0x4C,0x4D,0x4E,0x4F,0x50,0x51,0x52,0x53,0x54,
            0x55,0x56,0x57,0x58,0x59,0x5A,
            0x30,0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,
            0x70,0x71,0x72,0x73,
        ];
        unsafe {
            for &vk in SAMPLED_VKS {
                let down = (GetAsyncKeyState(vk) as u16 & 0x8000) != 0;
                if down && !self.prev_vk_states[vk as usize] {
                    self.keystroke_count += 1;
                }
                self.prev_vk_states[vk as usize] = down;
            }
            let lb = (GetAsyncKeyState(0x01) as u16 & 0x8000) != 0;
            let rb = (GetAsyncKeyState(0x02) as u16 & 0x8000) != 0;
            if lb && !self.prev_vk_states[0x01] { self.mouse_click_count += 1; }
            if rb && !self.prev_vk_states[0x02] { self.mouse_click_count += 1; }
            self.prev_vk_states[0x01] = lb;
            self.prev_vk_states[0x02] = rb;

            let mut pt = POINT { x: 0, y: 0 };
            let _ = GetCursorPos(&mut pt);
            let dx = (pt.x - self.last_cursor_x) as f64;
            let dy = (pt.y - self.last_cursor_y) as f64;
            self.mouse_distance_px += (dx*dx + dy*dy).sqrt();
            self.last_cursor_x = pt.x;
            self.last_cursor_y = pt.y;
        }
        InputSample {
            keystroke_count: self.keystroke_count,
            mouse_click_count: self.mouse_click_count,
            mouse_distance_px: self.mouse_distance_px,
        }
    }

    #[cfg(not(windows))]
    pub fn tick(&mut self) -> InputSample {
        InputSample { keystroke_count: 0, mouse_click_count: 0, mouse_distance_px: 0.0 }
    }

    pub fn reset_counts(&mut self) {
        self.keystroke_count = 0;
        self.mouse_click_count = 0;
        self.mouse_distance_px = 0.0;
    }
}

