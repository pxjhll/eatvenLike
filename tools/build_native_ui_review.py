"""Build local reference/runtime comparison previews after render_native_ui.gd."""
from pathlib import Path
from html import escape
import argparse
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--references", type=Path, default=ROOT / "_work/pancake_stall/UI图片/ui_review_2026_11_06/references")
parser.add_argument("--output", type=Path, default=ROOT / "output/native-ui")
args = parser.parse_args()
references = sorted(args.references.glob("*.png"))
shots = sorted(path for path in args.output.glob("*.png") if path.stem[:2].isdigit())
if len(references) != 13 or len(shots) != 13:
    raise SystemExit("Expected thirteen references and thirteen native captures")
args.output.mkdir(parents=True, exist_ok=True)
overview = Image.new("RGB", (960, 1844), "#e6dacc")
comparison = Image.new("RGB", (1920, 1844), "#e6dacc")
rows = []
for index, (ref, shot) in enumerate(zip(references, shots)):
    col, row = index % 4, index // 4
    target = Image.open(ref).convert("RGB")
    runtime = Image.open(shot).convert("RGB")
    overview.paste(runtime.resize((240, 427), Image.Resampling.LANCZOS), (col * 240, row * 461 + 28))
    ImageDraw.Draw(overview).text((col * 240 + 8, row * 461 + 7), shot.stem, fill="#57351d")
    for side, source in enumerate((target, runtime)):
        x = col * 480 + side * 240
        comparison.paste(source.resize((240, 427), Image.Resampling.LANCZOS), (x, row * 461 + 28))
        ImageDraw.Draw(comparison).text((x + 8, row * 461 + 7), f"{index + 1:02} " + ("REFERENCE" if side == 0 else "GODOT"), fill="#57351d")
    ref_path = escape(ref.resolve().as_uri())
    shot_path = escape(shot.name)
    rows.append(f"""<section><h2>{escape(ref.stem)}</h2><div class="pair"><figure><figcaption>原始效果图</figcaption><a href="{ref_path}"><img src="{ref_path}" loading="lazy"></a></figure><figure><figcaption>Godot 实际渲染</figcaption><a href="{shot_path}"><img src="{shot_path}" loading="lazy"></a></figure></div></section>""")
overview.save(args.output / "overview.jpg", quality=92)
comparison.save(args.output / "comparison_overview.jpg", quality=92)
html = """<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>13 屏原图与 Godot 对照</title><style>body{margin:0;padding:24px;background:#e9dfd1;color:#57351d;font-family:system-ui,sans-serif}header,main{max-width:1440px;margin:auto}h1{font-size:26px}p{line-height:1.7}section{margin:32px 0 56px}h2{font-size:20px}.pair{display:grid;grid-template-columns:1fr 1fr;gap:18px}figure{margin:0}figcaption{padding:10px;background:#fff3de;border-radius:10px 10px 0 0}img{display:block;width:100%;height:auto}a{color:inherit}header{position:relative}</style><header><h1>原始效果图 / Godot 实际渲染</h1><p>左侧原图，右侧原生 UI。点击图片查看完整分辨率。两侧按相同比例显示，保留原图白边。角色与设备使用已确认的现有资源；价格、经营状态和升级数值来自实际模拟器，画面状态不作伪造。此页用于视觉复核，不代表已经达到逐像素一致。</p><p>分支：codex/native-ui-reference-20261106 · Godot 4.6.1 · 720×1280 实机渲染</p></header><main>""" + "".join(rows) + "</main></html>"
(args.output / "comparison.html").write_text(html, encoding="utf-8")
print(args.output.resolve() / "comparison.html")
