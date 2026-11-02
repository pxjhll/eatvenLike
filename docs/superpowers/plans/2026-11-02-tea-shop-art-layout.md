# Tea shop independent artwork and dining layout implementation plan

**Goal:** Replace the shop furniture/machines with refined orthographic cartoon sprites, shift the front counter upward, add dining furniture and a separate front lemonade-to-lemon-tea station, and submit a PR.

**Architecture:** Keep existing kitchen station IDs and approximate positions. Layer transparent sprites as independent children with contact-point sorting. Keep the existing viewport and use the freed front area for four two-seat tables; extend world height only if necessary. HUD width follows the actual shop width and its top/bottom follow the window. The front lemon station uses its own state and front-staff task, separate from the existing kitchen press.

**Tech Stack:** Godot 4.6.3, GDScript, built-in image_gen, PNG RGBA, Python Pillow for export sizing, GitHub CLI.

**Spec:** User-approved requirements summarized in this conversation, including final exact-size constraint.

## Global constraints
- Work on codex/tea-shop-art-layout, never merge or deploy automatically.
- Existing replacement texture pixel dimensions must remain EXACTLY equal to origin/main versions. Preserve independent sprites, aspect ratios and useful transparent padding.
- All assets use coherent orthographic projection, same elevated viewing angle, warm cartoon styling, crisp dark brown outlines.
- Keep boil=pot, mix=automatic mixer; retain old kitchen press art and function.
- New front lemon station is independent: lemonade -> hand-muddling -> lemon tea.
- All tabletop props, containers, machines, belts and cups are separate from their support tables.
- Two-tier open rack; four two-seat round dining tables; glass divider independently toggleable.
- Existing stash and unrelated worktrees remain untouched.

## Task 1: Independent artwork
Files: art/reference/*.png; art_src/shop_layout_2026_11/manifest.json; tools/export_shop_art.py.
- [x] Record baseline image dimensions and alpha/content bounds.
- [x] Generate one complete isolated transparent asset per object from approved references.
- [x] Export each replacement to exact existing canvas dimensions with uniform scaling and padding. New props receive practical game-density canvases.
- [x] Preserve generation prompts/provenance and visually inspect assets.

## Task 2: Front lemon production
Files: game/tea_playtest/tea_shop_sim.gd, content/tea/front_lemon_table.tres, tests/test_tea_business.gd, tests/test_tea_shop_save.gd; narrowly necessary resource definitions.
Consumes: existing sim job/task and save interfaces, Layout.POINTS.
Produces: independent lemon_front station and front staff tasks. Existing lemon_tea dish now comes from lemonade at the front; banana tea stays on kitchen press.
- [x] Add failing real simulation regressions covering production prerequisites, delivered lemon tea, recall/refund and save/load.
- [x] Implement minimal independent station, inventory reservations, unlock/upgrade UI data and migration.
- [x] Run targeted tests and report integration points to layout worker.

## Task 3: Scene layout and dining presentation
Files: presentation/reference/shop_art.tscn, content/tea/art_playtest_layout.gd, presentation/tea_playtest/tea_playtest.gd, new focused presentation helper(s), tests/test_reference_art.gd, tests/test_tea_playtest.gd, tests/render_shop_layout.gd.
Consumes: existing sprites (same pixel dimensions) and new prop assets; sim lemon_front interface.
Produces: upper front counter, passable work areas, independent front props, dining visuals and optional glass panel.
- [x] Test shifted front service and traversable path; dining fixtures represent available/occupied seats without overlapping queue.
- [x] Preserve approximate kitchen positions, move partition/front counter upward to make room for four table groups. Update all world interaction points and badges together.
- [x] Add independent table/chair sprites, dining occupancy visuals, front lemon station and optional glass toggle.
- [x] Update geometry audit only for intentionally moved/resized nodes and verify click/drag interaction.

## Task 4: Integration, verification and PR
- [x] Import all resources and run tests/run_all.gd (must have no parse/runtime failures).
- [x] Render opening and fully unlocked shop at portrait/small/wide window sizes; inspect PNGs and fix overlap or clipping.
- [x] Verify every replaced PNG width/height against baseline; confirm alpha and standalone exports.
- [x] Review branch for production, save compatibility and scene interaction defects; resolve findings.
- [x] Prepare the tested feature branch, screenshots and validation evidence for the requested PR.
