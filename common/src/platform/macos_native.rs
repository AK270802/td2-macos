//! Native macOS capture backend — feature `macos-native` (EffiLens native app).
//!
//! Replaces the subprocess-based `macos_impl` (osascript/ioreg every second)
//! with direct system-framework calls. Only `extern "C"` declarations against
//! Apple frameworks are used — no extra crates and no Swift↔Rust FFI.
//!
//! Permissions (never bypassed; each capability degrades independently):
//! - Accessibility → focused-window title via AX (fallback: CGWindow name).
//! - Screen Recording → window titles in CGWindowList + window screenshots.
//!   Without it, screenshots are SKIPPED — there is no full-screen fallback.
//! - Input Monitoring → listen-only event tap for activity COUNTS. Key codes
//!   and characters are never read; only the event type is inspected.
//! - Automation (per browser) → URL read; reduced to eTLD+1 by the caller.

#![allow(non_upper_case_globals, non_snake_case, clippy::upper_case_acronyms)]

use super::{ForegroundWindow, WindowInfo, WindowRect};
use std::ffi::{c_void, CString};
use std::os::raw::{c_char, c_int};
use std::sync::atomic::{AtomicBool, AtomicPtr, AtomicU32, AtomicU64, Ordering};
use std::sync::Once;

// ── Core Foundation / Core Graphics / AX / IOKit declarations ────────────────

type CFTypeRef = *const c_void;
type CFIndex = isize;
type CGWindowID = u32;

#[repr(C)]
#[derive(Clone, Copy, Debug)]
struct CGPoint {
    x: f64,
    y: f64,
}
#[repr(C)]
#[derive(Clone, Copy, Debug)]
struct CGSize {
    width: f64,
    height: f64,
}
#[repr(C)]
#[derive(Clone, Copy, Debug)]
struct CGRect {
    origin: CGPoint,
    size: CGSize,
}

const kCFStringEncodingUTF8: u32 = 0x0800_0100;
const kCFNumberSInt64Type: CFIndex = 4;

const kCGWindowListOptionOnScreenOnly: u32 = 1 << 0;
const kCGWindowListOptionIncludingWindow: u32 = 1 << 3;
const kCGWindowListExcludeDesktopElements: u32 = 1 << 4;
const kCGWindowImageBoundsIgnoreFraming: u32 = 1 << 0;
const kCGWindowImageNominalResolution: u32 = 1 << 4;
const kCGNullWindowID: CGWindowID = 0;

const kCGEventSourceStateCombinedSessionState: i32 = 0;
const kCGAnyInputEventType: u32 = 0xFFFF_FFFF;

const kCGSessionEventTap: u32 = 1;
const kCGHeadInsertEventTap: u32 = 0;
const kCGEventTapOptionListenOnly: u32 = 1;
const kCGEventLeftMouseDown: u32 = 1;
const kCGEventRightMouseDown: u32 = 3;
const kCGEventMouseMoved: u32 = 5;
const kCGEventLeftMouseDragged: u32 = 6;
const kCGEventKeyDown: u32 = 10;
const kCGEventOtherMouseDown: u32 = 25;
const kCGEventTapDisabledByTimeout: u32 = 0xFFFF_FFFE;
const kCGEventTapDisabledByUserInput: u32 = 0xFFFF_FFFF;

const kIOHIDRequestTypeListenEvent: u32 = 1;
const kIOHIDAccessTypeGranted: u32 = 0;
const kAXErrorSuccess: i32 = 0;

type CGEventTapCallBack =
    extern "C" fn(proxy: *const c_void, kind: u32, event: *const c_void, user: *mut c_void) -> *const c_void;

#[link(name = "CoreFoundation", kind = "framework")]
extern "C" {
    fn CFArrayGetCount(array: CFTypeRef) -> CFIndex;
    fn CFArrayGetValueAtIndex(array: CFTypeRef, idx: CFIndex) -> CFTypeRef;
    fn CFDictionaryGetValue(dict: CFTypeRef, key: CFTypeRef) -> CFTypeRef;
    fn CFStringCreateWithCString(alloc: CFTypeRef, c_str: *const c_char, encoding: u32) -> CFTypeRef;
    fn CFStringGetLength(s: CFTypeRef) -> CFIndex;
    fn CFStringGetMaximumSizeForEncoding(length: CFIndex, encoding: u32) -> CFIndex;
    fn CFStringGetCString(s: CFTypeRef, buf: *mut c_char, size: CFIndex, encoding: u32) -> u8;
    fn CFStringGetTypeID() -> usize;
    fn CFGetTypeID(cf: CFTypeRef) -> usize;
    fn CFNumberGetValue(number: CFTypeRef, the_type: CFIndex, value_ptr: *mut c_void) -> u8;
    fn CFDataGetBytePtr(data: CFTypeRef) -> *const u8;
    fn CFDataGetLength(data: CFTypeRef) -> CFIndex;
    fn CFRelease(cf: CFTypeRef);
    fn CFDictionaryCreate(
        alloc: CFTypeRef,
        keys: *const CFTypeRef,
        values: *const CFTypeRef,
        count: CFIndex,
        key_callbacks: *const c_void,
        value_callbacks: *const c_void,
    ) -> CFTypeRef;
    static kCFBooleanTrue: CFTypeRef;
    static kCFTypeDictionaryKeyCallBacks: c_void;
    static kCFTypeDictionaryValueCallBacks: c_void;
    fn CFRunLoopGetCurrent() -> CFTypeRef;
    fn CFRunLoopAddSource(rl: CFTypeRef, source: CFTypeRef, mode: CFTypeRef);
    fn CFRunLoopRun();
    fn CFMachPortCreateRunLoopSource(alloc: CFTypeRef, port: CFTypeRef, order: CFIndex) -> CFTypeRef;
    static kCFRunLoopCommonModes: CFTypeRef;
}

#[link(name = "CoreGraphics", kind = "framework")]
extern "C" {
    fn CGWindowListCopyWindowInfo(option: u32, relative_to: CGWindowID) -> CFTypeRef;
    fn CGRectMakeWithDictionaryRepresentation(dict: CFTypeRef, rect: *mut CGRect) -> bool;
    fn CGEventSourceSecondsSinceLastEventType(state: i32, event_type: u32) -> f64;
    fn CGPreflightScreenCaptureAccess() -> bool;
    fn CGRequestScreenCaptureAccess() -> bool;
    fn CGWindowListCreateImage(bounds: CGRect, list_option: u32, window: CGWindowID, image_option: u32) -> CFTypeRef;
    fn CGImageGetWidth(image: CFTypeRef) -> usize;
    fn CGImageGetHeight(image: CFTypeRef) -> usize;
    fn CGImageGetBytesPerRow(image: CFTypeRef) -> usize;
    fn CGImageGetBitsPerPixel(image: CFTypeRef) -> usize;
    fn CGImageGetDataProvider(image: CFTypeRef) -> CFTypeRef;
    fn CGDataProviderCopyData(provider: CFTypeRef) -> CFTypeRef;
    fn CGImageRelease(image: CFTypeRef);
    fn CGEventTapCreate(
        tap: u32,
        place: u32,
        options: u32,
        events_of_interest: u64,
        callback: CGEventTapCallBack,
        user_info: *mut c_void,
    ) -> CFTypeRef;
    fn CGEventTapEnable(tap: CFTypeRef, enable: bool);
    fn CGEventGetLocation(event: CFTypeRef) -> CGPoint;
    static CGRectNull: CGRect;
    static kCGWindowOwnerName: CFTypeRef;
    static kCGWindowOwnerPID: CFTypeRef;
    static kCGWindowName: CFTypeRef;
    static kCGWindowNumber: CFTypeRef;
    static kCGWindowLayer: CFTypeRef;
    static kCGWindowBounds: CFTypeRef;
}

#[link(name = "ApplicationServices", kind = "framework")]
extern "C" {
    fn AXIsProcessTrusted() -> bool;
    fn AXIsProcessTrustedWithOptions(options: CFTypeRef) -> bool;
    fn AXUIElementCreateApplication(pid: c_int) -> CFTypeRef;
    fn AXUIElementCopyAttributeValue(element: CFTypeRef, attribute: CFTypeRef, value: *mut CFTypeRef) -> i32;
}

#[link(name = "IOKit", kind = "framework")]
extern "C" {
    fn IOHIDCheckAccess(request_type: u32) -> u32;
    fn IOHIDRequestAccess(request_type: u32) -> bool;
}

extern "C" {
    // libproc (libSystem)
    fn proc_pidpath(pid: c_int, buffer: *mut c_void, buffersize: u32) -> c_int;
}

// ── Safe helpers ─────────────────────────────────────────────────────────────

/// Owned CF object released on drop (for objects from Copy/Create calls).
struct Owned(CFTypeRef);
impl Owned {
    fn new(ptr: CFTypeRef) -> Option<Self> {
        if ptr.is_null() { None } else { Some(Self(ptr)) }
    }
}
impl Drop for Owned {
    fn drop(&mut self) {
        unsafe { CFRelease(self.0) }
    }
}

fn cfstring(s: &str) -> Option<Owned> {
    let c = CString::new(s).ok()?;
    Owned::new(unsafe { CFStringCreateWithCString(std::ptr::null(), c.as_ptr(), kCFStringEncodingUTF8) })
}

/// Borrowed CFString → Rust String (None for null / non-string values).
fn to_string(value: CFTypeRef) -> Option<String> {
    if value.is_null() || unsafe { CFGetTypeID(value) != CFStringGetTypeID() } {
        return None;
    }
    unsafe {
        let len = CFStringGetLength(value);
        let cap = CFStringGetMaximumSizeForEncoding(len, kCFStringEncodingUTF8) + 1;
        let mut buf = vec![0 as c_char; cap.max(1) as usize];
        if CFStringGetCString(value, buf.as_mut_ptr(), cap, kCFStringEncodingUTF8) == 0 {
            return None;
        }
        Some(std::ffi::CStr::from_ptr(buf.as_ptr()).to_string_lossy().into_owned())
    }
}

fn dict_i64(dict: CFTypeRef, key: CFTypeRef) -> Option<i64> {
    let number = unsafe { CFDictionaryGetValue(dict, key) };
    if number.is_null() {
        return None;
    }
    let mut out: i64 = 0;
    let ok = unsafe { CFNumberGetValue(number, kCFNumberSInt64Type, &mut out as *mut i64 as *mut c_void) };
    (ok != 0).then_some(out)
}

fn dict_string(dict: CFTypeRef, key: CFTypeRef) -> Option<String> {
    to_string(unsafe { CFDictionaryGetValue(dict, key) })
}

fn dict_rect(dict: CFTypeRef) -> Option<WindowRect> {
    let bounds = unsafe { CFDictionaryGetValue(dict, kCGWindowBounds) };
    if bounds.is_null() {
        return None;
    }
    let mut r = CGRect { origin: CGPoint { x: 0.0, y: 0.0 }, size: CGSize { width: 0.0, height: 0.0 } };
    if !unsafe { CGRectMakeWithDictionaryRepresentation(bounds, &mut r) } {
        return None;
    }
    Some(WindowRect {
        x: r.origin.x as i32,
        y: r.origin.y as i32,
        width: r.size.width.max(0.0) as u32,
        height: r.size.height.max(0.0) as u32,
    })
}

/// One on-screen, normal-layer window.
struct WinEntry {
    id: CGWindowID,
    pid: i32,
    owner: String,
    title: String,
    rect: Option<WindowRect>,
}

/// Owners that sit at layer 0 but are never "the app the user is working in".
const IGNORED_OWNERS: &[&str] = &["Window Server", "Dock", "Control Centre", "Control Center", "Notification Center", "EffiLens"];

/// On-screen layer-0 windows, front-to-back (CGWindowList ordering).
fn on_screen_windows() -> Vec<WinEntry> {
    let Some(list) = Owned::new(unsafe {
        CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID)
    }) else {
        return Vec::new();
    };
    let count = unsafe { CFArrayGetCount(list.0) };
    let mut out = Vec::with_capacity(count.max(0) as usize);
    for i in 0..count {
        let dict = unsafe { CFArrayGetValueAtIndex(list.0, i) };
        if dict.is_null() || dict_i64(dict, unsafe { kCGWindowLayer }) != Some(0) {
            continue;
        }
        let owner = dict_string(dict, unsafe { kCGWindowOwnerName }).unwrap_or_default();
        if owner.is_empty() || IGNORED_OWNERS.contains(&owner.as_str()) {
            continue;
        }
        out.push(WinEntry {
            id: dict_i64(dict, unsafe { kCGWindowNumber }).unwrap_or(0) as CGWindowID,
            pid: dict_i64(dict, unsafe { kCGWindowOwnerPID }).unwrap_or(0) as i32,
            owner,
            // Present only with Screen Recording permission.
            title: dict_string(dict, unsafe { kCGWindowName }).unwrap_or_default(),
            rect: dict_rect(dict),
        });
    }
    out
}

/// Focused window title via Accessibility (None if not trusted / unavailable).
fn ax_focused_title(pid: i32) -> Option<String> {
    if pid <= 0 || !unsafe { AXIsProcessTrusted() } {
        return None;
    }
    let app = Owned::new(unsafe { AXUIElementCreateApplication(pid) })?;
    let focused_attr = cfstring("AXFocusedWindow")?;
    let title_attr = cfstring("AXTitle")?;
    let mut window: CFTypeRef = std::ptr::null();
    if unsafe { AXUIElementCopyAttributeValue(app.0, focused_attr.0, &mut window) } != kAXErrorSuccess {
        return None;
    }
    let window = Owned::new(window)?;
    let mut title: CFTypeRef = std::ptr::null();
    if unsafe { AXUIElementCopyAttributeValue(window.0, title_attr.0, &mut title) } != kAXErrorSuccess {
        return None;
    }
    let title = Owned::new(title)?;
    to_string(title.0)
}

fn exe_path(pid: i32) -> String {
    if pid <= 0 {
        return String::new();
    }
    let mut buf = vec![0u8; 4096];
    let n = unsafe { proc_pidpath(pid, buf.as_mut_ptr() as *mut c_void, buf.len() as u32) };
    if n <= 0 {
        return String::new();
    }
    String::from_utf8_lossy(&buf[..n as usize]).into_owned()
}

// ── Platform interface (mirrors macos_impl / windows_impl) ───────────────────

pub fn foreground_window() -> Option<ForegroundWindow> {
    let front = on_screen_windows().into_iter().next()?;
    let title = ax_focused_title(front.pid).unwrap_or(front.title);
    Some(ForegroundWindow {
        app_name: front.owner.clone(),
        // Lowercased owner name — the key used by browser/meeting tables.
        process_name: front.owner.to_lowercase(),
        exe_path: exe_path(front.pid),
        window_title: title.chars().take(200).collect(),
        rect: front.rect,
        // CGWindowID: lets the screenshot path capture exactly this window.
        native_handle: front.id as isize,
    })
}

pub fn idle_ms() -> u64 {
    let secs = unsafe {
        CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateCombinedSessionState, kCGAnyInputEventType)
    };
    if secs.is_finite() && secs > 0.0 { (secs * 1000.0) as u64 } else { 0 }
}

/// Browser URL via Apple Events, only for a frontmost scriptable browser and
/// only at the capture interval (not per second). The caller reduces it to
/// eTLD+1 in memory. Reuses the existing tested script table.
pub fn browser_url(win: &ForegroundWindow) -> Option<String> {
    super::macos_impl::browser_url(win)
}

pub fn enumerate_windows() -> Vec<WindowInfo> {
    on_screen_windows()
        .into_iter()
        .filter(|w| !w.title.is_empty())
        .map(|w| WindowInfo { process_name: w.owner.to_lowercase(), title: w.title })
        .collect()
}

// ── Permissions ──────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
pub struct Permissions {
    pub accessibility: bool,
    pub screen_recording: bool,
    pub input_monitoring: bool,
}

/// Preflight only — never triggers a system prompt (onboarding UI does that).
pub fn permissions() -> Permissions {
    unsafe {
        Permissions {
            accessibility: AXIsProcessTrusted(),
            screen_recording: CGPreflightScreenCaptureAccess(),
            input_monitoring: IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted,
        }
    }
}

// ── Window screenshot (window-level only) ────────────────────────────────────

/// Captures exactly one window (by CGWindowID) as RGBA. Returns None when
/// Screen Recording is not granted or the window cannot be imaged — callers
/// must then skip the screenshot rather than capture the display.
pub fn capture_window(window_id: u32) -> Option<image::RgbaImage> {
    if window_id == 0 || !unsafe { CGPreflightScreenCaptureAccess() } {
        return None;
    }
    let image = unsafe {
        CGWindowListCreateImage(
            CGRectNull,
            kCGWindowListOptionIncludingWindow,
            window_id,
            kCGWindowImageBoundsIgnoreFraming | kCGWindowImageNominalResolution,
        )
    };
    if image.is_null() {
        return None;
    }
    struct ImageGuard(CFTypeRef);
    impl Drop for ImageGuard {
        fn drop(&mut self) {
            unsafe { CGImageRelease(self.0) }
        }
    }
    let image = ImageGuard(image);

    let (w, h, stride, bpp) = unsafe {
        (CGImageGetWidth(image.0), CGImageGetHeight(image.0), CGImageGetBytesPerRow(image.0), CGImageGetBitsPerPixel(image.0))
    };
    if w < 2 || h < 2 || bpp != 32 || stride < w * 4 {
        return None;
    }
    let provider = unsafe { CGImageGetDataProvider(image.0) };
    if provider.is_null() {
        return None;
    }
    let data = Owned::new(unsafe { CGDataProviderCopyData(provider) })?;
    let len = unsafe { CFDataGetLength(data.0) } as usize;
    let ptr = unsafe { CFDataGetBytePtr(data.0) };
    if ptr.is_null() || len < stride * h {
        return None;
    }
    let bytes = unsafe { std::slice::from_raw_parts(ptr, len) };

    // Window images are 32-bit BGRA (premultiplied first, little-endian).
    let mut rgba = Vec::with_capacity(w * h * 4);
    for row in 0..h {
        let line = &bytes[row * stride..row * stride + w * 4];
        for px in line.chunks_exact(4) {
            rgba.extend_from_slice(&[px[2], px[1], px[0], px[3]]);
        }
    }
    image::RgbaImage::from_raw(w as u32, h as u32, rgba)
}

// ── Input activity counts (listen-only event tap) ────────────────────────────

static KEY_DOWNS: AtomicU32 = AtomicU32::new(0);
static MOUSE_DOWNS: AtomicU32 = AtomicU32::new(0);
/// Accumulated cursor distance in px, stored as f64 bits.
static MOUSE_DISTANCE_BITS: AtomicU64 = AtomicU64::new(0);
static LAST_X_BITS: AtomicU64 = AtomicU64::new(0);
static LAST_Y_BITS: AtomicU64 = AtomicU64::new(0);
static HAS_LAST: AtomicBool = AtomicBool::new(false);
static TAP: AtomicPtr<c_void> = AtomicPtr::new(std::ptr::null_mut());
static TAP_ACTIVE: AtomicBool = AtomicBool::new(false);
static TAP_START: Once = Once::new();

extern "C" fn tap_callback(_proxy: *const c_void, kind: u32, event: *const c_void, _user: *mut c_void) -> *const c_void {
    match kind {
        // Only the event TYPE is inspected — never key codes or characters.
        kCGEventKeyDown => {
            KEY_DOWNS.fetch_add(1, Ordering::Relaxed);
        }
        kCGEventLeftMouseDown | kCGEventRightMouseDown | kCGEventOtherMouseDown => {
            MOUSE_DOWNS.fetch_add(1, Ordering::Relaxed);
        }
        kCGEventMouseMoved | kCGEventLeftMouseDragged if !event.is_null() => {
            let p = unsafe { CGEventGetLocation(event) };
            if HAS_LAST.swap(true, Ordering::Relaxed) {
                let lx = f64::from_bits(LAST_X_BITS.load(Ordering::Relaxed));
                let ly = f64::from_bits(LAST_Y_BITS.load(Ordering::Relaxed));
                let d = ((p.x - lx).powi(2) + (p.y - ly).powi(2)).sqrt();
                let cur = f64::from_bits(MOUSE_DISTANCE_BITS.load(Ordering::Relaxed));
                MOUSE_DISTANCE_BITS.store((cur + d).to_bits(), Ordering::Relaxed);
            }
            LAST_X_BITS.store(p.x.to_bits(), Ordering::Relaxed);
            LAST_Y_BITS.store(p.y.to_bits(), Ordering::Relaxed);
        }
        kCGEventTapDisabledByTimeout | kCGEventTapDisabledByUserInput => {
            let tap = TAP.load(Ordering::Acquire);
            if !tap.is_null() {
                unsafe { CGEventTapEnable(tap, true) };
            }
        }
        _ => {}
    }
    event // listen-only: pass through untouched
}

/// Starts the event tap once on a dedicated run-loop thread. If Input
/// Monitoring is not granted the tap cannot be created and counts stay 0
/// (no synthetic values).
fn ensure_tap() {
    TAP_START.call_once(|| {
        if unsafe { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) } != kIOHIDAccessTypeGranted {
            tracing::info!("Input Monitoring not granted — activity counts disabled");
            return;
        }
        let spawned = std::thread::Builder::new().name("input-tap".into()).spawn(|| {
            let mask: u64 = (1 << kCGEventKeyDown)
                | (1 << kCGEventLeftMouseDown)
                | (1 << kCGEventRightMouseDown)
                | (1 << kCGEventOtherMouseDown)
                | (1 << kCGEventMouseMoved)
                | (1 << kCGEventLeftMouseDragged);
            let tap = unsafe {
                CGEventTapCreate(
                    kCGSessionEventTap,
                    kCGHeadInsertEventTap,
                    kCGEventTapOptionListenOnly,
                    mask,
                    tap_callback,
                    std::ptr::null_mut(),
                )
            };
            if tap.is_null() {
                tracing::warn!("CGEventTapCreate failed — activity counts disabled");
                return;
            }
            TAP.store(tap as *mut c_void, Ordering::Release);
            unsafe {
                let source = CFMachPortCreateRunLoopSource(std::ptr::null(), tap, 0);
                if source.is_null() {
                    return;
                }
                CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
                CGEventTapEnable(tap, true);
                TAP_ACTIVE.store(true, Ordering::Release);
                CFRunLoopRun(); // runs for the process lifetime
            }
        });
        if let Err(e) = spawned {
            tracing::warn!("input tap thread spawn failed: {e}");
        }
    });
}

/// Counts since the previous call: (key downs, mouse downs, cursor px).
pub fn take_input_counts() -> (u32, u32, f64) {
    ensure_tap();
    if !TAP_ACTIVE.load(Ordering::Acquire) {
        return (0, 0, 0.0);
    }
    let keys = KEY_DOWNS.swap(0, Ordering::Relaxed);
    let clicks = MOUSE_DOWNS.swap(0, Ordering::Relaxed);
    let dist = f64::from_bits(MOUSE_DISTANCE_BITS.swap(0f64.to_bits(), Ordering::Relaxed));
    (keys, clicks, dist)
}

/// Asks macOS to register THIS process (the agent — the process that actually
/// captures) in each Privacy & Security list that is still missing, so the
/// user can switch it on. Only permissions not yet granted are requested; the
/// return value is a fresh preflight, never the request APIs' result (a
/// request returning means nothing about the user's decision).
///
/// Why this exists: launchd starts the agent as its own responsible process,
/// so TCC checks the agent's code identity, not EffiLens.app's. Granting only
/// "EffiLens" in System Settings does not authorise the agent.
pub fn request_missing_permissions() -> Permissions {
    let before = permissions();
    unsafe {
        if !before.accessibility {
            if let Some(key) = cfstring("AXTrustedCheckOptionPrompt") {
                let keys = [key.0];
                let values = [kCFBooleanTrue];
                let dict = CFDictionaryCreate(
                    std::ptr::null(),
                    keys.as_ptr(),
                    values.as_ptr(),
                    1,
                    &kCFTypeDictionaryKeyCallBacks as *const c_void,
                    &kCFTypeDictionaryValueCallBacks as *const c_void,
                );
                if !dict.is_null() {
                    let _ = AXIsProcessTrustedWithOptions(dict);
                    CFRelease(dict);
                }
            }
        }
        if !before.screen_recording {
            let _ = CGRequestScreenCaptureAccess();
        }
        if !before.input_monitoring {
            let _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent);
        }
    }
    permissions()
}
