# PXJ-26 graybox verification

Godot 4.7 stable; current 2D 3/4 specification. This is a functional graybox, not an approved final art direction. The 45-degree proposal in PXJ-39 is unchanged.

## Automated checks

- `godot --headless --path . --import`
- `godot --headless --path . -s tests/run_all.gd`: **35 cases, zero failures** (32 existing + 3 presentation regressions).
- Presentation regressions cover snapshot immutability and signal rebind/detach, claimed versus unclaimed manual work, and distinct input/output item identities. Both display regressions failed before correction and passed afterward.
- `git diff --check` and the project inspection script passed; `game/` and `content/` are unchanged.

## Real renderer and input

Run `godot --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/render_graybox.gd` with an X11 display. The script uses a fresh in-memory profile, pauses the simulation, advances deterministic time and submits mouse events through Godot's actual input path.

Verified: oven click selection, paid upgrade, paid parallel activation, staff reassignment, and reopening the world view without changing business state. All assertions passed. Rendered with Mesa llvmpipe; this proves desktop visual/input behavior, not mobile GPU performance or touch quality. Virtual-display V-Sync warning is environmental; no script errors occurred in the final render run.

Screen captures: [720×1280 shop](pxj26-whitebread.png), [parallel line](pxj26-parallel.png), [540×960](pxj26-small.png), [1280×720](pxj26-landscape.png), [resource gallery](pxj26-assets.png). Landscape keeps the portrait playfield centered; it does not introduce a separate landscape layout.

![White-bread graybox](pxj26-whitebread.png)

## Scope

- Nineteen original transparent PNG assets and corresponding SVG source files; the largest sheet is 1280×480.
- Six workstations, staff animation sheets with idle/walk/work in three directions, one tinted customer sheet, four items and sixteen UI icons.
- Floors, divider/window, belts, item positions, stock stacking, waiting/working indicators, order bubbles, patience arcs, worker activity, income pop and selection feedback.
- Current owned roster and white-bread balance are unchanged. Slicer, cat and additional material assets are visible in the gallery, not silently enabled in the live economy.
- No free placement, hiring, restart, rotation or hint action is invented; the supplied future-action icons have no misleading live buttons. Current fixed-slot gameplay uses the existing command API.
- Broader symptom usability testing remains PXJ-24. New content remains PXJ-35/37. PXJ-26 stays In Progress until the PR is merged and its P0 review is accepted.
