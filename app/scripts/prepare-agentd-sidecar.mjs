// Builds agentd for the host and copies it into app/src-tauri/binaries/
// named with the rustc host target triple, as Tauri's `externalBin`
// (sidecar) mechanism requires. Used by `beforeBuildCommand` for local/dev
// single-arch builds; CI cross-compiles multiple triples and places them
// directly, bypassing this script (see .github/workflows/main.yml).
import { execFileSync } from "node:child_process";
import { copyFileSync, mkdirSync, chmodSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const repoRoot = path.resolve(fileURLToPath(new URL("../..", import.meta.url)));
const binariesDir = path.join(repoRoot, "app", "src-tauri", "binaries");

execFileSync("cargo", ["build", "--release", "-p", "agentd"], { stdio: "inherit", cwd: repoRoot });

const hostLine = execFileSync("rustc", ["-vV"], { cwd: repoRoot }).toString();
const triple = /host:\s*(\S+)/.exec(hostLine)?.[1];
if (!triple) {
  throw new Error("could not determine host target triple from `rustc -vV`");
}

const exeSuffix = triple.includes("windows") ? ".exe" : "";
const src = path.join(repoRoot, "target", "release", `agentd${exeSuffix}`);
const dest = path.join(binariesDir, `agentd-${triple}${exeSuffix}`);

mkdirSync(binariesDir, { recursive: true });
copyFileSync(src, dest);
if (!exeSuffix) {
  chmodSync(dest, 0o755);
}
console.log(`prepared sidecar: ${dest}`);
