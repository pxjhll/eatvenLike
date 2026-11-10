# Worker transition and lifecycle boundary

The user asked to continue the architecture sequence with worker state transitions after inventory PR73. Base9a38db7ddb54dc2491427a56763d95993079f0bc is PR73 OPEN, with265 tests and successful Godot4.7CI42640211903. Use D:/Tes/eatventure on codex/worker-transitions without another worktree/main writes/merges; stack on codex/inventory-reservations while PR73 remains open.

## Scope and design

Centralize employee phase/path/timer/cleanup transitions in a stateless data module and remove the duplicate path-advance algorithm used by handoff and single modes. Keeping scattered writes makes the meaning of completion versus cancellation implicit. Moving the complete employee/fulfillment executors would also move stock, machine recipes, customer ownership and payment. This PR keeps those decisions with Rules and extracts only the worker-record transition boundary.

Create game/rules/worker_state.gd extending RefCounted, no class_name. Every method is static. Inputs are a mutable worker Dictionary plus explicit IDs/strings/numeric data/positions/path/step values. No Rules/host/context, callbacks, SpecShop, nav, bus, RNG, inventory owner or persistence reference; no global state/cache, serialization or new simulation. Mutations are explicit on the caller-owned worker record. Arrays assigned as routes/steps become worker-owned inputs as in the old implementation; the module retains no independent reference. Worker dictionaries and saved phase strings/field presence stay compatible. No new serialized fields or enum representation.

## Exact transition APIs

```gdscript
static func create(id: int, kind: String, name: String, stats: Dictionary, position: Vector2) -> Dictionary
static func place(worker: Dictionary, post: String, position: Vector2) -> void
static func assign_path(worker: Dictionary, path: PackedVector2Array) -> void
static func begin_walk(worker: Dictionary, path: PackedVector2Array, phase: String) -> void
static func advance_walk(worker: Dictionary, distance: float) -> bool
static func arrive(worker: Dictionary) -> void
static func enter_handoff_action(worker: Dictionary, phase: String, seconds: float) -> void
static func tick_handoff_action(worker: Dictionary, delta: float) -> bool
static func finish_handoff(worker: Dictionary) -> void
static func cancel_assignment(worker: Dictionary) -> void
static func begin_single_work(worker: Dictionary, seconds: float) -> void
static func tick_single_work(worker: Dictionary, delta: float) -> bool
static func finish_single_work(worker: Dictionary) -> void
static func wait_single(worker: Dictionary, label: String) -> void
static func standby_single(worker: Dictionary) -> void
static func claim_single_order(worker: Dictionary, order_id: int, steps: Array) -> void
static func finish_single_order(worker: Dictionary) -> void
```

create returns the exact existing _new_worker row in its current key order, with fresh job/ticket/steps/path containers and one copy of numeric stats. Do not add duration at creation: it is an optional field first captured by single work. Rules retains kind fallback, ID allocation, deployment/source fields and spawn-point resolution. place only changes post/pos. assign_path sets path and index1 when size>1, otherwise0; it does not change phase/walking/position. begin_walk then sets the supplied existing phase and walking=true. Its phase is walk/walk_pickup/walk_dropoff; enter_handoff_action receives pickup/work/dropoff. These arguments are internal valid phase tokens, not a new user-command/validation layer.

advance_walk is the exact old shared loop: consume distance while positive and path_index<size, snap at gap<=distance+0.00001, otherwise move_toward, discard residual distance at route end. Return true at path end and call arrive (walking=false); return false otherwise. Empty route/index-at-end counts as arrived even with distance0. An unconsumed zero-distance route is not advanced when distance0. Preserve duplicate waypoints, fractional epsilon behavior, position and index updates. No path recomputation, phase/action start, extra work or timer decrement in this helper. Rules retains navigation and the old early return after arrival. Single legacy empty-path reconstruction uses assign_path without normalizing its phase.

enter_handoff_action changes walking=false, phase, action_left=seconds. tick_handoff_action clamps maxf(0, old-delta) and returns completion at<=0.000001. finish_handoff increments completed, clears carry_item/count and job, sets idle/idle/walking=false; retains ticket as already advanced by Rules, path/index/action_left and single-mode/history fields. cancel_assignment clears job/ticket/carry, sets idle/idle/walking=false, replaces path with empty PackedVector2Array, zeroes path_index/action_left; retains completed/post/deployment/position/stats and existing single order/chore/timer/steps/history fields. Cancellation must replace job/ticket containers rather than clearing old aliases in place. Inventory rollback and serve-order reservation release remain before this worker cleanup in Rules.

begin_single_work sets phase=work, timer=seconds and duration=seconds. tick_single_work subtracts delta without clamp, completion at<=0 (not handoff epsilon). finish_single_work sets phase=idle only: preserve current label/order/carry/timer/duration until existing completion logic updates them. wait_single sets wait and its supplied label; does not clear routes, orders, history or durations. standby_single sets walk if walking, otherwise idle, with existing label 待命. claim_single_order sets order/steps/step0/walking=false without resetting other fields. finish_single_order clears order=-1/steps/carry only; retain last step index, timer/duration, target/label/path as before. Every transition leaves unrelated fields untouched; no new cleanup or normalization policy.

## Rules integration and observable ordering

Keep _new_worker/_seat_at/_walk/_work_single/_finish and other existing facades. Route the selected worker mutations and both movement loops through WorkerState. Single _go still sets target/label, resolves nav goal, takes the existing distance<1 immediate-arrival branch, and otherwise starts a walk. Legacy path reconstruction, crowded/home preemption, job selection, station user ownership, ticket advancement, stock/recipes, step advancement and payment remain in Rules.

Preserve timer and event ordering: arrival does not consume work time in the same tick. Handoff sale is emitted while the worker still has its dropoff job/carry, before removal/finish. Single completion enters idle before its sale event, retaining the old label/order/steps/carry during that callback, then clears the order afterward. Deployment/placement/recall event order and inventory rollback remain unchanged. Numeric timing queries must retain their current effective values; if extracting an entry would change a phase-sensitive read, keep the computation at the corresponding point in Rules.

Do not tighten the current validator or deployment/recall command eligibility, including compatibility APIs hidden by a shop's UI. Existing single-mode order/chore history on generic _cancel_job is preserved; this PR does not invent customer progress transfer or machine-lease cancellation policy. No new automatic state rejection, worker diagnostics or gameplay behavior. No source edits to inventory/audit, fulfillment planner, state validator, content, UI, resources/font, save format/fingerprints or migration policy.

## Evidence

Before any production edit capture an overwrite-protected old trace from exact base source. Use actual public commands and seed42 for tea mobile, tea seated brewer, pancake and noodle. Observe real sales, work, walking, single waits, handoff pickup/dropoff, belts, legal drag/recall/redeploy and active save/load/reset/reopen. Use5000 ticks at0.1 per scenario and1000 after reopen, complete state checkpoints0/500/1000/2500/5000/6000, first occurrences of each distinct relevant job/phase, and command boundaries. Capture employee/state snapshots synchronously from sale/deployed/placed/recalled event callbacks too. Old/new comparisons cover complete recorded to_dict payloads, RNG/events and callback observations, not selected totals. Do not record every full tick again: counters may be sampled each tick, full trace must stay<=50MiB. Preserve old binary/provenance and frozen runner; no baseline recapture after production edits.

Committed direct module tests first produce ordinary missing-module RED using safe ResourceLoader guards. Independent literals cover exact factory/default field presence/ownership; multisegment paths, duplicates/empty/zero-distance/epsilon and residual budget; handoff versus single timer boundaries; immediate arrival timing; cleanup versus finish changed/retained fields and old container aliases; single wait/standby/claim/complete/history. Actual Rules tests verify legacy pathless save continuation, active work/pickup/dropoff save/load, mode-specific callbacks and restart without hidden phase normalization. Returned records are tested directly, not only deep-copied snapshots. Existing inventory_diagnostics remains empty at stable boundaries during real play. Existing fixtures stay unchanged except new suite registration.

Freeze before a single final full tests/run_all.gd, unchanged pancake golden and tea/pancake/noodle real scenes. Parent runs remaining config/layout/extend/guide/audio/retry/lifecycle/commandUI/presentation-boundary/work-actions without duplicating passed suites. Independent task review plus strongest-model whole review, then exact-head Godot4.7CI success before delivery. Check remote PR73/main state before publication; if dependency merged, preserve human changes and rebase only own feature commits.

## Environment and records

All engines explicitly set APPDATA under D:/Tes/eatventure-analysis/worker-transitions-userdata/session-lifecycle-userdata/<runner>, use D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe --headless, no local --import/native window probes. tests/error_counter.gd errors fail even with exit0. Capture/compare real-userdata manifest before/after, never restore it automatically. External records D:/Tes/eatventure-analysis/worker-transitions-pr/validation-records. Only this plan's ignored SDD workspace may be read/written; use committed fixtures rather than old ignored workspaces. Verified-copy archive, no retry of previously rejected recursive cleanup, no merge or main push.
