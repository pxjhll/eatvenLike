"""Draw the P0 UI art from docs/art/ui-art-list.md: coin and order bubble.

Run from the project root:  python3 art_src/ui/generate_ui_p0.py
Everything is drawn at 4x and downsampled, so outlines stay smooth at delivery size.
Style follows the tea-shop reference art: thick dark-brown outline, warm flat fills,
one soft highlight, round openings as flat ellipses (same squash as the tea tin lid).
"""
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parents[2] / "art" / "ui"
SS = 4
INK = (52, 26, 14, 255)


def canvas(w, h):
    return Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))


def finish(img, w, h, name):
    img.resize((w, h), Image.LANCZOS).save(OUT / f"{name}.png")


def w(v):
    return max(1, round(v * SS))


def s(v):
    return [c * SS for c in v] if isinstance(v, (list, tuple)) else v * SS


def ellipse(d, cx, cy, rx, ry, fill, width=0, outline=INK):
    d.ellipse(s((cx - rx, cy - ry, cx + rx, cy + ry)), fill=fill, outline=outline if width else None, width=w(width) if width else 0)


# ---------------------------------------------------------------- coin

def coin(size, name, emblem):
    img = canvas(size, size)
    d = ImageDraw.Draw(img)
    u = size / 64.0
    cx, cy, r = 32 * u, 30 * u, 26 * u
    edge = 4 * u
    lw = max(2.2, 3.4 * u)
    # Coin edge (thickness seen from the camera), then the face.
    ellipse(d, cx, cy + edge, r, r, (176, 112, 30, 255), lw)
    d.rectangle(s((cx - r + lw / 2, cy, cx + r - lw / 2, cy + edge)), fill=(176, 112, 30, 255))
    ellipse(d, cx, cy, r, r, (242, 190, 72, 255), lw)
    if emblem:
        ellipse(d, cx, cy, r * 0.70, r * 0.70, (226, 160, 46, 255))
        ellipse(d, cx, cy - 1 * u, r * 0.66, r * 0.66, (247, 204, 96, 255))
        # Tea leaf stamp.
        leaf = [(cx - 7 * u, cy + 7 * u), (cx - 8 * u, cy - 3 * u), (cx - 1 * u, cy - 10 * u), (cx + 9 * u, cy - 9 * u),
                (cx + 8 * u, cy + 1 * u), (cx + 1 * u, cy + 7 * u)]
        d.polygon([tuple(s(p)) for p in leaf], fill=(198, 128, 32, 255))
        d.line(s((cx - 7 * u, cy + 7 * u, cx + 6 * u, cy - 6 * u)), fill=(247, 204, 96, 255), width=w(2.2 * u))
    else:
        ellipse(d, cx, cy, r * 0.62, r * 0.62, (226, 160, 46, 255))
    # Highlight arc on the upper left.
    d.arc(s((cx - r + 4 * u, cy - r + 4 * u, cx + r - 4 * u, cy + r - 4 * u)), 200, 250, fill=(255, 243, 200, 255), width=w(3 * u))
    finish(img, size, size, name)


# ---------------------------------------------------------------- order bubble

def bubble():
    W, H, body_h, radius = 192, 120, 96, 28
    img = canvas(W, H)
    d = ImageDraw.Draw(img)
    lw = 4
    fill, edge, inner = (255, 250, 240, 255), (139, 100, 70, 255), (242, 228, 204, 255)
    # Drop shadow under the box.
    d.rounded_rectangle(s((3, 6, W - 3, body_h)), radius=w(radius), fill=(88, 62, 45, 60))
    d.rounded_rectangle(s((2, 2, W - 2, body_h - 4)), radius=w(radius), fill=fill, outline=edge, width=w(lw))
    # Tail, centred, pointing down; drawn over the outline so the joint is open.
    tail = [(W / 2 - 14, body_h - 8), (W / 2 + 14, body_h - 8), (W / 2, H - 4)]
    d.polygon([tuple(s(p)) for p in tail], fill=fill)
    d.line(s((W / 2 - 14, body_h - 5.6, W / 2, H - 4, W / 2 + 14, body_h - 5.6)), fill=edge, width=w(lw), joint="curve")
    # Soft inner band at the bottom gives the card a little thickness.
    d.rounded_rectangle(s((10, body_h - 20, W - 10, body_h - 10)), radius=w(5), fill=inner)
    d.polygon([tuple(s(p)) for p in [(W / 2 - 12, body_h - 20), (W / 2 + 12, body_h - 20), (W / 2, H - 12)]], fill=inner)
    finish(img, W, H, "bubble")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    coin(64, "coin", True)
    coin(40, "coin_small", False)
    bubble()
