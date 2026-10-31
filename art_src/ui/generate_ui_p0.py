"""Draw the P0 UI art from docs/art/ui-art-list.md: coin, drink icons, order bubble.

Run from the project root:  python3 art_src/ui/generate_ui_p0.py
Everything is drawn at 4x and downsampled, so outlines stay smooth at delivery size.
Style follows the tea-shop reference art: thick dark-brown outline, warm flat fills,
one soft highlight, round openings as flat ellipses (same squash as the tea tin lid).
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parents[2] / "art" / "ui"
SS = 4
INK = (52, 26, 14, 255)
# Rim ellipses use the tea tin lid's height / width, so icons read as the same camera.
RIM = 0.30


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


# ---------------------------------------------------------------- drinks

DRINKS = {
    # name: liquid, liquid shade, toppings, straw colour
    "lemonade": ((246, 196, 72), (226, 160, 40), "lemon", (124, 176, 72)),
    "black_tea": ((170, 84, 40), (136, 60, 28), None, (226, 92, 70)),
    "plain_milk_tea": ((226, 186, 138), (204, 158, 110), None, (226, 92, 70)),
    "pearl_milk_tea": ((226, 186, 138), (204, 158, 110), "pearl", (92, 60, 44)),
    "coconut_milk_tea": ((240, 222, 186), (220, 196, 156), "coconut", (110, 178, 150)),
    "redbean_milk_tea": ((232, 184, 160), (210, 154, 132), "redbean", (196, 70, 64)),
    "taro_milk_tea": ((196, 168, 230), (168, 136, 208), "taro", (130, 90, 190)),
}


def cup_x(y, top, bottom, tw, bw, cx):
    t = (y - top) / (bottom - top)
    return (tw + (bw - tw) * t) / 2


def drink(name, liquid, shade, topping, straw):
    W = H = 72
    img = canvas(W, H)
    d = ImageDraw.Draw(img)
    cx, top, bottom, tw, bw = 36, 22, 66, 44, 32
    lw = 3.2
    # Straw behind the lid, angled to the right.
    d.line(s((cx + 4, top + 2, cx + 13, 4)), fill=INK, width=w(8.6))
    d.line(s((cx + 4, top + 2, cx + 13, 4)), fill=straw + (255,), width=w(4.6))
    body = [(cx - tw / 2, top), (cx + tw / 2, top), (cx + bw / 2, bottom), (cx - bw / 2, bottom)]
    d.polygon([tuple(s(p)) for p in body], fill=liquid + (255,))
    # Shade on the right third.
    shade_poly = [(cx + tw / 2 - 11, top), (cx + tw / 2, top), (cx + bw / 2, bottom), (cx + bw / 2 - 8, bottom)]
    d.polygon([tuple(s(p)) for p in shade_poly], fill=shade + (255,))
    # Toppings sit at the bottom of the cup.
    if topping == "pearl":
        for x, y in [(-11, 60), (-3, 61), (5, 60), (12, 59), (-8, 54), (0, 55), (8, 54), (-14, 53)]:
            if abs(x) + 4 <= cup_x(y, top, bottom, tw, bw, cx):
                ellipse(d, cx + x, y, 4, 4, (60, 34, 24, 255))
                ellipse(d, cx + x - 1.3, y - 1.4, 1.2, 1.2, (150, 110, 90, 255))
    elif topping == "redbean":
        for x, y in [(-10, 60), (-2, 61), (6, 60), (12, 58), (-6, 55), (2, 55), (9, 53), (-13, 54)]:
            if abs(x) + 3 <= cup_x(y, top, bottom, tw, bw, cx):
                d.ellipse(s((cx + x - 3.6, y - 2.6, cx + x + 3.6, y + 2.6)), fill=(132, 40, 38, 255))
                ellipse(d, cx + x - 1.2, y - 1, 1, 0.8, (210, 120, 110, 255))
    elif topping == "coconut":
        for x, y in [(-11, 57), (-2, 59), (7, 57), (-6, 50), (4, 51), (11, 50)]:
            if abs(x) + 4 <= cup_x(y, top, bottom, tw, bw, cx):
                d.rounded_rectangle(s((cx + x - 4, y - 4, cx + x + 4, y + 4)), radius=w(1.6), fill=(255, 255, 248, 235), outline=(196, 180, 150, 255), width=w(1))
    elif topping == "taro":
        for x, y in [(-10, 58), (0, 59), (10, 57), (-5, 51), (6, 51)]:
            if abs(x) + 4 <= cup_x(y, top, bottom, tw, bw, cx):
                d.rounded_rectangle(s((cx + x - 4.5, y - 3.5, cx + x + 4.5, y + 3.5)), radius=w(2.4), fill=(132, 92, 182, 255))
                ellipse(d, cx + x - 1.5, y - 1.5, 1.3, 1, (190, 160, 230, 255))
    elif topping == "lemon":
        ly = 44
        ellipse(d, cx - 4, ly, 9, 9, (255, 240, 140, 255), 2, (214, 160, 20, 255))
        for a in range(0, 360, 60):
                d.line(s((cx - 4, ly, cx - 4 + 7 * math.cos(math.radians(a)), ly + 7 * math.sin(math.radians(a)))), fill=(232, 190, 50, 255), width=w(1.2))
        ellipse(d, cx + 9, 58, 3, 3, (255, 255, 255, 170))
        ellipse(d, cx - 10, 60, 2, 2, (255, 255, 255, 170))
    # Highlight stripe on the left.
    hl = [(cx - tw / 2 + 5, top + 5), (cx - tw / 2 + 9, top + 5), (cx - bw / 2 + 7, bottom - 5), (cx - bw / 2 + 4, bottom - 5)]
    d.polygon([tuple(s(p)) for p in hl], fill=(255, 255, 255, 110))
    # Cup outline.
    d.line([tuple(s(p)) for p in body + [body[0]]], fill=INK, width=w(lw), joint="curve")
    for p in body:
        ellipse(d, p[0], p[1], lw / 2, lw / 2, INK)
    # Sealing film: a flat ellipse rim with the same squash as the tea tin lid.
    rx, ry = tw / 2 + 1.5, (tw / 2 + 1.5) * RIM
    ellipse(d, cx, top, rx, ry, (252, 246, 232, 255), lw)
    ellipse(d, cx - 4, top - 1, rx * 0.45, ry * 0.35, (255, 255, 255, 255))
    # Straw pokes through the film.
    d.line(s((cx + 4, top + 1, cx + 7, top - 5)), fill=INK, width=w(8.6))
    d.line(s((cx + 4, top + 1, cx + 7, top - 5)), fill=straw + (255,), width=w(4.6))
    finish(img, W, H, f"drink_{name}")


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
    for key, (liquid, shade, topping, straw) in DRINKS.items():
        drink(key, liquid, shade, topping, straw)
    bubble()
