import React, { createContext, useContext, useState, useCallback, useEffect } from "react";

export interface ToastMessage {
    id: number;
    title: string;
    body?: string;
    tone: "gold" | "coral" | "emerald" | "red";
}

interface ToastCtx {
    toast: (title: string, body?: string, tone?: ToastMessage["tone"]) => void;
}

const Ctx = createContext<ToastCtx>({ toast: () => {} });

export function useToast() {
    return useContext(Ctx);
}

let nextId = 1;

export function ToastProvider({ children }: { children: React.ReactNode }) {
    const [toasts, setToasts] = useState<ToastMessage[]>([]);

    const toast = useCallback((title: string, body?: string, tone: ToastMessage["tone"] = "gold") => {
        const id = nextId++;
        setToasts(t => [...t.slice(-2), { id, title, body, tone }]);
    }, []);

    const remove = useCallback((id: number) => {
        setToasts(t => t.filter(x => x.id !== id));
    }, []);

    return (
        <Ctx.Provider value={{ toast }}>
            {children}
            <div style={{
                position: "fixed", bottom: 44, right: 16, display: "flex",
                flexDirection: "column", gap: 8, zIndex: 9999, pointerEvents: "none",
            }}>
                {toasts.map(t => <ToastCard key={t.id} toast={t} onDone={remove} />)}
            </div>
        </Ctx.Provider>
    );
}

const TONE: Record<ToastMessage["tone"], { border: string; label: string }> = {
    gold: { border: "var(--gold-line)", label: "var(--gold)" },
    coral: { border: "rgba(224,107,77,0.55)", label: "var(--coral-2)" },
    emerald: { border: "rgba(62,207,142,0.5)", label: "var(--emerald)" },
    red: { border: "rgba(248,113,113,0.5)", label: "var(--red)" },
};

function ToastCard({ toast, onDone }: { toast: ToastMessage; onDone: (id: number) => void }) {
    useEffect(() => {
        const t = setTimeout(() => onDone(toast.id), 3600);
        return () => clearTimeout(t);
    }, [toast.id, onDone]);

    const tone = TONE[toast.tone];
    return (
        <div style={{
            background: "var(--panel-2)",
            border: `1px solid ${tone.border}`,
            borderLeft: `3px solid ${tone.label}`,
            borderRadius: "var(--radius)",
            padding: "12px 16px",
            minWidth: 260,
            maxWidth: 340,
            pointerEvents: "auto",
            boxShadow: "var(--shadow)",
            animation: "wp-toast-in 0.18s ease-out",
        }}>
            <div className="wp-overline" style={{ color: tone.label, borderTopColor: tone.border, marginBottom: toast.body ? 6 : 0 }}>
                {toast.title}
            </div>
            {toast.body && (
                <div style={{ fontSize: 13, color: "var(--text-2)", lineHeight: 1.45 }}>{toast.body}</div>
            )}
        </div>
    );
}
