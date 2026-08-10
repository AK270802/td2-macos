import React, { useState, useEffect } from "react";
import ReactDOM from "react-dom/client";
import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import "./styles/tokens.css";
import { AuthProvider, useAuth } from "./hooks/useAuth";
import { ToastProvider } from "./components/Toast";
import LoginPage from "./pages/Login";
import ConsentPage from "./pages/Consent";
import MainPage from "./pages/Main";
import MiniWidget from "./windows/MiniWidget";
import IdleWarning from "./windows/IdleWarning";

/** Window label from the URL only — cheap, synchronous, matches windowLabel() below. */
function labelForLogging(): string {
    return new URLSearchParams(window.location.search).get("window") || "main";
}

/**
 * Secondary windows (mini widget, idle warning) have no visible console —
 * a JS crash there just renders blank with no way to tell why short of
 * manually opening devtools at the right moment. Mirror both render-time
 * errors (React error boundary) and errors outside the render path
 * (rejected promises, thrown errors in event handlers/effects — neither of
 * which an error boundary catches) to stderr, where a `tauri dev` terminal
 * already shows.
 */
function reportFrontendError(message: string) {
    console.error(message);
    invoke("log_frontend_error", { window: labelForLogging(), message }).catch(() => {});
}
window.addEventListener("error", (e) => reportFrontendError(e.error?.stack || e.message));
window.addEventListener("unhandledrejection", (e) => {
    const reason = e.reason;
    reportFrontendError(reason instanceof Error ? (reason.stack || reason.message) : String(reason));
});

class ErrorBoundary extends React.Component<{ children: React.ReactNode }, { error: string | null }> {
    constructor(props: any) { super(props); this.state = { error: null }; }
    static getDerivedStateFromError(e: Error) { return { error: e.message }; }
    componentDidCatch(e: Error) { reportFrontendError(e.stack || e.message); }
    render() {
        if (this.state.error) return (
            <div style={{ padding: 32, fontFamily: "var(--wp-font-mono)", color: "var(--red)", background: "var(--bg)", whiteSpace: "pre-wrap", height: "100vh" }}>
                <b>Render error:</b>{"\n"}{this.state.error}
            </div>
        );
        return this.props.children;
    }
}

type ConsentState = "checking" | "required" | "cleared";

function MainWindowApp() {
    const { session, loading } = useAuth();
    const [consent, setConsent] = useState<ConsentState>("checking");
    const [policy, setPolicy] = useState<{ version: number; content: string | null }>({ version: 1, content: null });

    useEffect(() => {
        if (!session) { setConsent("checking"); return; }
        invoke<{ consent_status: string; policy_version: number | null; policy_content: string | null }>("get_consent_status")
            .then(s => {
                // Only an explicit "accepted" (fresh from the server, or
                // cached from a prior successful check) clears the gate —
                // everything else, including a brand new install's
                // "required" fallback, shows the consent screen. Consent is
                // a privacy requirement, not something safe to bypass on
                // ambiguity.
                if (s.consent_status === "accepted") {
                    setConsent("cleared");
                } else {
                    setPolicy({ version: s.policy_version ?? 1, content: s.policy_content });
                    setConsent("required");
                }
            })
            // get_consent_status itself already falls back to a local cache
            // (or "required" with no cache) before ever rejecting — a
            // rejection here means the Tauri command call itself failed
            // (e.g. local db unreadable), which is exactly the case to fail
            // closed on, not silently let through.
            .catch(() => {
                setPolicy({ version: 1, content: null });
                setConsent("required");
            });
    }, [session]);

    if (loading) return <div style={{ background: "var(--bg)", height: "100vh" }} />;
    if (!session) return <LoginPage />;
    if (consent === "checking") return <div style={{ background: "var(--bg)", height: "100vh" }} />;
    if (consent === "required") {
        return <ConsentPage policyVersion={policy.version} policyContent={policy.content} onAccepted={() => setConsent("cleared")} />;
    }
    return <MainPage />;
}

function windowLabel(): string {
    // Primary signal: the `?window=` query param baked into the window's own
    // URL at creation time (windows.rs) — available synchronously from
    // `location.search`, so it can't be affected by any timing race in when
    // Tauri's `getCurrentWindow()` bridge finishes initializing. Falling back
    // to "main" on any failure here would be the worst possible default for
    // a secondary window: it would silently render the entire heavyweight
    // Main/Login/Consent app squeezed into that window's small frame instead
    // of erroring visibly.
    const fromUrl = new URLSearchParams(window.location.search).get("window");
    if (fromUrl) return fromUrl;
    try {
        return getCurrentWindow().label;
    } catch {
        return "main"; // no Tauri bridge at all — browser preview
    }
}

function App() {
    const label = windowLabel();
    if (label === "mini") return <MiniWidget />;
    if (label === "idle_warning") return <IdleWarning />;
    return (
        <AuthProvider>
            <ToastProvider>
                <MainWindowApp />
            </ToastProvider>
        </AuthProvider>
    );
}

ReactDOM.createRoot(document.getElementById("root")!).render(
    <React.StrictMode>
        <ErrorBoundary>
            <App />
        </ErrorBoundary>
    </React.StrictMode>
);
