import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";

interface Stats { worked_today_sec: number; worked_week_sec: number; sessions_today: number; }

function fmt(secs: number) {
    const h = Math.floor(secs / 3600);
    const m = Math.floor((secs % 3600) / 60);
    return `${h}h ${m}m`;
}

export default function StatRow() {
    const [stats, setStats] = useState<Stats>({ worked_today_sec: 0, worked_week_sec: 0, sessions_today: 0 });

    useEffect(() => {
        const load = () => {
            invoke<Stats>("send_ipc", { cmd: "get_time_stats" })
                .then(r => { if (r) setStats(r as any); })
                .catch(() => {});
        };
        load();
        const id = setInterval(load, 60_000);
        return () => clearInterval(id);
    }, []);

    return (
        <div style={{ display: "grid", gridTemplateColumns: "repeat(3, 1fr)", gap: 10, marginBottom: 14 }}>
            <StatCard label="Worked today" value={fmt(stats.worked_today_sec)} />
            <StatCard label="This week" value={fmt(stats.worked_week_sec)} />
            <StatCard label="Sessions" value={String(stats.sessions_today)} />
        </div>
    );
}

function StatCard({ label, value }: { label: string; value: string }) {
    return (
        <div style={{
            background: "var(--surface)",
            border: "1px solid var(--line)",
            borderRadius: 11,
            padding: "10px 14px",
            boxShadow: "var(--shadow-sm)",
        }}>
            <div style={{ fontSize: 10.5, fontWeight: 700, color: "var(--ink-faint)", letterSpacing: 0.5, marginBottom: 5, textTransform: "uppercase" }}>
                {label}
            </div>
            <div style={{
                fontSize: 15,
                fontWeight: 700,
                color: "var(--ink)",
                fontFamily: "'Space Grotesk', 'Segoe UI', system-ui, sans-serif",
            }}>
                {value}
            </div>
        </div>
    );
}