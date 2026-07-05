import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";

const COUNTDOWN_SECS = 60;

export default function IdleWarningPage() {
  const [remaining, setRemaining] = useState(COUNTDOWN_SECS);

  useEffect(() => {
    const id = setInterval(() => {
      setRemaining(r => {
        if (r <= 1) {
          invoke("send_ipc", { cmd: "idle_auto_stop" }).catch(() => {});
          return 0;
        }
        return r - 1;
      });
    }, 1000);
    return () => clearInterval(id);
  }, []);

  const keepWorking = () => invoke("send_ipc", { cmd: "idle_keep_working" }).catch(() => {});
  const stopTracking = () => invoke("send_ipc", { cmd: "toggle_play_pause" }).catch(() => {});

  return (
    <div style={{ background: "var(--surface)", borderRadius: 16, padding: "28px 32px",
      display: "flex", flexDirection: "column", alignItems: "center", gap: 20 }}>
      <div style={{ width: 48, height: 48, borderRadius: "50%", background: "var(--amber-soft)",
        display: "flex", alignItems: "center", justifyContent: "center", fontSize: 22 }}>⚠</div>

      <div style={{ textAlign: "center" }}>
        <h2 style={{ margin: "0 0 8px", fontSize: 18, fontWeight: 700, color: "var(--ink)" }}>
          Are you still working?
        </h2>
        <p style={{ margin: 0, fontSize: 13, color: "var(--ink-soft)", lineHeight: 1.5 }}>
          No activity detected. Tracking will stop in{" "}
          <strong style={{ color: "var(--amber)" }}>{remaining} second{remaining !== 1 ? "s" : ""}</strong>{" "}
          unless you confirm.
        </p>
      </div>

      {/* Countdown ring */}
      <div style={{ position: "relative", width: 64, height: 64 }}>
        <svg width="64" height="64" viewBox="0 0 64 64">
          <circle cx="32" cy="32" r="28" fill="none" stroke="var(--line)" strokeWidth="4" />
          <circle cx="32" cy="32" r="28" fill="none" stroke="var(--amber)" strokeWidth="4"
            strokeDasharray={`${2 * Math.PI * 28}`}
            strokeDashoffset={`${2 * Math.PI * 28 * (1 - remaining / COUNTDOWN_SECS)}`}
            transform="rotate(-90 32 32)" strokeLinecap="round" />
        </svg>
        <span style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center",
          justifyContent: "center", fontSize: 18, fontWeight: 700, color: "var(--ink)" }}>
          {remaining}
        </span>
      </div>

      <div style={{ display: "flex", gap: 12, width: "100%" }}>
        <button onClick={stopTracking}
          style={{ flex: 1, padding: "10px", borderRadius: 8, border: "1px solid var(--line)",
            background: "transparent", color: "var(--ink-soft)", fontSize: 13, cursor: "pointer" }}>
          Stop tracking
        </button>
        <button onClick={keepWorking}
          style={{ flex: 2, padding: "10px", borderRadius: 8, border: "none",
            background: "var(--brass)", color: "#fff", fontSize: 13, fontWeight: 700, cursor: "pointer" }}>
          Keep working
        </button>
      </div>
    </div>
  );
}
