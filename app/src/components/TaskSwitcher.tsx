import { useState, useEffect, useMemo, useRef } from "react";
import type { Task } from "../pages/Main";
import { taskCode } from "../lib/format";

interface Props {
    tasks: Task[];
    onSelect: (t: Task) => void;
    onClose: () => void;
}

/** ⌘K task switcher — type to filter, arrows to move, Enter to start. */
export default function TaskSwitcher({ tasks, onSelect, onClose }: Props) {
    const [query, setQuery] = useState("");
    const [cursor, setCursor] = useState(0);
    const inputRef = useRef<HTMLInputElement>(null);

    const filtered = useMemo(() => {
        const q = query.trim().toLowerCase();
        if (!q) return tasks;
        return tasks.filter(t =>
            t.task_name.toLowerCase().includes(q) ||
            t.project_name.toLowerCase().includes(q) ||
            taskCode(t.project_name, t.task_id).toLowerCase().includes(q));
    }, [tasks, query]);

    useEffect(() => { setCursor(0); }, [query]);
    useEffect(() => { inputRef.current?.focus(); }, []);

    const handleKey = (e: React.KeyboardEvent) => {
        if (e.key === "ArrowDown") { e.preventDefault(); setCursor(c => Math.min(c + 1, filtered.length - 1)); }
        if (e.key === "ArrowUp") { e.preventDefault(); setCursor(c => Math.max(c - 1, 0)); }
        if (e.key === "Enter" && filtered[cursor]) { onSelect(filtered[cursor]); }
        if (e.key === "Escape") onClose();
    };

    return (
        <div
            onClick={onClose}
            style={{
                position: "fixed", inset: 0, background: "rgba(4,6,12,.7)", zIndex: 150,
                display: "flex", alignItems: "flex-start", justifyContent: "center",
                paddingTop: "16vh", animation: "wp-fade-in .1s ease-out",
            }}>
            <div
                onClick={e => e.stopPropagation()}
                className="wp-card"
                style={{ width: 520, background: "var(--panel-2)", boxShadow: "var(--shadow)", overflow: "hidden" }}>
                <div style={{ padding: "14px 16px", borderBottom: "1px solid var(--line)" }}>
                    <input
                        ref={inputRef}
                        className="wp-input"
                        placeholder="Switch to task…"
                        value={query}
                        onChange={e => setQuery(e.target.value)}
                        onKeyDown={handleKey}
                        autoComplete="off"
                        spellCheck={false}
                        style={{ background: "var(--panel)", padding: "11px 14px" }}
                    />
                </div>
                <div style={{ maxHeight: 320, overflowY: "auto", padding: "6px 0" }}>
                    {filtered.length === 0 ? (
                        <div style={{ padding: "18px 20px", color: "var(--text-3)", fontSize: 13 }}>No matching tasks.</div>
                    ) : (
                        filtered.map((t, i) => (
                            <button
                                key={t.task_id}
                                onClick={() => onSelect(t)}
                                onMouseEnter={() => setCursor(i)}
                                style={{
                                    display: "flex", alignItems: "center", gap: 14,
                                    width: "100%", textAlign: "left",
                                    padding: "10px 18px", border: "none",
                                    background: i === cursor ? "var(--panel-3)" : "transparent",
                                }}>
                                <span className="wp-mono" style={{ fontSize: 11, color: i === cursor ? "var(--gold-2)" : "var(--text-3)", letterSpacing: "0.08em", flex: "0 0 62px" }}>
                                    {taskCode(t.project_name, t.task_id)}
                                </span>
                                <span style={{ flex: 1, minWidth: 0 }}>
                                    <span style={{ display: "block", fontSize: 13.5, color: "var(--text-1)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                                        {t.task_name}
                                    </span>
                                    <span style={{ display: "block", fontSize: 11.5, color: "var(--text-3)", marginTop: 1 }}>
                                        {t.project_name}
                                    </span>
                                </span>
                                {i === cursor && (
                                    <span className="wp-mono" style={{ fontSize: 10, color: "var(--text-3)" }}>↵</span>
                                )}
                            </button>
                        ))
                    )}
                </div>
            </div>
        </div>
    );
}
