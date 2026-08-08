import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { formatClock, formatCompact } from "../lib/format";

interface FeedEvent {
    event_uuid: string;
    event_type: string;
    ts: number;
    duration_sec: number;
    payload: Record<string, any>;
}

function describe(ev: FeedEvent): string | null {
    switch (ev.event_type) {
        case "app": {
            const app = ev.payload?.process_name || ev.payload?.app_name;
            if (!app) return null;
            return `Foreground · ${app}${ev.duration_sec > 0 ? ` · ${formatCompact(ev.duration_sec)}` : ""}`;
        }
        case "browser":
            return ev.payload?.domain ? `Browser · ${ev.payload.domain}` : null;
        case "input":
            return `Input activity · ${ev.payload?.keystroke_count ?? 0} keys · ${ev.payload?.mouse_click_count ?? 0} clicks`;
        case "idle":
            return `Idle ${formatCompact(ev.duration_sec)} detected`;
        case "tracking_pause":
            return "Tracking paused";
        case "tracking_resume":
            return "Tracking resumed";
        default:
            return null;
    }
}

export default function RecentFeed() {
    const [events, setEvents] = useState<FeedEvent[]>([]);

    useEffect(() => {
        const load = () => {
            invoke<FeedEvent[]>("send_ipc", { cmd: "get_recent_events", payload: { limit: 14 } })
                .then(r => { if (Array.isArray(r)) setEvents(r); })
                .catch(() => {});
        };
        load();
        const id = setInterval(load, 15_000);
        return () => clearInterval(id);
    }, []);

    const rows = events
        .map(ev => ({ ev, text: describe(ev) }))
        .filter(r => r.text)
        .slice(0, 8)
        .reverse();

    return (
        <div className="wp-card" style={{ marginBottom: 16, padding: "16px 20px 14px" }}>
            <span className="wp-overline" style={{ marginBottom: 12, display: "inline-block" }}>Recent</span>
            {rows.length === 0 ? (
                <div style={{ padding: "6px 0 10px", color: "var(--text-3)", fontSize: 12.5 }}>
                    Activity appears here once tracking starts.
                </div>
            ) : (
                rows.map(({ ev, text }) => (
                    <div key={ev.event_uuid} style={{ display: "flex", gap: 20, padding: "5px 0", alignItems: "baseline" }}>
                        <span className="wp-mono" style={{ fontSize: 11.5, color: "var(--text-3)", flexShrink: 0 }}>
                            {formatClock(ev.ts)}
                        </span>
                        <span className="wp-mono" style={{ fontSize: 12, color: "var(--text-2)" }}>{text}</span>
                    </div>
                ))
            )}
        </div>
    );
}
