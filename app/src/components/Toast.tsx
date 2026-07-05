import { useEffect, useState } from "react";

export interface ToastMessage { id: string; message: string; type?: "info" | "warning" | "error"; }

interface Props { toasts: ToastMessage[]; onRemove: (id: string) => void; }

const DURATION = 2400;

export default function ToastStack({ toasts, onRemove }: Props) {
  return (
    <div style={{ position: "fixed", bottom: 48, right: 20, display: "flex",
      flexDirection: "column", gap: 8, zIndex: 9999, pointerEvents: "none" }}>
      {toasts.map(t => <Toast key={t.id} toast={t} onRemove={onRemove} />)}
    </div>
  );
}

function Toast({ toast, onRemove }: { toast: ToastMessage; onRemove: (id: string) => void }) {
  const [visible, setVisible] = useState(false);
  useEffect(() => {
    requestAnimationFrame(() => setVisible(true));
    const t = setTimeout(() => { setVisible(false); setTimeout(() => onRemove(toast.id), 200); }, DURATION);
    return () => clearTimeout(t);
  }, [toast.id, onRemove]);

  const bg = toast.type === "error" ? "var(--alert)"
    : toast.type === "warning" ? "var(--amber)"
    : "var(--hero-bg)";

  return (
    <div style={{ background: bg, color: "#fff", padding: "10px 16px", borderRadius: 10,
      fontSize: 13, fontWeight: 500, maxWidth: 320, pointerEvents: "auto",
      boxShadow: "0 4px 16px rgba(0,0,0,0.3)",
      opacity: visible ? 1 : 0, transform: visible ? "translateY(0)" : "translateY(8px)",
      transition: "opacity 0.2s, transform 0.2s" }}>
      {toast.message}
    </div>
  );
}
