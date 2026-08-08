import { useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";

/** Shared window-chrome button — used by TitleBar (main) and the minimal
 * controls on pre-auth screens (Login/Consent), which own no TitleBar. */
export function CtrlBtn({ children, title, isClose, onClick }: {
    children: React.ReactNode; title: string; isClose?: boolean; onClick?: () => void;
}) {
    const [hovered, setHovered] = useState(false);
    return (
        <button
            title={title}
            onClick={onClick}
            onMouseEnter={() => setHovered(true)}
            onMouseLeave={() => setHovered(false)}
            style={{
                width: 32, height: 30, borderRadius: 7, border: "none",
                background: hovered ? (isClose ? "var(--red)" : "var(--panel-3)") : "transparent",
                color: hovered && isClose ? "#1b0d0d" : "var(--text-3)",
                display: "flex", alignItems: "center", justifyContent: "center",
                transition: "background 0.1s, color 0.1s",
                padding: 0, flexShrink: 0,
            }}>
            {children}
        </button>
    );
}

export function MinimizeIcon() {
    return <svg width="11" height="2" viewBox="0 0 11 2" fill="currentColor"><rect width="11" height="1.6" rx="0.8" /></svg>;
}
export function MaximizeIcon() {
    return <svg width="11" height="11" viewBox="0 0 11 11" fill="none" stroke="currentColor" strokeWidth="1.4"><rect x=".8" y=".8" width="9.4" height="9.4" rx="2" /></svg>;
}
export function CloseIcon() {
    return (
        <svg width="11" height="11" viewBox="0 0 11 11" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round">
            <path d="M1.5 1.5l8 8M9.5 1.5l-8 8" />
        </svg>
    );
}

/**
 * Minimize/maximize/close for screens with no timer session yet (Login,
 * Consent) — these render inside the same physical "main" window but had no
 * window controls of their own at all, leaving the window unclosable except
 * via Alt+F4 if agentd wasn't reachable and the app never advanced past them.
 * Minimize here is native OS minimize (no session to show a mini widget
 * for yet); close quits the app outright rather than hiding to tray.
 */
export default function MinimalWindowControls({ onClose }: { onClose: () => void }) {
    const appWindow = getCurrentWindow();
    return (
        <div style={{ display: "flex", alignItems: "center", gap: 2, WebkitAppRegion: "no-drag" } as React.CSSProperties}>
            <CtrlBtn title="Minimize" onClick={() => appWindow.minimize()}><MinimizeIcon /></CtrlBtn>
            <CtrlBtn title="Maximize" onClick={() => appWindow.toggleMaximize()}><MaximizeIcon /></CtrlBtn>
            <CtrlBtn title="Close" isClose onClick={onClose}><CloseIcon /></CtrlBtn>
        </div>
    );
}
