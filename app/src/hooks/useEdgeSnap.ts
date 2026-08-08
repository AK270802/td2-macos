import { useEffect, useRef, useState } from "react";
import {
    getCurrentWindow,
    currentMonitor,
    PhysicalPosition,
    PhysicalSize,
} from "@tauri-apps/api/window";

export type SnapSide = "left" | "right" | null;

/** Logical (DPI-independent) dimensions for the two widget layouts. */
export const UNSNAPPED_SIZE = { width: 264, height: 50 };
export const SNAPPED_SIZE = { width: 46, height: 208 };

const SNAP_THRESHOLD = 44; // logical px from a screen edge that triggers a snap
const UNSNAP_THRESHOLD = 130; // logical px dragged away from the edge that releases it — mirrors the original agent's drag-to-unsnap distance
const SETTLE_MS = 160; // treat the window as "at rest" this long after the last move event
// Ignore `onMoved` events for this long after mount. The window's initial
// creation position (wherever the OS/Tauri happens to place it) can land
// well inside the snap threshold by coincidence, and window-manager/DPI
// housekeeping can fire a synthetic "moved" event around creation/show time
// that is NOT a real user drag — evaluating snap logic against either one
// docks the widget (and resizes it) before its webview has even finished
// its first paint, which is what produced the oversized/blank-white widget.
const IGNORE_MOVES_UNTIL_MS = 900;

/**
 * TimeDoctor2-style edge snapping for the mini widget: drag near a screen
 * edge and it docks flush against it as a slim vertical bar; drag it back
 * away and it returns to the compact horizontal pill. Position/size come
 * from Tauri's window APIs directly — there is no CSS-only way to dock a
 * separate OS window, so this owns the actual setPosition/setSize calls.
 */
export function useEdgeSnap(): SnapSide {
    const [snapSide, setSnapSide] = useState<SnapSide>(null);
    const snapSideRef = useRef<SnapSide>(null);
    const settleTimer = useRef<number | null>(null);
    const mountedAt = useRef(Date.now());

    useEffect(() => {
        let alive = true;
        let unlisten: (() => void) | undefined;
        const win = getCurrentWindow();

        const evaluate = async (xPhys: number, yPhys: number) => {
            const monRaw = await currentMonitor();
            if (!monRaw || !alive) return;
            const mon = {
                x: monRaw.position.x, y: monRaw.position.y,
                width: monRaw.size.width, height: monRaw.size.height,
                scale: monRaw.scaleFactor,
            };
            const s = mon.scale;
            const unsnappedWPhys = UNSNAPPED_SIZE.width * s;
            const unsnappedHPhys = UNSNAPPED_SIZE.height * s;
            const snappedWPhys = SNAPPED_SIZE.width * s;
            const snappedHPhys = SNAPPED_SIZE.height * s;
            const thresholdPhys = SNAP_THRESHOLD * s;
            const unsnapPhys = UNSNAP_THRESHOLD * s;

            const monLeft = mon.x;
            const monRight = mon.x + mon.width;

            // Apply the native resize/reposition FIRST and only flip the
            // React state (which switches the rendered layout) once that
            // has actually succeeded — never let the "docked" layout render
            // over a window that's still whatever size it was before.
            const dockTo = async (side: "left" | "right", ySrc: number) => {
                const x = side === "left" ? monLeft : monRight - snappedWPhys;
                const y = Math.min(Math.max(ySrc, mon.y), mon.y + mon.height - snappedHPhys);
                try {
                    await win.setSize(new PhysicalSize(snappedWPhys, snappedHPhys));
                    await win.setPosition(new PhysicalPosition(x, y));
                } catch {
                    return; // native resize failed — stay in the current layout
                }
                if (!alive) return;
                snapSideRef.current = side;
                setSnapSide(side);
            };

            const undock = async (xSrc: number, ySrc: number) => {
                try {
                    await win.setSize(new PhysicalSize(unsnappedWPhys, unsnappedHPhys));
                    await win.setPosition(new PhysicalPosition(xSrc, ySrc));
                } catch {
                    return;
                }
                if (!alive) return;
                snapSideRef.current = null;
                setSnapSide(null);
            };

            if (!snapSideRef.current) {
                const distLeft = xPhys - monLeft;
                const distRight = monRight - (xPhys + unsnappedWPhys);
                if (distLeft <= thresholdPhys) {
                    await dockTo("left", yPhys);
                } else if (distRight <= thresholdPhys) {
                    await dockTo("right", yPhys);
                }
            } else {
                const edgeX = snapSideRef.current === "left" ? monLeft : monRight - snappedWPhys;
                if (Math.abs(xPhys - edgeX) > unsnapPhys) {
                    await undock(xPhys, yPhys);
                }
            }
        };

        (async () => {
            const off = await win.onMoved(({ payload }) => {
                if (Date.now() - mountedAt.current < IGNORE_MOVES_UNTIL_MS) return;
                if (settleTimer.current) window.clearTimeout(settleTimer.current);
                settleTimer.current = window.setTimeout(() => {
                    evaluate(payload.x, payload.y);
                }, SETTLE_MS);
            });
            if (!alive) { off(); return; }
            unlisten = off;
        })();

        return () => {
            alive = false;
            if (settleTimer.current) window.clearTimeout(settleTimer.current);
            unlisten?.();
        };
    }, []);

    return snapSide;
}
