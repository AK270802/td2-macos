import { useMemo } from "react";
import type { Task } from "../pages/Main";

interface Props {
    tasks: Task[];
    onSelectTask: (task_id: string, project_id: string, task_name: string, project_name: string) => void;
    activeTaskId: string | null;
    activeProject: string | null;
}

export default function TaskList({ tasks, onSelectTask, activeTaskId, activeProject }: Props) {
    const grouped = useMemo(() => {
        const map = new Map<string, Task[]>();
        tasks.forEach(t => {
            const bucket = map.get(t.project_name) ?? [];
            bucket.push(t);
            map.set(t.project_name, bucket);
        });
        return map;
    }, [tasks]);

    const projectNames = Array.from(grouped.keys());
    const displayProject = activeProject ?? (projectNames[0] ?? null);
    const visibleTasks = displayProject ? (grouped.get(displayProject) ?? []) : [];

    return (
        <div style={{
            background: "var(--surface)", border: "1px solid var(--line)",
            borderRadius: "var(--radius)", marginBottom: 16, overflow: "hidden",
            boxShadow: "var(--shadow-sm)",
        }}>
            {/* Card header */}
            <div style={{
                display: "flex", alignItems: "center", justifyContent: "space-between",
                padding: "12px 16px", borderBottom: "1px solid var(--line-soft)",
            }}>
                <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                    <span style={{ fontSize: 13, fontWeight: 700, color: "var(--ink)" }}>
                        {displayProject ?? "Tasks"}
                    </span>
                    {visibleTasks.length > 0 && (
                        <span style={{
                            fontSize: 11, fontWeight: 600, color: "var(--ink-faint)",
                            background: "var(--surface-2)", border: "1px solid var(--line)",
                            borderRadius: 20, padding: "1px 7px",
                        }}>
                            {visibleTasks.length}
                        </span>
                    )}
                </div>
                <button style={{ fontSize: 12, fontWeight: 600, color: "var(--link)", background: "none", border: "none", cursor: "pointer", padding: 0 }}>
                    + New task
                </button>
            </div>

            {/* Task rows */}
            {visibleTasks.length === 0 ? (
                <div style={{ padding: "20px 16px", color: "var(--ink-faint)", fontSize: 13, textAlign: "center" }}>
                    {tasks.length === 0 ? "Waiting for agent sync…" : "No tasks in this project"}
                </div>
            ) : (
                visibleTasks.map(t => {
                    const isActive = t.task_id === activeTaskId;
                    return (
                        <div
                            key={t.task_id}
                            style={{
                                display: "flex", alignItems: "center", gap: 12,
                                padding: "10px 16px",
                                background: isActive ? "var(--brass-soft)" : "transparent",
                                borderBottom: "1px solid var(--line-soft)",
                                transition: "background 0.1s",
                            }}>
                            <span style={{
                                width: 8, height: 8, borderRadius: "50%", flexShrink: 0,
                                background: isActive ? "var(--brass-ink)" : "transparent",
                                border: isActive ? "none" : "1.5px solid var(--line)",
                            }} />
                            <span style={{
                                flex: 1, fontSize: 13,
                                fontWeight: isActive ? 700 : 500,
                                color: isActive ? "var(--brass-ink)" : "var(--ink)",
                                minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
                            }}>
                                {t.task_name}
                            </span>
                            <span style={{
                                fontSize: 12, color: "var(--ink-faint)",
                                fontFamily: "'Space Grotesk', monospace",
                                flexShrink: 0, marginRight: 8,
                            }}>
                                {isActive ? "" : "0:00"}
                            </span>
                            <button
                                onClick={() => onSelectTask(t.task_id, t.project_id, t.task_name, t.project_name)}
                                style={{
                                    width: 28, height: 28, borderRadius: "50%",
                                    border: "1.5px solid var(--line)",
                                    background: isActive ? "var(--brass)" : "transparent",
                                    color: isActive ? "#fff" : "var(--ink-soft)",
                                    display: "flex", alignItems: "center", justifyContent: "center",
                                    cursor: "pointer", flexShrink: 0, transition: "all 0.15s",
                                }}>
                                <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor">
                                    <path d="M8 5v14l11-7z" />
                                </svg>
                            </button>
                        </div>
                    );
                })
            )}
        </div>
    );
}
