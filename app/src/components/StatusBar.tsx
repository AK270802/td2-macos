import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useSyncStatus } from "../hooks/useSyncStatus";
import { useToast } from "./Toast";

function clockTime(ts: number): string {
    const d = new Date(ts * 1000);
    let h = d.getHours();
    const ampm = h >= 12 ? "pm" : "am";
    h = h % 12 || 12;
    return `${String(h).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")} ${ampm}`;
}

interface Props {
    /** Local agentd IPC reachability — independent of internet/backend. */
    agentConnected: boolean;
}

export default function StatusBar({ agentConnected }: Props) {
    const status = useSyncStatus();
    const { toast } = useToast();
    const [, forceTick] = useState(0);
    const [syncing, setSyncing] = useState(false);

    // Re-render every second so the "next sync" countdown moves.
    useEffect(() => {
        const id = setInterval(() => forceTick(x => x + 1), 1000);
        return () => clearInterval(id);
    }, []);

    const syncNow = async () => {
        if (syncing) return;
        setSyncing(true);
        try {
            await invoke("send_ipc", { cmd: "sync_now" });
            toast("Synced", "Latest activity and tasks are up to date.", "emerald");
            // Tell Main.tsx's 30s task/task-time poll to refetch immediately
            // instead of waiting for its next tick.
            window.dispatchEvent(new CustomEvent("wp-sync-now"));
        } catch (e) {
            toast("Sync failed", String(e), "red");
        } finally {
            setSyncing(false);
        }
    };

    const nextIn = status.next_sync_ts
        ? Math.max(0, status.next_sync_ts - Math.floor(Date.now() / 1000))
        : null;
    const nextStr = nextIn != null ? `${Math.floor(nextIn / 60)}m ${String(nextIn % 60).padStart(2, "0")}s` : "—";

    // "cloud sync" reflects internet/backend reachability only — the agent
    // itself keeps capturing and writing locally regardless, so this must
    // never be worded in a way that implies tracking stopped when it hasn't.
    const cloudUp = status.connected;

    return (
        <div className="wp-mono" style={{
            height: "var(--status-bar-h)",
            background: "var(--bg-2)",
            borderTop: "1px solid var(--line)",
            display: "flex", alignItems: "center", justifyContent: "space-between",
            padding: "0 16px", fontSize: 11, flexShrink: 0,
            color: "var(--text-3)", letterSpacing: "0.04em",
        }}>
            <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
                <span style={{ display: "flex", alignItems: "center", gap: 7 }} title="Local agent process — tracking works even without internet">
                    <span style={{
                        width: 7, height: 7, borderRadius: "50%", flexShrink: 0,
                        background: agentConnected ? "var(--emerald)" : "var(--red)",
                    }} />
                    <span style={{ color: "var(--text-2)" }}>agent · {agentConnected ? "running" : "offline"}</span>
                </span>
                <span style={{ display: "flex", alignItems: "center", gap: 7 }} title="Internet/backend reachability — unrelated to local tracking">
                    <span style={{
                        width: 7, height: 7, borderRadius: "50%", flexShrink: 0,
                        background: cloudUp ? "var(--emerald)" : "var(--gold)",
                    }} />
                    <span style={{ color: "var(--text-2)" }}>cloud sync · {cloudUp ? "connected" : "no internet"}</span>
                </span>
                <span>last batch · {status.last_sync_ts ? clockTime(status.last_sync_ts) : "—"}</span>
                {cloudUp ? (
                    <span>next sync · {nextStr}</span>
                ) : (
                    <span style={{ color: "var(--gold)" }}>
                        {status.pending_events > 0 ? `${status.pending_events} events queued — tracking continues offline` : "tracking continues offline"}
                    </span>
                )}
                <button
                    onClick={syncNow}
                    disabled={syncing}
                    className="wp-mono"
                    style={{
                        background: "transparent", border: "1px solid var(--line-strong)",
                        borderRadius: 6, padding: "3px 9px", fontSize: 10.5,
                        color: syncing ? "var(--text-3)" : "var(--gold)",
                        letterSpacing: "0.04em", cursor: syncing ? "default" : "pointer",
                    }}>
                    {syncing ? "Syncing…" : "Sync now"}
                </button>
            </div>
            <span>v{status.agent_version || "2.0.0"} · SQLCipher OK</span>
        </div>
    );
}
