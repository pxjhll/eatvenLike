# Inventory ownership and reservation consistency

The user approved continuing with inventory/reservations and related consistency checks. Work from latest main21db93128564d8f6db8cc7f00bcffc5985da8623; PR69–72 are merged and the tree is identical to delivered PR72. Main Godot4.7CI42631512899 succeeded; baseline249 tests need no unchanged rerun. Work in D:/Tes/eatventure on codex/inventory-reservations, no worktree/main writes/merges.

## Design and scope

Create an independent inventory owner and route handoff transfer accounting through it. Keeping independent counter updates embedded in employee cancellation and belts leaves rollback/reservation symmetry implicit. A broad employee/fulfillment rewrite or new serialized inventory schema would expand the scope. The chosen design keeps existing Rules fields as forwarding properties and isolates accounting without a Rules/host/context/callback dependency.

RuleInventory owns exactly six existing state fields: stations, shelf_stock, shelf_count, shelf_reserved_in, shelf_reserved_out, generated. It holds no Rules, employee roster, order list, bus, RNG, navigation, SpecShop or services. Job dictionaries passed to methods are read-only inputs and never retained. The full stations map remains the shared internal storage for machine execution; this step centralizes handoff transfer accounting, not every machine conversion or employee action.

ShopRules keeps the six existing field names/types/get-set behavior, backed by its private inventory instance created before any forwarded property is used. STATE_KEYS/BY_DATA_ID/to_dict/load_dict, schema/fingerprints and migration policies stay unchanged. Assignment and nested map mutation remain compatible. Reset and atomic candidate restoration must rebind the current maps/counters without leaving the owner on stale dictionaries. Every Rules/candidate has its own owner. No cycles/class_name/global singleton or duplicate shadow counters.

## Transfer API

Create game/rules/rule_inventory.gd extending RefCounted without class_name. Fresh no-argument instances have the six empty/zero fields. Constants SHELF/RACK are authoritative there; existing ShopRules constants retain their values through aliases. Public methods:

```gdscript
static func is_operation(job: Dictionary) -> bool
static func stock(station: Dictionary) -> int
static func refresh_after_pickup(station: Dictionary) -> void
func reserve(job: Dictionary, supply_id: String, counter_id: String) -> void
func take(job: Dictionary, supply_id: String) -> void
func deliver(destination: String, item: String, count: int) -> void
func cancel(job: Dictionary, carried: int, supply_id: String, counter_id: String, clear_processing_item: bool = false) -> void
```

Operations are work/pot_start/pot_take/stir. Preserve current accounting exactly: pot_take/stir claim work but no source stock; supply transport increases generated only at take; shelf source/destination counters retain current units and item keys; other sources use input for work/pot_start, output otherwise; operation jobs claim work_reserved, transfers claim destination except counter. take releases source reservation and refreshes source phase/progress with the existing processing/working guard. deliver expects its item key already normalized by the Rules facade (_cup for shelf/processing pickup, raw for rack/other stations); it adds stock and releases destination reservation once.

cancel rolls back only inventory: carried goods return to their original source, supply-generated count is undone, unpicked source reservations are released, destination/work reservations are released, optional manual-topping processing_item is cleared, then source phase is refreshed. It does not reset worker phase/ticket/path or touch orders. Rules keeps those responsibilities in the existing order. Empty jobs do nothing; valid nonempty calls are one accounting transition, not an idempotent token API. Do not clamp away inconsistent/negative data or introduce hidden repairs.

Rules _reserve keeps ticket/flavor selection, order reservation and employee walking around the inventory call in their existing order. _take/_deliver/_stock/_is_operation/_refresh_after_pickup become thin inventory adapters. _cancel_job retains worker/order cleanup and delegates its inventory portion. _run_belts uses the same reserve+take path; its reachable jobs are carry_to_rack from processing pickup to rack, so shared reservation semantics match the old belt code. Preserve shipping iteration, clocks, timing and event ordering. Existing capacity/demand queries can keep reading the forwarded fields; no broad query/dispatch rewrite. Single-mode pot stock conversions remain untouched.

## Read-only diagnostics

Create game/rules/inventory_audit.gd, no class_name/cycle, with:

```gdscript
static func inspect(inventory: RefCounted, workers: Array, belt_items: Array, orders: Array, mode: String, supply_id: String, counter_id: String) -> Array
```

ShopRules.inventory_diagnostics() forwards current owner and collections. Audit is opt-in and read-only; do not call it automatically each tick, reject compatible saves, change commands or add UI. It is a live accounting consistency inspector, not a replacement shape validator for arbitrary malformed save types.

Results are fresh data-only rows {code,path,expected,actual}; no live aliases or Objects. Use deterministic current-state iteration order. Codes: negative_inventory, shelf_count_mismatch, reservation_mismatch, work_reservation_mismatch, multiple_work_claims, order_reservation_mismatch, source_over_reserved. Paths identify the corresponding existing field/item. Negative expected is0; mismatches use the independently computed expected count/bool and actual stored value; source_over_reserved expected is available physical stock and actual is unpicked claimed quantity.

For both modes check nonnegative generated/shelf counters, shelf items, station input/output/reserved_out/reserved_in/processing/stock/capacity, worker carry_count and shipment count, and shelf_count equals the sum of shelf_stock. Compare the numeric value directly so a negative fractional map value is not hidden by integer truncation; report its original value. In handoff additionally derive expected claims from deployed worker jobs and in-flight belt items: unpicked sources only (carried==0), excluding supply and pot_take/stir; destination claims for all unfinished nonoperation transfers except counter; work ownership for operations; order reserved flags from serve jobs. Compare actual and expected counters/maps, including stale positive entries. Include belt destination claims after their source has been taken. Detect multiple work jobs on one station and per-item unpicked claims exceeding their source pool. Distinguish input/output pools for work/pot_start versus transport, rather than combining transformed goods. Single-mode jobs use different execution fields; do not falsely apply handoff claim matching to them.

Conservation is asserted for local transfer lifecycles and cancellation with explicit test expectations. Do not claim that summing raw materials, finished goods, machine processing and sales yields generated: machine recipes/batches transform items and quantities, and single pots may start with stock. No speculative global capacity/recipe invariant or automatic balancing.

## Evidence and integration

Before any production edit capture deterministic old traces on main-derived source for tea/pancake/noodle with legal opening/upgrades/hiring/deployment, actual sales/work, handoff cancellation at several observed job phases, belt shipments, save/load with active claims and reset/continued operation. Record complete to_dict states, commands, RNG/event histories at checkpoints; preserve old reference, runner/provenance and overwrite protection. After owner extraction compare complete old/new binary traces, not only totals. If a genuine preexisting accounting defect is discovered, report its minimal reproducible case before changing behavior; it requires a documented scoped fix and explicit trace interpretation rather than silently replacing the reference.

Task1 direct tests must fail by safe missing-module assertions before implementation, then exercise standalone owner transitions with independent literal stock/reservation/generated expectations: source supply/shelf/station input/output; processing guards; destination shelf/pickup/rack; work/pot_start/pot_take/stir; before/after pickup cancellation; no mutation/retention of job inputs. Integration verifies Rules forwarding via nested mutation/assignment, independent Rules owners, active save/restore/reset and source map rebinding. Existing recall/transfer/save suites remain green.

Task2 starts with guarded missing-audit/API RED and real bad-counter fixtures. Test independently expected diagnostics for each code, including matching wrong totals that hide per-item/source-pool errors, extra positive reservations and belt in-flight claims. Actual legal tea work/belts/recall/redeployment, single-mode work and active save/load/reset should produce no diagnostics at stable method/tick boundaries. Require observed active jobs, sales, belt shipments and multiple cancellation phases. Inspect before/after diagnostics calls to prove state/RNG/events/identities unchanged; mutate retained reports and verify new reports/live state remain independent. No production test-only hooks or shadow simulation.

Two sequential implementation tasks with task spec+quality gates and strongest-model whole review. Freeze source before final full/regressions. Parent and workers share exact-source evidence, not duplicate passed suites. Godot4.7CI must succeed before delivery. Publish one PR against latest main, do not merge.

## Environment

Every engine explicitly sets APPDATA under D:/Tes/eatventure-analysis/inventory-reservations-userdata/session-lifecycle-userdata/<runner> and runs D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe --headless. No local --import/native-window probes. Runtime errors via tests/error_counter.gd are failures even with exit0. Capture/compare full real-userdata manifest before/after; never restore it automatically. Records: D:/Tes/eatventure-analysis/inventory-reservations-pr/validation-records. Work only in this plan's ignored SDD workspace. Verified-copy archive only; no retry of previously rejected recursive cleanup. Preserve font/assets/economy/content/save/event policies and human changes.
