# Reference art QA, 2026-10-27

Branch: `codex/tea-reference-art`, based on `main` at `9b2b3c5`.

## Visual acceptance

- [Reconstructed scene versus original, left/right](reference-comparison.png)
- [Independent sprite gallery](reference-assets.png)
- [Full portrait scene](reference-shop.png)
- [Isolated floor](reference-floor-only.png)
- [Character behind solid partition](reference-behind-wall.png)
- [Character in front of partition](reference-in-front-of-wall.png)
- [Clear doorway and separate lintel](reference-doorway.png)
- [360 by 640](reference-small.png)
- [Landscape, full composition fits](reference-landscape.png)
- [Opened from the actual game](reference-in-game.png)

Images were captured from Godot's real OpenGL renderer on Godot 4.6.3, NVIDIA RTX 3060. Inspected all asset silhouettes, transparent margins, independent floor/walls, foreground counter over fox, partition left/right separation, doorway lintel and small/landscape framing. Reference-derived redraws retain the source look and layout but are not pixel-identical extractions; characters currently have one pose each.

The walking probe tests both solid-wall and open-door routes across the wall's floor-contact sorting depth. The doorway frame can cover the top of a tall character while passing behind it, while the aperture remains transparent.

## Automated verification

```sh
godot --headless --path . -s tests/run_all.gd
godot --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/render_reference_art.gd
```

The headless suite passed all 66 cases (64 existing, 2 new): independent occluding nodes and transparent door aperture, a straight bench with uniform scaling and a separate machine workbench, and independently hiding layers without changing placements. The baseline suite reports existing Canvas/ObjectDB/resource shutdown warnings after passing; those warnings were present before this change.

Real-renderer QA reports zero failures. It clicks the actual ART button, checks unchanged business state while previewing, closes through Escape, checks previous pause/visibility restoration, and checks that a running session resumes. It temporarily redirects any application save to a dedicated QA path and restores the original profile/path on completion.

A review reproduced hidden gameplay handling mouse input despite invisibility. The regression test now drags over an actual hidden worker and checks the pending command queue as well as saved business state. It failed before the fix and passed after disabling world/control/hud processing during preview; the previous process modes are restored on close.

The scene incorporates the user's visual corrections: the left preparation bench has no corner and is scaled uniformly, the pot and brewer have a separate support table, and the sealer belt is wider and longer with the correct foreground/background ordering.

## Stage-one boundary

The new art is an in-game static preview. Production, inventory, jobs, customer logic and prices are still rendered by the existing gameplay view outside this preview. The next integration stage will connect the new pieces to the simulation snapshots and provide animation poses and live stock/order displays.
