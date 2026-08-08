import { invoke } from "@tauri-apps/api/core";
import { useTimerState } from "../hooks/useTimerState";
import { useEdgeSnap } from "../hooks/useEdgeSnap";
import { formatHMS, taskCode } from "../lib/format";

/**
 * Always-on-top widget: a sleek horizontal pill by default; drag it to a
 * screen edge and it docks flush as a slim vertical bar (TimeDoctor2-style
 * edge snapping) — drag it back out to return to the pill.
 */
export default function MiniWidget() {
    const { timer, togglePlayPause } = useTimerState();
    const snapSide = useEdgeSnap();
    const isRunning = timer.state === "running";
    const onBreak = timer.state === "on_break";
    const inMeeting = isRunning && timer.in_meeting;
    const accent = onBreak ? "rgba(224,107,77,0.55)" : inMeeting ? "var(--sky)" : isRunning ? "var(--gold-line)" : "var(--line-strong)";
    const dotColor = inMeeting ? "var(--sky)" : isRunning ? "var(--emerald)" : onBreak ? "var(--coral)" : "var(--text-3)";
    const label = timer.task
        ? (onBreak ? "On break" : inMeeting ? "In meeting" : timer.task.task_name)
        : (timer.agent_connected ? "No task" : "Offline");
    const clock = formatHMS(onBreak && timer.break_remaining_secs != null ? timer.break_remaining_secs : timer.elapsed_secs);

    const restoreMain = async () => {
        await invoke("show_main_window").catch(() => {});
        await invoke("hide_mini_widget").catch(() => {});
    };

    const playPauseBtn = (
        <button
            onClick={togglePlayPause}
            style={{
                width: 32, height: 32, borderRadius: "50%", border: "none", flexShrink: 0,
                background: onBreak ? "var(--coral)" : "var(--gold)",
                color: onBreak ? "var(--coral-ink)" : "#16110a",
                display: "flex", alignItems: "center", justifyContent: "center",
            }}>
            {isRunning || onBreak
                ? <svg width="11" height="11" viewBox="0 0 24 24" fill="currentColor"><path d="M7 5h3.4v14H7zM13.6 5H17v14h-3.4z" /></svg>
                : <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z" /></svg>}
        </button>
    );

    // Explicit, discoverable way to bring the main window back — the
    // existing double-click-to-restore gesture on the pill isn't obvious
    // from looking at the widget alone.
    const openMainBtn = (
        <button
            title="Open EffiLens"
            onClick={() => invoke("show_main_window").catch(() => {})}
            style={{
                width: 18, height: 18, borderRadius: "50%", flexShrink: 0,
                border: "1px solid var(--line-strong)", background: "transparent",
                color: "var(--text-3)",
                display: "flex", alignItems: "center", justifyContent: "center",
            }}>
            <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M9 15 20 4M20 4h-6M20 4v6" />
                <path d="M20 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h6" />
            </svg>
        </button>
    );

    if (snapSide) {
        // Docked: slim vertical bar flush against the screen edge.
        return (
            <div
                data-tauri-drag-region
                onDoubleClick={restoreMain}
                style={{
                    height: "100vh", width: "100vw", display: "flex", flexDirection: "column",
                    alignItems: "center", justifyContent: "flex-start", gap: 14,
                    padding: "14px 0",
                    background: "var(--bg)",
                    border: `1px solid ${accent}`,
                    borderRadius: snapSide === "left" ? "0 12px 12px 0" : "12px 0 0 12px",
                    userSelect: "none", overflow: "hidden", boxSizing: "border-box",
                }}>
                {playPauseBtn}
                <span style={{ width: 6, height: 6, borderRadius: "50%", flexShrink: 0, background: dotColor }} />
                <div
                    className="wp-mono"
                    style={{
                        writingMode: "vertical-rl",
                        textOrientation: "mixed",
                        fontSize: 15, fontWeight: 700, letterSpacing: "0.02em",
                        color: isRunning ? "var(--text-1)" : "var(--text-3)",
                        flexShrink: 0,
                    }}>
                    {clock}
                </div>
                <div
                    className="wp-mono"
                    data-tauri-drag-region
                    style={{
                        writingMode: "vertical-rl",
                        textOrientation: "mixed",
                        fontSize: 9.5, letterSpacing: "0.14em", textTransform: "uppercase",
                        color: onBreak ? "var(--coral-2)" : "var(--gold)",
                        flex: 1, minHeight: 0, overflow: "hidden",
                        pointerEvents: "none",
                    }}>
                    {label}
                </div>
                {openMainBtn}
            </div>
        );
    }

    // Floating: compact horizontal pill.
    return (
        <div
            data-tauri-drag-region
            onDoubleClick={() => invoke("show_main_window").catch(() => {})}
            style={{
                height: "100vh", display: "flex", alignItems: "center", gap: 10,
                background: "var(--bg)",
                border: `1px solid ${accent}`,
                borderRadius: 30,
                padding: "0 14px 0 8px",
                userSelect: "none", overflow: "hidden",
                boxSizing: "border-box",
            }}>
            {playPauseBtn}

            <div data-tauri-drag-region style={{ flex: 1, minWidth: 0, pointerEvents: "none" }}>
                {timer.task && (
                    <div className="wp-mono" style={{
                        fontSize: 8.5, letterSpacing: "0.14em", textTransform: "uppercase",
                        color: onBreak ? "var(--coral-2)" : "var(--gold)", marginBottom: 2,
                    }}>
                        {taskCode(timer.task.project_name, timer.task.task_id)}
                    </div>
                )}
                <div style={{
                    fontSize: 12.5, fontWeight: 500, color: "var(--text-1)",
                    overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
                }}>
                    {label}
                </div>
            </div>

            <span className="wp-mono" style={{
                fontSize: 14.5, fontWeight: 700, flexShrink: 0,
                color: onBreak ? "var(--coral-2)" : isRunning ? "var(--text-1)" : "var(--text-3)",
            }}>
                {clock}
            </span>

            <span style={{ width: 6, height: 6, borderRadius: "50%", flexShrink: 0, background: dotColor }} />
            {openMainBtn}
        </div>
    );
}
