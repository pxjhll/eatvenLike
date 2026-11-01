# Current-frame rabbit skeletal preview

**Approved scope:** User corrected the initial old-branch prototype: both artwork and movement must come from the current 35-frame rabbit. Deliver only a standalone preview; gameplay integration waits for visual approval.

**Latest artwork correction:** User explicitly selected the complete reconstructed 3×3 component sheet. Use that exact right-front PNG and generate the four other complete views from the current frame references. Runtime must use `art/rabbit_skeleton/complete/`, with complete heads and closed-contour components; no hard-cut assembled-frame sections or facial windows. The original frame PNGs remain motion/reference inputs only.

**Architecture:** Godot partitions original source RGBA into editable cutouts. Python measures source-part transforms against all seven poses in each view, preserving original durations. Per the user's correction, each cutout is a Sprite2D parented directly to its Bone2D; animation uses position and rotation only. No whole-character surface, scale animation, joint fillers or seam correction is used. Small original facial patches and external shared AnimationLibraries are retained. The independent viewer synchronizes the source clip, large rig and gameplay-size rig; cup/tool policies stay separate.

- [x] Add a failing source-specific preview test, then build five source-pixel cutout sets and record hashes/crop metadata.
- [x] Fit all35 poses from the actual source PNGs and retain per-frame durations and unequal directional periods.
- [x] Build native rigs with visible rigid cutout sprites and shared motion libraries; remove whole-character skinning and scaling. Verify constant cutout dimensions and zero shear throughout playback. Leave seams for the user to repair.
- [x] Add expression patches with held source timing; verify the near-boundary blink does not change early.
- [x] Add source/rig synchronized viewing, eight facings, gameplay-size comparison, playback controls and both prop policies.
- [x] Verify actual input and GPU renders, including long-to-short direction transitions and source reference mirroring. Fix independent review findings.
- [x] Run source-native tests, original atlas/game-visual tests and the130-case regression suite.
- [x] Save the standalone scene, source comparison images, actual-render GIF and documented limitations.
- [x] Open the standalone preview for user review. Do not change the game actor or main scene.
