# Art and font credits

`art/reference/` contains independently usable room, furniture, equipment, character and drink layers derived from the reference image supplied by the user on 2026-10-27. Built-in imagegen reconstructed hidden regions; Godot tooling sliced the generated sheets. See `art/reference/manifest.json` for crop and placement metadata. Original sheets and generation prompts were archived outside the repository during the 2026-11-01 cleanup; see `docs/cleanup-2026-11-01.md`.

The rabbit walking animation uses the user's original frames. Copies, source timing and provenance remain in `art_src/rabbit_walk_frames/`; runtime resources are in `art/rabbit_walk_frames/`.

Font credits and the complete license are in `art/ui/font_license.txt`. Glyph subsetting changes only coverage, not letter design. Rebuild the subset with `tools/subset_font.py` and an appropriate licensed source font. The existing font filename is retained so current scenes and scripts keep their resource references.

## Audio

The two shop themes and seven interaction cues in `art/audio/` are original compositions and synthesized sounds made for eatvenLike. They use no third-party samples or recordings. The editable score and rendering instructions are in `art_src/audio/render.py`.

## Opening

`art/opening/welcome.png` is the complete welcome image supplied by the user on 2026-11-16. `intro.mp4` and `intro.ogv` are silent runtime transcodes of the user's supplied first intro video; `final_web.png` and `final_native.png` are its exact final decoded frames in the corresponding runtime formats. Original inputs and compression probes remain in the ignored `_work/opening_video_20261116/` directory. `start_button.svg` is a code-drawn button face following the user's reference, with live text rendered using the existing UI font.
