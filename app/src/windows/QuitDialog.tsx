import { invoke } from "@tauri-apps/api/core";
import { exit } from "@tauri-apps/plugin-shell";

interface Props { isTracking: boolean; taskName?: string; }

export default function QuitDialog({ isTracking, taskName }: Props) {
  const confirmQuit = async () => {
    if (isTracking) {
      await invoke("send_ipc", { cmd: "toggle_play_pause" }).catch(() => {});
    }
    await exit(0);
  };

  return (
    <div style={{ background: "var(--surface)", borderRadius: 14, padding: "28px 32px", width: 380 }}>
      <h2 style={{ margin: "0 0 12px", fontSize: 17, fontWeight: 700, color: "var(--ink)" }}>
        Quit WorkPulse?
      </h2>
      {isTracking && (
        <div style={{ background: "var(--amber-soft)", borderRadius: 8, padding: "10px 14px",
          fontSize: 13, color: "#92400e", marginBottom: 16 }}>
          You are currently tracking <strong>{taskName}</strong>. Quitting will stop the timer.
        </div>
      )}
      <p style={{ fontSize: 13, color: "var(--ink-soft)", margin: "0 0 24px", lineHeight: 1.5 }}>
        The WorkPulse background service will continue running. You can reopen WorkPulse from the system tray at any time.
      </p>
      <div style={{ display: "flex", gap: 12 }}>
        <button onClick={() => window.history.back()}
          style={{ flex: 1, padding: "10px", borderRadius: 8, border: "1px solid var(--line)",
            background: "transparent", color: "var(--ink-soft)", fontSize: 14, cursor: "pointer" }}>
          Cancel
        </button>
        <button onClick={confirmQuit}
          style={{ flex: 1, padding: "10px", borderRadius: 8, border: "none",
            background: "var(--alert)", color: "#fff", fontSize: 14, fontWeight: 700, cursor: "pointer" }}>
          Quit
        </button>
      </div>
    </div>
  );
}
