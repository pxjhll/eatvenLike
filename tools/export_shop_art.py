"""Export generated independent sprites onto the game's original pixel canvases."""
import argparse
import json
from pathlib import Path

from PIL import Image


def export(row, baseline):
    destination = Path(row["destination"])
    source = Image.open(row["source"]).convert("RGBA")
    if "crop" in row:
        source = source.crop(row["crop"])
    # Ignore near-invisible compression/alpha dust when fitting independent sprites.
    bbox = source.getchannel("A").point(lambda alpha: 255 if alpha > 16 else 0).getbbox()
    if bbox is None:
        raise ValueError(f"Empty generated sprite: {source.filename}")
    source = source.crop(bbox)
    original = baseline.get(destination.name)
    width, height = original["size"] if original else row["size"]
    bounds = row.get("fit_bounds", original["alpha_bbox"] if original else [int(width * .03), int(height * .03), int(width * .97), int(height * .97)])
    left, top, right, bottom = bounds
    factor = min((right - left) / source.width, (bottom - top) / source.height)
    size = (max(1, round(source.width * factor)), max(1, round(source.height * factor)))
    source = source.resize(size, Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    canvas.alpha_composite(source, (left + (right - left - size[0]) // 2, bottom - size[1]))
    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(destination)
    assert Image.open(destination).size == (width, height)
    return {"asset": destination.as_posix(), "size": [width, height], "source": row["source"]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    data = json.loads(args.manifest.read_text(encoding="utf-8"))
    baseline = json.loads(Path("art_src/shop_layout_2026_11/baseline-sizes.json").read_text(encoding="utf-8"))
    results = [export(row, baseline) for row in data["assets"]]
    if data.get("apply_reference_palette", False):
        from recolor_shop_art import WOOD, recolor
        for asset in ["back_wall", "floor", *WOOD]:
            recolor(asset)
    print(json.dumps(results, ensure_ascii=False, indent=2))
