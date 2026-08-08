//! Production wrapper around the pure `TimerState` machine: applies state
//! transitions, converts emitted `StateEvent`s into persisted rows
//! (task_time_logs, active_tracking_session, agent_config last-task keys,
//! tracking_pause/resume activity events), and carries the idle/break
//! accounting the state machine itself doesn't know about.
//!
//! Accounting model (mirrors the Python agent and the backend contract):
//!   duration_sec = active seconds (net of pauses) − idle_sec
//!   idle_sec     = idle spans the user chose to keep working through
//!   break_sec    = break spans taken during the session

use crate::db::queries;
use crate::models::{ActivityEvent, Task, TaskTimeLog};
use crate::timer_state::{BreakKind, StateEvent, TimerState};
use rusqlite::Connection;
use uuid::Uuid;

#[derive(Debug, Clone, serde::Serialize)]
pub struct IdleWarning {
    pub started_ts: i64,
    pub idle_secs: u64,
}

pub struct TimerService {
    state: TimerState,
    /// Wall-clock start of the current session (survives pause/resume).
    session_started_wall: Option<i64>,
    idle_secs: u64,
    break_secs: u64,
    meeting_secs: u64,
    break_started_wall: Option<i64>,
    idle_warning: Option<IdleWarning>,
    /// Stable id for the in-progress session's task_time_log row. Set on
    /// TaskStarted, reused by every periodic `flush_active` upsert and by
    /// the final TaskStopped write, so the backend sees one row updated in
    /// place (via ON CONFLICT DO UPDATE) instead of duplicates per flush.
    session_log_id: Option<Uuid>,
    /// Wall-clock timestamp of the most recent transition into `Idle`
    /// (nothing being tracked). Drives the "you're not tracking anything"
    /// reminder — set at construction since the timer starts idle.
    idle_since_wall: Option<i64>,
}

impl Default for TimerService {
    fn default() -> Self {
        Self::new()
    }
}

impl TimerService {
    pub fn new() -> Self {
        Self {
            state: TimerState::Idle,
            session_started_wall: None,
            idle_secs: 0,
            break_secs: 0,
            meeting_secs: 0,
            break_started_wall: None,
            idle_warning: None,
            session_log_id: None,
            idle_since_wall: Some(chrono::Utc::now().timestamp()),
        }
    }

    pub fn state(&self) -> &TimerState {
        &self.state
    }

    pub fn idle_warning(&self) -> Option<&IdleWarning> {
        self.idle_warning.as_ref()
    }

    /// Seconds since the timer last became Idle (nothing being tracked),
    /// or None while a task is running/paused/on break. Drives the
    /// "still there? you're not tracking" reminder.
    pub fn idle_since_secs(&self) -> Option<u64> {
        if !matches!(self.state, TimerState::Idle) {
            return None;
        }
        self.idle_since_wall.map(|t| (chrono::Utc::now().timestamp() - t).max(0) as u64)
    }

    /// Meeting seconds accumulated so far in the CURRENT session (not yet
    /// necessarily flushed to `task_time_logs`) — added on top of the
    /// persisted daily sum so the "Meeting time" KPI updates live instead of
    /// waiting for the next ~5-minute flush_active() cycle.
    pub fn meeting_secs(&self) -> u64 {
        self.meeting_secs
    }

    pub fn is_running(&self) -> bool {
        matches!(self.state, TimerState::Running { .. })
    }

    /// Called by the capture loop's meeting detector while a task is running
    /// and the user is judged to be in a meeting. Accumulates alongside
    /// (not instead of) worked time — meeting_sec is informational, mirroring
    /// the Python agent's MeetingTracker.session_meeting_sec.
    pub fn add_meeting_seconds(&mut self, secs: u64) {
        if self.is_running() {
            self.meeting_secs += secs;
        }
    }

    /// Elapsed work seconds for display: net of idle attributed so far.
    pub fn display_elapsed(&self) -> u64 {
        self.state.elapsed_secs().saturating_sub(match self.state {
            TimerState::OnBreak { .. } => 0, // break clock shows break time
            _ => self.idle_secs,
        })
    }

    // ── Transitions ──────────────────────────────────────────────────────────

    pub fn toggle_play_pause(&mut self, conn: &Connection) {
        let (next, events) = std::mem::replace(&mut self.state, TimerState::Idle).toggle_play_pause();
        self.state = next;
        self.apply_events(conn, &events, None);
    }

    pub fn select_task(&mut self, conn: &Connection, task: Task) {
        // Persist last-used task for resume-from-idle.
        let _ = queries::set_config(conn, "last_task_id", &task.task_id.to_string());
        let _ = queries::set_config(conn, "last_project_id", &task.project_id.to_string());
        let _ = queries::set_config(conn, "last_task_name", &task.task_name);
        let _ = queries::set_config(conn, "last_project_name", &task.project_name);

        let (next, events) = std::mem::replace(&mut self.state, TimerState::Idle).select_task(task);
        self.state = next;
        self.apply_events(conn, &events, None);
    }

    pub fn start_break(&mut self, conn: &Connection, kind: BreakKind) {
        let (next, events) = std::mem::replace(&mut self.state, TimerState::Idle).start_break(kind);
        self.state = next;
        self.apply_events(conn, &events, None);
    }

    /// Resume the last-used task from config when idle (hero play button).
    pub fn resume_last_task(&mut self, conn: &Connection) {
        if !matches!(self.state, TimerState::Idle) {
            return self.toggle_play_pause(conn);
        }
        let task = (|| {
            Some(Task {
                task_id: queries::get_config(conn, "last_task_id")?.parse().ok()?,
                project_id: queries::get_config(conn, "last_project_id")?.parse().ok()?,
                task_name: queries::get_config(conn, "last_task_name")?,
                project_name: queries::get_config(conn, "last_project_name")?,
            })
        })();
        if let Some(task) = task {
            self.select_task(conn, task);
        }
    }

    /// System sleep detected — pause without user interaction.
    pub fn pause_for_sleep(&mut self, conn: &Connection) {
        if self.is_running() {
            self.toggle_play_pause(conn);
            tracing::info!("Timer paused: system sleep detected");
        }
    }

    /// Explicit stop (quit, task unassigned). Writes the session log.
    pub fn stop(&mut self, conn: &Connection) {
        let (next, events) = std::mem::replace(&mut self.state, TimerState::Idle).stop();
        self.state = next;
        self.apply_events(conn, &events, None);
    }

    // ── Idle flow ────────────────────────────────────────────────────────────

    /// Called by the capture loop when the idle threshold is crossed while
    /// running. Idle start is back-dated to when input actually stopped.
    pub fn on_idle_threshold(&mut self, idle_started_ts: i64) {
        if self.is_running() && self.idle_warning.is_none() {
            self.idle_warning = Some(IdleWarning { started_ts: idle_started_ts, idle_secs: 0 });
            tracing::info!("Idle timer started (no input since {idle_started_ts})");
        }
    }

    /// Called each capture tick while a warning is active to update its span.
    pub fn tick_idle_warning(&mut self) {
        if let Some(w) = &mut self.idle_warning {
            w.idle_secs = (chrono::Utc::now().timestamp() - w.started_ts).max(0) as u64;
        }
    }

    /// User said "still working": attribute the idle span to idle_sec
    /// (deducted from worked time) and keep the timer running.
    pub fn idle_keep_working(&mut self, conn: &Connection) {
        if let Some(w) = self.idle_warning.take() {
            let span = (chrono::Utc::now().timestamp() - w.started_ts).max(0) as u64;
            self.idle_secs += span;
            self.checkpoint(conn);
            tracing::info!("Idle timer paused ({span}s idle, kept working)");
        }
    }

    /// User went on break / countdown expired: stop the session back-dated to
    /// when the idle actually began, excluding the idle span entirely.
    pub fn idle_auto_stop(&mut self, conn: &Connection) {
        if let Some(w) = self.idle_warning.take() {
            let idle_span = (chrono::Utc::now().timestamp() - w.started_ts).max(0) as u64;
            tracing::info!("Idle timer ended ({idle_span}s idle) — task auto-stopped");
            let (next, events) = std::mem::replace(&mut self.state, TimerState::Idle).stop();
            self.state = next;
            self.apply_events(conn, &events, Some(BackdatedStop { ended_at: w.started_ts, exclude_secs: idle_span }));
        }
    }

    /// Any real input clears a pending warning (user came back on their own).
    pub fn clear_idle_warning_on_activity(&mut self) {
        self.idle_warning = None;
    }

    // ── Crash recovery ───────────────────────────────────────────────────────

    /// On agentd startup: if a checkpointed session exists, write an
    /// "interrupted" log covering start→last-checkpoint (≤60s of loss), then
    /// clear the checkpoint. The timer starts idle; auto-resume is a UI choice.
    pub fn recover_crashed_session(conn: &Connection) {
        if let Some(s) = queries::get_active_session(conn) {
            let duration = s.accumulated_seconds.max(0);
            if duration > 0 {
                let log = TaskTimeLog {
                    id: Uuid::new_v4(),
                    task_id: s.task.task_id,
                    project_id: s.task.project_id,
                    task_name: s.task.task_name.clone(),
                    project_name: s.task.project_name.clone(),
                    started_at: s.session_start_ts,
                    ended_at: s.saved_at,
                    duration_sec: duration,
                    idle_sec: 0,
                    break_sec: 0,
                    meeting_sec: 0,
                    synced: false,
                };
                if queries::insert_task_time_log(conn, &log).is_ok() {
                    tracing::info!("Recovered interrupted session: {} ({}s)", s.task.task_name, duration);
                }
            }
            let _ = queries::save_active_session(conn, None, 0);
        }
    }

    /// Periodic checkpoint (call ~every 60s) so a crash loses ≤ one interval.
    pub fn checkpoint(&self, conn: &Connection) {
        let accumulated = self.state.elapsed_secs().saturating_sub(self.idle_secs);
        let _ = queries::save_active_session(conn, self.state.active_task(), accumulated);
    }

    /// Called by the sync loop (and manual "sync now") while a task is
    /// actively running or paused: upserts a provisional task_time_log for
    /// the in-progress session using the stable `session_log_id`, so the
    /// backend/dashboard reflects live progress instead of waiting for the
    /// session to fully stop. The final TaskStopped write reuses the same
    /// id and overwrites this row with the finalized values.
    pub fn flush_active(&mut self, conn: &Connection) {
        let (task, accumulated_state) = match &self.state {
            TimerState::Running { task, .. } | TimerState::Paused { task, .. } => {
                (task.clone(), self.state.elapsed_secs())
            }
            _ => return,
        };
        let now = chrono::Utc::now().timestamp();
        let id = *self.session_log_id.get_or_insert_with(Uuid::new_v4);
        let started_at = self.session_started_wall.unwrap_or(now);
        let net = accumulated_state.saturating_sub(self.idle_secs) as i64;
        let log = TaskTimeLog {
            id,
            task_id: task.task_id,
            project_id: task.project_id,
            task_name: task.task_name,
            project_name: task.project_name,
            started_at,
            ended_at: now,
            duration_sec: net,
            idle_sec: self.idle_secs as i64,
            break_sec: self.break_secs as i64,
            meeting_sec: self.meeting_secs as i64,
            synced: false,
        };
        // Zero-duration provisional rows are skipped — nothing worth
        // showing yet (mirrors the drop rule in apply_events). Meeting
        // seconds still count as "worth showing": a session can accrue
        // meeting time while net work is momentarily 0 (e.g. just started,
        // or entirely idle-excluded so far), and dropping the row here would
        // silently lose that meeting time since flush_active periodically
        // overwrites the same provisional row.
        if log.duration_sec > 0 || log.meeting_sec > 0 {
            let _ = queries::insert_task_time_log(conn, &log);
        }
    }

    // ── Event application ────────────────────────────────────────────────────

    fn apply_events(&mut self, conn: &Connection, events: &[StateEvent], backdate: Option<BackdatedStop>) {
        let now = chrono::Utc::now().timestamp();
        for ev in events {
            match ev {
                StateEvent::TaskStarted { task } => {
                    self.session_started_wall = Some(now);
                    self.idle_secs = 0;
                    self.break_secs = 0;
                    self.meeting_secs = 0;
                    self.idle_warning = None;
                    self.session_log_id = Some(Uuid::new_v4());
                    let _ = queries::save_active_session(conn, Some(task), 0);
                    self.record_tracking_event(conn, "tracking_resume", now);
                    tracing::info!("Task started: {} ({})", task.task_name, task.project_name);
                }
                StateEvent::TaskStopped { task, duration_secs } => {
                    let (ended_at, excluded) = match &backdate {
                        Some(b) => (b.ended_at, b.exclude_secs),
                        None => (now, 0),
                    };
                    let gross = duration_secs.saturating_sub(excluded);
                    let net = gross.saturating_sub(self.idle_secs);
                    let started_at = self.session_started_wall.unwrap_or(ended_at - gross as i64);
                    let log = TaskTimeLog {
                        id: self.session_log_id.take().unwrap_or_else(Uuid::new_v4),
                        task_id: task.task_id,
                        project_id: task.project_id,
                        task_name: task.task_name.clone(),
                        project_name: task.project_name.clone(),
                        started_at,
                        ended_at,
                        duration_sec: net as i64,
                        idle_sec: self.idle_secs as i64,
                        break_sec: self.break_secs as i64,
                        meeting_sec: self.meeting_secs as i64,
                        synced: false,
                    };
                    // Zero-duration no-op segments are dropped, matching the Python agent.
                    // meeting_sec is included so a session with real meeting time isn't
                    // silently discarded just because net work/idle/break all landed at 0.
                    if log.duration_sec > 0 || log.idle_sec > 0 || log.break_sec > 0 || log.meeting_sec > 0 {
                        let _ = queries::insert_task_time_log(conn, &log);
                    }
                    self.session_started_wall = None;
                    self.idle_secs = 0;
                    self.break_secs = 0;
                    self.meeting_secs = 0;
                    self.idle_warning = None;
                    let _ = queries::save_active_session(conn, None, 0);
                    self.record_tracking_event(conn, "tracking_pause", ended_at);
                    tracing::info!("Task stopped: {} ({}s worked, {}s idle, {}s break)",
                        task.task_name, log.duration_sec, log.idle_sec, log.break_sec);
                }
                StateEvent::TrackingPaused => {
                    self.checkpoint(conn);
                    self.record_tracking_event(conn, "tracking_pause", now);
                    tracing::info!("Task paused: {}", self.state.active_task().map(|t| t.task_name.as_str()).unwrap_or("?"));
                }
                StateEvent::TrackingResumed => {
                    if self.session_started_wall.is_none() {
                        self.session_started_wall = Some(now);
                    }
                    self.record_tracking_event(conn, "tracking_resume", now);
                    tracing::info!("Task resumed: {}", self.state.active_task().map(|t| t.task_name.as_str()).unwrap_or("?"));
                }
                StateEvent::BreakStarted => {
                    self.break_started_wall = Some(now);
                    self.checkpoint(conn);
                    if let TimerState::OnBreak { kind, .. } = &self.state {
                        tracing::info!("Break started: {}", kind.display());
                    }
                }
                StateEvent::BreakEnded => {
                    if let Some(started) = self.break_started_wall.take() {
                        let span = (now - started).max(0) as u64;
                        self.break_secs += span;
                        tracing::info!("Break ended ({span}s)");
                    }
                }
            }
        }

        // Single source of truth for idle_since_wall: whatever path led
        // here (stop, idle_auto_stop, a switch that lands on a new task,
        // …), it's driven off the FINAL state, not the specific event.
        if matches!(self.state, TimerState::Idle) {
            self.idle_since_wall.get_or_insert(now);
        } else {
            self.idle_since_wall = None;
        }
    }

    fn record_tracking_event(&self, conn: &Connection, event_type: &str, ts: i64) {
        let user_id: Uuid = match queries::get_config(conn, "user_id").and_then(|s| s.parse().ok()) {
            Some(id) => id,
            None => return,
        };
        let tenant_id: Uuid = match queries::get_config(conn, "tenant_id").and_then(|s| s.parse().ok()) {
            Some(id) => id,
            None => return,
        };
        let ev = ActivityEvent {
            event_uuid: Uuid::new_v4(),
            user_id,
            tenant_id,
            event_type: event_type.into(),
            ts,
            duration_sec: 0,
            payload: serde_json::json!({}),
        };
        let _ = queries::insert_event(conn, &ev);
    }
}

struct BackdatedStop {
    ended_at: i64,
    exclude_secs: u64,
}
