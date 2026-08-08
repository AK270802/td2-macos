import { useEffect, useState } from "react";
import type { Task } from "../pages/Main";
import { formatHMS, taskCode } from "../lib/format";

interface Props {
    tasks: Task[];
    taskTimes: Record<string, number>;
    /** Date.now() when `taskTimes` was fetched — lets the tracking row tick
     * live between polls instead of only jumping every 30s. */
    taskTimesFetchedAt: number;
    onSelectTask: (t: Task) => void;
    activeTaskId: string | null;
    isRunning: boolean;
    onSwitcher: () => void;
}

export default function TaskList({ tasks, taskTimes, taskTimesFetchedAt, onSelectTask, activeTaskId, isRunning, onSwitcher }: Props) {
    // Re-render every second while a task is actively tracking so its row
    // ticks like the hero timer, instead of only updating on each 30s poll.
    const [, forceTick] = useState(0);
    useEffect(() => {
        if (!isRunning || !activeTaskId) return;
        const id = setInterval(() => forceTick(x => x + 1), 1000);
        return () => clearInterval(id);
    }, [isRunning, activeTaskId]);

    const liveSeconds = (taskId: string, tracking: boolean) => {
        const baseline = taskTimes[taskId] ?? 0;
        if (!tracking) return baseline;
        return baseline + Math.floor((Date.now() - taskTimesFetchedAt) / 1000);
    };

    return (
        <div className="wp-card" style={{ marginBottom: 14, overflow: "hidden" }}>
            <div style={{
                display: "flex", alignItems: "center", justifyContent: "space-between",
                padding: "16px 20px 12px",
            }}>
                <span className="wp-overline">Assigned tasks</span>
                <button
                    onClick={onSwitcher}
                    className="wp-btn-ghost"
                    style={{ display: "flex", alignItems: "center", gap: 8, padding: "6px 12px", borderRadius: 8, fontSize: 12 }}>
                    Switch task
                    <span className="wp-mono" style={{
                        fontSize: 10, border: "1px solid var(--line-strong)", borderRadius: 4,
                        padding: "2px 5px", color: "var(--text-3)",
                    }}>
                        ⌘K
                    </span>
                </button>
            </div>

            {tasks.length === 0 ? (
                <div style={{ padding: "26px 20px 30px", textAlign: "center", color: "var(--text-3)", fontSize: 13 }}>
                    No tasks assigned yet — they appear here when your manager assigns them.
                </div>
            ) : (
                tasks.map(t => {
                    const active = t.task_id === activeTaskId;
                    const tracking = active && isRunning;
                    return (
                        <button
                            key={t.task_id}
                            onClick={() => onSelectTask(t)}
                            className="wp-row-hover"
                            style={{
                                display: "flex", alignItems: "center", gap: 16,
                                width: "100%", textAlign: "left",
                                padding: "13px 20px",
                                border: "none", borderTop: "1px solid var(--line)",
                                background: active ? "var(--panel-2)" : "transparent",
                                boxShadow: tracking ? "inset 3px 0 0 var(--gold)" : "none",
                            }}>
                            {/* Play / pause dot button */}
                            <span style={{
                                width: 32, height: 32, borderRadius: "50%", flexShrink: 0,
                                border: `1px solid ${tracking ? "var(--gold-line)" : "var(--line-strong)"}`,
                                background: tracking ? "var(--gold)" : "transparent",
                                color: tracking ? "#16110a" : "var(--text-3)",
                                display: "flex", alignItems: "center", justifyContent: "center",
                            }}>
                                {tracking
                                    ? <svg width="11" height="11" viewBox="0 0 24 24" fill="currentColor"><path d="M7 5h3.4v14H7zM13.6 5H17v14h-3.6z" /></svg>
                                    : <svg width="11" height="11" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z" /></svg>}
                            </span>

                            <span className="wp-mono" style={{ fontSize: 11, color: "var(--text-3)", letterSpacing: "0.08em", flex: "0 0 64px" }}>
                                {taskCode(t.project_name, t.task_id)}
                            </span>

                            <span style={{ flex: 1, minWidth: 0 }}>
                                <span style={{ display: "block", fontSize: 13.5, fontWeight: 500, color: "var(--text-1)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                                    {t.task_name}
                                </span>
                                <span style={{ display: "block", fontSize: 11.5, color: "var(--text-3)", marginTop: 2 }}>
                                    {t.project_name}
                                </span>
                            </span>

                            <span className="wp-mono" style={{
                                fontSize: 13, flexShrink: 0,
                                color: tracking ? "var(--gold-2)" : "var(--text-2)",
                            }}>
                                {formatHMS(liveSeconds(t.task_id, tracking))}
                            </span>

                            <span className={`wp-chip ${tracking ? "wp-chip--tracking" : ""}`} style={{ flexShrink: 0 }}>
                                {tracking ? "Tracking" : "Idle"}
                            </span>
                        </button>
                    );
                })
            )}
        </div>
    );
}
