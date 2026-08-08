interface Props { checked: boolean; onChange: (v: boolean) => void; disabled?: boolean; }

export default function ToggleSwitch({ checked, onChange, disabled }: Props) {
    return (
        <label style={{ position: "relative", width: 38, height: 21, flexShrink: 0, cursor: disabled ? "not-allowed" : "pointer", opacity: disabled ? 0.5 : 1, display: "inline-block" }}>
            <input
                type="checkbox"
                checked={checked}
                onChange={e => onChange(e.target.checked)}
                disabled={disabled}
                style={{ opacity: 0, width: 0, height: 0, position: "absolute" }}
            />
            <span style={{ position: "absolute", inset: 0, background: checked ? "var(--gold)" : "var(--line-strong)", borderRadius: 20, transition: "background .15s" }} />
            <span style={{ position: "absolute", top: 2, left: checked ? 19 : 2, width: 17, height: 17, borderRadius: "50%", background: checked ? "#16110a" : "var(--text-2)", transition: "left .15s, background .15s" }} />
        </label>
    );
}
