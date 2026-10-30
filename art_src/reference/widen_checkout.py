"""Rebuild checkout.png at its scene aspect (1400 x 280) instead of stretching 620 x 280 by 2.3x.

Three-slice: the left and right ends (legs, corners) are kept at native size; the plain
middle is repeated with a short cross-fade so no seam shows. Run from the project root:
    python3 art_src/reference/widen_checkout.py
"""
from PIL import Image

SRC = "art_src/reference/masters/checkout_620.png"
OUT = "art/reference/checkout.png"
WIDTH = 1400
END = 120          # left / right end caps, legs included
FADE = 48          # cross-fade between repeated middle tiles

src = Image.open(SRC).convert("RGBA")
w, h = src.size
left = src.crop((0, 0, END, h))
right = src.crop((w - END, 0, w, h))
middle = src.crop((END, 0, w - END, h))
out = Image.new("RGBA", (WIDTH, h), (0, 0, 0, 0))
x = END
step = middle.width - FADE
mask = Image.linear_gradient("L").rotate(90).resize((FADE, h))  # 0 -> 255 left to right
while x < WIDTH - END:
    if x == END:
        out.alpha_composite(middle, (x, 0))
    else:
        tile = middle.copy()
        under = out.crop((x, 0, x + FADE, h))
        head = Image.composite(tile.crop((0, 0, FADE, h)), under, mask.transpose(Image.FLIP_LEFT_RIGHT).point(lambda v: 255 - v))
        tile.paste(head, (0, 0))
        out.paste(tile, (x, 0))
    x += step
out.paste(right, (WIDTH - END, 0))
out.paste(left, (0, 0))
out.save(OUT)
