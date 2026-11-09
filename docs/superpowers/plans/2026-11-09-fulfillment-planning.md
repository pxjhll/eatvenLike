# Fulfillment planning implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task by task.

**Goal:** Separate pure fulfillment definition planning from live ShopRules without changing simulation results.
**Architecture:** A stateless FulfillmentPlan compiles role/chain metadata and single-order step rows from SpecShop. ShopRules retains the existing fields/facades and owns all execution/state.
**Tech Stack:** Godot GDScript, existing headless tests, deterministic old/new state traces.
**Spec:** docs/superpowers/specs/2026-11-09-fulfillment-planning.md

## Global Constraints

Use D:/Tes/eatventure on codex/fulfillment-planning; no worktrees/main writes/merges. Engine D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe --headless, explicitly set APPDATA under D:/Tes/eatventure-analysis/fulfillment-planning-userdata/session-lifecycle-userdata/<runner> before every engine. No --import/native-window probes. Helpers no class_name/cycles. Preserve definitions/assets/font, business/RNG/event ordering, saved state format and current migration policies. Planner has no Rules/host/context/callback input, serialization, new Rules construction or persistent cache. Worker does not spawn/stage/commit. Baseline exacthead2b12eb4 has Godot4.7 CI42605719229 SUCCESS and244 tests; do not repeat the unchanged baseline suite.

### Task 1: Extract and verify fulfillment definition planning

**Files:** Create game/rules/fulfillment_plan.gd and tests/test_fulfillment_plan.gd. Modify game/rules/shop_rules.gd (_derive_roles, _order_steps and now-unused _option only) and tests/run_all.gd. Add docs/fulfillment-planning.md. Ignored trace/focused runners stay in this plan's SDD workspace; trace outputs/logs stay in the external records directory.

**Interfaces:**

```gdscript
# New stateless preload helper, extends RefCounted, no class_name:
static func derive(shop: SpecShop) -> Dictionary
static func single_steps(shop: SpecShop, counter_id: String, order: Dictionary) -> Array

# ShopRules compatibility facade:
func _order_steps(c: Dictionary) -> Array:
    return FulfillmentPlan.single_steps(shop, counter_id, c)
```

derive returns exactly counter_id/supply_id/pickup_id; pots/autos/seatables/dish_ids/front_dishes/kitchen_dishes; chains/station_output/station_input. Preserve the current first/last/overwrite/iteration rules enumerated in spec. Assign typed arrays with assign; keep their declared types.

```gdscript
func _derive_roles() -> void:
    var plan: Dictionary = FulfillmentPlan.derive(shop)
    counter_id = plan.counter_id
    supply_id = plan.supply_id
    pickup_id = plan.pickup_id
    pots.assign(plan.pots)
    autos.assign(plan.autos)
    seatables.assign(plan.seatables)
    dish_ids.assign(plan.dish_ids)
    front_dishes.assign(plan.front_dishes)
    kitchen_dishes.assign(plan.kitchen_dishes)
    chains = plan.chains
    station_output = plan.station_output
    station_input = plan.station_input
```

Single rows follow the existing _order_steps shape, including take/hand labels/seconds and all original step fields. A private common step conversion may remove duplicate dish/option row construction; its station argument must preserve option fallback and exact action alias resolution. Do not move _roll_options or any random call.

- [ ] Before production edits, create ignored trace runner and capture old-engine reference. For each tea/pancake/noodle shop seed42, fund fixture gold1e8, legally open stages/boxes, hire/deploy up to two additional employees, buy supported upgrades, run1200 ticks of0.1s, change work tuning at tick300, buy seat when allowed at tick450, attempt flyer at tick600, save/load current data at tick700 and continue. Record initialization/command outcomes and complete state at ticks0/100/300/600/700/1200; count active work observations and require sales>0 per shop. Keep setup legal and deterministic; report any needed fixture correction before capturing the final old reference. Use to_dict only in validation, never the planner. Baseline file must be preserved after production edits.
- [ ] Add real planner tests first. Absent module RED must be an assertion failure with no parse/runtime error:

```gdscript
func _planner() -> Script:
    var path := "res://game/rules/fulfillment_plan.gd"
    check(ResourceLoader.exists(path), "fulfillment planning is independently usable")
    return load(path) if ResourceLoader.exists(path) else null
```

Guard each affected case when null. Derive independent literal expectations from a small synthetic shop exercising first supply/last counter/processing pickup, manual versus automatic combine, repeated chain stations, front exclusion, multiple produced/consumed items and station input first-write. A deliberate planner dependency on live Rules would fail the standalone fixture.
- [ ] Test real pancake route plus synthetic addon-before/addon-after/main-is-addon, on_take/on_hand labels, take/hand times, repeat/flags, missing option/null step, option station fallback and layout aliases. Assertions compare literal row fields/routes, not another call to the same builder. Test nested mutation isolation and fresh calls across all3 shops. Planning must leave caller order/shop/live Rules state/RNG/events unchanged; returned payloads contain no Objects. Retained old output must remain unchanged when later definition values change, while new calls see new values.
- [ ] Capture focused assertion RED, implement the stateless extraction and thin Rules facades. Move existing algorithm semantics unchanged; no duplicate old planner body and no broad refactoring. Keep all production code outside declared sections untouched.
- [ ] Run focused GREEN. Rerun the exact old trace probe against extracted source and compare every checkpoint/command/state recursively or as exact binary data produced in the same engine. Save trace-before/trace-after/comparison logs externally. Do not replace missing behavior with a mock or regenerate the old reference.
- [ ] Self-review, document public planner inputs/ownership/order semantics and preserved save/execution behavior. Freeze production/test/docs source. Run exactly one tests/run_all.gd full suite, existing tests/baselines/record_rules.gd -- --check, and tests/render_shop_tea.gd, render_shop_pancake.gd, render_shop_noodle.gd. Collect runtime logger evidence, not only exit codes. No unchanged suite reruns. Parent owns remaining config/layout/extend/guide/audio/retry/lifecycle/command/boundary/work-action integration after freeze.
- [ ] Detailed report to .superpowers/sdd/2026-11-09-fulfillment-planning/task-1-report.md: files/interfaces/decisions; exact RED/GREEN/full/trace commands and absolute logs/results; old-reference provenance; nonvacuous sales/work counts; source freeze; concerns. No staging/commits/subagents. Parent commits after reading evidence, runs independent task review then strongest-model whole review.

## Parent gates and publication

Capture production userdata manifest before first engine; permit isolated worker engines only after manifest READY. Parent handles ledger/preflight, remaining integration, review/fix loops and commits. Branch from2b12eb4; stack PR on codex/ui-state-boundary while PR71 OPEN. Check remote state before publishing, preserve/revalidate human changes if rebase needed. Push feature branch/create PR, wait for Godot4.7 CI to completion, compare userdata and archive only this plan's workflow files by verified copy. Never merge or retry known blocked recursive deletion.
