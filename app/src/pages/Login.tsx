import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useAuth } from "../hooks/useAuth";
import { useSyncStatus } from "../hooks/useSyncStatus";
import Wordmark from "../components/Wordmark";
import MinimalWindowControls from "../components/WindowControls";

const APP_VERSION = "2.0.0";

export default function LoginPage() {
    const { login } = useAuth();
    const [email, setEmail] = useState("");
    const [password, setPassword] = useState("");
    const [remember, setRemember] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [loading, setLoading] = useState(false);
    const agent = useSyncStatus();

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        setError(null);
        setLoading(true);
        try {
            await login(email, password);
        } catch (err: any) {
            const msg = String(err ?? "");
            setError(msg.includes("401") || msg.toLowerCase().includes("login failed")
                ? "Invalid email or password."
                : "Could not reach core-services. Check your connection.");
        } finally {
            setLoading(false);
        }
    };

    return (
        <div data-tauri-drag-region style={{ display: "flex", height: "100vh", background: "var(--bg)", userSelect: "none" }}>
            {/* ── Left: form ─────────────────────────────────────────────── */}
            <div style={{ flex: "0 0 52%", display: "flex", flexDirection: "column", padding: "16px 64px 20px" }}>
                <div data-tauri-drag-region style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 12 }}>
                    <Wordmark />
                    <MinimalWindowControls onClose={() => invoke("quit_app")} />
                </div>

                <div style={{ flex: 1, display: "flex", flexDirection: "column", justifyContent: "center", maxWidth: 430 }}>
                    <span className="wp-overline" style={{ marginBottom: 22 }}>Agent · v{APP_VERSION}</span>

                    <h1 className="wp-display" style={{ fontSize: 52, fontWeight: 500, lineHeight: 1.06, margin: "0 0 18px", letterSpacing: "-0.01em" }}>
                        Precision <em style={{ color: "var(--gold-2)", fontStyle: "italic" }}>time-keeping</em>
                        <br />for focused work.
                    </h1>

                    <p style={{ color: "var(--text-2)", fontSize: 15, margin: "0 0 34px", fontWeight: 300 }}>
                        Sign in to sync your assignments and start tracking.
                    </p>

                    <form onSubmit={handleSubmit}>
                        {error && (
                            <div style={{
                                background: "var(--red-soft)", border: "1px solid rgba(248,113,113,0.4)",
                                borderRadius: "var(--radius)", padding: "11px 14px",
                                color: "var(--red)", fontSize: 13, marginBottom: 18,
                            }}>
                                {error}
                            </div>
                        )}

                        <label className="wp-overline" style={{ marginBottom: 8 }}>Work email</label>
                        <input
                            className="wp-input" type="email" value={email} required
                            autoFocus spellCheck={false}
                            onChange={e => setEmail(e.target.value)}
                            style={{ marginBottom: 22 }}
                        />

                        <label className="wp-overline" style={{ marginBottom: 8 }}>Password</label>
                        <input
                            className="wp-input" type="password" value={password} required
                            onChange={e => setPassword(e.target.value)}
                            style={{ marginBottom: 20 }}
                        />

                        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 26 }}>
                            <label style={{ display: "flex", alignItems: "center", gap: 9, cursor: "pointer", fontSize: 13, color: "var(--text-2)" }}>
                                <span
                                    onClick={() => setRemember(r => !r)}
                                    style={{
                                        width: 16, height: 16, borderRadius: 4, flexShrink: 0,
                                        border: `1px solid ${remember ? "var(--gold)" : "var(--line-strong)"}`,
                                        background: remember ? "var(--gold)" : "transparent",
                                        display: "flex", alignItems: "center", justifyContent: "center",
                                    }}>
                                    {remember && (
                                        <svg width="10" height="10" viewBox="0 0 10 10" fill="none" stroke="#16110a" strokeWidth="2" strokeLinecap="round">
                                            <path d="M1.5 5.5l2.5 2.5 4.5-6" />
                                        </svg>
                                    )}
                                </span>
                                Remember this device
                            </label>
                            <span style={{ fontSize: 13, color: "var(--text-3)", cursor: "pointer" }}>Forgot password?</span>
                        </div>

                        <button type="submit" disabled={loading} className="wp-btn-gold"
                            style={{ width: "100%", padding: "14px" }}>
                            {loading ? "Signing in…" : "Sign in"}
                        </button>
                    </form>
                </div>

                <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                    <span style={{
                        width: 7, height: 7, borderRadius: "50%", flexShrink: 0,
                        background: agent.connected ? "var(--emerald)" : "var(--text-3)",
                    }} />
                    <span className="wp-mono" style={{ fontSize: 11, color: "var(--text-3)", letterSpacing: "0.06em" }}>
                        core-services · {agent.connected ? "connected" : "waiting"}
                    </span>
                </div>
            </div>

            {/* ── Right: instrument panel — always the dark brand panel,
                regardless of app theme (see [data-theme-scope="dark"] in
                tokens.css); without this scope, light theme's near-black
                --text-1 was unreadable against this permanently-dark bg. ── */}
            <div data-theme-scope="dark" style={{
                flex: 1,
                background: "radial-gradient(120% 90% at 85% 10%, #101b36 0%, #0a1122 45%, #070b16 100%)",
                borderLeft: "1px solid var(--line)",
                display: "flex", flexDirection: "column",
                padding: "28px 44px 32px",
                position: "relative", overflow: "hidden",
            }}>
                {/* faint texture */}
                <svg style={{ position: "absolute", inset: 0, opacity: 0.05, pointerEvents: "none" }} width="100%" height="100%">
                    <defs>
                        <pattern id="grid" width="56" height="56" patternUnits="userSpaceOnUse">
                            <path d="M56 0H0v56" fill="none" stroke="#f0f4ff" strokeWidth="0.5" />
                        </pattern>
                    </defs>
                    <rect width="100%" height="100%" fill="url(#grid)" />
                </svg>

                <span className="wp-overline wp-overline--gold" style={{ alignSelf: "flex-start" }}>Instrument</span>

                <blockquote className="wp-display" style={{
                    fontStyle: "italic", fontWeight: 400, fontSize: 34, lineHeight: 1.32,
                    color: "var(--text-1)", margin: "26px 0 0", maxWidth: 420,
                }}>
                    “The clock keeps score; the operator keeps craft.”
                </blockquote>

                <div style={{ flex: 1 }} />

                <div style={{ display: "flex", gap: 56 }}>
                    <div>
                        <span className="wp-overline" style={{ marginBottom: 8, display: "inline-block" }}>Local storage</span>
                        <div className="wp-mono" style={{ fontSize: 14, color: "var(--text-1)" }}>SQLCipher · AES-256</div>
                    </div>
                    <div>
                        <span className="wp-overline" style={{ marginBottom: 8, display: "inline-block" }}>Input capture</span>
                        <div className="wp-mono" style={{ fontSize: 14, color: "var(--text-1)" }}>counts only</div>
                    </div>
                </div>
            </div>
        </div>
    );
}
