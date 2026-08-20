import { useState, useEffect, useMemo, useRef, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { useTimerState } from "../hooks/useTimerState";
import { useToast } from "../components/Toast";
import HeroCard from "../components/HeroCard";
import StatRow from "../components/StatRow";
import TaskList from "../components/TaskList";
import Sidebar from "../components/Sidebar";
import StatusBar from "../components/StatusBar";
import RecentFeed from "../components/RecentFeed";
import TaskSwitcher from "../components/TaskSwitcher";
import TitleBar from "../components/TitleBar";
import Settings from "./Settings";

export interface Task { task_id: string; project_id: string; task_name: string; project_name: string; }

export default function MainPage() {
    const { timer, togglePlayPause, selectTask, startBreak } = useTimerState(true);
    const { toast } = useToast();
    const [showSettings, setShowSettings] = useState(false);
    const [showQuit, setShowQuit] = useState(false);
    const [showSwitcher, setShowSwitcher] = useState(false);
    const [activeProject, setActiveProject] = useState<string | null>(null);
    const [tasks, setTasks] = useState<Task[]>([]);
    const [taskTimes, setTaskTimes] = useState<Record<string, number>>({});
    const [taskTimesFetchedAt, setTaskTimesFetchedAt] = useState(() => Date.now());
    const prevState = useRef(timer.state);

    // Assigned tasks + per-task times, refreshed every 30s. agentd only
    // flushes the in-progress session into task_time_logs every few minutes
    // (see agentd/src/sync_loop.rs flush_active), so TaskList ticks the
    // active row live between polls using taskTimesFetchedAt as the baseline
    // timestamp rather than waiting on flush cadence.
    useEffect(() => {
        const load = () => {
            invoke<Task[]>("send_ipc", { cmd: "get_assigned_tasks" })
                .then(r => { if (Array.isArray(r)) setTasks(r); })
                .catch(e => console.error("get_assigned_tasks failed:", e));
            invoke<Record<string, number>>("send_ipc", { cmd: "get_task_times_today" })
                .then(r => { if (r) { setTaskTimes(r); setTaskTimesFetchedAt(Date.now()); } })
                .catch(() => {});
        };
        load();
        const id = setInterval(load, 30_000);
        // "Sync now" (StatusBar) fires this so the task list/times refresh
        // immediately instead of waiting for the next 30s tick.
        window.addEventListener("wp-sync-now", load);
        return () => {
            clearInterval(id);
            window.removeEventListener("wp-sync-now", load);
        };
    }, []);

    // State-transition toasts (break started, tracking started/paused).
    useEffect(() => {
        if (prevState.current === timer.state) return;
        if (timer.state === "on_break") {
            toast("Break started", "Capture paused. Enjoy your break.", "coral");
        } else if (timer.state === "running" && prevState.current !== "running") {
            toast("Tracking", timer.task ? `Timer running on ${timer.task.task_name}.` : "Timer running.", "emerald");
        } else if (timer.state === "paused" && prevState.current === "running") {
            toast("Paused", "Timer paused. Capture is stopped.", "gold");
        }
        prevState.current = timer.state;
    }, [timer.state, timer.task, toast]);

    // Ctrl/Cmd+K in-app; global shortcut arrives as a Tauri event.
    useEffect(() => {
        const onKey = (e: KeyboardEvent) => {
            if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "k") {
                e.preventDefault();
                setShowSwitcher(s => !s);
            }
            if (e.key === "Escape") setShowSwitcher(false);
        };
        window.addEventListener("keydown", onKey);
        const unlisten = listen("open-task-switcher", () => setShowSwitcher(true));
        return () => {
            window.removeEventListener("keydown", onKey);
            unlisten.then(f => f());
        };
    }, []);

    const handleSelectTask = useCallback((t: Task) => {
        selectTask(t.task_id, t.project_id, t.task_name, t.project_name);
        setShowSwitcher(false);
    }, [selectTask]);

    const projects = useMemo(() => {
        const map = new Map<string, number>();
        for (const t of tasks) map.set(t.project_name, (map.get(t.project_name) ?? 0) + 1);
        return Array.from(map.entries()).map(([name, count]) => ({ name, count }));
    }, [tasks]);

    const visibleTasks = useMemo(
        () => activeProject ? tasks.filter(t => t.project_name === activeProject) : tasks,
        [tasks, activeProject],
    );

    return (
        <div style={{ display: "flex", flexDirection: "column", height: "100vh", background: "var(--bg)", userSelect: "none", overflow: "hidden" }}>
            <TitleBar onClose={() => setShowQuit(true)} />

            <div style={{ display: "flex", flex: 1, overflow: "hidden" }}>
                <Sidebar
                    projects={projects}
                    activeProject={activeProject}
                    onSelectProject={setActiveProject}
                    onBreak={() => startBreak("coffee")}
                    onSettings={() => setShowSettings(true)}
                    onMini={() => invoke("show_mini_widget").catch(() => {})}
                    onBreak_active={timer.state === "on_break"}
                />

                <main style={{ flex: 1, display: "flex", flexDirection: "column", overflow: "hidden" }}>
                    <div style={{ flex: 1, overflowY: "auto", padding: "18px 22px 8px" }}>
                        <HeroCard timer={timer} onToggle={togglePlayPause} />
                        <StatRow inMeeting={timer.in_meeting} />
                        <TaskList
                            tasks={visibleTasks}
                            taskTimes={taskTimes}
                            taskTimesFetchedAt={taskTimesFetchedAt}
                            onSelectTask={handleSelectTask}
                            activeTaskId={timer.state === "running" || timer.state === "paused" ? timer.task?.task_id ?? null : null}
                            isRunning={timer.state === "running"}
                            onSwitcher={() => setShowSwitcher(true)}
                        />
                        <RecentFeed />
                    </div>
                    <StatusBar agentConnected={timer.agent_connected} />
                </main>
            </div>

            {showSwitcher && (
                <TaskSwitcher tasks={tasks} onSelect={handleSelectTask} onClose={() => setShowSwitcher(false)} />
            )}

            {showSettings && (
                <div
                    onClick={() => setShowSettings(false)}
                    style={{ position: "fixed", inset: 0, background: "rgba(4,6,12,.65)", zIndex: 100, display: "flex", alignItems: "center", justifyContent: "center", animation: "wp-fade-in .12s ease-out" }}>
                    <div onClick={e => e.stopPropagation()}>
                        <Settings onClose={() => setShowSettings(false)} />
                    </div>
                </div>
            )}

            {showQuit && (
                <QuitDialog
                    tracking={timer.state === "running"}
                    onCancel={() => setShowQuit(false)}
                    onHide={() => { setShowQuit(false); invoke("hide_main_window").catch(() => {}); }}
                    onQuit={async () => {
                        await invoke("send_ipc", { cmd: "stop_tracking" }).catch(() => {});
                        invoke("quit_app").catch(() => {});
                    }}
                />
            )}
        </div>
    );
}

function QuitDialog({ tracking, onCancel, onHide, onQuit }: {
    tracking: boolean; onCancel: () => void; onHide: () => void; onQuit: () => void;
}) {
    return (
        <div
            onClick={onCancel}
            style={{ position: "fixed", inset: 0, background: "rgba(4,6,12,.65)", zIndex: 200, display: "flex", alignItems: "center", justifyContent: "center", animation: "wp-fade-in .12s ease-out" }}>
            <div
                onClick={e => e.stopPropagation()}
                className="wp-card"
                style={{ width: 400, background: "var(--panel-2)", boxShadow: "var(--shadow)", overflow: "hidden" }}>
                <div style={{ padding: "22px 24px 18px" }}>
                    <span className="wp-overline" style={{ marginBottom: 12, display: "inline-block" }}>Quit EffiLens</span>
                    <div className="wp-display" style={{ fontSize: 20, fontWeight: 500, marginBottom: 10 }}>
                        {tracking ? "You're still on the clock." : "Close the agent?"}
                    </div>
                    <div style={{ fontSize: 13, color: "var(--text-2)", lineHeight: 1.6, fontWeight: 300 }}>
                        {tracking
                            ? "Quitting stops your running timer and ends the session. You can also keep tracking in the background and just hide this window."
                            : "Background tracking stops when the agent quits. Hide to tray to keep the timer available."}
                    </div>
                </div>
                <div style={{ display: "flex", justifyContent: "flex-end", gap: 8, padding: "14px 24px 20px" }}>
                    <button className="wp-btn-ghost" onClick={onCancel} style={{ padding: "9px 16px" }}>Cancel</button>
                    <button className="wp-btn-ghost" onClick={onHide} style={{ padding: "9px 16px" }}>Hide to tray</button>
                    <button
                        onClick={onQuit}
                        style={{
                            padding: "9px 18px", borderRadius: 10, border: "none",
                            background: "var(--red)", color: "#1b0d0d", fontSize: 13, fontWeight: 600,
                        }}>
                        {tracking ? "Stop & quit" : "Quit"}
                    </button>
                </div>
            </div>
        </div>
    );
}
