//! Sync queue backoff + retry-queue semantics.

use common::db::{queries, schema, sync_queue};
use common::models::ActivityEvent;
use rusqlite::Connection;
use uuid::Uuid;

fn test_db() -> Connection {
    let conn = Connection::open_in_memory().unwrap();
    schema::ensure_schema(&conn).unwrap();
    conn
}

#[test]
fn backoff_matches_locked_spec() {
    // 1 → 2 → 4 → 8 → 16 → capped at 30 minutes.
    assert_eq!(sync_queue::backoff_secs(0), 60);
    assert_eq!(sync_queue::backoff_secs(1), 120);
    assert_eq!(sync_queue::backoff_secs(2), 240);
    assert_eq!(sync_queue::backoff_secs(3), 480);
    assert_eq!(sync_queue::backoff_secs(4), 960);
    assert_eq!(sync_queue::backoff_secs(5), 1800);
    assert_eq!(sync_queue::backoff_secs(20), 1800);
}

#[test]
fn retry_batch_resends_only_its_own_unsynced_events() {
    let conn = test_db();
    let user = Uuid::new_v4();
    let tenant = Uuid::new_v4();

    let mk = |i: i64| ActivityEvent {
        event_uuid: Uuid::new_v4(),
        user_id: user, tenant_id: tenant,
        event_type: "app".into(), ts: 1000 + i, duration_sec: 30,
        payload: serde_json::json!({"app_name": "code.exe"}),
    };
    let batch_events: Vec<_> = (0..3).map(mk).collect();
    let later_event = mk(99);
    for ev in batch_events.iter().chain([&later_event]) {
        queries::insert_event(&conn, ev).unwrap();
    }

    let batch_uuids: Vec<_> = batch_events.iter().map(|e| e.event_uuid).collect();
    sync_queue::enqueue(&conn, "batch-1", &batch_uuids).unwrap();

    // One of the batch's events was synced by another path meanwhile.
    queries::mark_events_synced(&conn, &[batch_uuids[0]]).unwrap();

    let due = sync_queue::get_due_batches(&conn).unwrap();
    assert_eq!(due.len(), 1);
    let resend = queries::get_unsynced_events_by_uuids(&conn, &due[0].event_uuids).unwrap();

    // Exactly the two still-unsynced batch members — never the later event.
    assert_eq!(resend.len(), 2);
    assert!(resend.iter().all(|e| batch_uuids.contains(&e.event_uuid)));
    assert!(resend.iter().all(|e| e.event_uuid != later_event.event_uuid));
}

#[test]
fn failed_after_max_retries() {
    let conn = test_db();
    sync_queue::enqueue(&conn, "b", &[Uuid::new_v4()]).unwrap();
    sync_queue::schedule_retry(&conn, "b", 10).unwrap(); // >= MAX_RETRIES
    let status: String = conn.query_row(
        "SELECT status FROM sync_queue WHERE batch_id='b'", [], |r| r.get(0)).unwrap();
    assert_eq!(status, "failed");
    assert!(sync_queue::get_due_batches(&conn).unwrap().is_empty());
}

#[test]
fn events_are_ordered_and_capped() {
    let conn = test_db();
    let user = Uuid::new_v4();
    let tenant = Uuid::new_v4();
    for i in 0..600 {
        let ev = ActivityEvent {
            event_uuid: Uuid::new_v4(), user_id: user, tenant_id: tenant,
            event_type: "input".into(), ts: i, duration_sec: 30,
            payload: serde_json::json!({"keystroke_count": 1}),
        };
        queries::insert_event(&conn, &ev).unwrap();
    }
    let got = queries::get_unsynced_events(&conn, 500).unwrap();
    assert_eq!(got.len(), 500, "batch size must cap at 500 (server max_length)");
    assert!(got.windows(2).all(|w| w[0].ts <= w[1].ts), "oldest-first ordering");
}
