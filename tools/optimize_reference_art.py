"""Inventory repository art and downsample oversized reference textures with Godot.

256 artwork pixels per nominal 100-unit display cell; never upscale or move nodes.
PNG pixels are processed by Godot, not this script. Source sheets and QA are retained.
"""

import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from datetime import datetime

ROOT = Path(__file__).resolve().parents[1]
SCENE = ROOT / "presentation/reference/shop_art.tscn"
MANIFEST = ROOT / "art_src/reference/manifest.json"
AUDIT = ROOT / "art_src/reference/texture_budget.json"
DENSITY = 256 / 100
IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".svg"}


def png_size(path):
    with path.open("rb") as stream:
        header = stream.read(24)
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"Expected PNG: {path}")
    return struct.unpack(">II", header[16:24])


def sprite_records(text):
    refs = dict((m[2], m[1]) for m in re.finditer(
        r'\[ext_resource[^\n]*path="([^"]+)" id="([^"]+)"', text))
    for match in re.finditer(r'\[node [^\n]+\][\s\S]*?(?=\n\[node |\Z)', text):
        section = match[0]
        if 'type="Sprite2D"' not in section.splitlines()[0]:
            continue
        texture = re.search(r'texture = ExtResource\("([^"]+)"\)', section)
        if not texture:
            continue
        scale = re.search(r'scale = Vector2\(([^,]+), ([^)]+)\)', section)
        position = re.search(r'position = Vector2\(([^,]+), ([^)]+)\)', section)
        name = re.search(r'name="([^"]+)"', section)[1]
        parent = re.search(r'parent="([^"]+)"', section)[1]
        yield {"path": refs[texture[1]], "node": parent + "/" + name,
               "scale": list(map(float, scale.groups())) if scale else [1, 1],
               "position": list(map(float, position.groups())) if position else [0, 0],
               "start": match.start(), "end": match.end(), "section": section}


def inventory():
    rows = []
    for path in sorted(ROOT.rglob("*")):
        relative = path.relative_to(ROOT)
        if any(part in {".git", ".godot"} for part in relative.parts):
            continue
        if path.suffix.lower() not in IMAGE_EXTENSIONS:
            continue
        width, height = png_size(path) if path.suffix.lower() == ".png" else (None, None)
        if path.suffix.lower() == ".svg":
            svg = ET.parse(path).getroot()
            viewbox = svg.get("viewBox", "").split()
            if len(viewbox) == 4:
                width, height = map(float, viewbox[2:])
            else:
                width, height = [float(re.match(r"[\d.]+", svg.get(key, "0"))[0]) for key in ("width", "height")]
        category = ("runtime" if relative.parts[0] == "art" else
                    "source" if relative.parts[0] == "art_src" else "qa")
        rows.append({"path": relative.as_posix(), "category": category,
                     "width": width, "height": height, "bytes": path.stat().st_size})
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    if args.apply and AUDIT.exists():
        raise SystemExit("Optimization audit already exists; retain it and inspect changes before another batch.")
    before = inventory()
    text = SCENE.read_text(encoding="utf-8")
    sprites = list(sprite_records(text))
    uses = {}
    for sprite in sprites:
        uses.setdefault(sprite["path"], []).append(sprite["scale"])
    cat_path = "res://art/reference/cat.png"
    cw, ch = png_size(ROOT / cat_path.removeprefix("res://"))
    uses[cat_path].append([104 / cw, 140 / ch])
    records = {}
    jobs = []
    for resource, scales in sorted(uses.items()):
        relative = resource.removeprefix("res://")
        path = ROOT / relative
        w, h = png_size(path)
        # The largest usage on either axis determines the budget. Preserve aspect ratio.
        factor = min(1.0, max(max(scale) for scale in scales) * DENSITY)
        nw, nh = min(w, math.ceil(w * factor)), min(h, math.ceil(h * factor))
        records[relative] = {"before": [w, h], "after": [nw, nh],
                             "bytes_before": path.stat().st_size,
                             "sha256_before": hashlib.sha256(path.read_bytes()).hexdigest(),
                             "status": "downsampled" if (nw, nh) != (w, h) else "kept",
                             "display_density_before": round(1 / max(max(s) for s in scales), 3)}
        if (nw, nh) != (w, h):
            jobs.append({"path": resource, "width": nw, "height": nh})
    print(json.dumps({"images": len(before), "downsample": len(jobs), "textures": records}, indent=2))
    if not args.apply:
        return

    backup = Path(tempfile.mkdtemp(prefix="eatventure-art-256-"))
    for path in [SCENE, MANIFEST] + [ROOT / p for p, r in records.items() if r["status"] == "downsampled"]:
        target = backup / path.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
    (backup / "inventory-before.json").write_text(json.dumps(before, indent=2), encoding="utf-8")
    # The locally edited table is not reproduced by the older source sheet.
    masters = ROOT / "art_src/reference/masters"
    masters.mkdir(exist_ok=True)
    (masters / ".gdignore").touch()
    shutil.copy2(ROOT / "art/reference/machine_table.png", masters / "machine_table.png")
    with tempfile.TemporaryDirectory(prefix="eatventure-resize-") as directory:
        job_path = Path(directory) / "jobs.json"
        job_path.write_text(json.dumps(jobs), encoding="utf-8")
        subprocess.run([args.godot, "--headless", "--path", str(ROOT), "-s",
                        "art_src/reference/resize_assets.gd", "--", str(job_path)], check=True)
    for path, row in records.items():
        assert list(png_size(ROOT / path)) == row["after"], path
        row["bytes_after"] = (ROOT / path).stat().st_size

    # Patch only Sprite scales. Keep all user/editor changes and existing geometry.
    for sprite in reversed(sprites):
        record = records[sprite["path"].removeprefix("res://")]
        if record["before"] == record["after"]:
            continue
        scale = [sprite["scale"][i] * record["before"][i] / record["after"][i] for i in range(2)]
        section = re.sub(r'scale = Vector2\([^\n]+\)',
                         f"scale = Vector2({scale[0]:.10f}, {scale[1]:.10f})", sprite["section"])
        text = text[:sprite["start"]] + section + text[sprite["end"]:]
    SCENE.write_text(text, encoding="utf-8")
    manifest_text = MANIFEST.read_text(encoding="utf-8")
    manifest = json.loads(manifest_text)
    manifest["texture_budget"] = {"art_pixels_per_cell": 256, "display_units_per_cell": 100,
                                   "mode": "downsample_only_preserve_current_layout"}
    manifest["runtime_sizes"] = {Path(p).stem: r["after"] for p, r in records.items()}
    manifest["asset_overrides"] = {"machine_table": "masters/machine_table.png"}
    extra_keys = ("texture_budget", "runtime_sizes", "asset_overrides")
    extra = json.dumps({key: manifest[key] for key in extra_keys}, indent=2)[2:-2]
    MANIFEST.write_text(manifest_text.rstrip()[:-1].rstrip() + ",\n" + extra + "\n}\n", encoding="utf-8", newline="\n")
    geometry = []
    for sprite in sprites:
        original = records[sprite["path"].removeprefix("res://")]["before"]
        geometry.append({"node": sprite["node"], "position": sprite["position"],
                         "size": [original[i] * sprite["scale"][i] for i in range(2)]})
    AUDIT.write_text(json.dumps({"art_pixels_per_cell": 256, "display_units_per_cell": 100,
                                  "textures": records, "scene_geometry_before": geometry}, indent=2) + "\n", encoding="utf-8")

    after = {row["path"]: row for row in inventory()}
    report_dir = ROOT / "docs/art"
    report_dir.mkdir(exist_ok=True)
    with (report_dir / "resource-inventory-256.csv").open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["path", "category", "width_before", "height_before", "width_after", "height_after", "bytes_before", "bytes_after", "action"])
        for row in before:
            current = after[row["path"]]
            record = records.get(row["path"])
            action = record["status"] if record else "preserved_source_or_qa" if row["category"] != "runtime" else "preserved_atlas_vector_or_legacy"
            writer.writerow([row["path"], row["category"], row["width"], row["height"], current["width"], current["height"], row["bytes"], current["bytes"], action])
    old_pixels = sum(math.prod(r["before"]) for r in records.values())
    new_pixels = sum(math.prod(r["after"]) for r in records.values())
    old_bytes = sum(r["bytes_before"] for r in records.values())
    new_bytes = sum(r["bytes_after"] for r in records.values())
    counts = {category: sum(row["category"] == category for row in before) for category in ("runtime", "source", "qa")}
    report = ["# 现有美术资源整理：每格 256 像素", "",
              f"扫描时间：{datetime.now().astimezone().isoformat(timespec='seconds')}", "",
              f"整理前仓库图片 {len(before)} 个：运行时 {counts['runtime']} 个、源素材 {counts['source']} 个、QA 截图 {counts['qa']} 个。新增保留的机器底桌母版不计入整理前统计。", "",
              "规格：每格 256 美术像素，对应当前基准画面约 100 显示单位，名义缩放 0.390625。当前预览没有正式的逐物体占地定义，本次依据各资源最大实际显示范围估算像素预算，不重排布局、不改变占地。", "",
              "每张图按所有场景引用的最大需求计算，保留纵横比，只缩小、不放大；整数取整误差小于 1 像素。动态遮挡测试角色的额外引用也已计入。现有拉伸通过节点反向补偿保留，本次不重画、不修正旧比例。", "",
              f"分层场景引用 PNG 共 {len(records)} 张，缩小 {len(jobs)} 张，保留 {len(records)-len(jobs)} 张。", "",
              f"上述贴图 PNG 合计：{old_bytes/1048576:.2f} → {new_bytes/1048576:.2f} MiB。", "",
              f"上述贴图 RGBA8 基础像素内存估算：{old_pixels*4/1048576:.2f} → {new_pixels*4/1048576:.2f} MiB；不含引擎额外开销、比较原图和源文件。", "",
              "| 资源 | 原尺寸 | 整理后尺寸 | 处理 |", "|---|---:|---:|---|"]
    for p, r in records.items():
        label = "等比缩小" if r["status"] == "downsampled" else "保留，原图已低于预算"
        report.append(f"| {Path(p).name} | {r['before'][0]}×{r['before'][1]} | {r['after'][0]}×{r['after'][1]} | {label} |")
    report += ["", "旧动画按单帧判断：员工图集为 10×3 帧，顾客图集为 6×3 帧，每帧 128×160；整张 1280×480 并不代表单个角色过大。它们低于新制作标准，保留原尺寸，放大不能补充细节。", "",
               "UI 图集 256×256 内含 64×64 图标；按固定区域取图，保持尺寸。SVG 保留矢量。原始生成图、参考原图 reference.png 和 QA 截图保留；它们不适用每格预算。", "",
               "墙、地板、货架、展示柜和收银台等部分原图分辨率已经低于此预算，后续若要全部达到每格 256 的原生清晰度，需要重新绘制。本次不会插值放大伪造细节。", "",
               f"本机原文件备份：`{backup}`。备份包含本次修改前的 PNG、场景和 manifest。用户编辑后的机器底桌母版另存于 `art_src/reference/masters/machine_table.png`。", "",
               "`manifest.json` 的 runtime_sizes 固定导出尺寸，asset_overrides 保留编辑后的底桌。原有 build_assets.gd --assets 会沿用这些尺寸，避免重新导出大图。场景中的摆放以当前 .tscn 为准，不需要运行场景重建命令。", ""]
    (report_dir / "resource-inventory-256.md").write_text("\n".join(report), encoding="utf-8")
    print(f"Backup: {backup}\nPNG MiB: {old_bytes/1048576:.2f} -> {new_bytes/1048576:.2f}\nRGBA8 MiB: {old_pixels*4/1048576:.2f} -> {new_pixels*4/1048576:.2f}")


if __name__ == "__main__":
    main()
