// Renders installer artwork that reproduces the prototype's install screens
// (EffiLens-macOS-Prototype.html: #dmg 620×400, #installer sidebar) using the
// official logo and the bundled Instrument Serif.
//
// Usage: node render-assets.mjs <mac-os dir> <out dir>
// Writes: dmg-background.png (620×400) + dmg-background@2x.png,
//         pkg-background.png / pkg-background-dark.png (Installer.app, 620×418, bottom-left).
import { chromium } from "playwright";
import { pathToFileURL } from "node:url";
import { mkdirSync, readFileSync } from "node:fs";
import path from "node:path";

const [, , macOS, outDir] = process.argv;
if (!macOS || !outDir) { console.error("usage: node render-assets.mjs <mac-os dir> <out dir>"); process.exit(2); }
mkdirSync(outDir, { recursive: true });

// data: URIs — pages created with setContent() cannot load file:// resources.
const dataURI = (p, mime) => `data:${mime};base64,${readFileSync(path.resolve(macOS, p)).toString("base64")}`;
const logo = dataURI("Resources/Assets.xcassets/BrandMark.imageset/brand-mark.png", "image/png");
const serif = dataURI("Resources/Fonts/InstrumentSerif-Regular.ttf", "font/ttf");
const serifItalic = dataURI("Resources/Fonts/InstrumentSerif-Italic.ttf", "font/ttf");
void pathToFileURL;

const fonts = `
@font-face{font-family:IS;src:url("${serif}")}
@font-face{font-family:IS;font-style:italic;src:url("${serifItalic}")}
*{margin:0;padding:0;box-sizing:border-box}
body{width:100%;height:100%;overflow:hidden;font-family:-apple-system,"SF Pro Text","Helvetica Neue",sans-serif;-webkit-font-smoothing:antialiased}`;

// DMG window body (prototype .dmg-body): navy gradient, gold glow at the
// bottom, serif "Install EffiLens", subtitle, gold arrow between the icon
// slots. Finder draws the real app / Applications icons on top at
// (170,205) and (450,205); the PKG sits at (310,330).
const dmgHTML = `<!doctype html><html><head><style>${fonts}
body{width:620px;height:400px;background:
  radial-gradient(400px 200px at 50% 110%,rgba(213,160,74,.35),transparent),
  linear-gradient(180deg,#a3a6ae,#5d6068);color:#141B2C}
h3{font-family:IS;font-weight:400;font-size:30px;text-align:center;margin-top:26px}
h3 em{font-style:italic;color:#F0C779}
p{text-align:center;color:rgba(20,27,44,.68);margin-top:4px;font-size:13px}
.arrow{position:absolute;left:292px;top:180px;font-size:36px;color:#F0C779}
</style></head><body>
<h3>Install <em>EffiLens</em></h3>
<p>Drag EffiLens to your Applications folder — or use the guided installer.</p>
<div class="arrow">⟶</div>
</body></html>`;

// Installer.app background (bottom-left aligned, under the step sidebar):
// prototype .inst-side — gold tint fading out, official logo near the top.
const pkgHTML = (dark) => `<!doctype html><html><head><style>${fonts}
body{width:620px;height:418px;background:transparent}
.side{position:absolute;left:0;top:0;bottom:0;width:210px;
  background:linear-gradient(170deg,rgba(213,160,74,${dark ? ".22" : ".18"}),transparent 60%)}
.tile{position:absolute;left:22px;bottom:26px;width:70px;height:70px;border-radius:17px;background:#fff;
  box-shadow:0 8px 22px rgba(213,160,74,.35);display:grid;place-items:center}
.tile img{width:62px;height:62px}
</style></head><body><div class="side"></div><div class="tile"><img src="${logo}"></div></body></html>`;

const browser = await chromium.launch();
async function render(html, w, h, file, scale = 1, transparent = false) {
  const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: scale });
  await page.setContent(html, { waitUntil: "load" });
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: path.join(outDir, file), omitBackground: transparent });
  await page.close();
  console.log("wrote", file);
}
await render(dmgHTML, 620, 400, "dmg-background.png", 1);
await render(dmgHTML, 620, 400, "dmg-background@2x.png", 2);
await render(pkgHTML(false), 620, 418, "pkg-background.png", 1, true);
await render(pkgHTML(true), 620, 418, "pkg-background-dark.png", 1, true);
await browser.close();
