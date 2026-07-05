export default function StatusBar() {
    return (
        <div style={{
            height: "var(--status-bar-h)",
            background: "var(--surface)",
            borderTop: "1px solid var(--line)",
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            padding: "0 16px",
            fontSize: 11,
            flexShrink: 0,
        }}>
            <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                <span style={{
                    width: 6,
                    height: 6,
                    borderRadius: "50%",
                    background: "var(--mint)",
                    display: "inline-block",
                    flexShrink: 0,
                }} />
                <span style={{ color: "var(--ink-soft)" }}>Synced just now</span>
            </div>
            <span style={{ color: "var(--ink-faint)" }}>WorkPulse Agent v0.1</span>
        </div>
    );
}