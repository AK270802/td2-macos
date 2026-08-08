import type { TimerState } from "../hooks/useTimerState";
import { formatHMS, taskCode } from "../lib/format";

interface Props { timer: TimerState; onToggle: () => void; }

export default function HeroCard({ timer, onToggle }: Props) {
    const onBreak = timer.state === "on_break";
    const isRunning = timer.state === "running";
    const isPaused = timer.state === "paused";

    if (onBreak) {
        return (
            <div style={{
                background: "var(--coral)",
                borderRadius: "var(--radius-lg)",
                padding: "26px 30px",
                display: "flex", alignItems: "center", gap: 22,
                marginBottom: 14,
                transition: "background .3s ease",
            }}>
                <CircleButton onClick={onToggle} dark>
                    <PauseIcon />
                </CircleButton>
                <div style={{ flex: 1, minWidth: 0 }}>
                    <span className="wp-overline" style={{ color: "rgba(35,20,15,0.75)", borderTopColor: "rgba(35,20,15,0.4)", marginBottom: 8, display: "inline-block" }}>
                        On break
                    </span>
                    <div className="wp-display" style={{ fontSize: 25, fontWeight: 500, color: "var(--coral-ink)", fontStyle: "italic" }}>
                        Timer is paused for your break.
                    </div>
                </div>
                <div className="wp-mono" style={{ fontSize: 54, fontWeight: 700, color: "var(--coral-ink)", letterSpacing: "0.02em", flexShrink: 0 }}>
                    {formatHMS((timer.break_remaining_secs != null && timer.break_remaining_secs > 0)
                        ? timer.break_remaining_secs : 0)}
                </div>
            </div>
        );
    }

    const overline = isRunning && timer.task
        ? `Currently tracking · ${timer.task.project_name}`
        : isPaused && timer.task
        ? `Paused · ${timer.task.project_name}`
        : "Not tracking";

    return (
        <div style={{
            background: "linear-gradient(135deg, var(--panel-2) 0%, var(--panel) 100%)",
            border: "1px solid var(--line)",
            borderRadius: "var(--radius-lg)",
            padding: "26px 30px",
            display: "flex", alignItems: "center", gap: 22,
            marginBottom: 14,
            transition: "background .3s ease",
        }}>
            <CircleButton onClick={onToggle}>
                {isRunning ? <PauseIcon /> : <PlayIcon />}
            </CircleButton>

            <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 8 }}>
                    {isRunning && (
                        <span style={{ position: "relative", width: 7, height: 7, flexShrink: 0 }}>
                            <span style={{ position: "absolute", inset: 0, borderRadius: "50%", background: "var(--emerald)", animation: "wp-pulse 1.6s ease-out infinite" }} />
                            <span style={{ position: "absolute", inset: 0, borderRadius: "50%", background: "var(--emerald)" }} />
                        </span>
                    )}
                    <span className={`wp-overline ${isRunning ? "wp-overline--gold" : ""}`}>{overline}</span>
                </div>
                <div className="wp-display" style={{
                    fontSize: 26, fontWeight: 500, color: "var(--text-1)",
                    whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis",
                    letterSpacing: "-0.01em", marginBottom: 4,
                }}>
                    {timer.task?.task_name ?? "Choose a task to start"}
                </div>
                {timer.task && (
                    <div className="wp-mono" style={{ fontSize: 12, color: "var(--text-3)", letterSpacing: "0.08em" }}>
                        {taskCode(timer.task.project_name, timer.task.task_id)}
                    </div>
                )}
            </div>

            <div className="wp-mono" style={{
                fontSize: 58, fontWeight: 700,
                color: isRunning ? "var(--text-1)" : "var(--text-3)",
                letterSpacing: "0.02em", flexShrink: 0, lineHeight: 1,
            }}>
                {formatHMS(timer.elapsed_secs)}
            </div>
        </div>
    );
}

function CircleButton({ children, onClick, dark }: { children: React.ReactNode; onClick: () => void; dark?: boolean }) {
    return (
        <button
            onClick={onClick}
            style={{
                width: 58, height: 58, borderRadius: "50%", border: "none",
                background: dark ? "#1a2440" : "var(--gold)",
                color: dark ? "var(--coral-2)" : "#16110a",
                display: "flex", alignItems: "center", justifyContent: "center",
                flexShrink: 0, transition: "transform .12s ease, background .15s ease",
            }}
            onMouseDown={e => (e.currentTarget.style.transform = "scale(0.94)")}
            onMouseUp={e => (e.currentTarget.style.transform = "scale(1)")}
            onMouseLeave={e => (e.currentTarget.style.transform = "scale(1)")}>
            {children}
        </button>
    );
}

function PlayIcon() {
    return <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z" /></svg>;
}
function PauseIcon() {
    return <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M7 5h3.4v14H7zM13.6 5H17v14h-3.4z" /></svg>;
}
