use common::models::Task;
use common::timer_state::{BreakKind, TimerState, StateEvent};
use uuid::Uuid;

fn task(name: &str) -> Task {
    Task { task_id: Uuid::new_v4(), project_id: Uuid::new_v4(), task_name: name.into(), project_name: "P".into() }
}

fn same_task(a: &Task, b: &Task) -> bool { a.task_id == b.task_id }

#[test]
fn idle_toggle_is_noop() {
    let (s, ev) = TimerState::Idle.toggle_play_pause();
    assert!(matches!(s, TimerState::Idle));
    assert!(ev.is_empty());
}

#[test]
fn running_toggle_pauses() {
    let t = task("A");
    let s = TimerState::Running { task: t, started: std::time::Instant::now(), accumulated: 10 };
    let (s2, ev) = s.toggle_play_pause();
    assert!(matches!(s2, TimerState::Paused { .. }));
    assert!(ev.iter().any(|e| matches!(e, StateEvent::TrackingPaused)));
}

#[test]
fn paused_toggle_resumes() {
    let t = task("A");
    let s = TimerState::Paused { task: t, accumulated: 10 };
    let (s2, ev) = s.toggle_play_pause();
    assert!(matches!(s2, TimerState::Running { .. }));
    assert!(ev.iter().any(|e| matches!(e, StateEvent::TrackingResumed)));
}

#[test]
fn break_toggle_resumes_prev_task_not_paused() {
    let t = task("A");
    let s = TimerState::OnBreak {
        kind: BreakKind::Coffee,
        prev_task: Some(t.clone()),
        prev_accumulated: 30,
        break_started: std::time::Instant::now(),
    };
    let (s2, ev) = s.toggle_play_pause();
    // Must become Running, NOT Paused
    assert!(matches!(s2, TimerState::Running { .. }));
    assert!(ev.iter().any(|e| matches!(e, StateEvent::BreakEnded)));
    assert!(ev.iter().any(|e| matches!(e, StateEvent::TrackingResumed)));
}

#[test]
fn click_same_task_while_running_pauses_it() {
    let t = task("A");
    let s = TimerState::Running { task: t.clone(), started: std::time::Instant::now(), accumulated: 0 };
    let (s2, ev) = s.select_task(t.clone());
    assert!(matches!(s2, TimerState::Paused { .. }));
    assert!(ev.iter().any(|e| matches!(e, StateEvent::TrackingPaused)));
}

#[test]
fn click_different_task_while_running_switches() {
    let a = task("A");
    let b = task("B");
    let s = TimerState::Running { task: a.clone(), started: std::time::Instant::now(), accumulated: 0 };
    let (s2, ev) = s.select_task(b.clone());
    if let TimerState::Running { task, .. } = &s2 {
        assert_eq!(task.task_name, "B");
    } else { panic!("expected Running"); }
    assert!(ev.iter().any(|e| matches!(e, StateEvent::TaskStopped { .. })));
    assert!(ev.iter().any(|e| matches!(e, StateEvent::TaskStarted { .. })));
}

#[test]
fn click_prev_task_while_on_break_does_not_double_toggle() {
    let a = task("A");
    let s = TimerState::OnBreak {
        kind: BreakKind::Lunch,
        prev_task: Some(a.clone()),
        prev_accumulated: 100,
        break_started: std::time::Instant::now(),
    };
    // Click the same task that was running before the break
    let (s2, ev) = s.select_task(a.clone());
    // Should end up Running(A), NOT Paused
    assert!(matches!(s2, TimerState::Running { .. }));
    if let TimerState::Running { task, .. } = &s2 {
        assert_eq!(task.task_name, "A");
    }
    assert!(ev.iter().any(|e| matches!(e, StateEvent::BreakEnded)));
}

#[test]
fn click_new_task_while_on_break_ends_break_and_starts_new() {
    let a = task("A");
    let b = task("B");
    let s = TimerState::OnBreak {
        kind: BreakKind::Coffee,
        prev_task: Some(a.clone()),
        prev_accumulated: 60,
        break_started: std::time::Instant::now(),
    };
    let (s2, ev) = s.select_task(b.clone());
    assert!(matches!(s2, TimerState::Running { .. }));
    if let TimerState::Running { task, .. } = &s2 { assert_eq!(task.task_name, "B"); }
    assert!(ev.iter().any(|e| matches!(e, StateEvent::BreakEnded)));
    assert!(ev.iter().any(|e| matches!(e, StateEvent::TaskStarted { .. })));
}
