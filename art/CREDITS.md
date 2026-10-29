# Graybox assets

The original graybox vector illustrations, sprite sheets and UI icons in this repository were created for eatvenLike. No third-party illustration, animal pack, emoji artwork or stock image is included.

Sources: `art_src/graybox/svg/`. Rebuild sources with `python3 art_src/graybox/generate.py`, then export PNGs with `godot --headless --path . -s art_src/graybox/rasterize.gd`.

Frame sizes, directions, animation frame indices and bottom-center anchors are recorded in `art/graybox_manifest.json`. Images are sRGB RGBA, with transparent sprite backgrounds and a maximum sheet dimension of 1280 pixels. Staff sheets have 10 columns × 3 directions; customer sheet has 6 × 3.

Font credits and license are in `art/ui/font_license.txt`. Font glyph subsetting changes only coverage, not letter design.

## Tea reference reconstruction

`art/reference/` is a separate art set derived from the image supplied by the user on 2026-10-27. Built-in imagegen extracted/reconstructed independently usable room, wall, furniture, equipment, character and drink layers; native Godot tooling sliced the generated sheets. The original graybox attribution above applies to the original graybox set, not this supplied reference. See `art/reference/README.md` and `art_src/reference/generation_prompts.json` for source and rebuild details.
