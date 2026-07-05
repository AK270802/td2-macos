import { useState } from "react";
import { useAuth } from "../hooks/useAuth";

export default function LoginPage() {
  const { login } = useAuth();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      await login(email, password);
    } catch (err: any) {
      setError(err?.toString() ?? "Login failed");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{ background: "var(--login-bg)", minHeight: "100vh", display: "flex", alignItems: "center", justifyContent: "center" }}>
      <div style={{ width: 560, background: "var(--surface)", borderRadius: "var(--radius-xl)" }}>
        {/* Brand panel */}
        <div style={{ height: 195, background: "var(--login-brand)", borderRadius: "20px 20px 0 0",
          display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 12 }}>
          <svg width="48" height="48" viewBox="0 0 48 48" fill="none">
            <path d="M4 24 L12 16 L20 28 L28 12 L36 28 L44 20" stroke="#D4A24C" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
          <span style={{ color: "#e2eaf8", fontSize: 22, fontWeight: 700, letterSpacing: -0.5 }}>WorkPulse</span>
          <span style={{ color: "#94A3B8", fontSize: 13 }}>Workforce Intelligence Platform</span>
        </div>

        {/* Form */}
        <form onSubmit={handleSubmit} style={{ padding: "32px 40px 36px" }}>
          <h2 style={{ color: "var(--ink)", fontSize: 20, fontWeight: 700, margin: "0 0 24px" }}>Sign in to your account</h2>

          {error && (
            <div style={{ background: "#FEE2E2", border: "1px solid var(--alert)", borderRadius: 8,
              padding: "10px 14px", color: "var(--alert)", fontSize: 13, marginBottom: 16 }}>
              {error}
            </div>
          )}

          <div style={{ marginBottom: 16 }}>
            <label style={{ display: "block", fontSize: 13, fontWeight: 600, color: "var(--ink-soft)", marginBottom: 6 }}>
              Email address
            </label>
            <input type="email" value={email} onChange={e => setEmail(e.target.value)} required
              style={{ width: "100%", padding: "10px 14px", borderRadius: 8, border: "1px solid var(--line)",
                background: "var(--surface-2)", color: "var(--ink)", fontSize: 14, outline: "none" }}
            />
          </div>

          <div style={{ marginBottom: 24 }}>
            <label style={{ display: "block", fontSize: 13, fontWeight: 600, color: "var(--ink-soft)", marginBottom: 6 }}>
              Password
            </label>
            <input type="password" value={password} onChange={e => setPassword(e.target.value)} required
              style={{ width: "100%", padding: "10px 14px", borderRadius: 8, border: "1px solid var(--line)",
                background: "var(--surface-2)", color: "var(--ink)", fontSize: 14, outline: "none" }}
            />
          </div>

          <button type="submit" disabled={loading}
            style={{ width: "100%", padding: "12px", borderRadius: 8, border: "none",
              background: loading ? "var(--brass-2)" : "var(--brass)", color: "#fff",
              fontSize: 15, fontWeight: 700, cursor: loading ? "not-allowed" : "pointer" }}>
            {loading ? "Signing in…" : "Sign in"}
          </button>
        </form>
      </div>
    </div>
  );
}
