"""Archive new E:/Work animation PNGs without transforming or duplicating existing walks.

python tools/import_work_actions.py E:/Work
Then use build_atlas.gd --source=<manifest folder> --atlas, import, and rebuild without --atlas.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
from PIL import Image

PROJECT = Path(__file__).resolve().parents[1]
DIRECTIONS = [("front", "正面"), ("front_right", "正侧45"), ("right", "侧面"),
              ("back_right", "背侧45"), ("back", "背面")]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def archive(root, name, clips, anchor, height, base=None):
    target = PROJECT / "art_src" / name
    manifest = {"asset_prefix": name, "output": f"res://art/{name}/", "external_source": str(root.resolve()),
                "frame_size": [256, 256], "columns": 14, "rows": len(clips),
                "anchor": anchor, "visible_height": height,
                "source_preservation": "Byte-identical PNG copies. No redraw, recolor, resize, crop or per-frame recenter.",
                "directions": []}
    if base:
        manifest["base_frames"] = base
    for row, (clip, relative) in enumerate(clips):
        folder = root / relative
        files = sorted(folder.glob("*.png"))
        assert files, f"No PNG frames in {folder}"
        manifest["columns"] = max(manifest["columns"], len(files))
        gifs = sorted(folder.glob("*.gif"))
        preview = next((p for p in gifs if "4秒" in p.name), gifs[0])
        with Image.open(preview) as gif:
            durations = []
            for i in range(gif.n_frames):
                gif.seek(i)
                durations.append(gif.info["duration"])
        assert len(durations) == len(files) and all(d > 0 for d in durations)
        images = [Image.open(p).convert("RGBA") for p in files]
        assert all(im.size == (256, 256) for im in images)
        pixels = [im.tobytes() for im in (images[0], images[-1])]
        equal = all(pixels[0][i+3] == pixels[1][i+3] and
                    (not pixels[0][i+3] or pixels[0][i:i+3] == pixels[1][i:i+3])
                    for i in range(0, len(pixels[0]), 4))
        kept = list(range(1, len(files) + (0 if equal else 1)))
        out = target / "frames" / clip
        out.mkdir(parents=True, exist_ok=True)
        records = []
        for i, (p, im) in enumerate(zip(files, images), 1):
            dest = out / f"{i:02d}.png"
            if not dest.exists() or digest(dest) != digest(p):
                shutil.copy2(p, dest)
            records.append({"index": i, "source_name": p.name, "sha256": digest(p),
                            "alpha_bbox_32": im.getchannel("A").point(lambda a: 255 if a >= 32 else 0).getbbox()})
        notes = target / "source_notes"
        notes.mkdir(exist_ok=True)
        for note in folder.glob("*.txt"):
            shutil.copy2(note, notes / f"{clip}.txt")
        manifest["directions"].append({"key": clip, "animation": clip, "row": row,
            "source_mirrored": name == "dog_actions" and clip in ("walk_right", "sit_right", "sit_front_right"),
            "source_folder": relative, "source_preview": preview.name, "frame_count": len(files),
            "durations_ms": durations, "cycle_ms": sum(durations[i-1] for i in kept),
            "kept_frames": kept, "removed_frames": [len(files)] if equal else [],
            "first_last_pixel_equal": equal, "frames": records})
    (target / "frames/.gdignore").write_text("", encoding="utf-8")
    (target / "source_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {"source": f"res://art_src/{name}/", "clips": len(clips),
            "frames": sum(r["frame_count"] for r in manifest["directions"])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    root = parser.parse_args().root
    # Verify every old walk before skipping it, rather than trusting directory names.
    skipped = []
    for name, external in [("rabbit", "小兔子走路"), ("gray_cat", "小灰猫走路")]:
        manifest = json.loads((PROJECT / f"art_src/{name}_walk_frames/source_manifest.json").read_text("utf-8"))
        available = {digest(p) for p in (root / external).rglob("*.png")}
        archived = [f["sha256"] for r in manifest["directions"] for f in r["frames"]]
        assert all(h in available for h in archived), f"Existing {name} walk differs; inspect before replacing"
        skipped.append({"asset": f"{name}_walk", "matching_frames": len(archived), "status": "already integrated; skipped"})
    batches = []
    for name, folder, animal, side, anchor, height in [
        ("rabbit", "小兔子待机", "小兔子", "正侧", [128, 244], 228),
        ("gray_cat", "小灰猫待机", "小灰猫", "侧面", [128, 247], 240),
    ]:
        clips = []
        for key, label in DIRECTIONS:
            label = side if key == "right" else label + ("度" if "45" in label else "")
            clips.append((f"idle_{key}", f"{folder}/{animal}{label}待机"))
        batches.append(archive(root, f"{name}_actions", clips, anchor, height,
                               f"res://art/{name}_walk_frames/{name}_walk_frames.tres"))
    bear = [(f"{action}_{key}", f"{folder}/{animal}{label}{ending}")
            for action, folder, animal, ending in [("walk", "小熊走路", "小熊", "走路"), ("idle", "小熊待机", "小熊猫", "待机")]
            for key, label in DIRECTIONS]
    batches.append(archive(root, "bear_actions", bear, [128, 247], 240))
    customers = {
        "squirrel": [("walk_right", "小松鼠走路/小松鼠侧面走路关键帧"), ("idle_back_right", "小松鼠站立/小松鼠背侧45度待机"), ("sit_right", "小松鼠坐姿/小松鼠坐姿待机")],
        "dog": [("walk_right", "小狗走路/小狗正侧走路"), ("idle_back_right", "小狗站立待机/小狗背侧45站立待机"), ("sit_right", "小狗坐姿/小狗正侧坐姿"), ("sit_front_right", "小狗坐姿/小狗正侧45度坐姿")],
        "sheep": [("walk_right", "小羊走路/小羊侧面走路关键帧"), ("walk_back_right", "小羊走路/小羊背侧45走路关键帧"), ("idle_back_right", "小羊待机/小羊站立待机关键帧"), ("sit_right", "小羊坐姿/小羊侧坐关键帧"), ("sit_front_right", "小羊坐姿/小羊正侧45坐关健帧")],
    }
    for name, clips in customers.items():
        animal = {"squirrel": "小松鼠", "dog": "小狗", "sheep": "小羊"}[name]
        batches.append(archive(root, f"{name}_actions", [(clip, f"顾客备份/{animal}/{path}") for clip, path in clips], [128, 247], 240))
    audit = {"external_source": str(root.resolve()), "skipped": skipped, "imported": batches,
             "excluded": "7z packages duplicate expanded folders. Videos, GIF previews and 1024px concept images are not runtime animation frames."}
    (PROJECT / "art_src/work_actions_inventory.json").write_text(json.dumps(audit, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(audit, ensure_ascii=True, indent=2))


if __name__ == "__main__":
    main()
