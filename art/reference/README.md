# Tea reference art, stage one

This is a static, layered reconstruction of the user-supplied tea-shop image. Open the normal game and press **ART** in the upper right, or run `presentation/reference/art_preview.tscn` directly (F6). Escape or **Back to game** returns to the existing session. **Layers** toggles individual asset categories and offers a walking occlusion probe. **Original** overlays the supplied source for comparison.

The preview pauses the existing simulation and restores its previous paused/running state. It is a composition review, not the completed live-art integration: drinks, staffing and customer poses in this scene are arranged examples. The normal tea-shop gameplay remains available underneath.

## Editable assets

- `floor.png`: floor only; no walls, tables, belts or stock.
- `back_wall.png`, `outer_left.png`, `outer_right.png`: rear and boundary walls.
- `partition_left.png`, `partition_right.png`, `door_lintel.png`: independent partition/door parts, real transparent doorway.
- `ingredient_table.png`, `prep_bench.png`, `machine_table.png`, `rack.png`, `display_case.png`, `checkout.png`, `register.png`: furniture and checkout props. The preparation bench is straight and preserves its native aspect ratio; the pot and brewer rest on the separate cream workbench.
- `belt_horizontal.png`, `belt_vertical.png`, `belt_corner.png`: separate modular conveyor sections.
- `pearl_pot.png`, `brewer.png`, `sealer.png`, `pearl_jar.png`, `tea_tin.png`, `milk_bottle.png`: equipment and containers.
- `cat.png`, `raccoon.png`, `fox.png`, `squirrel.png`, `hamster.png`: single static character poses.
- `pearl_tea.png`, `fruit_tea.png`, `cream_tea.png`: individual drink sprites.
- `reference.png`: unmodified uploaded source, used only by the comparison toggle.

`presentation/reference/shop_art.tscn` contains 46 separately editable placement nodes. A shared Y-sorted container uses floor contact anchors, including the partition and doorway lintel. Nested rack/counter/display/workbench props remain attached to their parent furniture: hiding a furniture parent also hides its attached props. Source-generation sheets and crop/placement metadata are under `art_src/reference`; they are not runtime imports.

## Rebuild

Runtime textures use a **256 art pixels per nominal 100-unit display cell** budget.
Oversized PNGs are downsampled with Lanczos filtering; existing scene Sprite scales
are compensated so placement, size and occlusion anchors stay the same. This budget
is inferred from the current composition, not a new footprint or layout definition.
Smaller originals are retained without upscaling. Existing nonuniform scaling is
preserved; fixing distorted artwork requires a separate proportion/layout review.

See `docs/art/resource-inventory-256.md` and its CSV for every repository image,
before/after sizes and memory estimates. `art_src/reference/texture_budget.json`
records the geometry before optimization. Source sheets remain unchanged, and
the locally edited support-table master is retained under `art_src/reference/masters`.
`manifest.json` records runtime export sizes and that table's source override, so
extracting the source sheets again preserves the optimized resolution.

**Do not repack the scene to apply a texture change:** `_pack` regenerates placements
from the older manifest and can overwrite manual scene edits. The optimizer patches
only Sprite scales in the existing `.tscn`. The original preview also keeps the
uploaded full-resolution `reference.png` for visual comparison; it is exempt from
the gameplay texture budget, as are source sheets, UI atlases and animation sheets.

Run from the project root with Godot 4:

```sh
godot --headless --path . -s art_src/reference/build_assets.gd -- --assets
godot --headless --path . --import
godot --headless --path . -s art_src/reference/build_assets.gd
```

The native build script losslessly slices the generated sheets into independent RGBA PNGs using `Image.get_region`, then packs the editable scene. Exact crop bounds, placement rectangles and sorting depths are in `art_src/reference/manifest.json`.

`checkout.png` is no longer a straight crop: it is rebuilt at scene aspect (1400 x 280) from
`art_src/reference/masters/checkout_620.png` by `art_src/reference/widen_checkout.py`. Re-extracting the
sheets would bring back the stretched 620 px crop; rerun that script afterwards.

## Provenance and scope

Source: the portrait image supplied by the user in this chat on 2026-10-27. Parts hidden behind animals, text or other props were reconstructed with the built-in imagegen tool; these are reference-based painted derivatives rather than pixel-identical cutouts. No third-party stock pack was substituted. Prompts are archived in `art_src/reference/generation_prompts.json` and `correction_prompts.json`.

The scene retains the reference's pot, brewer and sealing-machine appearance. Connecting these to the existing brewer/mixing/topping business roles is a later integration step; stage one adds no sealing simulation or new economy rules.

Validation artifacts are in `docs/qa/reference-*.png`: full scene, all sprites, original comparison, isolated floor, partition occlusion, doorway, small screen, landscape and live game entry.
