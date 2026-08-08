import { useState, useEffect, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
import { formatCompact } from "../lib/format";
import { useTimerState } from "../hooks/useTimerState";

const COUNTDOWN_SECS = 60;

/**
 * Idle-warning window. 60s countdown ring; expiry auto-selects "on break"
 * (session stops back-dated to idle start — matching the disclosure).
 */
export default function IdleWarning() {
    const { timer } = useTimerState();
    const [remaining, setRemaining] = useState(COUNTDOWN_SECS);
    const acted = useRef(false);

    const respond = async (cmd: "idle_keep_working" | "idle_auto_stop") => {
        if (acted.current) return;
        acted.current = true;
        await invoke("send_ipc", { cmd }).catch(() => {});
        invoke("close_idle_warning").catch(() => {});
    };

    useEffect(() => {
        const id = setInterval(() => {
            setRemaining(r => {
                if (r <= 1) {
                    clearInterval(id);
                    respond("idle_auto_stop");
                    return 0;
                }
                return r - 1;
            });
        }, 1000);
        return () => clearInterval(id);
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    const idleFor = timer.idle_warning?.idle_secs ?? 0;
    const pct = remaining / COUNTDOWN_SECS;

    return (
        <div style={{
            height: "100vh", background: "var(--bg)", userSelect: "none",
            border: "1px solid var(--gold-line)", borderRadius: 14,
            display: "flex", flexDirection: "column", alignItems: "center",
            padding: "22px 26px 20px", boxSizing: "border-box",
        }} data-tauri-drag-region>
            <span className="wp-overline wp-overline--gold" style={{ marginBottom: 14 }}>Inactivity detected</span>

            {/* Countdown ring */}
            <div style={{ position: "relative", width: 74, height: 74, marginBottom: 12 }}>
                <svg width="74" height="74" viewBox="0 0 74 74" style={{ transform: "rotate(-90deg)" }}>
                    <circle cx="37" cy="37" r="32" fill="none" stroke="var(--line)" strokeWidth="4" />
                    <circle
                        cx="37" cy="37" r="32" fill="none"
                        stroke={remaining <= 10 ? "var(--red)" : "var(--gold)"}
                        strokeWidth="4" strokeLinecap="round"
                        strokeDasharray={`${Math.PI * 64}`}
                        strokeDashoffset={`${Math.PI * 64 * (1 - pct)}`}
                        style={{ transition: "stroke-dashoffset 1s linear, stroke .3s" }}
                    />
                </svg>
                <span className="wp-mono" style={{
                    position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center",
                    fontSize: 21, fontWeight: 700, color: remaining <= 10 ? "var(--red)" : "var(--text-1)",
                }}>
                    {remaining}
                </span>
            </div>

            <div className="wp-display" style={{ fontSize: 18, fontWeight: 500, marginBottom: 5 }}>
                Are you still working?
            </div>
            <div style={{ fontSize: 12.5, color: "var(--text-2)", marginBottom: 18, textAlign: "center", fontWeight: 300 }}>
                No input for {formatCompact(idleFor)}. Unanswered, this session pauses
                and the idle time is excluded.
            </div>

            <div style={{ display: "flex", gap: 10, width: "100%" }}>
                <button className="wp-btn-ghost" onClick={() => respond("idle_auto_stop")}
                    style={{ flex: 1, padding: "11px 0" }}>
                    I'm on a break
                </button>
                <button className="wp-btn-gold" onClick={() => respond("idle_keep_working")}
                    style={{ flex: 1, padding: "11px 0" }}>
                    Still working
                </button>
            </div>
        </div>
    );
}
