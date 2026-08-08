use crate::models::Task;
use std::time::Instant;

#[derive(Debug, Clone, PartialEq)]
pub enum BreakKind {
    Coffee,
    Lunch,
    Custom(String, u64),
}

impl BreakKind {
    pub fn display(&self) -> &str {
        match self {
            BreakKind::Coffee => "Coffee Break",
            BreakKind::Lunch => "Lunch",
            BreakKind::Custom(name, _) => name.as_str(),
        }
    }
    pub fn duration_secs(&self) -> u64 {
        match self {
            BreakKind::Coffee => 600,
            BreakKind::Lunch => 1800,
            BreakKind::Custom(_, d) => *d,
        }
    }
}

#[derive(Debug, Clone)]
pub enum TimerState {
    Idle,
    Running { task: Task, started: Instant, accumulated: u64 },
    Paused { task: Task, accumulated: u64 },
    OnBreak { kind: BreakKind, prev_task: Option<Task>, prev_accumulated: u64, break_started: Instant },
}

impl TimerState {
    /// Play/pause button pressed from any state.
    pub fn toggle_play_pause(self) -> (TimerState, Vec<StateEvent>) {
        match self {
            TimerState::Idle => (TimerState::Idle, vec![]),
            TimerState::Running { task, started, accumulated } => {
                let elapsed = started.elapsed().as_secs();
                let total = accumulated + elapsed;
                (TimerState::Paused { task, accumulated: total }, vec![StateEvent::TrackingPaused])
            }
            TimerState::Paused { task, accumulated } => {
                (TimerState::Running { task, started: Instant::now(), accumulated },
                 vec![StateEvent::TrackingResumed])
            }
            TimerState::OnBreak { prev_task, prev_accumulated, .. } => {
                // End break → resume whatever was running before
                match prev_task {
                    Some(task) => (
                        TimerState::Running { task, started: Instant::now(), accumulated: prev_accumulated },
                        vec![StateEvent::BreakEnded, StateEvent::TrackingResumed]
                    ),
                    None => (TimerState::Idle, vec![StateEvent::BreakEnded]),
                }
            }
        }
    }

    /// User clicked a task row.
    pub fn select_task(self, new_task: Task) -> (TimerState, Vec<StateEvent>) {
        match self {
            TimerState::OnBreak { prev_task, prev_accumulated, .. } => {
                // End the break, then resume/switch — clicking the pre-break
                // task resumes it (never a pause double-toggle).
                match prev_task {
                    Some(t) if t.task_id == new_task.task_id => (
                        TimerState::Running { task: t, started: Instant::now(), accumulated: prev_accumulated },
                        vec![StateEvent::BreakEnded, StateEvent::TrackingResumed],
                    ),
                    Some(t) => (
                        TimerState::Running { task: new_task.clone(), started: Instant::now(), accumulated: 0 },
                        vec![
                            StateEvent::BreakEnded,
                            StateEvent::TaskStopped { task: t, duration_secs: prev_accumulated },
                            StateEvent::TaskStarted { task: new_task },
                        ],
                    ),
                    None => (
                        TimerState::Running { task: new_task.clone(), started: Instant::now(), accumulated: 0 },
                        vec![StateEvent::BreakEnded, StateEvent::TaskStarted { task: new_task }],
                    ),
                }
            }
            TimerState::Running { task: current, started, accumulated } => {
                if current.task_id == new_task.task_id {
                    // Same task → pause it (toggle)
                    let elapsed = started.elapsed().as_secs();
                    let total = accumulated + elapsed;
                    (TimerState::Paused { task: current, accumulated: total },
                     vec![StateEvent::TrackingPaused])
                } else {
                    // Different task → stop current, start new
                    let elapsed = started.elapsed().as_secs();
                    let total = accumulated + elapsed;
                    (TimerState::Running { task: new_task.clone(), started: Instant::now(), accumulated: 0 },
                     vec![StateEvent::TaskStopped { task: current, duration_secs: total },
                          StateEvent::TaskStarted { task: new_task }])
                }
            }
            TimerState::Paused { task: current, accumulated } => {
                if current.task_id == new_task.task_id {
                    // Resume paused task
                    (TimerState::Running { task: current, started: Instant::now(), accumulated },
                     vec![StateEvent::TrackingResumed])
                } else {
                    (TimerState::Running { task: new_task.clone(), started: Instant::now(), accumulated: 0 },
                     vec![StateEvent::TaskStopped { task: current, duration_secs: accumulated },
                          StateEvent::TaskStarted { task: new_task }])
                }
            }
            TimerState::Idle => {
                (TimerState::Running { task: new_task.clone(), started: Instant::now(), accumulated: 0 },
                 vec![StateEvent::TaskStarted { task: new_task }])
            }
        }
    }

    pub fn start_break(self, kind: BreakKind) -> (TimerState, Vec<StateEvent>) {
        let (prev_task, prev_accumulated) = match &self {
            TimerState::Running { task, started, accumulated } => {
                let total = accumulated + started.elapsed().as_secs();
                (Some(task.clone()), total)
            }
            TimerState::Paused { task, accumulated } => (Some(task.clone()), *accumulated),
            _ => (None, 0),
        };
        (TimerState::OnBreak { kind, prev_task, prev_accumulated, break_started: Instant::now() },
         vec![StateEvent::BreakStarted])
    }

    /// Explicit stop from any state (idle auto-stop, task unassigned, quit).
    pub fn stop(self) -> (TimerState, Vec<StateEvent>) {
        match self {
            TimerState::Idle => (TimerState::Idle, vec![]),
            TimerState::Running { task, started, accumulated } => {
                let total = accumulated + started.elapsed().as_secs();
                (TimerState::Idle, vec![StateEvent::TaskStopped { task, duration_secs: total }])
            }
            TimerState::Paused { task, accumulated } => {
                (TimerState::Idle, vec![StateEvent::TaskStopped { task, duration_secs: accumulated }])
            }
            TimerState::OnBreak { prev_task, prev_accumulated, .. } => {
                let mut events = vec![StateEvent::BreakEnded];
                if let Some(task) = prev_task {
                    events.push(StateEvent::TaskStopped { task, duration_secs: prev_accumulated });
                }
                (TimerState::Idle, events)
            }
        }
    }

    pub fn elapsed_secs(&self) -> u64 {
        match self {
            TimerState::Running { started, accumulated, .. } => accumulated + started.elapsed().as_secs(),
            TimerState::Paused { accumulated, .. } => *accumulated,
            TimerState::OnBreak { break_started, .. } => break_started.elapsed().as_secs(),
            TimerState::Idle => 0,
        }
    }

    pub fn active_task(&self) -> Option<&Task> {
        match self {
            TimerState::Running { task, .. } | TimerState::Paused { task, .. } => Some(task),
            TimerState::OnBreak { prev_task, .. } => prev_task.as_ref(),
            TimerState::Idle => None,
        }
    }

    pub fn state_name(&self) -> &str {
        match self {
            TimerState::Idle => "idle",
            TimerState::Running { .. } => "running",
            TimerState::Paused { .. } => "paused",
            TimerState::OnBreak { .. } => "on_break",
        }
    }
}

#[derive(Debug, Clone)]
pub enum StateEvent {
    TaskStarted { task: Task },
    TaskStopped { task: Task, duration_secs: u64 },
    TrackingPaused,
    TrackingResumed,
    BreakStarted,
    BreakEnded,
}
