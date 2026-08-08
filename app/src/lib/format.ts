/** Shared formatting helpers for the Instrument UI. */

/** 00:23:11 — always HH:MM:SS, tabular. */
export function formatHMS(secs: number): string {
    const s = Math.max(0, Math.floor(secs));
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const r = s % 60;
    return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:${String(r).padStart(2, "0")}`;
}

/** 4h 37m — for stat tiles. */
export function formatHM(secs: number): string {
    const s = Math.max(0, Math.floor(secs));
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    return `${h}h ${String(m).padStart(2, "0")}m`;
}

/** 46m / 1h 12m — compact durations for feed rows. */
export function formatCompact(secs: number): string {
    const s = Math.max(0, Math.floor(secs));
    if (s < 60) return `${s}s`;
    if (s < 3600) return `${Math.floor(s / 60)}m`;
    return `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m`;
}

/** 09:14 — clock time for the recent feed. */
export function formatClock(tsSecs: number): string {
    const d = new Date(tsSecs * 1000);
    return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

/**
 * Project prefix: first letter + following consonants, 3 chars.
 * APEX → APX, HORIZON → HRZ, MERIDIAN → MRD.
 */
export function projectPrefix(projectName: string): string {
    const clean = (projectName || "PRJ").toUpperCase().replace(/[^A-Z]/g, "");
    if (!clean) return "PRJ";
    let out = clean[0];
    for (let i = 1; i < clean.length && out.length < 3; i++) {
        if (!"AEIOU".includes(clean[i])) out += clean[i];
    }
    for (let i = 1; i < clean.length && out.length < 3; i++) {
        if ("AEIOU".includes(clean[i])) out += clean[i];
    }
    return out.padEnd(3, "X");
}

/** Stable short number from a task UUID, e.g. APX-158. */
export function taskCode(projectName: string, taskId: string): string {
    let h = 0;
    for (let i = 0; i < taskId.length; i++) {
        h = (h * 31 + taskId.charCodeAt(i)) >>> 0;
    }
    return `${projectPrefix(projectName)}-${(h % 199) + 1}`;
}
