import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { formatHM, formatCompact } from "../lib/format";

interface Stats {
    worked_today_sec: number;
    worked_week_sec: number;
    worked_month_sec: number;
    sessions_today: number;
    meeting_today_sec: number;
}

interface Props {
    /** True while the meeting detector currently judges the user to be on a call. */
    inMeeting: boolean;
}

export default function StatRow({ inMeeting }: Props) {
    const [stats, setStats] = useState<Stats>({ worked_today_sec: 0, worked_week_sec: 0, worked_month_sec: 0, sessions_today: 0, meeting_today_sec: 0 });

    useEffect(() => {
        const load = () => {
            invoke<Stats>("send_ipc", { cmd: "get_time_stats" })
                .then(r => { if (r) setStats(r as Stats); })
                .catch(() => {});
        };
        load();
        const id = setInterval(load, 30_000);
        return () => clearInterval(id);
    }, []);

    const avg = stats.sessions_today > 0
        ? formatCompact(Math.floor(stats.worked_today_sec / stats.sessions_today))
        : "—";

    return (
        <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 12, marginBottom: 14 }}>
            <StatCard label="Worked today" value={formatHM(stats.worked_today_sec)} sub="synced with core-services" />
            <StatCard label="This week" value={formatHM(stats.worked_week_sec)} sub={`${formatHM(stats.worked_month_sec)} this month`} />
            <StatCard label="Sessions today" value={String(stats.sessions_today)} sub={stats.sessions_today > 0 ? `Avg ${avg} each` : "no sessions yet"} />
            <StatCard
                label="Meeting time"
                value={formatHM(stats.meeting_today_sec)}
                sub={inMeeting ? "In a meeting now" : "No meeting detected"}
                dotColor={inMeeting ? "var(--emerald)" : "var(--red)"}
            />
        </div>
    );
}

function StatCard({ label, value, sub, dotColor }: { label: string; value: string; sub: string; dotColor?: string }) {
    return (
        <div className="wp-card" style={{ padding: "16px 20px 14px", borderRadius: 14 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 6, marginBottom: 12 }}>
                {dotColor && (
                    <span style={{ width: 7, height: 7, borderRadius: "50%", background: dotColor, flexShrink: 0 }} />
                )}
                <span className="wp-overline" style={{ display: "inline-block" }}>{label}</span>
            </div>
            <div className="wp-mono" style={{ fontSize: 27, fontWeight: 700, color: "var(--text-1)", marginBottom: 6, letterSpacing: "0.01em" }}>
                {value}
            </div>
            <div style={{ fontSize: 11.5, color: "var(--text-3)", fontWeight: 300 }}>{sub}</div>
        </div>
    );
}
