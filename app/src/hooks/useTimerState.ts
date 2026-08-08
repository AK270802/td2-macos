import { useState, useEffect, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";

export interface TimerTask {
    task_id: string;
    project_id: string;
    task_name: string;
    project_name: string;
}

export interface IdleWarningInfo {
    started_ts: number;
    idle_secs: number;
}

export interface TimerState {
    state: "idle" | "running" | "paused" | "on_break";
    task: TimerTask | null;
    elapsed_secs: number;
    break_type: string | null;
    break_remaining_secs: number | null;
    idle_warning: IdleWarningInfo | null;
    /** Seconds since the timer last went idle (nothing tracked); null otherwise. */
    idle_since_secs: number | null;
    /** True while the meeting detector judges the user to be on a call. */
    in_meeting: boolean;
    /** false when agentd is unreachable. */
    agent_connected: boolean;
}

const DISCONNECTED: TimerState = {
    state: "idle", task: null, elapsed_secs: 0,
    break_type: null, break_remaining_secs: null,
    idle_warning: null, idle_since_secs: null, in_meeting: false, agent_connected: false,
};

/**
 * Polls agentd timer state (1s). In the main window it also drives the
 * idle-warning window: the warning appears when agentd reports one and
 * closes when it resolves.
 */
export function useTimerState(driveWindows = false) {
    const [timer, setTimer] = useState<TimerState>(DISCONNECTED);
    const warningShown = useRef(false);

    useEffect(() => {
        let alive = true;
        const poll = async () => {
            try {
                const state = await invoke<Omit<TimerState, "agent_connected">>("get_timer_state");
                if (!alive) return;
                setTimer({ ...state, agent_connected: true });

                if (driveWindows) {
                    const hasWarning = !!state.idle_warning;
                    if (hasWarning && !warningShown.current) {
                        warningShown.current = true;
                        invoke("show_idle_warning").catch(() => {});
                    } else if (!hasWarning && warningShown.current) {
                        warningShown.current = false;
                        invoke("close_idle_warning").catch(() => {});
                    }
                }
            } catch {
                if (alive) setTimer(DISCONNECTED);
            }
        };
        poll();
        const id = setInterval(poll, 1000);
        return () => { alive = false; clearInterval(id); };
    }, [driveWindows]);

    const togglePlayPause = () => invoke("toggle_play_pause").catch(() => {});
    const selectTask = (task_id: string, project_id: string, task_name: string, project_name: string) =>
        invoke("select_task", { task_id, project_id, task_name, project_name }).catch(() => {});
    const startBreak = (break_type = "coffee", duration_secs?: number) =>
        invoke("send_ipc", { cmd: "start_break", payload: { break_type, duration_secs } }).catch(() => {});

    return { timer, togglePlayPause, selectTask, startBreak };
}
