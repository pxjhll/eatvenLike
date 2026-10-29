# Shop UI Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Establish the agreed shop/build/staff/recruit UI structure while retaining real playtest actions.

**Architecture:** An editable `shop_hud.tscn` owns static controls and containers. `shop_hud.gd` binds the session read model and emits actions to the playtest view. The existing simulator remains the authority for all prices, staff, production and assignment.

**Tech Stack:** Godot 4.6.3, GDScript, native Control containers, SVG icons, existing licensed WenQuanYi font.

**Spec:** `docs/superpowers/specs/2026-10-29-shop-ui-foundation.md` (approved in conversation).

## Global Constraints

- Preserve furniture, simulation rules and session-only save boundaries.
- No construction rules, random recruitment, rarity, paid currency or fake inventory.
- Opening UI never changes pause state; overlays block world input; hidden cards never start gestures.
- Support 720×1280, 360×640 and 1280×720.

### Task 1: UI shell and real action panels

**Files:** Create `presentation/tea_playtest/shop_hud.tscn`, `shop_hud.gd`, `art/ui/shop/*.svg`; modify `tea_playtest.gd`, `tea_playtest.tscn`; test `tests/render_shop_ui.gd`.

**Interfaces:** HUD `setup(view: Node2D)`, `refresh()`, `open_page(page: String)`, `blocks_world(screen: Vector2) -> bool`, `begin_staff_drag()`; view `open_page(page: String)` exposes page navigation. HUD actions call existing view `hire_worker`, `train_selected`, `toggle_transport`, `restart`.

- [x] Write real UI regression: missing HUD produces an explicit assertion; navigate using pointer events, open recruit, hire, select staff, train and verify actual gold/level changes.
- [x] Run `godot --headless --path . -s tests/render_shop_ui.gd`; confirm the new shell is absent.
- [x] Build editor-visible container scene and bind existing simulation state. Add disabled construction/high recruitment states, dismissible menus and restart confirmation.
- [x] Verify navigation, economic side effects, pause preservation and confirmation cancellation using native InputEvent injection.

```gdscript
await click(hud.recruit_button)
var gold_before: int = view.sim.gold
await click(hud.hire_button)
check(view.sim.workers.size() == 2 and view.sim.gold == gold_before - 35)
```

### Task 2: Drag, selection and small-screen integration

**Files:** Modify `staff_drag_controller.gd`, `staff_actor.gd`, existing render tests; extend `render_shop_ui.gd`.

**Interfaces:** Drag checks HUD `blocks_world`, visible card bounds, and calls `begin_staff_drag` once a card gesture crosses the threshold. Employee body selection calls view `select_worker(id)`; view holds current selection without assigning posts.

- [x] Test a pointer gesture over an overlay cannot pick a world worker; hidden card coordinates cannot initiate a drag; dragging a visible employee card hides panel and assigns a real manual post.
- [x] Integrate HUD hit testing and keep ESC/touch cancellation behavior. Retain existing immediate placement and cargo-refund contracts.
- [x] Convert previous render tests to navigate to visible controls. Remove tiny global stats/task text from the home screen.
- [x] Rebuild font subset with all `.gd`, `.tres`, `.tscn` text so new visible labels have glyph coverage.

```gdscript
await click(hud.staff_button)
await drag(view._staff_cards[0].get_global_rect().get_center(), world_point(Vector2(325, 210)))
check(view.sim.workers[0].post == "boil" and hud.page == "shop")
```

### Task 3: Verification and delivery

**Files:** Update `README.md`, create `docs/qa/shop-ui.md`, capture `docs/qa/shop-ui-*.png`.

- [x] Run `godot --headless --path . -s tests/run_all.gd` and actual GL GUI tests `render_shop_ui.gd`, `render_staff_posts.gd`, `render_tea_playtest.gd`.
- [x] Inspect portrait home/staff/recruit/build, small portrait and landscape images for text overflow, cut-off controls and scene interference.
- [x] Request read-only code review, address confirmed issues, then commit to `codex/shop-ui-foundation` and report main merge SHA separately from UI change SHA.
