# Tea Art Playtest Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development to implement and review the simulation and scene, then verify the complete playable prototype.

**Goal:** Run the agreed staff-driven tea workflow inside the existing layered art scene.

**Architecture:** A session-only TeaPlaytestSim exposes real workers, station inventories, machine phases and transport items. ArtPlaytestLayout maps current artwork to navigation and interaction points. The new scene instances the unchanged editable artwork and displays simulation state; old GameSim and saves remain separate.

**Tech Stack:** Godot 4.6.3, GDScript, existing PNGs and font.

**Spec:** docs/superpowers/specs/2026-10-28-tea-art-playtest.md

## Global Constraints

- Existing furniture placements and source PNGs remain unchanged.
- No new generated art, no automatic scene repack.
- Current branch is codex/tea-reference-art with user edits; work in place on this feature branch, do not reset or commit unrelated files.
- Navigation units and art pixel density are independent.
- No playtest state is written into old saves or old GameSim. Old-game entry saves its own old session before leaving.

## Shared interfaces

`content/tea/art_playtest_layout.gd` extends RefCounted, preloaded as Layout. `Layout.POINTS` maps supply, boil, mix, topping, seal, shelf, counter, belt_in, seal_belt to Vector2 positions. `Layout.path(from: Vector2,to: Vector2)->PackedVector2Array` returns traversable world waypoints. `Layout.belt_path(route: String)->PackedVector2Array` supports topping_to_seal and seal_to_shelf. `Layout.STATION_ART` maps station IDs to unchanged scene node paths.

`game/tea_playtest/tea_playtest_sim.gd` extends RefCounted, preloaded as Sim:

```
var workers: Array # dictionaries: id, name, art, role, pos:Vector2, walking:bool,
# phase:String, task_label:String, carry_item:String, carry_count:int,
# speed:float (display units/second), capacity:int, skill:float,
# fatigue:float [0,1], completed:int, level:int
var stations: Dictionary # boil/mix/topping/seal: input/output dictionaries,
# phase:String, progress:float [0,1], label:String
var belt_items: Array # dictionaries: route:String, item:String, count:int, progress:float [0,1]
var shelf_count:int
var orders:Array # dictionaries id:int, wait:float; up to three waiting customers
var gold:int
var sold:int
var elapsed:float
var use_belts:bool
var paused:bool
var events:Array # recent dictionaries kind:String,text:String (ASCII or Chinese)
func _init() # one worker, all stations available
func advance(dt:float)->void # internally fixed .1 s steps
func hire_cost()->int
func hire()->bool # max three workers
func train_cost(worker_id:int)->int
func train(worker_id:int)->bool
func set_belts(enabled:bool)->void # in-flight jobs retain old route
func audit()->Dictionary # counts/invariants for tests, no state mutation
```

## Task 1: Map current artwork to navigation

- [x] Create content/tea/art_playtest_layout.gd: grid step 20, floor x40..680/y260..1200, rectangles for furniture bases and partition with open doorway. Interaction points: supply (190,310), boil (310,330), mix (470,410), topping (190,490), seal (530,430), shelf (470,670), counter (410,930), belt_in (410,390), seal_belt (530,430); snap to grid centers.
- [x] Verify all points are walkable and all station pairs connected, with divider crossed only through doorway. This is a navigation subgrid, not a redefinition of furniture footprints.

## Task 2: Real playable rules and TDD (delegated implementer)

- [x] Write tests in tests/test_tea_playtest.gd; first demonstrate failure, then implement game/tea_playtest/tea_playtest_sim.gd.
- [x] Real input/output stock, manual load/unload/work, automated heating/mixing/sealing, carry jobs and service jobs. Reserve before pickup, count carried items, preserve capacity when concurrent workers operate.
- [x] Joint task/worker scoring accounts for capacity and actual route duration, bounded soft fatigue, urgency. Assign once and finish atomic task before reassignment.
- [x] Real belt items move over time and deliver; switching mode only changes future jobs. Hire and train mutate live stats and charge real session gold.
- [x] Verify one worker sells, multiple workers contribute, training changes proper attribute, fatigue never reduces speed/skill, stock conservation and no dangling reservations after long runs. Report before/after test evidence.

## Task 3: Actual-art presentation and controls

- [x] Create presentation/tea_playtest/tea_playtest.tscn plus tea_playtest.gd and staff_actor.gd; instance shop_art.tscn. Hide static actor/drink layers at runtime only.
- [x] Render workers at simulated positions in shared Y-sort, carried goods, station stock/progress and belt goods; retain furniture positions and proportional scaling.
- [x] Controls pause, hire, train selected employee, toggle conveyors, restart, old-game entry. Separate header, compact station labels and bottom employee cards from active gameplay.
- [x] Set project.godot main scene to new playable prototype. Add static-preview entry for discovering the playable version.
- [x] Font contains all newly used Chinese strings; regenerate licensed WQY subset if needed.

## Task 4: Integration, review and renderer verification

- [x] Add tests to tests/run_all.gd; run full suite. Fix failures, then review simulation and presentation together using independent reviewer.
- [x] Real renderer capture at 720x1280, smaller portrait and landscape; verify staff paths, divider occlusion and button input.
- [x] Save representative screenshots to docs/qa/tea-playtest-*.png; open the actual runnable scene for user and provide concise usage instructions.
- [x] Record any limits: session-only save, static-pose animation and first-flavor scope. Do not claim finished full game integration.
