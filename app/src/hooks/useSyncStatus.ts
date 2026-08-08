import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";

export interface SyncStatus {
    connected: boolean;
    last_sync_ts: number | null;
    last_result: string;
    pending_events: number;
    next_sync_ts: number | null;
    agent_version: string;
}

const OFFLINE: SyncStatus = {
    connected: false, last_sync_ts: null, last_result: "agent offline",
    pending_events: 0, next_sync_ts: null, agent_version: "",
};

/** Real sync telemetry from agentd, refreshed every 5s. */
export function useSyncStatus() {
    const [status, setStatus] = useState<SyncStatus>(OFFLINE);

    useEffect(() => {
        let alive = true;
        const poll = () => {
            invoke<SyncStatus>("send_ipc", { cmd: "get_sync_status" })
                .then(s => { if (alive && s) setStatus(s); })
                .catch(() => { if (alive) setStatus(OFFLINE); });
        };
        poll();
        const id = setInterval(poll, 5000);
        return () => { alive = false; clearInterval(id); };
    }, []);

    return status;
}
