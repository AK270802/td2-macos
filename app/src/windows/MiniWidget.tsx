import { useTimerState } from "../hooks/useTimerState";

function formatShort(secs: number) {
  const h = Math.floor(secs / 3600);
  const m = Math.floor((secs % 3600) / 60);
  const s = secs % 60;
  return h > 0 ? `${h}:${String(m).padStart(2,"0")}` : `${m}:${String(s).padStart(2,"0")}`;
}

export default function MiniWidget({ layout = "horizontal" }: { layout?: "horizontal" | "vertical" }) {
  const { timer, togglePlayPause } = useTimerState();
  const isRunning = timer.state === "running";

  if (layout === "vertical") {
    return (
      <div style={{ width: 52, background: "var(--hero-bg)", borderRadius: 14,
        display: "flex", flexDirection: "column", alignItems: "center", padding: "10px 0",
        gap: 8, border: "1px solid rgba(212,162,76,0.3)" }}>
        {/* ECG glyph mark */}
        <svg width="32" height="18" viewBox="0 0 48 28" fill="none">
          <path d="M2 14 L10 14 L14 4 L18 24 L22 10 L26 20 L30 14 L46 14"
            stroke="#D4A24C" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"/>
        </svg>
        <div style={{ width: 36, height: 1, background: "rgba(255,255,255,0.08)" }} />
        <span style={{ color: "#fff", fontSize: 13, fontWeight: 700, letterSpacing: -0.5 }}>
          {formatShort(timer.elapsed_secs)}
        </span>
        <button onClick={togglePlayPause}
          style={{ width: 28, height: 28, borderRadius: "50%", border: "none",
            background: isRunning ? "var(--brass)" : "rgba(212,162,76,0.2)", cursor: "pointer",
            display: "flex", alignItems: "center", justifyContent: "center" }}>
          {isRunning
            ? <svg width="10" height="10" viewBox="0 0 24 24" fill="#fff"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>
            : <svg width="10" height="10" viewBox="0 0 24 24" fill="var(--brass)"><path d="M8 5v14l11-7z"/></svg>}
        </button>
      </div>
    );
  }

  // Horizontal layout (default) — 320×52
  return (
    <div data-tauri-drag-region
      style={{ width: 320, height: 52, background: "var(--hero-bg)", borderRadius: 12,
        display: "flex", alignItems: "center", padding: "0 12px", gap: 10,
        border: "1px solid rgba(212,162,76,0.25)", WebkitAppRegion: "drag" } as any}>
      {/* ECG mark */}
      <svg width="24" height="14" viewBox="0 0 48 28" fill="none" style={{ flexShrink: 0 }}>
        <path d="M2 14 L10 14 L14 4 L18 24 L22 10 L26 20 L30 14 L46 14"
          stroke="#D4A24C" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"/>
      </svg>

      {/* Task name — renders live from IPC */}
      <span style={{ flex: 1, color: "#fff", fontSize: 13, fontWeight: 600, minWidth: 0,
        whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
        {timer.task?.task_name ?? (timer.state === "on_break" ? "On break" : "Not tracking")}
      </span>

      {/* Elapsed */}
      <span style={{ color: "var(--brass)", fontSize: 15, fontWeight: 700,
        letterSpacing: -0.5, flexShrink: 0 }}>
        {formatShort(timer.elapsed_secs)}
      </span>

      {/* Play/Pause */}
      <button onClick={togglePlayPause}
        style={{ width: 28, height: 28, borderRadius: "50%", border: "none",
          background: isRunning ? "var(--brass)" : "transparent",
          cursor: "pointer", flexShrink: 0, WebkitAppRegion: "no-drag",
          display: "flex", alignItems: "center", justifyContent: "center" } as any}>
        {isRunning
          ? <svg width="10" height="10" viewBox="0 0 24 24" fill="#fff"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>
          : <svg width="10" height="10" viewBox="0 0 24 24" fill="var(--brass)"><path d="M8 5v14l11-7z"/></svg>}
      </button>
    </div>
  );
}
