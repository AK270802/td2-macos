//! TimerService persistence-glue tests: the production wrapper around the
//! TimerState machine, exercised against an in-memory SQLite database.

use common::db::{queries, schema};
use common::models::Task;
use common::timer_service::TimerService;
use common::timer_state::BreakKind;
use rusqlite::Connection;
use uuid::Uuid;

fn test_db() -> Connection {
    let conn = Connection::open_in_memory().unwrap();
    schema::ensure_schema(&conn).unwrap();
    queries::set_config(&conn, "user_id", &Uuid::new_v4().to_string()).unwrap();
    queries::set_config(&conn, "tenant_id", &Uuid::new_v4().to_string()).unwrap();
    conn
}

fn task(name: &str) -> Task {
    Task {
        task_id: Uuid::new_v4(),
        project_id: Uuid::new_v4(),
        task_name: name.into(),
        project_name: "Apex".into(),
    }
}

fn log_count(conn: &Connection) -> i64 {
    conn.query_row("SELECT COUNT(*) FROM task_time_logs", [], |r| r.get(0)).unwrap()
}

#[test]
fn select_task_starts_running_and_checkpoints() {
    let conn = test_db();
    let mut svc = TimerService::new();
    let t = task("SQLCipher schema port");
    svc.select_task(&conn, t.clone());

    assert!(svc.is_running());
    assert_eq!(svc.state().active_task().unwrap().task_id, t.task_id);

    // Active session checkpoint written for crash recovery.
    let saved = queries::get_active_session(&conn).expect("checkpoint expected");
    assert_eq!(saved.task.task_id, t.task_id);

    // Last-task config persisted for resume.
    assert_eq!(queries::get_config(&conn, "last_task_id").unwrap(), t.task_id.to_string());
}

#[test]
fn stop_after_work_writes_time_log() {
    let conn = test_db();
    let mut svc = TimerService::new();
    svc.select_task(&conn, task("Rewrite capture loop"));
    std::thread::sleep(std::time::Duration::from_millis(1200));
    svc.stop(&conn);

    assert_eq!(log_count(&conn), 1);
    let (duration, idle): (i64, i64) = conn.query_row(
        "SELECT duration_sec, idle_sec FROM task_time_logs", [], |r| Ok((r.get(0)?, r.get(1)?))).unwrap();
    assert!(duration >= 1, "expected >=1s of work, got {duration}");
    assert_eq!(idle, 0);

    // Checkpoint cleared after clean stop.
    assert!(queries::get_active_session(&conn).is_none());
}

#[test]
fn instant_stop_writes_no_noop_log() {
    let conn = test_db();
    let mut svc = TimerService::new();
    svc.select_task(&conn, task("Zero duration"));
    svc.stop(&conn);
    assert_eq!(log_count(&conn), 0, "zero-duration segments must be dropped");
}

#[test]
fn switch_task_logs_previous_session() {
    let conn = test_db();
    let mut svc = TimerService::new();
    svc.select_task(&conn, task("First"));
    std::thread::sleep(std::time::Duration::from_millis(1100));
    svc.select_task(&conn, task("Second"));

    assert_eq!(log_count(&conn), 1);
    let name: String = conn.query_row("SELECT task_name FROM task_time_logs", [], |r| r.get(0)).unwrap();
    assert_eq!(name, "First");
    assert!(svc.is_running());
    assert_eq!(svc.state().active_task().unwrap().task_name, "Second");
}

#[test]
fn idle_keep_working_reports_idle_within_duration() {
    let conn = test_db();
    let mut svc = TimerService::new();
    svc.select_task(&conn, task("Idle attribution"));
    std::thread::sleep(std::time::Duration::from_millis(3100));

    // Last 2s were idle (back-dated); user says "still working".
    let idle_start = chrono::Utc::now().timestamp() - 2;
    svc.on_idle_threshold(idle_start);
    assert!(svc.idle_warning().is_some());
    svc.idle_keep_working(&conn);
    assert!(svc.idle_warning().is_none());

    svc.stop(&conn);
    let (duration, idle): (i64, i64) = conn.query_row(
        "SELECT duration_sec, idle_sec FROM task_time_logs", [], |r| Ok((r.get(0)?, r.get(1)?))).unwrap();
    // Backend contract: duration INCLUDES idle (active = duration − idle).
    assert!(duration >= 3, "duration must include the idle span, got {duration}");
    assert!(idle >= 2, "idle span should be attributed, got {idle}");
    assert!(idle <= duration, "idle must never exceed duration ({idle} > {duration})");
}

#[test]
fn idle_is_capped_to_tracked_duration() {
    let conn = test_db();
    let mut svc = TimerService::new();
    svc.select_task(&conn, task("Idle cap"));
    std::thread::sleep(std::time::Duration::from_millis(1100));

    // Idle start predates the session — must not produce idle > duration
    // (that is what made the portal show negative active time).
    svc.on_idle_threshold(chrono::Utc::now().timestamp() - 30);
    svc.idle_keep_working(&conn);
    svc.stop(&conn);
    let (duration, idle): (i64, i64) = conn.query_row(
        "SELECT duration_sec, idle_sec FROM task_time_logs", [], |r| Ok((r.get(0)?, r.get(1)?))).unwrap();
    assert!(idle <= duration, "idle must be capped ({idle} > {duration})");
}

#[test]
fn idle_auto_stop_backdates_session_end() {
    let conn = test_db();
    let mut svc = TimerService::new();
    svc.select_task(&conn, task("Backdated stop"));
    // 3s session where the last 2s were idle: 1s of real work survives,
    // the session end is back-dated to when the idle began.
    std::thread::sleep(std::time::Duration::from_millis(3100));

    let idle_start = chrono::Utc::now().timestamp() - 2;
    svc.on_idle_threshold(idle_start);
    svc.idle_auto_stop(&conn);

    assert!(matches!(svc.state(), common::timer_state::TimerState::Idle));
    let (ended_at, duration): (i64, i64) = conn.query_row(
        "SELECT ended_at, duration_sec FROM task_time_logs", [], |r| Ok((r.get(0)?, r.get(1)?))).unwrap();
    assert_eq!(ended_at, idle_start, "session end must be back-dated to idle start");
    assert!(duration >= 1, "pre-idle work must survive, got {duration}");
    assert!(duration <= 2, "idle span must be excluded, got {duration}");
}

#[test]
fn break_time_is_attributed_to_break_sec() {
    let conn = test_db();
    let mut svc = TimerService::new();
    svc.select_task(&conn, task("Break accounting"));
    std::thread::sleep(std::time::Duration::from_millis(1100));

    svc.start_break(&conn, BreakKind::Coffee);
    assert_eq!(svc.state().state_name(), "on_break");
    std::thread::sleep(std::time::Duration::from_millis(1100));

    svc.toggle_play_pause(&conn); // end break → resume task
    assert!(svc.is_running());
    svc.stop(&conn);

    let break_sec: i64 = conn.query_row("SELECT break_sec FROM task_time_logs", [], |r| r.get(0)).unwrap();
    assert!(break_sec >= 1, "break span should be recorded, got {break_sec}");
}

#[test]
fn crash_recovery_writes_interrupted_log() {
    let conn = test_db();
    let t = task("Crashed session");
    // Simulate a checkpoint left behind by a crash 90 seconds into a session.
    queries::save_active_session(&conn, Some(&t), 90).unwrap();

    TimerService::recover_crashed_session(&conn);

    assert_eq!(log_count(&conn), 1);
    let duration: i64 = conn.query_row("SELECT duration_sec FROM task_time_logs", [], |r| r.get(0)).unwrap();
    assert_eq!(duration, 90);
    // Checkpoint consumed — a second recovery is a no-op.
    TimerService::recover_crashed_session(&conn);
    assert_eq!(log_count(&conn), 1);
}

#[test]
fn resume_last_task_from_idle() {
    let conn = test_db();
    let mut svc = TimerService::new();
    let t = task("Resumable");
    svc.select_task(&conn, t.clone());
    std::thread::sleep(std::time::Duration::from_millis(1100));
    svc.stop(&conn);

    let mut svc2 = TimerService::new();
    svc2.resume_last_task(&conn);
    assert!(svc2.is_running());
    assert_eq!(svc2.state().active_task().unwrap().task_id, t.task_id);
}
