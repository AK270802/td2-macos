//! Meeting detection — port of the Python agent's `MeetingTracker`.
//!
//! v1 signals (Windows-primary; degrades gracefully elsewhere):
//!   A. A known meeting app process is running               (+30)
//!   B. A visible window title matches an in-call pattern     (+30)
//! Threshold 60 means both signals must agree — this deliberately excludes
//! the Python agent's microphone/audio-output signals (no WASAPI binding in
//! v1), so a meeting app merely running in the background (not on a call)
//! never counts on its own.
//!
//! Debounce mirrors the Python agent: 2 consecutive above-threshold ticks
//! (10s @ 5s interval) before a meeting is declared started, 6 consecutive
//! below-threshold ticks (30s) of grace before it's declared ended — so a
//! muted mic moment or a transient title change doesn't flap the state.
//!
//! Privacy: only a boolean in-meeting state and an integer second counter
//! ever leave this module. No participant names, audio, or meeting content.

const EVAL_INTERVAL_SECS: u64 = 5;
const SCORE_APP_MATCH: u32 = 30;
const SCORE_TITLE_MATCH: u32 = 30;
const THRESHOLD: u32 = 60;
const MIN_START_TICKS: u32 = 2;
const GRACE_TICKS: u32 = 6;

const MEETING_APPS: &[&str] = &[
    "zoom.exe", "ms-teams.exe", "teams.exe", "webex.exe", "slack.exe",
    "discord.exe", "lync.exe", "skype.exe", "goto.exe", "g2mcomm.exe",
    "ringcentral.exe",
];

/// Case-insensitive substrings that indicate an *active call* (not just the
/// app being open) for a given owning process. Checked against every window
/// title belonging to that process.
fn app_call_title_match(process_name: &str, title_lower: &str) -> bool {
    match process_name {
        "zoom.exe" => title_lower.contains("zoom meeting") || title_lower.contains("zoom webinar"),
        // Loosened from a strict "starts with Meeting/Call AND contains
        // Microsoft Teams" — real-world Teams window titles vary a lot
        // (meeting name only, "Meeting in progress", the new Teams client's
        // separate floating call-control window, etc.) and rarely matched
        // that exact shape, so real meetings were going undetected.
        "ms-teams.exe" | "teams.exe" => {
            title_lower.contains("meeting")
                || title_lower.contains("call")
                || title_lower.contains("huddle")
        }
        "webex.exe" => title_lower.contains("webex") || title_lower.contains("meeting"),
        "slack.exe" => title_lower.contains("huddle") || title_lower.contains("call"),
        "discord.exe" => title_lower.contains("voice connected") || title_lower.contains("call"),
        "skype.exe" | "lync.exe" | "goto.exe" | "g2mcomm.exe" | "ringcentral.exe" => {
            title_lower.contains("call") || title_lower.contains("meeting")
        }
        _ => false,
    }
}

/// Web-based meeting title patterns, checked against any visible browser
/// window regardless of focus (a Meet tab can be running while the user
/// works in another app).
fn browser_call_title_match(title_lower: &str) -> bool {
    title_lower.contains("google meet")
        || title_lower.contains("zoom meeting")
        || title_lower.contains("zoom webinar")
        || title_lower.contains("webex meeting")
        || title_lower.contains("jitsi meet")
        || title_lower.contains("whereby")
        || (title_lower.contains("microsoft teams")
            && (title_lower.starts_with("meeting") || title_lower.starts_with("call")))
}

pub struct MeetingDetector {
    consecutive_above: u32,
    grace_remaining: u32,
    in_meeting: bool,
    session_meeting_secs: u64,
    tick_count: u32,
}

impl Default for MeetingDetector {
    fn default() -> Self {
        Self::new()
    }
}

impl MeetingDetector {
    pub fn new() -> Self {
        Self { consecutive_above: 0, grace_remaining: 0, in_meeting: false, session_meeting_secs: 0, tick_count: 0 }
    }

    pub fn is_in_meeting(&self) -> bool {
        self.in_meeting
    }

    pub fn session_meeting_secs(&self) -> u64 {
        self.session_meeting_secs
    }

    pub fn reset_session_meeting_secs(&mut self) {
        self.session_meeting_secs = 0;
    }

    /// Call once every `EVAL_INTERVAL_SECS` (the capture loop gates this).
    /// `accumulate` should be false while nothing is being tracked, so
    /// seconds never accrue against no active task (mirrors the Python
    /// agent's `pause()`/`resume()` around TaskTimer state).
    pub fn evaluate(&mut self, accumulate: bool) -> bool {
        let windows = crate::platform::enumerate_windows();

        let mut app_match = false;
        let mut title_match = false;

        for w in &windows {
            let proc = w.process_name.as_str();
            let title_lower = w.title.to_lowercase();
            if MEETING_APPS.contains(&proc) {
                app_match = true;
                if app_call_title_match(proc, &title_lower) {
                    title_match = true;
                }
            } else if crate::capture::browser_tracker::is_browser(proc)
                && browser_call_title_match(&title_lower)
            {
                // A specific web-meeting tab title (Google Meet, Zoom
                // Meeting, Webex, etc.) is strong evidence on its own —
                // count it as both signals so browser-based meetings can
                // reach the threshold too, not just native desktop apps.
                app_match = true;
                title_match = true;
            }
        }

        let mut score = 0u32;
        if app_match {
            score += SCORE_APP_MATCH;
        }
        if title_match {
            score += SCORE_TITLE_MATCH;
        }
        let above = score >= THRESHOLD;
        let was_in_meeting = self.in_meeting;

        // Visible at the default "info" log level (no RUST_LOG=debug needed)
        // every ~60s so a "why isn't this detecting?" report always has real
        // signal data to look at, even when no meeting is ever detected.
        self.tick_count += 1;
        if self.tick_count % 12 == 0 {
            tracing::info!(
                "meeting check: app_match={app_match} title_match={title_match} score={score}/{THRESHOLD} in_meeting={} windows_seen={}",
                self.in_meeting, windows.len()
            );
        }

        if above {
            if self.in_meeting {
                self.grace_remaining = GRACE_TICKS;
            } else {
                self.consecutive_above += 1;
                if self.consecutive_above >= MIN_START_TICKS {
                    self.in_meeting = true;
                    self.grace_remaining = GRACE_TICKS;
                }
            }
        } else if self.in_meeting {
            self.consecutive_above = 0;
            if self.grace_remaining > 0 {
                self.grace_remaining -= 1;
            } else {
                self.in_meeting = false;
            }
        } else {
            self.consecutive_above = 0;
        }

        if self.in_meeting && !was_in_meeting {
            tracing::info!("Meeting started (score={score}, app_match={app_match}, title_match={title_match})");
        } else if !self.in_meeting && was_in_meeting {
            tracing::info!("Meeting ended ({}s accumulated this session)", self.session_meeting_secs);
        }

        if self.in_meeting && accumulate {
            self.session_meeting_secs += EVAL_INTERVAL_SECS;
        }

        self.in_meeting
    }
}
