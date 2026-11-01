// Renders the approved prototype (mac-os/Design/EffiLens-macOS-Prototype.html)
// into reference screenshots, one per screen and appearance.
// Usage: node prototype-shots.mjs <prototype.html> <out-dir>
import { chromium } from "playwright";
import { pathToFileURL } from "node:url";
import { mkdirSync } from "node:fs";
import path from "node:path";

const [, , protoPath, outDir] = process.argv;
if (!protoPath || !outDir) {
  console.error("usage: node prototype-shots.mjs <prototype.html> <out-dir>");
  process.exit(2);
}
mkdirSync(outDir, { recursive: true });

// App screen name → prototype view key.
const APP_VIEWS = {
  dashboard: "dashboard", tracker: "tracker", projects: "projects", tasks: "tasks",
  history: "history", manualEntry: "manual", leaveOverview: "leave", applyLeave: "apply",
  myRequests: "requests", leaveCalendar: "calendar", leaveBalance: "balance", holidays: "holidays",
  team: "team", approvals: "approvals", reports: "reports", notifications: "notifications",
  activity: "activity", settings: "settings", about: "about",
};
const ONBOARDING = { signin: 0, "onboarding-setup": 1, "onboarding-privacy": 2, "onboarding-permissions": 3 };

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1440, height: 920 }, deviceScaleFactor: 1 });
await page.goto(pathToFileURL(path.resolve(protoPath)).href, { waitUntil: "load" });
await page.waitForTimeout(800);

async function prepare(theme) {
  await page.evaluate((light) => {
    document.body.classList.toggle("light", light);
    ["dmg", "installer", "onboard", "app", "mini"].forEach((id) => { try { hideW(id); } catch (_) {} });
    try { hint(""); } catch (_) {}
    document.querySelector("#popover")?.classList.remove("show");
    document.querySelector("#notifs")?.replaceChildren();
    try { closeDialog(); } catch (_) {}
  }, theme === "light");
}

async function shoot(selector, file) {
  await page.waitForTimeout(700); // let CSS animations settle
  const el = await page.$(selector);
  if (!el) { console.warn(`missing ${selector} for ${file}`); return; }
  await el.screenshot({ path: path.join(outDir, file), animations: "disabled" });
  console.log("wrote", file);
}

for (const theme of ["light", "dark"]) {
  for (const [name, step] of Object.entries(ONBOARDING)) {
    await prepare(theme);
    await page.evaluate((s) => { show("onboard"); obStep = s; renderOb(); }, step);
    await shoot("#onboard", `${name}-${theme}.png`);
  }
  for (const [name, view] of Object.entries(APP_VIEWS)) {
    await prepare(theme);
    await page.evaluate((v) => { S.onboarded = true; show("app"); S.view = v; render(); }, view);
    await shoot("#app", `${name}-${theme}.png`);
  }
  await prepare(theme);
  await page.evaluate(() => { S.onboarded = true; document.querySelector("#popover").classList.add("show"); renderPopover(); });
  await shoot("#popover", `menubar-${theme}.png`);
  await prepare(theme);
  await page.evaluate(() => { S.onboarded = true; show("mini"); updateMini(); });
  await shoot("#mini", `mini-${theme}.png`);
}

await browser.close();
