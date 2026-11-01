# Art and font credits

`art/reference/` contains independently usable room, furniture, equipment, character and drink layers derived from the reference image supplied by the user on 2026-10-27. Built-in imagegen reconstructed hidden regions; Godot tooling sliced the generated sheets. See `art/reference/manifest.json` for crop and placement metadata. Original sheets and generation prompts were archived outside the repository during the 2026-11-01 cleanup; see `docs/cleanup-2026-11-01.md`.

The rabbit walking animation uses the user's original frames. Copies, source timing and provenance remain in `art_src/rabbit_walk_frames/`; runtime resources are in `art/rabbit_walk_frames/`.

Font credits and the complete license are in `art/ui/font_license.txt`. Glyph subsetting changes only coverage, not letter design. Rebuild the subset with `tools/subset_font.py` and an appropriate licensed source font. The existing font filename is retained so current scenes and scripts keep their resource references.
