# Shop Gameplay Integration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development for independent implementation units and read-only review. The user already authorized execution in this conversation.

**Goal:** Make the art shop's unlocks, upgrades, employee collection/deployment and persistence genuinely playable.

**Architecture:** Preserve the existing production simulator as the tested base. A business subclass reads legacy tea resources, adds progression and owned staff, and serializes its full state. A separate atomic save service and the existing view/HUD bind this state.

**Tech Stack:** Godot 4.6.3, GDScript, current PNG assets, existing ShopConfig/StationDef/SaveService.

**Spec:** `docs/superpowers/specs/2026-10-29-shop-gameplay-integration.md`.

## Global Constraints

- Do not modify old GameSim behavior or player save.json.
- Preserve current furniture, manual production and stock conservation.
- All new actions validate before economic or inventory mutations.
- No free build, random recruitment or invented rewards.
- Tests inject simulations or dedicated paths; no player save writes.

### Task 1: Business simulator and roster (implementation unit)

Files: `game/tea_playtest/tea_shop_sim.gd`, targeted reusable hooks in `tea_playtest_sim.gd`, `tests/test_tea_business.gd`.

- [x] Write failing tests for real opening/unlocks, upgrades, exact-flavor dispatch, roster/deployment and resume.
- [x] Implement the spec's complete simulator interface, reuse tea Resource values, retain current sandbox defaults.
- [x] Verify conservation across manual/belt modes, flavor production, busy recall and reload.

```gdscript
var sim = Shop.new()
check(sim.unlock_station("lemonade") == "")
sim.advance(80)
check(sim.revenue > 0 and sim.gold > 40)
```

### Task 2: Atomic persistent shop save (independent implementation unit)

Files: `game/tea_playtest/tea_shop_save.gd`, `tests/test_tea_shop_save.gd`.

- [x] Write failing tests for full mid-flight save/resume, independent paths, malformed payload handling and failed write reporting.
- [x] Implement load_game/save_game using exact simulation state and format validation.
- [x] Test identical continuation after save/load with pending transport, workers and machine progress.

```gdscript
check(store.save_game(sim, 2.0) == OK)
var resumed = store.load_game()
check(resumed.to_dict() == sim.to_dict())
```

### Task 3: View and actionable HUD integration

Files: `presentation/tea_playtest/tea_playtest.gd`, `shop_hud.gd/.tscn`, `staff_drag_controller.gd`, `tests/render_shop_ui.gd`, `tests/render_tea_business.gd`; inject base simulations in old render tests.

- [x] Use the business simulator by default; injected simulations remain isolated from persistence.
- [x] Bind collection cards by employee id, add real deploy/recall controls, remove actors after recall and preserve body/card dragging contracts.
- [x] Add clickable world device signs, machine/material unlock/upgrade panel and real task progress; visually indicate locked machines and actual product identities.
- [x] Load on startup, save on actions/autosave/exit, expose save feedback; restart resets shop while retaining owned employee growth.
- [x] Run real input/render validation for progression, staff, saves and three viewport sizes.

### Task 4: Review, regression and delivery

- [x] Add new suites/GUI smoke to test entry and CI, rebuild font and inspect all new screenshots.
- [x] Run complete regression and old/new GUI tests, perform read-only code review and fix confirmed issues.
- [x] Update QA/README, commit and push feature branch. Do not merge the new work to main or deploy without further instruction.
