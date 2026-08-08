/** EffiLens logo: ECG glyph in a rounded tile + serif wordmark. */
export default function Wordmark({ compact = false }: { compact?: boolean }) {
    return (
        <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <span style={{
                width: compact ? 26 : 34, height: compact ? 26 : 34,
                borderRadius: compact ? 7 : 9,
                border: "1px solid var(--line-strong)",
                background: "var(--panel)",
                display: "flex", alignItems: "center", justifyContent: "center",
                flexShrink: 0,
            }}>
                <svg width={compact ? 14 : 18} height={compact ? 10 : 13} viewBox="0 0 48 28" fill="none">
                    <path d="M1 14h8l4-9 6 18 6-22 4 13h6l3-5 3 5h6"
                        stroke="var(--text-1)" strokeWidth="2.5" fill="none"
                        strokeLinecap="round" strokeLinejoin="round" />
                </svg>
            </span>
            <span className="wp-display" style={{
                fontSize: compact ? 15 : 18, fontWeight: 600,
                color: "var(--text-1)", letterSpacing: "-0.01em",
            }}>
                EffiLens
            </span>
        </div>
    );
}
