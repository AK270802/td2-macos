import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";

export interface TimerState {
  state: "idle" | "running" | "paused" | "on_break";
  task: { task_id: string; task_name: string; project_name: string } | null;
  elapsed_secs: number;
  break_type: string | null;
  break_remaining_secs: number | null;
}

export function useTimerState() {
  const [timer, setTimer] = useState<TimerState>({ state: "idle", task: null, elapsed_secs: 0, break_type: null });

  useEffect(() => {
    const poll = async () => {
      try {
        const state = await invoke<TimerState>("get_timer_state");
        setTimer(state);
      } catch {}
    };
    poll();
    const id = setInterval(poll, 1000);
    return () => clearInterval(id);
  }, []);

  const togglePlayPause = () => invoke("toggle_play_pause");
  const selectTask = (task_id: string, project_id: string, task_name: string, project_name: string) =>
    invoke("select_task", { task_id, project_id, task_name, project_name });

  return { timer, togglePlayPause, selectTask };
}
