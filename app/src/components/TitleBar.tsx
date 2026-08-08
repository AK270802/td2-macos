import { getCurrentWindow } from "@tauri-apps/api/window";
import { invoke } from "@tauri-apps/api/core";
import Wordmark from "./Wordmark";
import { CtrlBtn, MinimizeIcon, MaximizeIcon, CloseIcon } from "./WindowControls";

export default function TitleBar({ onClose }: { onClose: () => void }) {
    const appWindow = getCurrentWindow();

    // Minimize hides the main window and shows the always-on-top mini
    // widget instead of the native taskbar minimize — matching the
    // TimeDoctor2-style workflow where tracking stays visible while you work.
    // Uses a single backend command (rather than hide_main_window +
    // show_mini_widget) so it can skip re-showing the widget if the user
    // explicitly hid it — otherwise "hide" never actually stuck.
    const handleMinimize = async () => {
        await invoke("minimize_to_mini_widget").catch(() => {});
    };

    return (
        <div
            data-tauri-drag-region
            style={{
                height: "var(--title-bar-h)",
                background: "var(--bg-2)",
                borderBottom: "1px solid var(--line)",
                display: "flex",
                alignItems: "center",
                justifyContent: "space-between",
                padding: "0 10px 0 16px",
                flexShrink: 0,
            }}>
            <div data-tauri-drag-region style={{ pointerEvents: "none" }}>
                <Wordmark compact />
            </div>

            <div style={{ display: "flex", alignItems: "center", gap: 2 }}>
                <CtrlBtn title="Mini timer" onClick={() => invoke("show_mini_widget").catch(() => {})}>
                    <svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5">
                        <rect x="1.5" y="5" width="13" height="6" rx="3" />
                    </svg>
                </CtrlBtn>
                <CtrlBtn title="Minimize to mini timer" onClick={handleMinimize}><MinimizeIcon /></CtrlBtn>
                <CtrlBtn title="Maximize" onClick={() => appWindow.toggleMaximize()}><MaximizeIcon /></CtrlBtn>
                <CtrlBtn title="Close" isClose onClick={onClose}><CloseIcon /></CtrlBtn>
            </div>
        </div>
    );
}
