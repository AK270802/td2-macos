"""Builds visual-review/index.html: prototype reference vs current app, per
screen and appearance, for human side-by-side review.

Usage: python3 make-index.py <visual-review-dir>
"""
import html
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
ref, cur = root / "reference", root / "current"
names = sorted({p.stem for p in ref.glob("*.png")} | {p.stem for p in cur.glob("*.png")})

rows = []
for name in names:
    def cell(folder: pathlib.Path) -> str:
        f = folder / f"{name}.png"
        if f.exists():
            rel = f.relative_to(root).as_posix()
            return f'<a href="{rel}"><img src="{rel}" loading="lazy"></a>'
        return '<div class="missing">not captured</div>'
    rows.append(f"<tr><th>{html.escape(name)}</th><td>{cell(ref)}</td><td>{cell(cur)}</td></tr>")

page = f"""<!doctype html><meta charset="utf-8"><title>EffiLens visual review</title>
<style>
body{{font:13px -apple-system,system-ui,sans-serif;margin:24px;background:#f4f5f8;color:#141b2c}}
table{{border-collapse:collapse;width:100%}}th,td{{border-bottom:1px solid #ddd;padding:10px;vertical-align:top;text-align:left}}
th{{width:160px;font-weight:600}}img{{max-width:100%;border:1px solid #ccc;border-radius:6px;background:#fff}}
.missing{{color:#b00;padding:40px;text-align:center;border:1px dashed #b00;border-radius:6px}}
</style>
<h1>EffiLens macOS — prototype vs SwiftUI</h1>
<p>Left: approved prototype (rendered from mac-os/Design/EffiLens-macOS-Prototype.html, sample data).
Right: the Debug app in review mode — <b>not signed in</b>, so data areas show real loading / empty / error states.
Brand colours replace the prototype golds (BRAND_SPEC.md).</p>
<table><tr><th>Screen</th><th>Prototype (reference)</th><th>SwiftUI (current)</th></tr>{''.join(rows)}</table>
"""
(root / "index.html").write_text(page, encoding="utf-8")
print(f"index.html: {len(names)} screens")
