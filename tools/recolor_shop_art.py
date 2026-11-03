"""Apply reference palette corrections without redrawing edges, details or alpha."""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "art_src/shop_layout_2026_11/palette_sources"
WOOD = ["prep_bench", "lemonade_display_table", "rack", "dining_table", "dining_chair_left", "dining_chair_right"]


def recolor(name: str) -> None:
    source = Image.open(SOURCES / (name + ".png"))
    rgba = source.convert("RGBA")
    pixels = []
    samples = rgba.get_flattened_data() if hasattr(rgba, "get_flattened_data") else rgba.getdata()
    for index, (r, g, b, a) in enumerate(samples):
        y = index // rgba.width
        if name == "back_wall":
            # Preserve original light/shadow differences while changing cream plaster to slate blue.
            luminance = .2126 * r + .7152 * g + .0722 * b
            delta = (luminance - 227) * .62
            r, g, b = (round(base + delta) for base in (116, 137, 168))
        elif (name != "floor" or y >= 1110) and r > g * 1.08 and g > b * .97:
            # Warm wood keeps its grain and dark outlines; reduce bright orange saturation.
            r, g, b = round(r * .91), round(g * .94), round(b * 1.14)
        pixels.append((min(255, max(0, r)), min(255, max(0, g)), min(255, max(0, b)), a))
    rgba.putdata(pixels)
    output = rgba.convert(source.mode)
    assert output.size == source.size
    if source.mode == "RGBA":
        assert output.getchannel("A").tobytes() == source.getchannel("A").tobytes()
    output.save(ROOT / "art/reference" / (name + ".png"))
    print(name, source.size, "palette only; alpha and geometry preserved")


if __name__ == "__main__":
    for asset in ["back_wall", "floor", *WOOD]:
        recolor(asset)
