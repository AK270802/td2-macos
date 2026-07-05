import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-shell";
import ToggleSwitch from "../components/ToggleSwitch";

type Tab = "tracking" | "screenshots" | "notifications";

interface Props { onClose: () => void; }

const selectStyle: React.CSSProperties = {
    padding: "7px 10px",
    borderRadius: 8,
    border: "1px solid var(--line)",
    background: "var(--surface-2)",
    color: "var(--ink)",
    fontSize: 13,
    outline: "none",
    cursor: "pointer",
    fontFamily: "inherit",
};

export default function Settings({ onClose }: Props) {
    const [tab, setTab] = useState<Tab>("tracking");
    const [autostart, setAutostart] = useState(false);
    const [s, setS] = useState({
        track_input: "true",
        idle_threshold_sec: "300",
        track_apps: "true",
        screenshots_enabled: "true",
        screenshot_interval_sec: "300",
        blur_radius: "12",
        idle_alerts_enabled: "true",
        break_reminders_enabled: "true",
        daily_summary_enabled: "false",
        sound_enabled: "true",
    });

    useEffect(() => {
        invoke<Record<string, string>>("get_settings")
            .then(r => { if (r) setS(prev => ({ ...prev, ...r })); })
            .catch(() => {});
        invoke<boolean>("get_autostart")
            .then(v => setAutostart(!!v))
            .catch(() => {});
    }, []);

    const save = (key: string, value: string) => {
        setS(prev => ({ ...prev, [key]: value }));
        invoke("save_settings", { key, value }).catch(() => {});
    };

    const bool = (key: keyof typeof s) => s[key] === "true";
    const toggle = (key: string) => (v: boolean) => save(key, v ? "true" : "false");

    const tabs: { id: Tab; label: string }[] = [
        { id: "tracking", label: "Tracking" },
        { id: "screenshots", label: "Screenshots" },
        { id: "notifications", label: "Notifications" },
    ];

    return (
        <div style={{ width: 640, background: "var(--surface)", borderRadius: "var(--radius)", overflow: "hidden", boxShadow: "var(--shadow)", display: "flex", flexDirection: "column", maxHeight: "88vh" }}>
            {/* Header */}
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "16px 20px", borderBottom: "1px solid var(--line)", flexShrink: 0 }}>
                <span style={{ fontSize: 15, fontWeight: 700, color: "var(--ink)" }}>WorkPulse Settings</span>
                <button
                    onClick={onClose}
                    style={{ width: 28, height: 28, borderRadius: 7, border: "1px solid var(--line)", background: "var(--surface-2)", color: "var(--ink-soft)", display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer", fontSize: 16, lineHeight: 1 }}>
                    ×
                </button>
            </div>

            <div style={{ display: "flex", flex: 1, overflow: "hidden" }}>
                {/* Left tab column */}
                <div style={{ width: 170, borderRight: "1px solid var(--line)", padding: "12px 8px", flexShrink: 0, background: "var(--surface-2)" }}>
                    {tabs.map(t => (
                        <button
                            key={t.id}
                            onClick={() => setTab(t.id)}
                            style={{
                                width: "100%",
                                padding: "9px 12px",
                                borderRadius: 8,
                                border: "none",
                                background: tab === t.id ? "var(--surface)" : "transparent",
                                boxShadow: tab === t.id ? "var(--shadow-sm)" : "none",
                                color: tab === t.id ? "var(--ink)" : "var(--ink-soft)",
                                fontSize: 13,
                                fontWeight: tab === t.id ? 600 : 400,
                                cursor: "pointer",
                                textAlign: "left",
                                marginBottom: 2,
                                transition: "all 0.1s",
                            }}>
                            {t.label}
                        </button>
                    ))}
                </div>

                {/* Right content */}
                <div style={{ flex: 1, overflowY: "auto", padding: "4px 0" }}>
                    {tab === "tracking" && (
                        <>
                            <SettingRow label="Track keyboard & mouse activity" desc="Record input counts to calculate activity levels.">
                                <ToggleSwitch checked={bool("track_input")} onChange={toggle("track_input")} />
                            </SettingRow>
                            <SettingRow label="Idle detection sensitivity" desc="Mark session idle after this period of no input.">
                                <select value={s.idle_threshold_sec} onChange={e => save("idle_threshold_sec", e.target.value)} style={selectStyle}>
                                    <option value="600">Low — 10 min</option>
                                    <option value="300">Medium — 5 min</option>
                                    <option value="120">High — 2 min</option>
                                </select>
                            </SettingRow>
                            <SettingRow label="Track websites & apps" desc="Log active application and browser domain usage.">
                                <ToggleSwitch checked={bool("track_apps")} onChange={toggle("track_apps")} />
                            </SettingRow>
                            <SettingRow label="Launch on startup" desc="Start WorkPulse automatically when you log in to Windows.">
                                <ToggleSwitch
                                    checked={autostart}
                                    onChange={v => {
                                        setAutostart(v);
                                        invoke("set_autostart", { enabled: v }).catch(() => {});
                                    }}
                                />
                            </SettingRow>
                        </>
                    )}

                    {tab === "screenshots" && (
                        <>
                            <SettingRow label="Capture screenshots" desc="Take periodic screenshots during active tracking sessions.">
                                <ToggleSwitch checked={bool("screenshots_enabled")} onChange={toggle("screenshots_enabled")} />
                            </SettingRow>
                            <SettingRow label="Screenshot interval" desc="How often screenshots are captured while tracking.">
                                <select value={s.screenshot_interval_sec} onChange={e => save("screenshot_interval_sec", e.target.value)} style={selectStyle}>
                                    <option value="180">Every 3 min</option>
                                    <option value="300">Every 5 min</option>
                                    <option value="600">Every 10 min</option>
                                </select>
                            </SettingRow>
                            <SettingRow label="Blur screenshots" desc="Apply blur before uploading to protect sensitive content.">
                                <ToggleSwitch
                                    checked={s.blur_radius !== "0"}
                                    onChange={v => save("blur_radius", v ? "12" : "0")}
                                />
                            </SettingRow>
                            <SettingRow label="My Screenshots" desc="View your captured screenshots on the web dashboard.">
                                <button
                                    onClick={() => open("https://app.workpulse.io/screenshots").catch(() => {})}
                                    style={{ fontSize: 12, fontWeight: 600, color: "var(--link)", background: "none", border: "none", cursor: "pointer", padding: 0, textDecoration: "underline" }}>
                                    Open dashboard ↗
                                </button>
                            </SettingRow>
                        </>
                    )}

                    {tab === "notifications" && (
                        <>
                            <SettingRow label="Idle alerts" desc="Notify when the agent detects prolonged inactivity.">
                                <ToggleSwitch checked={bool("idle_alerts_enabled")} onChange={toggle("idle_alerts_enabled")} />
                            </SettingRow>
                            <SettingRow label="Break reminders" desc="Remind you to take regular breaks during long sessions.">
                                <ToggleSwitch checked={bool("break_reminders_enabled")} onChange={toggle("break_reminders_enabled")} />
                            </SettingRow>
                            <SettingRow label="Daily summary popup" desc="Show a summary of your tracked time at end of day.">
                                <ToggleSwitch checked={bool("daily_summary_enabled")} onChange={toggle("daily_summary_enabled")} />
                            </SettingRow>
                            <SettingRow label="Sound on start / stop" desc="Play a short sound when tracking starts or stops.">
                                <ToggleSwitch checked={bool("sound_enabled")} onChange={toggle("sound_enabled")} />
                            </SettingRow>
                        </>
                    )}
                </div>
            </div>
        </div>
    );
}

function SettingRow({ label, desc, children }: { label: string; desc: string; children: React.ReactNode }) {
    return (
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 20, padding: "12px 20px", borderTop: "1px solid var(--line-soft)" }}>
            <div>
                <div style={{ fontSize: 13, fontWeight: 600, color: "var(--ink)", marginBottom: 2 }}>{label}</div>
                <div style={{ fontSize: 12, color: "var(--ink-soft)" }}>{desc}</div>
            </div>
            <div style={{ flexShrink: 0 }}>{children}</div>
        </div>
    );
}