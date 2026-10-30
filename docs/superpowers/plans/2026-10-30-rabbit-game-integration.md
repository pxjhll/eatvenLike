# Rabbit gameplay and character-preview integration

User requested the supplied frame animation inside the actual game, an in-game character preview with all available actions, and a recruitable rabbit employee.

- Keep the existing game, roster workflow, prices, three-deployed limit and user-edited shop content. Add rabbit at stable identity4 after cat/raccoon/fox; old saves remain readable.
- Use only AnimatedSprite2D for the rabbit. Driving pose from simulation time prevents walking while paused and respects game speed. Movement selects eight facing directions; stops hold the current facing's first pose. Preserve carrying, selection, dragging and Y-sort anchors.
- Share a character-visual library across portraits, world actors and preview. Discover authored action prefixes from SpriteFrames; static reference characters expose their existing pose. Do not invent missing idle/work clips.
- Add character-preview entries to the menu and employee page. Reuse the HUD sheet without changing the window or scene. Preview temporarily pauses business, returns to the original pause state and does not alter roster/save data.
- Verify actual recruitment, placement, carrying, animation, preview input and save/restore using native Godot tests and rendered screenshots.

Ownership: recruitment/save behavior and tests delegated to rabbit_recruitment; root owns visual library, staff adapter, HUD and preview integration. Existing unrelated art/content/project changes must not be reverted.

- [x] Inspect existing staff, recruit, save and HUD code.
- [x] Test and implement four-owned / three-deployed rabbit recruitment and save compatibility.
- [x] Add failing visual integration checks.
- [x] Integrate frame actor with simulation movement/time and shared portraits.
- [x] Add character/action preview and both in-game entries.
- [x] Refresh font coverage; run regression and actual GUI/render checks.
- [x] Review, document and open the resulting game after validation.
