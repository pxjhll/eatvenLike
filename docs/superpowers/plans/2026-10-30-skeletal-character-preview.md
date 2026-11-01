# Independent skeletal character preview

**Superseded by user correction:** the recovered old-branch artwork/gait is only a historical trial. The active implementation and review target are described in `2026-10-30-source-rabbit-skeleton-preview.md` and `presentation/rabbit_skeleton/README.md`.

> Execute inline using superpowers:executing-plans. The user approved the design in chat and requested a standalone preview before gameplay integration.

**Goal:** Preview the rabbit's native skeletal animation with eight directions, shared motion resources, and separate fixed-cup / hand-tool attachment policies.

**Architecture:** Recover only the skeletal asset, builder and viewer directories from commit `f2edb7c`. Keep the current gameplay and frame animation paths untouched. Extract each direction's native walk animation into an external AnimationLibrary shared by actor instances; keep bind-pose-specific RESET with its rig. A dedicated prop controller follows either a fixed actor-local anchor or a hand socket, with explicit depth ordering. The standalone viewer owns playback time and comparison controls.

**Tech Stack:** Godot 4.6.3, Skeleton2D, Bone2D, Polygon2D, AnimationPlayer, AnimationLibrary, GDScript.

**Spec:** Accepted conversation design: parallel skeletal workflow; cup stays at a fixed local position; selected tools attach to hands; preview approval precedes gameplay integration.

## Constraints

- No edits to game/, existing frame assets, staff_actor.gd, character_library.gd, project.godot or the current font.
- Recover old resources selectively; do not merge the old branch or overwrite unrelated user changes.
- Existing reconstructed rabbit artwork remains the initial preview artwork. Clearly describe its differences from source frames.
- A fixed cup follows actor movement/facing only, retaining its size and upright orientation. A tool follows the selected hand's position/rotation.
- Animation resources are shared; playback and attachment state remain instance-local.

## Task 1: Recover and verify the native skeletal actor

- [x] Add `tests/test_skeletal_character_preview.gd`, initially checking that the independent skeletal actor resource exists. Run headless and confirm the expected missing-resource failure.
- [x] Recover `art/rabbit_walk/`, `art_src/rabbit_walk/`, `presentation/rabbit_walk/`, and the four old skeletal test scripts from `f2edb7c` using Git object bytes, preserving all current files outside these paths.
- [x] Import assets, then run `tests/test_rabbit_walk.gd` and `tests/test_rabbit_directions.gd` using the installed Godot executable.

## Task 2: Separate shared motion and prop behavior

- [x] Extend the preview test to verify actual motion-resource sharing, instance-local playback, phase retention across all directions, fixed cup anchoring through a gait cycle, hand-tool movement/rotation, prop depth and stable prop state after switching directions. Confirm it fails before implementation.
- [x] Update `art_src/rabbit_walk/build_rig.gd` to emit native `walk` clips and libraries into `art/rabbit_walk/motions/*.tres`. Regenerate all five scenes through the existing builders, preserving the authored animation formulas. This avoids a separate one-off extraction script.
- [x] Update `presentation/rabbit_walk/directional_rabbit.gd` to cache direction rigs and expose phase sampling and hand sockets independently of the frame actor.
- [x] Add `presentation/rabbit_walk/prop_attachment.gd` with `set_prop(id)` and `update_pose()`; create a small editable spoon SVG for the hand-tool example and reuse the existing cup texture.
- [x] Run the behavior checks and both recovered rig tests.

## Task 3: Deliver a reviewable standalone viewer

- [x] Update `presentation/rabbit_walk/animation_viewer.gd` to show a large actor, a synchronized actor at gameplay size, a reference image, native skeleton overlay, and controls for action, direction, phase, speed, ear flexibility and prop policy. Keep playback driven solely by this standalone viewer.
- [x] Add `tests/render_skeletal_character_preview.gd` to exercise actual UI input, native animation and attachments, and save screenshots under `docs/qa/`.
- [x] Run the rendering check using the actual GPU; visually inspect screenshots and correct any overlap, clipping or prop placement issues.
- [x] Restore the old font as a dedicated `art/rabbit_walk/preview_font.ttf` and teach the glyph regression to check that actual font for these preview scripts. Keep the existing gameplay font byte-identical.
- [ ] Run the frame-actor tests and existing full regression suite once after the final changes.
- [ ] Document the preview entry, controls, attachment rules, inherited artwork limitations and verification results in `presentation/rabbit_walk/README.md` and `docs/qa/skeletal-character-preview.md`.
- [ ] Launch only `presentation/rabbit_walk/animation_viewer.tscn` as a separate Godot preview process and leave it available for the user to review.
