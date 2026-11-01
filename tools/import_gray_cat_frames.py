"""Archive exact source PNGs and loop timing; native Godot builds the runtime atlas.

Run: python tools/import_gray_cat_frames.py "E:/Work/小灰猫走路"
Then run art_src/rabbit_walk_frames/build_atlas.gd with the manifest's --source.
Requires Pillow for reading dimensions, alpha and preview GIF timing only.
"""
from pathlib import Path
from PIL import Image
import hashlib
import json
import shutil
import sys

project = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1])
target = project / "art_src/gray_cat_walk_frames"
directions = [("front", "正面"), ("front_right", "正侧45"), ("right", "侧面"),
              ("back_right", "背侧45"), ("back", "背面")]
manifest = {"asset_prefix": "gray_cat_walk", "output": "res://art/gray_cat_walk_frames/",
            "external_source": str(source.resolve()), "frame_size": [256, 256],
            "columns": 7, "rows": 5, "anchor": [128, 247], "visible_height": 240,
            "source_preservation": "Byte-identical PNG copies; fixed canvas; no redraw, recolor, resize or per-frame recenter.",
            "directions": []}
sheet = Image.new("RGBA", (1792, 1280), (246, 241, 229, 255))
for row, (key, label) in enumerate(directions):
    folder = source / f"小灰猫{label}走关键帧"
    files = sorted(folder.glob("*.png"))
    assert len(files) == 7, f"Expected seven source PNGs: {folder}"
    preview = next(folder.glob("*_256x256.gif"))
    durations = []
    with Image.open(preview) as gif:
        for index in range(gif.n_frames):
            gif.seek(index)
            durations.append(gif.info["duration"])
    assert len(durations) == len(files)
    images = [Image.open(path).convert("RGBA") for path in files]
    assert all(image.size == (256, 256) for image in images)
    first, last = (list(image.get_flattened_data()) for image in (images[0], images[-1]))
    equal = all(a[3] == b[3] and (a[3] == 0 or a[:3] == b[:3]) for a, b in zip(first, last))
    kept = list(range(1, len(files) + (0 if equal else 1)))
    out = target / "frames" / key
    out.mkdir(parents=True, exist_ok=True)
    records = []
    heights = []
    for index, (path, image) in enumerate(zip(files, images), 1):
        destination = out / f"{index:02d}.png"
        shutil.copy2(path, destination)
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        assert hashlib.sha256(destination.read_bytes()).hexdigest() == digest
        box = image.getchannel("A").point(lambda a: 255 if a >= 32 else 0).getbbox()
        heights.append(box[3] - box[1])
        records.append({"index": index, "source_name": path.name, "sha256": digest, "alpha_bbox_32": box})
        if index in kept:
            sheet.alpha_composite(image, ((index - 1) * 256, row * 256))
    notes = target / "source_notes"
    notes.mkdir(parents=True, exist_ok=True)
    shutil.copy2(folder / "关键帧说明.txt", notes / f"{key}.txt")
    manifest["directions"].append({"key": key, "animation": f"walk_{key}", "row": row,
        "source_folder": folder.name, "source_preview": preview.name, "frame_count": len(files),
        "durations_ms": durations, "cycle_ms": sum(durations[i - 1] for i in kept),
        "kept_frames": kept, "removed_frames": [7] if equal else [], "first_last_pixel_equal": equal,
        "endpoint_policy": "Remove only a visually identical terminal pose; keep distinct gait samples and interior holds.",
        "visible_height_range": [min(heights), max(heights)], "frames": records})
(target / "frames/.gdignore").write_text("", encoding="utf-8")
(target / "source_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
qa = project / ".godot/gray_cat_capture"
qa.mkdir(parents=True, exist_ok=True)
sheet.save(qa / "source-contact-sheet.png")
print(json.dumps([{key: row[key] for key in ("key", "cycle_ms", "kept_frames", "first_last_pixel_equal", "visible_height_range")} for row in manifest["directions"]]))
