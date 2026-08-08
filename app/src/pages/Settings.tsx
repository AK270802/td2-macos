import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-shell";
import { getVersion } from "@tauri-apps/api/app";
import ToggleSwitch from "../components/ToggleSwitch";
import { useAuth } from "../hooks/useAuth";
import { useToast } from "../components/Toast";

type Tab = "tracking" | "screenshots" | "notifications" | "appearance" | "about";
type Theme = "dark" | "light";

const THEME_STORAGE_KEY = "wp-theme";

function applyTheme(theme: Theme) {
    document.documentElement.setAttribute("data-theme", theme);
    try { localStorage.setItem(THEME_STORAGE_KEY, theme); } catch { /* private-browsing-style storage block */ }
}

interface Props { onClose: () => void; }

const TAB_ICONS: Record<Tab, React.ReactNode> = {
    tracking: (
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7">
            <circle cx="12" cy="12" r="9" /><path d="M12 7v5l3.2 2" strokeLinecap="round" />
        </svg>
    ),
    screenshots: (
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7">
            <rect x="3" y="5" width="18" height="14" rx="2" /><circle cx="12" cy="12" r="3.2" />
        </svg>
    ),
    notifications: (
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7">
            <path d="M6 9a6 6 0 1 1 12 0c0 3.4 1 5 2 6H4c1-1 2-2.6 2-6Z" strokeLinejoin="round" />
            <path d="M10 19a2 2 0 0 0 4 0" strokeLinecap="round" />
        </svg>
    ),
    appearance: (
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7">
            <circle cx="12" cy="12" r="9" />
            <path d="M12 3a9 9 0 0 0 0 18Z" fill="currentColor" stroke="none" />
        </svg>
    ),
    about: (
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7">
            <circle cx="12" cy="12" r="9" /><path d="M12 11v5.5" strokeLinecap="round" /><circle cx="12" cy="7.7" r="0.9" fill="currentColor" stroke="none" />
        </svg>
    ),
};

export default function Settings({ onClose }: Props) {
    const { session, logout } = useAuth();
    const { toast } = useToast();
    const [tab, setTab] = useState<Tab>("tracking");
    const [autostart, setAutostart] = useState(false);
    const [portalUrl, setPortalUrl] = useState("https://dev-workpulse.baseel.com");
    const [appVersion, setAppVersion] = useState("");
    const [checkingUpdate, setCheckingUpdate] = useState(false);
    const [s, setS] = useState({
        track_input: "true",
        idle_threshold_sec: "300",
        track_apps: "true",
        screenshots_enabled: "true",
        screenshot_interval_sec: "600",
        blur_radius: "8",
        idle_alerts_enabled: "true",
        break_reminders_enabled: "true",
        daily_summary_enabled: "false",
        sound_enabled: "true",
        sync_errors_enabled: "true",
        theme: "dark" as Theme,
    });

    useEffect(() => {
        invoke<Record<string, string>>("get_settings")
            .then(r => {
                if (r) {
                    const { portal_url, theme, ...rest } = r;
                    if (portal_url) setPortalUrl(portal_url);
                    setS(prev => ({ ...prev, ...rest, theme: (theme as Theme) || prev.theme }));
                    // The page already applied localStorage's theme instantly on
                    // load (see index.html) — this just reconciles it with
                    // whatever's persisted server-side, e.g. after a fresh
                    // install with no localStorage yet.
                    if (theme === "light" || theme === "dark") applyTheme(theme as Theme);
                }
            })
            .catch(() => {});
        invoke<boolean>("get_autostart")
            .then(v => setAutostart(!!v))
            .catch(() => {});
        getVersion().then(setAppVersion).catch(() => {});
    }, []);

    const save = (key: string, value: string) => {
        setS(prev => ({ ...prev, [key]: value }));
        invoke("save_settings", { key, value }).catch(() => {});
    };

    const bool = (key: keyof typeof s) => s[key] === "true";
    const toggle = (key: string) => (v: boolean) => save(key, v ? "true" : "false");

    const setTheme = (theme: Theme) => {
        applyTheme(theme);
        save("theme", theme);
    };

    const checkForUpdates = async () => {
        setCheckingUpdate(true);
        try {
            await invoke("check_for_updates");
            // Result (up to date / downloading / failed) arrives as a native
            // OS notification from the backend — this button just needs to
            // show it's working, not duplicate that feedback.
        } catch (e) {
            toast("Update check failed", String(e), "red");
        } finally {
            setCheckingUpdate(false);
        }
    };

    const handleSignOut = () => {
        logout().catch(() => {});
        onClose();
    };

    const tabs: { id: Tab; label: string }[] = [
        { id: "tracking", label: "Tracking" },
        { id: "screenshots", label: "Screenshots" },
        { id: "notifications", label: "Notifications" },
        { id: "appearance", label: "Appearance" },
        { id: "about", label: "About" },
    ];

    return (
        <div className="wp-card" style={{ width: 660, background: "var(--panel-2)", overflow: "hidden", boxShadow: "var(--shadow)", display: "flex", flexDirection: "column", maxHeight: "86vh" }}>
            {/* Header */}
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "18px 22px 14px", borderBottom: "1px solid var(--line)", flexShrink: 0 }}>
                <span className="wp-overline">Agent settings</span>
                <button
                    onClick={onClose}
                    style={{ width: 28, height: 28, borderRadius: 7, border: "1px solid var(--line-strong)", background: "transparent", color: "var(--text-2)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 15, lineHeight: 1 }}>
                    ×
                </button>
            </div>

            <div style={{ display: "flex", flex: 1, overflow: "hidden" }}>
                {/* Tabs */}
                <div style={{ width: 168, borderRight: "1px solid var(--line)", padding: "14px 10px", flexShrink: 0, background: "var(--bg-2)", display: "flex", flexDirection: "column" }}>
                    <div style={{ flex: 1 }}>
                        {tabs.map(t => (
                            <button
                                key={t.id}
                                onClick={() => setTab(t.id)}
                                style={{
                                    width: "100%",
                                    padding: "9px 12px",
                                    borderRadius: 8,
                                    border: "none",
                                    background: tab === t.id ? "var(--panel-3)" : "transparent",
                                    color: tab === t.id ? "var(--gold-2)" : "var(--text-2)",
                                    fontSize: 13,
                                    fontWeight: tab === t.id ? 600 : 400,
                                    textAlign: "left",
                                    marginBottom: 2,
                                    transition: "all 0.1s",
                                    display: "flex",
                                    alignItems: "center",
                                    gap: 9,
                                }}>
                                <span style={{ display: "flex", flexShrink: 0, opacity: tab === t.id ? 1 : 0.7 }}>{TAB_ICONS[t.id]}</span>
                                {t.label}
                            </button>
                        ))}
                    </div>

                    {/* Account footer */}
                    <div style={{ borderTop: "1px solid var(--line)", paddingTop: 12, marginTop: 8 }}>
                        {session && (
                            <div style={{ display: "flex", alignItems: "center", gap: 8, padding: "0 12px 10px", minWidth: 0 }}>
                                <span style={{
                                    width: 26, height: 26, borderRadius: "50%", flexShrink: 0,
                                    background: "var(--gold-soft)", color: "var(--gold-2)",
                                    display: "flex", alignItems: "center", justifyContent: "center",
                                    fontSize: 11, fontWeight: 700,
                                }}>
                                    {session.email.slice(0, 2).toUpperCase()}
                                </span>
                                <span className="wp-mono" style={{ fontSize: 11, color: "var(--text-2)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                                    {session.email}
                                </span>
                            </div>
                        )}
                        <button
                            onClick={handleSignOut}
                            style={{
                                width: "100%", padding: "8px 12px", borderRadius: 8, border: "none",
                                background: "transparent", color: "var(--red)", fontSize: 12.5,
                                fontWeight: 500, textAlign: "left",
                            }}>
                            Sign out
                        </button>
                    </div>
                </div>

                {/* Content */}
                <div style={{ flex: 1, overflowY: "auto", padding: "6px 0" }}>
                    {tab === "tracking" && (
                        <>
                            <SettingRow label="Track keyboard & mouse activity" desc="Record input counts to calculate activity levels. Never key content.">
                                <ToggleSwitch checked={bool("track_input")} onChange={toggle("track_input")} />
                            </SettingRow>
                            <SettingRow label="Track websites & apps" desc="Log the active application and browser domain (eTLD+1 only).">
                                <ToggleSwitch checked={bool("track_apps")} onChange={toggle("track_apps")} />
                            </SettingRow>
                            <SettingRow label="Launch on startup" desc="Start EffiLens automatically when you sign in to this device.">
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
                            <SettingRow label="Capture screenshots" desc="Blurred, active-window-only captures during tracked sessions.">
                                <ToggleSwitch checked={bool("screenshots_enabled")} onChange={toggle("screenshots_enabled")} />
                            </SettingRow>
                            <SettingRow label="My screenshots" desc="Review your captures on the web portal.">
                                <button
                                    onClick={() => open(`${portalUrl}/screenshots`).catch(() => {})}
                                    className="wp-mono"
                                    style={{ fontSize: 12, fontWeight: 500, color: "var(--sky)", background: "none", border: "none", cursor: "pointer", padding: 0 }}>
                                    Open portal ↗
                                </button>
                            </SettingRow>
                        </>
                    )}

                    {tab === "notifications" && (
                        <>
                            <SettingRow label="Idle alerts" desc="Ask whether you're still working after prolonged inactivity.">
                                <ToggleSwitch checked={bool("idle_alerts_enabled")} onChange={toggle("idle_alerts_enabled")} />
                            </SettingRow>
                            <SettingRow label="Break reminders" desc="Remind you to take regular breaks during long sessions.">
                                <ToggleSwitch checked={bool("break_reminders_enabled")} onChange={toggle("break_reminders_enabled")} />
                            </SettingRow>
                            <SettingRow label="Daily summary" desc="Show a summary of your tracked time at end of day.">
                                <ToggleSwitch checked={bool("daily_summary_enabled")} onChange={toggle("daily_summary_enabled")} />
                            </SettingRow>
                            <SettingRow label="Sound on start / stop" desc="Play a short sound when tracking starts or stops.">
                                <ToggleSwitch checked={bool("sound_enabled")} onChange={toggle("sound_enabled")} />
                            </SettingRow>
                            <SettingRow label="Sync errors" desc="Alert when activity data can't be uploaded to the server.">
                                <ToggleSwitch checked={bool("sync_errors_enabled")} onChange={toggle("sync_errors_enabled")} />
                            </SettingRow>
                        </>
                    )}

                    {tab === "appearance" && (
                        <SettingRow label="Theme" desc="Switch between the dark and light Instrument themes.">
                            <div style={{ display: "flex", gap: 6 }}>
                                {(["dark", "light"] as Theme[]).map(t => (
                                    <button
                                        key={t}
                                        onClick={() => setTheme(t)}
                                        style={{
                                            padding: "7px 14px",
                                            borderRadius: 8,
                                            border: `1px solid ${s.theme === t ? "var(--gold-line)" : "var(--line-strong)"}`,
                                            background: s.theme === t ? "var(--gold-soft)" : "transparent",
                                            color: s.theme === t ? "var(--gold-2)" : "var(--text-2)",
                                            fontSize: 12.5,
                                            fontWeight: s.theme === t ? 600 : 400,
                                            textTransform: "capitalize",
                                        }}>
                                        {t}
                                    </button>
                                ))}
                            </div>
                        </SettingRow>
                    )}

                    {tab === "about" && (
                        <>
                            <SettingRow label="Version" desc={appVersion ? `EffiLens ${appVersion}` : "Loading…"}>
                                <button
                                    onClick={checkForUpdates}
                                    disabled={checkingUpdate}
                                    className="wp-btn-ghost"
                                    style={{ padding: "7px 14px" }}>
                                    {checkingUpdate ? "Checking…" : "Check for updates"}
                                </button>
                            </SettingRow>
                            <SettingRow label="Automatic updates" desc="EffiLens checks for a new version every few hours and installs it automatically in the background.">
                                <span className="wp-chip wp-chip--tracking">On</span>
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
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 20, padding: "14px 22px", borderTop: "1px solid var(--line)" }}>
            <div>
                <div style={{ fontSize: 13, fontWeight: 500, color: "var(--text-1)", marginBottom: 3 }}>{label}</div>
                <div style={{ fontSize: 12, color: "var(--text-3)", fontWeight: 300 }}>{desc}</div>
            </div>
            <div style={{ flexShrink: 0 }}>{children}</div>
        </div>
    );
}
