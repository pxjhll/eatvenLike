# Tea Reference Art Implementation Plan

> **For agentic workers:** Execute inline in this chat; the user approved stage one and explicitly requested a new branch.

**Goal:** Deliver independently layered tea shop assets and a static in-game art preview.

**Architecture:** Source sheets are retained under art_src/reference. A native Godot build script slices assets and packs an editable scene. Preview UI runs above the existing game and restores its pause/visibility state on close.

**Tech Stack:** Godot 4 GDScript, built-in imagegen, RGBA PNG.

**Spec:** docs/superpowers/specs/2026-10-27-tea-reference-art.md

## Global constraints

- Branch: codex/tea-reference-art; no changes to main or simulation rules.
- Canvas: 720 by 1280; fit the full composition on wider/taller viewports.
- All occluding furniture and walls are independently editable.
- Door opening and sprite margins retain real transparency.
- Static preview does not stand in for animated gameplay integration.

## Task 1: Source art and asset extraction

- [x] Generate floor, walls, furniture, equipment, characters/drinks and modular belts using the uploaded reference.
- [x] Save source sheets, prompts and deterministic crop rectangles.
- [x] Extract separate PNG files with Godot Image.get_region and save_png.
- [x] Pack individual sprites as editable nodes with floor-contact sorting anchors.

Files: art_src/reference/build_assets.gd, art_src/reference/manifest.json, art/reference/*.png, presentation/reference/shop_art.tscn.

## Task 2: Preview and session isolation

- [x] Add failing contracts for independent partition pieces, transparent door opening, and preview pause/restore without simulation state changes.
- [x] Add presentation/reference/art_preview.gd and art_preview.tscn.
- [x] Add an ART entry to existing controls; preserve the live scene and close on Escape.
- [x] Add floor/wall/furniture/belt/equipment/actor/drink visibility toggles, original-image comparison and an occlusion probe.

Interfaces: Shop.open_art_preview(); preview.closed signal; preview.set_layer_visible(layer, visible); preview.set_occlusion_probe(enabled).

## Task 3: Verification and delivery

- [x] Run import and full headless regression suite.
- [x] Render preview screenshots at 720x1280, 360x640 and 1280x720; inspect layout and alpha edges.
- [x] Capture floor-only, partition occlusion and original comparison artifacts.
- [x] Document launch, rebuild, source provenance and stage-one limitations.

Files: tests/test_reference_art.gd, tests/render_reference_art.gd, docs/qa/reference-*.png, art/reference/README.md.
