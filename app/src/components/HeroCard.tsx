import type { TimerState } from "../hooks/useTimerState";

function formatTime(secs: number): string {
    const h = Math.floor(secs / 3600);
    const m = Math.floor((secs % 3600) / 60);
    const s = secs % 60;
    if (h > 0) return `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
    return `${m}:${String(s).padStart(2, "0")}`;
}

function formatBreak(secs: number): string {
    const m = Math.floor(secs / 60);
    const s = secs % 60;
    return `${m}:${String(s).padStart(2, "0")}`;
}

interface Props { timer: TimerState; onToggle: () => void; }

export default function HeroCard({ timer, onToggle }: Props) {
    const onBreak = timer.state === "on_break";
    const isRunning = timer.state === "running";

    const bgStyle = onBreak
        ? { background: "var(--clay)" }
        : { background: "linear-gradient(135deg, var(--navy) 0%, var(--navy-2) 100%)" };

    const statusText = isRunning && timer.task
        ? `Currently tracking · ${timer.task.project_name}`
        : onBreak
        ? `On ${timer.break_type === "coffee" ? "coffee break" : timer.break_type === "lunch" ? "lunch break" : "break"}`
        : "Not tracking";

    const taskName = timer.task?.task_name ?? (onBreak ? "On a break" : "Choose a task to start");
    const breakRemaining = onBreak && timer.break_remaining_secs != null ? timer.break_remaining_secs : null;

    return (
        <div style={{
            ...bgStyle,
            borderRadius: "var(--radius-lg)",
            padding: "22px 24px",
            display: "flex",
            alignItems: "center",
            gap: 20,
            minHeight: 110,
            marginBottom: 12,
            position: "relative",
            overflow: "hidden",
            boxShadow: "0 18px 40px -16px rgba(28,35,54,.5)",
            transition: "background 0.3s",
        }}>
            {/* Background concentric circles */}
            <svg style={{ position: "absolute", right: -40, top: -60, opacity: 0.07, pointerEvents: "none" }}
                width="280" height="280" viewBox="0 0 280 280" fill="none">
                <circle cx="140" cy="140" r="130" stroke="white" strokeWidth="1" />
                <circle cx="140" cy="140" r="100" stroke="white" strokeWidth="1" />
                <circle cx="140" cy="140" r="70" stroke="white" strokeWidth="1" />
                <circle cx="140" cy="140" r="40" stroke="white" strokeWidth="1" />
            </svg>

            {/* Play/Pause button */}
            <button
                onClick={onToggle}
                style={{
                    width: 52,
                    height: 52,
                    borderRadius: "50%",
                    border: "none",
                    background: onBreak ? "rgba(255,255,255,0.25)" : "var(--brass)",
                    color: onBreak ? "var(--clay)" : "var(--navy)",
                    cursor: "pointer",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    flexShrink: 0,
                    transition: "all 0.15s",
                    position: "relative",
                    zIndex: 1,
                }}>
                {isRunning ? <PauseIcon /> : <PlayIcon />}
            </button>

            {/* Status + task meta */}
            <div style={{ flex: 1, minWidth: 0, position: "relative", zIndex: 1 }}>
                <div style={{ display: "flex", alignItems: "center", gap: 7, marginBottom: 5 }}>
                    {isRunning && (
                        <span style={{ position: "relative", width: 8, height: 8, flexShrink: 0 }}>
                            <span style={{
                                position: "absolute",
                                inset: 0,
                                borderRadius: "50%",
                                background: "var(--mint)",
                                animation: "hpulse 1.4s ease-out infinite",
                            }} />
                            <span style={{
                                position: "absolute",
                                inset: 0,
                                borderRadius: "50%",
                                background: "var(--mint)",
                            }} />
                        </span>
                    )}
                    <span style={{ fontSize: 11, fontWeight: 700, color: "rgba(255,255,255,0.6)", letterSpacing: 0.6, textTransform: "uppercase" }}>
                        {statusText}
                    </span>
                </div>
                <div style={{
                    fontSize: 19,
                    fontWeight: 700,
                    color: "#fff",
                    whiteSpace: "nowrap",
                    overflow: "hidden",
                    textOverflow: "ellipsis",
                    fontFamily: "'Space Grotesk', 'Segoe UI', system-ui, sans-serif",
                }}>
                    {taskName}
                </div>
            </div>

            {/* Clock — elapsed when running, break countdown when on break */}
            <div style={{ flexShrink: 0, position: "relative", zIndex: 1, textAlign: "right" }}>
                <div style={{
                    fontFamily: "'Space Grotesk', 'Segoe UI Mono', monospace",
                    fontSize: 44, fontWeight: 700, color: "#fff",
                    letterSpacing: -2, lineHeight: 1,
                }}>
                    {onBreak && breakRemaining != null
                        ? formatBreak(breakRemaining)
                        : formatTime(timer.elapsed_secs)}
                </div>
                {onBreak && breakRemaining != null && (
                    <div style={{ fontSize: 10, color: "rgba(255,255,255,0.5)", marginTop: 4, letterSpacing: 0.4 }}>
                        remaining
                    </div>
                )}
            </div>
        </div>
    );
}

function PlayIcon() {
    return (
        <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor">
            <path d="M8 5v14l11-7z" />
        </svg>
    );
}

function PauseIcon() {
    return (
        <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor">
            <path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" />
        </svg>
    );
}