import { useState, useCallback, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { useTimerState } from "../hooks/useTimerState";
import HeroCard from "../components/HeroCard";
import StatRow from "../components/StatRow";
import TaskList from "../components/TaskList";
import Sidebar from "../components/Sidebar";
import StatusBar from "../components/StatusBar";
import Settings from "./Settings";

export interface Task { task_id: string; project_id: string; task_name: string; project_name: string; }

interface Props { theme: "light" | "dark"; onToggleTheme: () => void; }

export default function MainPage({ theme, onToggleTheme }: Props) {
    const { timer, togglePlayPause, selectTask } = useTimerState();
    const [showSettings, setShowSettings] = useState(false);
    const [showQuit, setShowQuit] = useState(false);
    const [activeProject, setActiveProject] = useState<string | null>(null);
    const [tasks, setTasks] = useState<Task[]>([]);

    useEffect(() => {
        const load = () => {
            invoke<Task[]>("send_ipc", { cmd: "get_assigned_tasks" })
                .then(r => { if (Array.isArray(r)) setTasks(r); })
                .catch(() => {});
        };
        load();
        const id = setInterval(load, 30_000);
        return () => clearInterval(id);
    }, []);

    const handleClose = useCallback(() => setShowQuit(true), []);

    return (
        <div style={{ display: "flex", flexDirection: "column", height: "100vh", background: "var(--bg)", userSelect: "none", overflow: "hidden" }}>
            <TitleBar onClose={handleClose} />

            <div style={{ display: "flex", flex: 1, overflow: "hidden" }}>
                <Sidebar
                    tasks={tasks}
                    onSettings={() => setShowSettings(true)}
                    activeProject={activeProject}
                    onSelectProject={setActiveProject}
                    theme={theme}
                    onToggleTheme={onToggleTheme}
                />

                <main style={{ flex: 1, display: "flex", flexDirection: "column", overflow: "hidden", background: "var(--bg)" }}>
                    {/* Sub-header */}
                    <div style={{
                        height: 44,
                        borderBottom: "1px solid var(--line)",
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "space-between",
                        padding: "0 20px",
                        background: "var(--surface)",
                        flexShrink: 0,
                    }}>
                        <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                            <span style={{ fontSize: 12, color: "var(--ink-faint)" }}>WorkPulse</span>
                            <span style={{ fontSize: 12, color: "var(--ink-faint)" }}>/</span>
                            <span style={{ fontSize: 12, fontWeight: 600, color: "var(--ink)" }}>Time Tracking</span>
                        </div>
                        <button
                            onClick={() => setShowSettings(true)}
                            style={{ width: 28, height: 28, borderRadius: 7, border: "1px solid var(--line)", background: "var(--surface-2)", color: "var(--ink-soft)", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer" }}>
                            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                                <circle cx="12" cy="12" r="3" />
                                <path d="M19.07 4.93a10 10 0 0 1 0 14.14M4.93 4.93a10 10 0 0 0 0 14.14" />
                            </svg>
                        </button>
                    </div>

                    {/* Scrollable content */}
                    <div style={{ flex: 1, overflowY: "auto", padding: "16px 18px 0" }}>
                        <HeroCard timer={timer} onToggle={togglePlayPause} />

                        {/* Idle banner — visible when was running, now idle */}
                        {timer.state === "idle" && timer.elapsed_secs > 0 && (
                            <div style={{
                                background: "var(--amber-soft)",
                                border: "1px solid #f3ddae",
                                borderRadius: 12,
                                padding: "12px 16px",
                                marginBottom: 12,
                                display: "flex",
                                alignItems: "center",
                                gap: 12,
                            }}>
                                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--amber-ink)" strokeWidth="2" strokeLinecap="round" style={{ flexShrink: 0 }}>
                                    <circle cx="12" cy="12" r="10" /><path d="M12 6v6l4 2" />
                                </svg>
                                <span style={{ flex: 1, fontSize: 12.5, color: "var(--amber-ink)" }}>
                                    We noticed inactivity — Keep this as tracked time, or discard it?
                                </span>
                                <button
                                    onClick={() => {}}
                                    style={{ fontSize: 12, fontWeight: 600, color: "var(--amber-ink)", background: "none", border: "1px solid #f3ddae", borderRadius: 7, padding: "4px 10px", cursor: "pointer" }}>
                                    Discard
                                </button>
                                <button
                                    onClick={() => {}}
                                    style={{ fontSize: 12, fontWeight: 600, color: "#fff", background: "var(--navy)", border: "none", borderRadius: 7, padding: "4px 10px", cursor: "pointer" }}>
                                    Keep time
                                </button>
                            </div>
                        )}

                        <StatRow />
                        <TaskList
                            tasks={tasks}
                            onSelectTask={selectTask}
                            activeTaskId={timer.task?.task_id ?? null}
                            activeProject={activeProject}
                        />

                        {/* Recently timed section */}
                        <div style={{ marginBottom: 16 }}>
                            <div style={{ fontSize: 10, fontWeight: 700, color: "var(--ink-faint)", letterSpacing: 0.6, textTransform: "uppercase", marginBottom: 8 }}>
                                Recently timed
                            </div>
                            <div style={{ background: "var(--surface)", border: "1px solid var(--line)", borderRadius: "var(--radius)", padding: "14px 16px", color: "var(--ink-faint)", fontSize: 12, textAlign: "center" }}>
                                No recent sessions
                            </div>
                        </div>
                    </div>

                    <StatusBar />
                </main>
            </div>

            {/* Settings modal overlay */}
            {showSettings && (
                <div
                    onClick={() => setShowSettings(false)}
                    style={{ position: "fixed", inset: 0, background: "rgba(8,8,12,.5)", zIndex: 100, display: "flex", alignItems: "center", justifyContent: "center" }}>
                    <div onClick={e => e.stopPropagation()}>
                        <Settings onClose={() => setShowSettings(false)} />
                    </div>
                </div>
            )}

            {/* Quit confirmation modal */}
            {showQuit && (
                <div
                    onClick={() => setShowQuit(false)}
                    style={{ position: "fixed", inset: 0, background: "rgba(8,8,12,.5)", zIndex: 200, display: "flex", alignItems: "center", justifyContent: "center" }}>
                    <div
                        onClick={e => e.stopPropagation()}
                        style={{ width: 360, background: "var(--surface)", borderRadius: "var(--radius)", boxShadow: "var(--shadow)", overflow: "hidden" }}>
                        <div style={{ padding: "20px 22px" }}>
                            <div style={{ fontSize: 15, fontWeight: 700, color: "var(--ink)", marginBottom: 8 }}>Quit WorkPulse?</div>
                            <div style={{ fontSize: 13, color: "var(--ink-soft)", lineHeight: 1.5 }}>The agent will stop tracking. Your data has been synced.</div>
                        </div>
                        <div style={{ display: "flex", justifyContent: "flex-end", gap: 8, padding: "12px 22px 18px", borderTop: "1px solid var(--line-soft)" }}>
                            <button
                                onClick={() => setShowQuit(false)}
                                style={{ padding: "8px 16px", borderRadius: 8, border: "1px solid var(--line)", background: "var(--surface-2)", color: "var(--ink-soft)", fontSize: 13, fontWeight: 500, cursor: "pointer" }}>
                                Cancel
                            </button>
                            <button
                                onClick={() => getCurrentWindow().close()}
                                style={{ padding: "8px 16px", borderRadius: 8, border: "none", background: "var(--alert)", color: "#fff", fontSize: 13, fontWeight: 600, cursor: "pointer" }}>
                                Quit
                            </button>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}

function TitleBar({ onClose }: { onClose: () => void }) {
    const appWindow = getCurrentWindow();

    return (
        <div
            data-tauri-drag-region
            style={{
                height: "var(--title-bar-h)",
                background: "var(--surface)",
                borderBottom: "1px solid var(--line)",
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                padding: "0 14px",
                flexShrink: 0,
                WebkitAppRegion: "drag",
            } as React.CSSProperties}>
            {/* Left: logo + title */}
            <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                <svg width="20" height="16" viewBox="0 0 48 28" fill="none">
                    <path d="M1 14h6l3-8 4 16 4-18 3 10h4l3-6 3 6h4" stroke="#c9974b" strokeWidth="2" fill="none" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
                <span style={{ fontSize: 13, fontWeight: 700, color: "var(--ink)", letterSpacing: -0.2 }}>WorkPulse Agent</span>
            </div>

            {/* Right: window controls */}
            <div style={{ display: "flex", alignItems: "center", gap: 4, WebkitAppRegion: "no-drag" } as React.CSSProperties}>
                {/* Compact view */}
                <WinCtrlBtn title="Compact view" onClick={() => {}}>
                    <svg width="11" height="11" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5">
                        <rect x="1" y="1" width="6" height="6" rx="1" /><rect x="9" y="1" width="6" height="6" rx="1" />
                        <rect x="1" y="9" width="6" height="6" rx="1" /><rect x="9" y="9" width="6" height="6" rx="1" />
                    </svg>
                </WinCtrlBtn>
                {/* Minimize */}
                <WinCtrlBtn title="Minimize" onClick={() => appWindow.minimize()}>
                    <svg width="11" height="2" viewBox="0 0 11 2" fill="currentColor"><rect width="11" height="2" rx="1" /></svg>
                </WinCtrlBtn>
                {/* Maximize */}
                <WinCtrlBtn title="Maximize" onClick={() => appWindow.toggleMaximize()}>
                    <svg width="11" height="11" viewBox="0 0 11 11" fill="none" stroke="currentColor" strokeWidth="1.5"><rect x=".75" y=".75" width="9.5" height="9.5" rx="1.5" /></svg>
                </WinCtrlBtn>
                {/* Close */}
                <WinCtrlBtn title="Close" isClose onClick={onClose}>
                    <svg width="11" height="11" viewBox="0 0 11 11" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
                        <path d="M1 1l9 9M10 1l-9 9" />
                    </svg>
                </WinCtrlBtn>
            </div>
        </div>
    );
}

function WinCtrlBtn({ children, title, isClose, onClick }: { children: React.ReactNode; title: string; isClose?: boolean; onClick?: () => void; }) {
    const [hovered, setHovered] = useState(false);
    return (
        <button
            title={title}
            onClick={onClick}
            onMouseEnter={() => setHovered(true)}
            onMouseLeave={() => setHovered(false)}
            style={{
                width: 28,
                height: 28,
                borderRadius: 6,
                border: "none",
                background: hovered ? (isClose ? "var(--alert)" : "var(--surface-2)") : "transparent",
                color: hovered && isClose ? "#fff" : "var(--ink-soft)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                cursor: "pointer",
                transition: "background 0.1s, color 0.1s",
                padding: 0,
            }}>
            {children}
        </button>
    );
}