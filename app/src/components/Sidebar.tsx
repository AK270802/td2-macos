import { useState } from "react";
import { useAuth } from "../hooks/useAuth";

interface Props {
    projects: { name: string; count: number }[];
    activeProject: string | null;
    onSelectProject: (name: string | null) => void;
    onBreak: () => void;
    onBreak_active: boolean;
    onSettings: () => void;
    onMini: () => void;
}

export default function Sidebar({ projects, activeProject, onSelectProject, onBreak, onBreak_active, onSettings, onMini }: Props) {
    const { logout } = useAuth();
    const [query, setQuery] = useState("");

    const shown = query
        ? projects.filter(p => p.name.toLowerCase().includes(query.toLowerCase()))
        : projects;

    return (
        <aside style={{
            width: "var(--sidebar-w)", flexShrink: 0,
            background: "var(--bg-2)", borderRight: "1px solid var(--line)",
            display: "flex", flexDirection: "column", padding: "16px 12px 14px",
        }}>
            <input
                className="wp-input"
                placeholder="Search tasks…"
                value={query}
                onChange={e => setQuery(e.target.value)}
                autoComplete="off"
                spellCheck={false}
                style={{ padding: "9px 12px", fontSize: 12.5, borderRadius: 9, marginBottom: 22 }}
            />

            <span className="wp-overline" style={{ margin: "0 6px 10px", flexShrink: 0 }}>Projects</span>
            <div style={{
                display: "flex", flexDirection: "column", gap: 2,
                flex: 1, minHeight: 0, overflowY: "auto",
                marginRight: -6, paddingRight: 6,
            }}>
                <ProjectRow
                    label="All projects"
                    count={projects.reduce((a, p) => a + p.count, 0)}
                    active={activeProject === null}
                    onClick={() => onSelectProject(null)}
                />
                {shown.map(p => (
                    <ProjectRow
                        key={p.name}
                        label={p.name}
                        count={p.count}
                        active={activeProject === p.name}
                        onClick={() => onSelectProject(p.name)}
                    />
                ))}
                {shown.length === 0 && (
                    <div style={{ padding: "8px 10px", fontSize: 12, color: "var(--text-3)" }}>No projects found</div>
                )}
            </div>

            <span className="wp-overline" style={{ margin: "26px 6px 10px", flexShrink: 0 }}>Breaks</span>
            <button
                onClick={onBreak}
                style={{
                    textAlign: "left",
                    padding: "12px 14px",
                    borderRadius: "var(--radius)",
                    border: `1px solid ${onBreak_active ? "rgba(224,107,77,0.55)" : "var(--line-strong)"}`,
                    background: onBreak_active ? "var(--coral)" : "transparent",
                    color: onBreak_active ? "var(--coral-ink)" : "var(--text-2)",
                    fontSize: 13, fontWeight: onBreak_active ? 600 : 400,
                    transition: "all .15s ease",
                    flexShrink: 0,
                }}>
                {onBreak_active ? "On break…" : "Start a break"}
            </button>

            <div style={{ display: "flex", gap: 6, marginTop: 14, flexShrink: 0 }}>
                <IconBtn title="Settings" onClick={onSettings}>
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
                        <circle cx="12" cy="12" r="3" />
                        <path d="M12 2v3M12 19v3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M2 12h3M19 12h3M4.9 19.1L7 17M17 7l2.1-2.1" />
                    </svg>
                </IconBtn>
                <IconBtn title="Mini timer" onClick={onMini}>
                    <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5">
                        <rect x="1.5" y="5" width="13" height="6" rx="3" />
                    </svg>
                </IconBtn>
                <IconBtn title="Sign out" onClick={() => logout()}>
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                        <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9" />
                    </svg>
                </IconBtn>
            </div>
        </aside>
    );
}

function ProjectRow({ label, count, active, onClick }: {
    label: string; count: number; active: boolean; onClick: () => void;
}) {
    return (
        <button
            onClick={onClick}
            className="wp-row-hover"
            style={{
                display: "flex", alignItems: "center", justifyContent: "space-between",
                padding: "9px 12px", borderRadius: 9, border: "none",
                background: active ? "var(--panel-2)" : "transparent",
                color: active ? "var(--gold-2)" : "var(--text-2)",
                fontSize: 13, fontWeight: active ? 600 : 400,
                textAlign: "left", width: "100%",
            }}>
            <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{label}</span>
            <span className="wp-mono" style={{ fontSize: 11, color: active ? "var(--gold)" : "var(--text-3)" }}>{count}</span>
        </button>
    );
}

function IconBtn({ children, title, onClick }: { children: React.ReactNode; title: string; onClick: () => void }) {
    return (
        <button
            title={title}
            onClick={onClick}
            className="wp-row-hover"
            style={{
                width: 34, height: 32, borderRadius: 8,
                border: "1px solid var(--line)",
                background: "transparent", color: "var(--text-3)",
                display: "flex", alignItems: "center", justifyContent: "center",
            }}>
            {children}
        </button>
    );
}
