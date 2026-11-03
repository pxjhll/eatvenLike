# FigCraft scene restoration plan

Goal: restore the user's `tea-shop-layout2.figcraft` transforms and grouped unlock visibility to the Godot shop, keeping PNG dimensions and existing production progression.

Source of truth: `art_src/figcraft_layout_2026_11_03/placement.json` and the accompanying original FigCraft file/reference render.

- [x] Add `tests/render_figcraft_layout.gd`: check every imported image corner, texture, opening visibility, staged group unlocks, reset visibility, and render the scene without HUD. Run against the old scene to confirm failures.
- [x] Restore `presentation/reference/shop_art.tscn` image transforms and the remaining downward arrow. Keep gameplay host paths/y-sort anchors; remove the deleted horizontal conveyor artwork. Update `content/tea/art_playtest_layout.gd` dining anchors, work/click points and obstacles to follow the furniture.
- [x] Add group visibility in `presentation/tea_playtest/shop_art_groups.gd`, invoked by the existing scene presenter. Base structure/items/rack always appear. Tea/milk props appear together after the first ingredient purchase. Existing station flags control machines; seal also controls the bag/base and conveyor/arrow. Keep prices, recipes, save schema and production code unchanged.
- [x] Verify source geometry, opening/stage/reset display, native UI interaction and full regression suite. Update outdated geometry fixtures/visual checks that explicitly encode the superseded layout, then save opening and full-layout screenshots.

Implementation ran in this existing branch and workspace without a new worktree. Existing uncommitted work is preserved. An independent read-only review caught the removed legacy press UI entry; it was restored without adding furniture, and a real UI/guide regression now covers stage 5. The reviewer confirmed the finding is resolved.
