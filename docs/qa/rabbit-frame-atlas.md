# Rabbit walking frame atlas — 2026-10-30

Delivered exact source frames as one 1792×1280 RGBA atlas, five native looping SpriteFrames clips and a frame-only eight-direction actor/preview.

Endpoint audit: keep all seven poses in every source direction. First/last visible poses differ in feet, arms or blinking; no exact terminal duplicate exists. Four source notes also document that the video endpoint was already excluded before PNG extraction. No closing copy of frame01 was appended. Preserve original source frame durations (front790ms, front-right960ms, side1000ms, back-right880ms, back750ms).

Validation:

- `tests/test_rabbit_frame_atlas.gd`: 0 failures. Covers terminal-only deduplication, transparent hidden RGB, preserved interior holds, all35 pixel-exact atlas cells including alpha, every frame's original duration, seven retained samples per clip, native loops, phase/pause retention and mirror mapping.
- `tests/render_rabbit_frame_atlas.gd`: 0 failures. Actual NVIDIA OpenGL renderer and mouse events verify controls, native AnimatedSprite2D playback/loop emission, 07→01 wrap, speed, seeking, keyframe stepping, direction changes and small-preview synchronization.
- Existing project regression suite: 126 cases, 0 failures, exit0. Existing intentional save-failure warning and Canvas/ObjectDB/resource cleanup warnings remain.
- Read-only review: no material findings. Reviewer independently checked all35 copied PNG hashes against the external originals and manifest, with no mismatches.

Artifacts: `rabbit-frame-preview.png` is an actual engine capture; `rabbit-frame-directions.gif` shows eight views sampled from the native clip regions at each original period. Each uses the original PNG pixels rather than regenerated artwork.

The fixed256px canvas and anchor preserve original motion. Visible silhouette heights vary211–229px and the back-diagonal source contains an existing fine white fringe; these source properties remain. Gameplay integration is outside this asset task. Existing unrelated working changes were preserved.
