import { useState, useMemo, useRef, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useAuth } from "../hooks/useAuth";
import type { Task } from "../pages/Main";

interface Props {
    tasks: Task[];
    onSettings: () => void;
    activeProject: string | null;
    onSelectProject: (name: string) => void;
    theme: "light" | "dark";
    onToggleTheme: () => void;
}

const PROJECT_COLORS = ["#6366f1", "#0eaf8c", "#f5a623", "#c0392b", "#33437a"];

function getInitials(email: string): string {
    const parts = email.split("@")[0].split(/[._-]/);
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return email.slice(0, 2).toUpperCase();
}

export default function Sidebar({ tasks, onSettings, activeProject, onSelectProject, theme, onToggleTheme }: Props) {
    const { session, logout } = useAuth();
    const [search, setSearch] = useState("");
    const [showUserMenu, setShowUserMenu] = useState(false);
    const menuRef = useRef<HTMLDivElement>(null);

    // Close user menu on outside click
    useEffect(() => {
        if (!showUserMenu) return;
        const handler = (e: MouseEvent) => {
            if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
                setShowUserMenu(false);
            }
        };
        document.addEventListener("mousedown", handler);
        return () => document.removeEventListener("mousedown", handler);
    }, [showUserMenu]);

    const grouped = useMemo(() => {
        const map = new Map<string, number>();
        tasks.forEach(t => { map.set(t.project_name, (map.get(t.project_name) ?? 0) + 1); });
        return map;
    }, [tasks]);

    const projectNames = useMemo(() => {
        const names = Array.from(grouped.keys());
        if (!search.trim()) return names;
        return names.filter(n => n.toLowerCase().includes(search.toLowerCase()));
    }, [grouped, search]);

    const initials = session?.email ? getInitials(session.email) : "WP";

    return (
        <nav style={{
            width: "var(--sidebar-w)",
            background: "linear-gradient(180deg, var(--sb-bg) 0%, var(--sb-bg-2) 100%)",
            display: "flex",
            flexDirection: "column",
            borderRight: "1px solid var(--sb-line)",
            flexShrink: 0,
            overflow: "hidden",
        }}>
            {/* Brand */}
            <div style={{ padding: "16px 16px 12px", borderBottom: "1px solid var(--sb-line)" }}>
                <div style={{ display: "flex", alignItems: "center", gap: 9 }}>
                    <svg width="22" height="18" viewBox="0 0 48 28" fill="none">
                        <defs>
                            <linearGradient id="sbecg" x1="0" y1="0" x2="48" y2="0" gradientUnits="userSpaceOnUse">
                                <stop offset="0%" stopColor="#c9974b" />
                                <stop offset="100%" stopColor="#e3bd82" />
                            </linearGradient>
                        </defs>
                        <path d="M1 14h6l3-8 4 16 4-18 3 10h4l3-6 3 6h4" stroke="url(#sbecg)" strokeWidth="2.5" fill="none" strokeLinecap="round" strokeLinejoin="round" />
                    </svg>
                    <span style={{ color: "#fff", fontWeight: 700, fontSize: 14, letterSpacing: -0.3 }}>WorkPulse</span>
                </div>
            </div>

            {/* Search */}
            <div style={{ padding: "10px 12px", borderBottom: "1px solid var(--sb-line)" }}>
                <div style={{
                    display: "flex", alignItems: "center", gap: 7,
                    background: "rgba(255,255,255,.06)", borderRadius: 8, padding: "6px 10px",
                }}>
                    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#6a6f82" strokeWidth="2.5" strokeLinecap="round">
                        <circle cx="11" cy="11" r="8" /><path d="m21 21-4.35-4.35" />
                    </svg>
                    <input
                        value={search}
                        onChange={e => setSearch(e.target.value)}
                        placeholder="Search projects…"
                        style={{ background: "none", border: "none", outline: "none", color: "var(--sb-text)", fontSize: 12, flex: 1, padding: 0 }}
                    />
                </div>
            </div>

            {/* Projects */}
            <div style={{ flex: 1, overflowY: "auto", padding: "10px 8px 0" }}>
                <div style={{ fontSize: 10.5, fontWeight: 700, color: "#6f6c8c", letterSpacing: 0.8, textTransform: "uppercase", padding: "0 8px", marginBottom: 6 }}>
                    Projects
                </div>
                {projectNames.map((name, i) => {
                    const isActive = activeProject === name;
                    const dot = PROJECT_COLORS[i % PROJECT_COLORS.length];
                    const count = grouped.get(name) ?? 0;
                    return (
                        <button
                            key={name}
                            onClick={() => onSelectProject(name)}
                            style={{
                                width: "100%", display: "flex", alignItems: "center", gap: 9,
                                padding: "8px 10px", borderRadius: 8, border: "none",
                                background: isActive
                                    ? "linear-gradient(90deg, rgba(201,151,75,.30) 0%, rgba(201,151,75,.05) 100%)"
                                    : "transparent",
                                boxShadow: isActive ? "inset 2px 0 0 var(--brass)" : "none",
                                cursor: "pointer", textAlign: "left", marginBottom: 2, transition: "background 0.12s",
                            }}>
                            <span style={{ width: 7, height: 7, borderRadius: "50%", background: dot, flexShrink: 0 }} />
                            <span style={{
                                flex: 1, fontSize: 12.5, fontWeight: isActive ? 600 : 400,
                                color: isActive ? "#fff" : "var(--sb-text)",
                                overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
                            }}>
                                {name}
                            </span>
                            <span style={{
                                fontSize: 10.5, fontWeight: 600,
                                color: isActive ? "var(--brass-2)" : "#6a6f82",
                                background: "rgba(255,255,255,.06)", borderRadius: 10, padding: "1px 6px", flexShrink: 0,
                            }}>
                                {count}
                            </span>
                        </button>
                    );
                })}
                {projectNames.length === 0 && (
                    <div style={{ fontSize: 12, color: "#6a6f82", padding: "8px 10px" }}>
                        {tasks.length === 0 ? "Connecting to agent…" : "No projects found"}
                    </div>
                )}

                {/* Breaks */}
                <div style={{ marginTop: 14, borderTop: "1px solid var(--sb-line)", paddingTop: 10 }}>
                    <div style={{ fontSize: 10.5, fontWeight: 700, color: "#6f6c8c", letterSpacing: 0.8, textTransform: "uppercase", padding: "0 8px", marginBottom: 6 }}>
                        Breaks
                    </div>
                    <BreakChip label="☕ Coffee Break · 10m" breakType="coffee" duration={600} />
                    <BreakChip label="🍽 Lunch · 30m" breakType="lunch" duration={1800} />
                </div>
            </div>

            {/* Dock */}
            <div style={{ borderTop: "1px solid var(--sb-line)", padding: "8px 10px", display: "flex", alignItems: "center", gap: 4, justifyContent: "space-between" }}>
                <DockBtn title="Timer" active>
                    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                        <circle cx="12" cy="12" r="10" /><path d="M12 6v6l4 2" />
                    </svg>
                </DockBtn>
                <DockBtn title="Settings" onClick={onSettings}>
                    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                        <circle cx="12" cy="12" r="3" />
                        <path d="M19.07 4.93a10 10 0 0 1 0 14.14M4.93 4.93a10 10 0 0 0 0 14.14" />
                    </svg>
                </DockBtn>
                <button
                    onClick={onToggleTheme}
                    title={theme === "dark" ? "Light mode" : "Dark mode"}
                    style={{ width: 28, height: 28, borderRadius: 7, border: "none", background: "transparent", color: "var(--sb-text)", cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 14 }}>
                    {theme === "dark" ? "☀" : "🌙"}
                </button>

                {/* Avatar + user menu — click to open, click outside to close */}
                <div ref={menuRef} style={{ position: "relative" }}>
                    <button
                        onClick={() => setShowUserMenu(v => !v)}
                        title={session?.email ?? "User"}
                        style={{
                            width: 26, height: 26, borderRadius: "50%",
                            background: "var(--brass)", border: "2px solid transparent",
                            outline: showUserMenu ? "2px solid var(--brass-2)" : "none",
                            display: "flex", alignItems: "center", justifyContent: "center",
                            fontSize: 9.5, fontWeight: 800, color: "var(--navy)",
                            cursor: "pointer", letterSpacing: 0.3,
                        }}>
                        {initials}
                    </button>

                    {showUserMenu && (
                        <div style={{
                            position: "absolute", bottom: 34, left: "50%",
                            transform: "translateX(-50%)",
                            background: "var(--surface)", border: "1px solid var(--line)",
                            borderRadius: 10, boxShadow: "var(--shadow)",
                            minWidth: 175, zIndex: 200, overflow: "hidden",
                        }}>
                            <div style={{ padding: "10px 14px 8px", borderBottom: "1px solid var(--line-soft)" }}>
                                <div style={{ fontSize: 10, fontWeight: 700, color: "var(--ink-faint)", textTransform: "uppercase", letterSpacing: 0.5, marginBottom: 3 }}>
                                    Signed in as
                                </div>
                                <div style={{ fontSize: 12, color: "var(--ink-soft)", wordBreak: "break-all" }}>
                                    {session?.email}
                                </div>
                            </div>
                            <button
                                onClick={() => { setShowUserMenu(false); logout(); }}
                                style={{
                                    width: "100%", padding: "9px 14px", background: "none",
                                    border: "none", textAlign: "left", cursor: "pointer",
                                    fontSize: 13, color: "var(--alert)", fontWeight: 600,
                                    display: "flex", alignItems: "center", gap: 8,
                                }}
                                onMouseEnter={e => (e.currentTarget.style.background = "var(--surface-2)")}
                                onMouseLeave={e => (e.currentTarget.style.background = "none")}>
                                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                                    <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
                                    <polyline points="16 17 21 12 16 7" />
                                    <line x1="21" y1="12" x2="9" y2="12" />
                                </svg>
                                Sign out
                            </button>
                        </div>
                    )}
                </div>
            </div>
        </nav>
    );
}

function BreakChip({ label, breakType, duration }: { label: string; breakType: string; duration: number }) {
    return (
        <button
            onClick={() => invoke("send_ipc", { cmd: "start_break", payload: { break_type: breakType, duration_secs: duration } }).catch(() => {})}
            style={{
                width: "100%", display: "flex", alignItems: "center",
                padding: "7px 10px", borderRadius: 8, border: "none",
                background: "transparent", color: "var(--sb-text)", fontSize: 12,
                cursor: "pointer", textAlign: "left", marginBottom: 2,
            }}
            onMouseEnter={e => { (e.currentTarget as HTMLButtonElement).style.background = "rgba(255,255,255,.05)"; }}
            onMouseLeave={e => { (e.currentTarget as HTMLButtonElement).style.background = "transparent"; }}>
            {label}
        </button>
    );
}

function DockBtn({ children, title, active, onClick }: { children: React.ReactNode; title: string; active?: boolean; onClick?: () => void }) {
    return (
        <button
            title={title}
            onClick={onClick}
            style={{
                width: 28, height: 28, borderRadius: 7, border: "none",
                background: active ? "var(--brass)" : "transparent",
                color: active ? "var(--navy)" : "var(--sb-text)",
                cursor: "pointer", display: "flex", alignItems: "center", justifyContent: "center",
                transition: "background 0.1s",
            }}>
            {children}
        </button>
    );
}
