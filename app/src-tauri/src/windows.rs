//! Window management. Every window loads the same SPA (index.html); the
//! React app renders Main / MiniWidget / IdleWarning based on the Tauri
//! window label, so there are no separate HTML entry points to drift.

use std::sync::atomic::{AtomicBool, Ordering};
use tauri::{window::Color, AppHandle, Manager, WebviewUrl, WebviewWindowBuilder};

/// Matches `--bg` / the `html,body` pre-hydration paint in index.html
/// (#080C18). Setting this at the native window+webview layer (not just in
/// CSS) means the very first frame WebView2 paints — before any HTML/CSS has
/// loaded, and on the GPU/driver configs where it fails to repaint after that
/// — is already the correct dark background instead of WebView2's white
/// default. This is the root fix for the mini widget (and other secondary
/// windows) rendering solid white; the `force_repaint` resize nudge below is
/// kept as a secondary safety net, not the primary fix.
const APP_BG: Color = Color(8, 12, 24, 255);

// The tray's menu/click handlers run ON the main event-loop thread, while the
// `show_mini_widget`/`show_main_window` Tauri commands (non-async) run on the
// async runtime's blocking-task pool. Calling `WebviewWindowBuilder::build()`
// from that background thread makes it hop to the main thread and block
// waiting for the round trip — a known source of hangs on Windows, especially
// combined with `always_on_top`/`skip_taskbar`. Queuing the whole
// check-then-create sequence onto the main thread via `run_on_main_thread`
// sidesteps both problems: it never blocks the calling thread, and the
// actual window creation always happens on the thread that owns the message
// loop.
//
// The pending flag must stay `true` for the ENTIRE check-then-create
// sequence, not just until the closure starts running — resetting it as the
// closure's first statement (as this used to do) reopens the exact race it
// was meant to close: a second call arriving while the first closure is
// still mid-flight would see "not pending", re-check `get_webview_window`
// (which doesn't know about the window until `build()` returns), and create
// a SECOND window under the same label. Tauri window labels are meant to be
// unique identifiers, and two windows racing to register the same one is
// exactly the kind of internal-state corruption that would explain a window
// coming up with its `decorations(false)` never applied. The flag is reset
// only once, at the very end of the closure, after every path (show-existing
// or build-new) has fully completed.
static MINI_PENDING: AtomicBool = AtomicBool::new(false);
static MAIN_PENDING: AtomicBool = AtomicBool::new(false);
static IDLE_WARNING_PENDING: AtomicBool = AtomicBool::new(false);

/// Tracks whether the user explicitly hid the mini widget (tray "Hide mini
/// timer", or double-clicking the widget to return to the main window) —
/// as opposed to it simply never having been shown yet. The title bar's
/// "minimize to mini timer" flow checks this so it stops forcing the widget
/// back open every time, which is what made "hide" feel like it didn't
/// stick. Cleared the moment the user asks for the widget again (tray
/// "Show mini timer", the title bar's mini-timer button), since that's an
/// explicit statement they want it visible.
static MINI_WIDGET_USER_HIDDEN: AtomicBool = AtomicBool::new(false);

pub fn mini_widget_user_hidden() -> bool {
    MINI_WIDGET_USER_HIDDEN.load(Ordering::SeqCst)
}

pub fn show_main(app: &AppHandle) -> tauri::Result<()> {
    if MAIN_PENDING.swap(true, Ordering::SeqCst) {
        return Ok(()); // a creation/show is already queued
    }
    let app = app.clone();
    app.clone().run_on_main_thread(move || {
        let result = if let Some(win) = app.get_webview_window("main") {
            win.show().and_then(|_| win.unminimize()).and_then(|_| win.set_focus())
        } else {
            WebviewWindowBuilder::new(&app, "main", WebviewUrl::App("index.html".into()))
                .title("EffiLens")
                .inner_size(1180.0, 780.0)
                .min_inner_size(980.0, 640.0)
                .decorations(false)
                .background_color(APP_BG)
                .center()
                .build()
                .map(|_| ())
        };
        if let Err(e) = &result {
            eprintln!("show_main failed: {e}");
        }
        MAIN_PENDING.store(false, Ordering::SeqCst);
    })
}

/// Known WebView2 quirk: on some GPU/driver configs, a window can paint
/// blank and never repaint again on its own — both on first creation before
/// content is ready, AND on `show()` after being hidden (e.g. the tray can
/// create the mini widget before login, then every later click just calls
/// `show()` on that same already-built window — a fresh build only happens
/// once). A trivial resize forces a real WM_SIZE, making WebView2 recompute
/// and repaint.
fn force_repaint(win: &tauri::WebviewWindow) {
    let size = win.inner_size().unwrap_or(tauri::PhysicalSize::new(264, 50));
    let bumped = tauri::PhysicalSize::new(size.width, size.height.saturating_add(1));
    let _ = win.set_size(tauri::Size::Physical(bumped));
    let _ = win.set_size(tauri::Size::Physical(size));
}

/// Nudges a window's paint from a fresh OS thread at each of `delays_ms`,
/// then drops it — used as a fallback for the WebView2 blank-paint quirk
/// when the immediate post-`build()`/`show()` repaint fires too early
/// (before WebView2 has actually finished attaching/painting the page).
/// Several staggered attempts (rather than one fixed guess) because how long
/// that takes is GPU/driver-dependent and not something this process can
/// observe directly — each attempt is cheap and a no-op if the window is
/// already fine. Safe to call `run_on_main_thread` from here because this is
/// a brand new thread, not a window-event callback already running on the
/// main thread — that distinction matters: an earlier fix that called
/// `run_on_main_thread` from inside an `on_page_load` callback (which
/// already runs on the main thread on Windows) deadlocked the whole app.
fn schedule_delayed_repaint(app: AppHandle, label: &'static str, delays_ms: &'static [u64]) {
    std::thread::spawn(move || {
        for delay in delays_ms {
            std::thread::sleep(std::time::Duration::from_millis(*delay));
            let handle = app.clone();
            let _ = app.run_on_main_thread(move || {
                if let Some(win) = handle.get_webview_window(label) {
                    force_repaint(&win);
                }
            });
        }
    });
}

pub fn show_mini_widget(app: &AppHandle) -> tauri::Result<()> {
    // An explicit show request always wins over a previous hide.
    MINI_WIDGET_USER_HIDDEN.store(false, Ordering::SeqCst);
    if MINI_PENDING.swap(true, Ordering::SeqCst) {
        return Ok(()); // a creation/show is already queued
    }
    let app = app.clone();
    app.clone().run_on_main_thread(move || {
        let result = if let Some(win) = app.get_webview_window("mini") {
            let r = win.show().and_then(|_| win.set_focus());
            force_repaint(&win);
            // The immediate resize above can still land before WebView2 has
            // actually repainted after coming back from hidden — this is the
            // common "reopen an already-built widget" path (tray / title bar
            // clicked again), so unlike the fresh-build path below it has no
            // `on_page_load` signal to hook; several staggered guesses stand
            // in for it instead.
            schedule_delayed_repaint(app.clone(), "mini", &[150, 350, 700, 1200]);
            // TEMPORARY diagnostic (dev builds only): the widget renders
            // blank specifically once real timer/task data is flowing
            // (works logged-out, breaks logged-in with an active session),
            // which points at a JS-side crash rather than a paint-timing
            // issue — auto-open devtools so the console error is visible.
            #[cfg(debug_assertions)]
            win.open_devtools();
            r
        } else {
            let build_result = WebviewWindowBuilder::new(&app, "mini", WebviewUrl::App("index.html?window=mini".into()))
                .title("EffiLens Mini")
                .inner_size(264.0, 50.0)
                // The synchronous force_repaint right after build() fires
                // before WebView2 has necessarily finished loading the page
                // — this is the real fix: nudge a resize once navigation has
                // actually completed. Must call force_repaint directly here,
                // NOT via `run_on_main_thread` — on Windows this callback
                // already runs on the main thread, and re-entering
                // `run_on_main_thread` from within it deadlocks the app
                // (an earlier attempt at exactly that froze the whole UI).
                .on_page_load(|window, payload| {
                    if payload.event() == tauri::webview::PageLoadEvent::Finished {
                        force_repaint(&window);
                    }
                })
                // Explicit safe starting position, well clear of any screen
                // edge — leaving this to the OS default risked landing close
                // enough to an edge (observed: x=25 on a 1080p display) to
                // fall inside useEdgeSnap's snap threshold on the very first
                // (non-drag) window-manager move event.
                .center()
                .decorations(false)
                .background_color(APP_BG)
                .always_on_top(true)
                .skip_taskbar(true)
                // Not user-resizable (no OS chrome to drag anyway, decorations
                // are off) — but the React side calls setSize()/setPosition()
                // programmatically to snap the widget to a screen edge, which
                // Tauri only honours if the window is marked resizable.
                .resizable(true)
                // Windows' own Snap Assist (drag-to-edge / drag-to-top) reads
                // the maximize capability, not `resizable` — with it left at
                // the default `true`, dragging the widget near a screen edge
                // could trigger the OS's native snap-to-fullscreen instead of
                // (or racing with) useEdgeSnap's own dock-to-edge logic. The
                // widget has no maximized layout of its own, so disable it
                // outright rather than fighting the OS for the gesture.
                .maximizable(false)
                .build();
            if let Ok(win) = &build_result {
                force_repaint(win);
                // `on_page_load(Finished)` fires on the HTML document's load
                // event, which can still land before the React bundle has
                // actually mounted and painted — a couple more delayed
                // nudges cover that gap.
                schedule_delayed_repaint(app.clone(), "mini", &[300, 700]);
                // TEMPORARY diagnostic (dev builds only): the show-existing
                // branch above already auto-opens devtools, but this
                // fresh-build branch — the one that actually runs on a
                // user's FIRST "show mini widget" click — never did, so any
                // JS crash on that first paint was invisible unless the
                // widget happened to be reopened afterward.
                #[cfg(debug_assertions)]
                win.open_devtools();
            }
            build_result.map(|_| ())
        };
        if let Err(e) = &result {
            eprintln!("show_mini_widget failed: {e}");
        }
        MINI_PENDING.store(false, Ordering::SeqCst);
    })
}

/// Runs on the main thread like the `show_*` functions above — callers
/// (Tauri commands, tray menu handlers) can run on a background thread pool,
/// and window-handle calls like `hide()` hitting the native window from off
/// the thread that owns the message loop are the same class of hazard
/// documented at the top of this file for `build()`.
pub fn hide_mini_widget(app: &AppHandle) -> tauri::Result<()> {
    MINI_WIDGET_USER_HIDDEN.store(true, Ordering::SeqCst);
    let app = app.clone();
    app.clone().run_on_main_thread(move || {
        if let Some(win) = app.get_webview_window("mini") {
            let _ = win.hide();
        }
    })
}

/// Runs on the main thread for the same reason as the `show_*`/`hide_mini_widget`
/// functions above — window-handle calls off the thread that owns the
/// message loop are a hang/UB hazard on Windows.
pub fn hide_main(app: &AppHandle) -> tauri::Result<()> {
    let app = app.clone();
    app.clone().run_on_main_thread(move || {
        if let Some(win) = app.get_webview_window("main") {
            let _ = win.hide();
        }
    })
}

pub fn show_idle_warning(app: &AppHandle) -> tauri::Result<()> {
    if IDLE_WARNING_PENDING.swap(true, Ordering::SeqCst) {
        return Ok(()); // a creation/show is already queued
    }
    let app = app.clone();
    app.clone().run_on_main_thread(move || {
        let result = if let Some(win) = app.get_webview_window("idle_warning") {
            win.show().and_then(|_| win.set_focus())
        } else {
            WebviewWindowBuilder::new(&app, "idle_warning", WebviewUrl::App("index.html?window=idle_warning".into()))
                .title("Are you still working?")
                .inner_size(420.0, 300.0)
                .decorations(false)
                .background_color(APP_BG)
                .always_on_top(true)
                .center()
                .resizable(false)
                .maximizable(false)
                .build()
                .map(|_| ())
        };
        if let Err(e) = &result {
            eprintln!("show_idle_warning failed: {e}");
        }
        IDLE_WARNING_PENDING.store(false, Ordering::SeqCst);
    })
}

pub fn close_idle_warning(app: &AppHandle) -> tauri::Result<()> {
    let app = app.clone();
    app.clone().run_on_main_thread(move || {
        if let Some(win) = app.get_webview_window("idle_warning") {
            let _ = win.close();
        }
    })
}
