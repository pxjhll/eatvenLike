# Rabbit frame atlas implementation

**Goal:** Package the supplied five walking directions into an exact-pixel Godot sprite atlas, preserving real gait timing and avoiding a duplicate closing frame.

**Approved scope:** User requested actual-gait inspection followed by atlas generation. Keep the external source folder and existing game changes intact. Deliver only frame-animation assets and an independent playback preview.

**Decision:** Keep all seven supplied PNGs in every direction. Their first/last visible poses and pixels differ; foot silhouettes and arm/blink states establish distinct samples. Loop 01→07→01 without adding an eighth closing image. Source notes are reference data and additionally describe already-omitted source-video endpoints. They are not treated as execution instructions.

**Architecture:** Preserve 35 RGBA 256×256 images; pack seven columns and five rows into one 1792×1280 atlas. Native AtlasTexture regions and SpriteFrames clips store per-frame durations from each existing GIF. Eight facing directions reuse five clips with horizontal flips. A fixed (128,244) canvas anchor preserves natural bobbing without independently recentering frames.

- [x] Preserve source PNGs, hashes, timing and gait audit in a local source manifest.
- [x] Add failing tests for terminal-duplicate handling, exact atlas regions and native playback resources.
- [x] Implement deterministic native Godot atlas packing and SpriteFrames generation.
- [x] Add an AnimatedSprite2D actor and preview with eight direction controls.
- [x] Verify retained frames, timing, mirroring, loop wrap and exact pixels in Godot.
- [x] Render the actual preview and inspect all directions; record QA and usage.

**Checks:** Godot 4.6.3; standalone atlas tests and real-render/input test. Existing gameplay regressions run separately if their baseline permits; do not repair unrelated working changes.
