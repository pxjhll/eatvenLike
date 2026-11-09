# Inventory and reservation ownership implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans task by task.

**Goal:** Centralize handoff transfer accounting and expose read-only reservation consistency diagnostics.
**Architecture:** RuleInventory owns the six existing fields behind compatible Rules properties; existing fulfillment keeps employee/order/machine execution. A separate opt-in audit reconstructs expected claims from jobs/shipments.
**Tech Stack:** Godot GDScript, headless direct/real-rule tests, complete old/new trace comparison.
**Spec:** docs/superpowers/specs/2026-11-09-inventory-reservations.md

## Global Constraints

Use D:/Tes/eatventure on codex/inventory-reservations, no worktrees/main writes/merges. Engine D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe --headless, explicit APPDATA D:/Tes/eatventure-analysis/inventory-reservations-userdata/session-lifecycle-userdata/<runner> before every invocation. No local --import/native-window probes. No class_name/cycles/global singleton/shadow counters/Rules-host-callback dependency in inventory. Preserve business/RNG/event ordering, save keys/shape/fingerprints/migration policy, font/assets/content. Audit is opt-in, never auto-repairs or enforces new save restrictions. Worker no subagents/staging/commits. Baseline main21db931 has identical delivered PR72 tree and passing4.7CI42631512899/full249; no unchanged full rerun. External records D:/Tes/eatventure-analysis/inventory-reservations-pr/validation-records.

### Task 1: Inventory owner and unified transfer accounting

**Files:** Create game/rules/rule_inventory.gd, tests/test_inventory.gd; modify game/rules/shop_rules.gd in six field declarations, constants and selected transfer facades only; tests/run_all.gd; add docs/inventory-reservations.md. Trace/focused runners only in this plan's SDD workspace.

**Interfaces:** Implement exact RuleInventory signatures and six state fields from spec. No-arg owner, no retained job/worker/order references. Preserve existing Rules types with property forwarding and initialize owner first:

```gdscript
const Inventory := preload("res://game/rules/rule_inventory.gd")
var _inventory := Inventory.new()
var stations: Dictionary:
    get: return _inventory.stations
    set(value): _inventory.stations = value
var shelf_stock: Dictionary:
    get: return _inventory.shelf_stock
    set(value): _inventory.shelf_stock = value
var shelf_count: int:
    get: return _inventory.shelf_count
    set(value): _inventory.shelf_count = value
var shelf_reserved_in: int:
    get: return _inventory.shelf_reserved_in
    set(value): _inventory.shelf_reserved_in = value
var shelf_reserved_out: int:
    get: return _inventory.shelf_reserved_out
    set(value): _inventory.shelf_reserved_out = value
var generated: int:
    get: return _inventory.generated
    set(value): _inventory.generated = value

func _take(job: Dictionary) -> void:
    _inventory.take(job, supply_id)

func _deliver(destination: String, item: String, count: int) -> void:
    var key := _cup(item) if destination in [SHELF, pickup_id] else item
    _inventory.deliver(destination, key, count)
```

- [ ] Read existing _reserve/_take/_deliver/_cancel_job/_run_belts and machine callbacks, then BEFORE production edits capture an overwrite-protected complete old trace. Use tea/pancake/noodle seed42, funded legal unlock/boxes/upgrades/hire/deploy and actual sales/work; tea buys enabled belts and observes shipments; recall/redeploy at >=4 distinct valid handoff kind/phase pairs. Run5000 ticks of0.1/shop, with complete checkpoints0/500/1000/2500/5000 and around each cancellation; save/load at2500 with active work/claims, then continue. At end reset, legally reopen and run1000 more ticks, capturing fresh continuing state. Record full states/commands/RNG/events. Adjust only fixture setup before final capture if necessary; report nonvacuous counts/provenance. No copied old engine in committed tests.
- [ ] Write independent standalone owner tests using ResourceLoader.exists guards for genuine missing-module RED without parse/runtime errors. Minimal literal lifecycle includes reserve shelf->rack count2 (source/destination reservations2, stock unchanged), take (shelf count/items down2, out0, rack in2), cancel after pickup (source count/items restored, rack in0), and completed delivery (rack output+2/in0). Add supply-generated undo, station input/output, operation kinds/work claims, processing refresh guards, cancellation before pickup and empty cancel. Check job inputs remain unchanged. Capture actual RED then implement.
- [ ] Route Rules fields/facades/belt accounting through owner. _reserve retains ticket/flavor and order/worker operations around reserve; _cancel_job retains employee/order cleanup after ledger rollback. Keep capacity/demand/query algorithms, machine conversions/single stock and all other execution untouched. No duplicate legacy accounting bodies or shadow scalar state.
- [ ] Tests verify getter/setter/nested-map forwarding, independent Rules states, candidate load/reset current bindings and full serialization compatibility. Run focused new owner tests plus existing real cancellation/recall/post/belt and save/atomic-restore tests selected through a logger runner. Rerun the same old trace after extraction and compare all bytes/checkpoints; preserve old binary and provenance, report counts and differences honestly.
- [ ] Self-review/docs, SOURCE FREEZE, then one full tests/run_all.gd for this state-ownership change. Parent need not run scenes yet; all live integration belongs to final Task2 freeze. Report exact RED/GREEN/full/trace commands/absolute logs, source hashes, files, concerns to .superpowers/sdd/2026-11-09-inventory-reservations/task-1-report.md. No staging/commits; parent commits then task review before Task2.

### Task 2: Independent inventory consistency inspection and live invariants

**Files:** Create game/rules/inventory_audit.gd, tests/test_inventory_audit.gd; modify game/rules/shop_rules.gd only audit preload/public forwarder; tests/run_all.gd; extend docs/inventory-reservations.md. Task1 owner remains unchanged unless a concrete audited defect requires controller ruling.

**Interfaces:**

```gdscript
static func inspect(inventory: RefCounted, workers: Array, belt_items: Array,
        orders: Array, mode: String, supply_id: String, counter_id: String) -> Array

func inventory_diagnostics() -> Array:
    return InventoryAudit.inspect(_inventory, workers, belt_items, orders,
        shop.fulfillment.handoff, supply_id, counter_id)
```

Rows {code,path,expected,actual}, all fresh data. Exact codes and expected semantics: spec Read-only diagnostics. Preload Inventory for shared is_operation; no dependency back from inventory to audit. Diagnostics assume existing live shape (save schema validator remains authoritative), never cache/mutate or call serialization/RNG/events/Rules construction in production.

- [ ] Guarded missing-audit/public-API RED plus real bad-counter assertions. Use standalone Inventory with literal well-shaped station/jobs/shipments/orders, and Rules public API where available. Test negative_inventory (including worker carry_count, shipment count and a negative fractional stock-map value), shelf_count_mismatch, reservation_mismatch (station/shelf/out/in/stale-positive), work_reservation_mismatch, multiple_work_claims, order_reservation_mismatch and source_over_reserved with independent expected rows/path/values. Change one invariant at a time; do not derive expectations through production audit helpers.
- [ ] Reconstruct handoff unpicked source claims from workers only, exclude supply and pot_take/stir; match station input vs output pools by job kind. Reconstruct destinations from unfinished nonoperation jobs plus shipments, exclude counter; work bool/count and order serve claims independently. Compare union actual/expected map keys so stale claims are detected. Both modes get nonnegative/shelf-total checks; single skips handoff claim assumptions. No speculative whole-recipe/global capacity invariant.
- [ ] Add real seeded three-shop runs with diagnostics empty after stable ticks and commands. Tea must encounter stock processing, transfer jobs, in-flight belts and >=4 distinct cancel/recall phases; check before/after recall/deploy, active save/load and reset/reopen. Single shops must sell and perform active work. Snapshot once around representative diagnostics reads to verify complete state/RNG/events/identity unchanged; do not serialize the entire game every audit tick. Negative reports must be detached and retained reports unaffected by later changes. Existing tests/fixtures unchanged.
- [ ] Focused GREEN and docs covering opt-in semantics, diagnostic codes/paths, local conservation versus recipe conversion, scope of single mode and transfer ownership. No production tick hook or new UI/config/save behavior. SOURCE FREEZE before final full. Run one tests/run_all.gd full, golden via existing record_rules.gd -- --check with runtime logger, tea/pancake/noodle real scene scripts. Parent owns other final config/layout/extend/guide/audio/retry/lifecycle/commandUI/presentation-boundary/work-action integration using separate APPDATA, without duplicate suites.
- [ ] Detailed report .superpowers/sdd/2026-11-09-inventory-reservations/task-2-report.md with exact RED/GREEN/full/live commands/logs/counts/runtime evidence, fixture/probe provenance, sourcefreeze and concerns. No staging/commit/subagents. Parent task review then strongest-model whole review and one scoped final fix wave if needed.

## Parent gates

Full real-userdata manifest READY before any engine, compare after and never restore. Each task has independent spec+quality review; parent owns commit/review packages/ledger and resolves ambiguities. Fresh sequential workers, no concurrent production writes. Verify latest remote main/human deltas before publication and rebase only own feature commits if required. One PR against main; push own feature branch, wait for exact-head Godot4.7CI success, no merges. Archive only this plan's SDD records by hash-verified copy, leave prior workspaces and do not retry blocked recursive deletion.
