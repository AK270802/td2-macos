import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import Wordmark from "../components/Wordmark";
import MinimalWindowControls from "../components/WindowControls";

interface Props {
    policyVersion: number;
    policyContent: string | null;
    onAccepted: () => void;
}

const RECORDS: { title: string; body: string }[] = [
    {
        title: "Active application",
        body: "The name of the foreground application window and how long it stayed foreground. e.g. “figma.exe · 12m”. Window titles are stored locally for context but stripped of anything identified as private before sync.",
    },
    {
        title: "Browser domain",
        body: "When your foreground window is a supported browser, we record the top-level domain only (e.g. github.com), never full URLs, query parameters, or page contents.",
    },
    {
        title: "Input activity",
        body: "The COUNT of keyboard and mouse events per minute — a scalar number. We never capture which keys were pressed, clipboard contents, or on-screen text.",
    },
    {
        title: "Periodic screenshots",
        body: "A blurred screenshot at a fixed interval (default every 10 minutes). Blur is applied on your device before the image ever leaves it; the unblurred image is not stored anywhere.",
    },
];

const NEVERS: { title: string; body: string }[] = [
    {
        title: "Keystroke content",
        body: "Ever. Not stored, not counted, not transmitted. This is a hard engineering guarantee, not a policy.",
    },
    {
        title: "Passwords, banking, personal browsing outside work hours",
        body: "Tracking is only active while you are clocked in. Outside a tracked session the agent captures nothing beyond a heartbeat that says it is running.",
    },
];

export default function ConsentPage({ policyVersion, policyContent, onAccepted }: Props) {
    const [checked, setChecked] = useState(false);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);

    const handleAccept = async () => {
        setLoading(true);
        setError(null);
        try {
            await invoke("accept_consent", { policyVersion });
            onAccepted();
        } catch (e: any) {
            setError("Could not record your consent. Check your connection and try again.");
        } finally {
            setLoading(false);
        }
    };

    const handleDecline = () => {
        invoke("quit_app").catch(() => {});
    };

    return (
        <div style={{ height: "100vh", display: "flex", flexDirection: "column", background: "var(--bg)", userSelect: "none" }}>
            {/* Top bar */}
            <div data-tauri-drag-region style={{
                display: "flex", alignItems: "center", justifyContent: "space-between",
                padding: "14px 28px", flexShrink: 0,
            }}>
                <Wordmark compact />
                <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
                    <span className="wp-mono" style={{ fontSize: 11, color: "var(--text-3)", letterSpacing: "0.08em" }}>
                        Disclosure · v{policyVersion}.0.0
                    </span>
                    <MinimalWindowControls onClose={handleDecline} />
                </div>
            </div>

            {/* Scrollable body */}
            <div style={{ flex: 1, overflowY: "auto", display: "flex", justifyContent: "center" }}>
                <div style={{ width: "100%", maxWidth: 640, padding: "24px 32px 40px" }}>
                    <span className="wp-overline" style={{ marginBottom: 18, display: "inline-block" }}>Before you begin</span>

                    <h1 className="wp-display" style={{ fontSize: 34, fontWeight: 500, lineHeight: 1.2, margin: "0 0 14px", letterSpacing: "-0.01em" }}>
                        What this agent records — and what it does <em style={{ fontStyle: "italic" }}>not</em>.
                    </h1>

                    <p style={{ color: "var(--text-2)", fontSize: 13.5, lineHeight: 1.65, margin: "0 0 28px", fontWeight: 300, maxWidth: 520 }}>
                        EffiLens Agent runs in the background while you work. Your employer receives a
                        summary of your activity to substantiate hours worked. This disclosure is legally
                        significant — please read it in full.
                    </p>

                    {policyContent && (
                        <div className="wp-card" style={{ padding: "16px 20px", marginBottom: 20, fontSize: 13, color: "var(--text-2)", lineHeight: 1.7, whiteSpace: "pre-wrap" }}>
                            {policyContent}
                        </div>
                    )}

                    <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
                        {RECORDS.map(card => (
                            <DisclosureCard key={card.title} kind="record" title={card.title} body={card.body} />
                        ))}
                        {NEVERS.map(card => (
                            <DisclosureCard key={card.title} kind="never" title={card.title} body={card.body} />
                        ))}
                    </div>
                </div>
            </div>

            {/* Sticky footer */}
            <div style={{
                borderTop: "1px solid var(--line)",
                background: "var(--bg-2)",
                padding: "14px 28px",
                display: "flex", alignItems: "center", gap: 16, flexShrink: 0,
            }}>
                <label style={{ display: "flex", alignItems: "center", gap: 10, cursor: "pointer", flex: 1, fontSize: 13, color: "var(--text-2)" }}>
                    <span
                        onClick={() => setChecked(c => !c)}
                        style={{
                            width: 18, height: 18, borderRadius: 4, flexShrink: 0,
                            border: `1px solid ${checked ? "var(--gold)" : "var(--line-strong)"}`,
                            background: checked ? "var(--gold)" : "var(--panel)",
                            display: "flex", alignItems: "center", justifyContent: "center",
                        }}>
                        {checked && (
                            <svg width="11" height="11" viewBox="0 0 10 10" fill="none" stroke="#16110a" strokeWidth="2" strokeLinecap="round">
                                <path d="M1.5 5.5l2.5 2.5 4.5-6" />
                            </svg>
                        )}
                    </span>
                    I have read and understood this disclosure.
                </label>
                {error && <span style={{ fontSize: 12, color: "var(--red)" }}>{error}</span>}
                <button className="wp-btn-ghost" onClick={handleDecline} style={{ padding: "10px 18px" }}>
                    Decline &amp; quit
                </button>
                <button className="wp-btn-gold" onClick={handleAccept} disabled={!checked || loading} style={{ padding: "10px 22px" }}>
                    {loading ? "Saving…" : "I agree — begin"}
                </button>
            </div>
        </div>
    );
}

function DisclosureCard({ kind, title, body }: { kind: "record" | "never"; title: string; body: string }) {
    return (
        <div className="wp-card" style={{ display: "flex", gap: 24, padding: "18px 22px", borderRadius: 14 }}>
            <div style={{ flex: "0 0 168px" }}>
                <span className={`wp-overline ${kind === "record" ? "wp-overline--gold" : "wp-overline--red"}`} style={{ marginBottom: 8, display: "inline-block" }}>
                    {kind === "record" ? "We record" : "We do not"}
                </span>
                <div className="wp-mono" style={{ fontSize: 13, fontWeight: 700, color: "var(--text-1)", lineHeight: 1.45 }}>
                    {title}
                </div>
            </div>
            <p style={{ margin: 0, fontSize: 13, color: "var(--text-2)", lineHeight: 1.65, flex: 1, fontWeight: 300 }}>
                {body}
            </p>
        </div>
    );
}
