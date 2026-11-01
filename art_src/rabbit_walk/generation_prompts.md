# Rabbit cutout generation

Tool: built-in `image_gen.imagegen`, edit mode, `transparent_background=true`.

## First pass

Input: `reference.png` (the user-supplied turn-around sheet).

```text
Use case: precise-object-edit / identity-preserve. Asset type: game character cutout rig texture atlas. Edit target: attached rabbit turn-around image. Produce a DISASSEMBLED 2D CUTOUT PARTS ATLAS for ONLY THE SECOND rabbit from the left, the PURE RIGHT-FACING SIDE VIEW. Preserve this exact rabbit's identity, cream paper-like soft texture, peach cheek, brown little forehead tuft, warm beige apron, dark brown/near-black thick hand-drawn outlines, original chubby proportions. Actual fully TRANSPARENT background. Square canvas with a precise 3 columns by 3 rows equal-size invisible grid, each part centered in its cell, ample transparent margin, no part crossing a cell boundary. NO grid drawn, NO text, NO labels, NO assembled character, NO additional views, NO shadows behind parts. Nine cells row-major: (1 top-left) complete round side-facing HEAD ONLY with cheek and small black eye looking RIGHT, brown forehead tuft, cute tiny right-facing muzzle; NO ears, NO neck, NO body. Reconstruct the missing ear bases as continuous cream skull outline. (2 top-middle) complete FAR EAR ONLY, upright long rounded cream rabbit ear, slight warm peach shading, complete rounded hidden base; NO head. (3 top-right) complete NEAR EAR ONLY, upright tall rounded cream rabbit ear seen from side, complete hidden rounded base, NO head. (4 middle-left) complete TORSO ONLY, compact pear-shaped cream rabbit body wearing beige apron seen from right side, dark straps and apron side panel, round belly; NO head, NO arms, NO feet, NO tail; reconstruct all hidden areas as complete clean outline. (5 middle-middle) complete FAR ARM ONLY: short soft cream curved capsule hanging down, rounded hidden shoulder, dark thick contour. (6 middle-right) complete NEAR ARM ONLY: chubby cream droplet shaped forelimb hanging down with full rounded hidden shoulder, black outline. (7 bottom-left) complete FAR FOOT ONLY: small horizontal oval pudgy warm tan/cream rabbit foot, a little ankle above, toe pointing RIGHT; thick dark outline. (8 bottom-middle) complete NEAR FOOT ONLY: small chubby horizontal oval warm tan foot, little cream ankle above, toe pointing RIGHT, thick dark outline. (9 bottom-right) complete TAIL ONLY: small round tan pompom black outline. All isolated parts fully drawn, no chopped edges, no duplicates, no collar debris. Keep a consistent outline thickness on every part. This is a usable animation puppet atlas, not a diagram. Parts should occupy about 65-80% of their own cell with separated transparent areas; head is the widest part; ears tall; arms and feet smaller. Preserve original drawing style closely.
```

## Selected correction

Input: first-pass generated atlas. Output: `parts_atlas.png` (1254 × 1254, RGBA).

```text
Edit only the middle-left grid cell (the torso) of this 3x3 transparent cutout atlas. The torso currently has a drawn-in arm on its left-center surface: an internal long black curve from upper center down to the lower middle and around into a U shape. Completely remove that drawn-in arm and its internal U-shaped black outline. Reconstruct a clean uninterrupted cream body and beige apron/straps in its place. Keep a COMPLETE pear-shaped torso silhouette, dark outer contour, the brown shoulder strap at upper right and the beige apron panel and pocket at right. No arms, feet or head attached to torso. All the OTHER EIGHT isolated parts must remain the same design, location, size and orientation. Keep original 3x3 equal-cell layout at same square canvas aspect ratio, warm textured cream painting and thick dark handdrawn outlines, with true transparent background. No text, no labels, no extra parts.
```

The torso/ears and occluded limb areas are reconstructed artwork, not pixel-exact extraction. Fixed crop rectangles in `build_rig.gd` deliberately use observed alpha bounds rather than assuming mathematically exact equal atlas cells.
