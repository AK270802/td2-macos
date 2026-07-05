import { useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useNavigate } from "react-router-dom";

export default function ConsentPage() {
  const [accepted, setAccepted] = useState(false);
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();

  const handleAccept = async () => {
    setLoading(true);
    try {
      await invoke("send_ipc", { cmd: "accept_consent", payload: { policy_version: "1.0" } });
      navigate("/");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{ background: "var(--bg)", minHeight: "100vh", display: "flex", alignItems: "center", justifyContent: "center" }}>
      <div style={{ width: 560, background: "var(--surface)", borderRadius: 20, padding: "40px 44px" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 24 }}>
          <svg width="32" height="32" viewBox="0 0 48 48" fill="none">
            <path d="M4 24 L12 16 L20 28 L28 12 L36 28 L44 20" stroke="#D4A24C" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
          <span style={{ fontSize: 20, fontWeight: 700, color: "var(--ink)" }}>WorkPulse</span>
        </div>

        <h2 style={{ fontSize: 18, fontWeight: 700, color: "var(--ink)", margin: "0 0 8px" }}>
          Activity Monitoring Disclosure
        </h2>
        <p style={{ fontSize: 13, color: "var(--ink-soft)", margin: "0 0 20px" }}>
          Please read the following carefully before continuing.
        </p>

        <div style={{ background: "var(--surface-2)", borderRadius: 10, padding: "18px 20px",
          fontSize: 13, color: "var(--ink-soft)", lineHeight: 1.7, marginBottom: 24,
          maxHeight: 280, overflowY: "auto", border: "1px solid var(--line)" }}>
          <p><strong style={{ color: "var(--ink)" }}>What we monitor</strong></p>
          <p>WorkPulse records the following activity on this device while you are clocked in to a task:</p>
          <ul>
            <li>The name and title of the active application window</li>
            <li>The registered domain (e.g. github.com) of browser tabs — <em>never</em> full URLs, paths, or page content</li>
            <li>Keyboard and mouse event counts (numbers only — key content is never recorded)</li>
            <li>Periodic screenshots of the active window, blurred before storage and transmission</li>
            <li>Time spent idle vs. active</li>
          </ul>
          <p><strong style={{ color: "var(--ink)" }}>What we do not collect</strong></p>
          <ul>
            <li>Keystroke content, passwords, or clipboard data</li>
            <li>Full URLs, page content, or browser history</li>
            <li>Activity outside of active task sessions</li>
            <li>Audio or video</li>
          </ul>
          <p><strong style={{ color: "var(--ink)" }}>How data is used</strong></p>
          <p>Collected data is transmitted securely to your organisation and used solely for workforce productivity reporting. Your employer is the data controller. Contact your IT administrator with questions.</p>
          <p><strong style={{ color: "var(--ink)" }}>Your rights</strong></p>
          <p>You may stop monitoring at any time by stopping your active task session. Data retention policies are set by your organisation.</p>
        </div>

        <label style={{ display: "flex", alignItems: "flex-start", gap: 10, marginBottom: 24, cursor: "pointer" }}>
          <input type="checkbox" checked={accepted} onChange={e => setAccepted(e.target.checked)}
            style={{ marginTop: 2, accentColor: "var(--brass)" }} />
          <span style={{ fontSize: 13, color: "var(--ink-soft)", lineHeight: 1.5 }}>
            I have read and understand the activity monitoring disclosure above and consent to monitoring as described while I am clocked in to a task.
          </span>
        </label>

        <div style={{ display: "flex", gap: 12 }}>
          <button onClick={() => navigate(-1)}
            style={{ flex: 1, padding: "11px", borderRadius: 8, border: "1px solid var(--line)",
              background: "transparent", color: "var(--ink-soft)", fontSize: 14, cursor: "pointer" }}>
            Go Back
          </button>
          <button onClick={handleAccept} disabled={!accepted || loading}
            style={{ flex: 2, padding: "11px", borderRadius: 8, border: "none",
              background: accepted && !loading ? "var(--brass)" : "var(--brass-2)",
              color: "#fff", fontSize: 14, fontWeight: 700,
              cursor: accepted && !loading ? "pointer" : "not-allowed" }}>
            {loading ? "Saving…" : "I Accept & Continue"}
          </button>
        </div>
      </div>
    </div>
  );
}
