# Tea reference art, stage one

Approved in chat: reproduce the supplied portrait tea shop using layered 2D art on the latest main branch. Work on `codex/tea-reference-art`.

Deliver a static Godot scene, independently reusable transparent assets, and reference/render comparisons. Keep the running tea simulation intact. Preview opens over the current game, pauses it, and restores the same session on close without loading or saving a different profile.

The floor contains no furniture or walls. Split rear wall, outer frame, partition left, partition right and doorway lintel. The doorway aperture must be transparent. Partition pieces and actors sort by their floor contact point. Split ingredient table, preparation bench, rack, display case, checkout counter and register. Conveyors have independent horizontal, vertical and elbow pieces. Machines, ingredient containers, characters and drinks are separate assets. Every scene prop is an editable node, not a region baked into a full scene illustration.

Use built-in imagegen with the uploaded picture as the edit/reference source, then Godot's native image region extraction for lossless atlas slicing. Keep source sheets, generation prompts and exact region/placement metadata in the repository. Runtime assets must live inside the project.

Stage one is an art preview: shelf drinks and animal poses are composed examples, not live inventory or production. Existing simulation rules and saves are unchanged. A layer panel and an occlusion probe allow verification of transparent floors and walls. The supplied original is available in the preview for comparison.

Validation: baseline Godot 4.6.3 has 64 passing cases and existing shutdown resource warnings. Run new preview contracts, the complete suite, real renderer screenshots in portrait and landscape, and inspect the screenshots. Do not claim the final animated integration is finished.
