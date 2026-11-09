# Worker record transitions

`game/rules/worker_state.gd` is a stateless `RefCounted` script with 17 static
methods and no `class_name`. Each transition receives only the caller's worker
dictionary and explicit numbers, identifiers, labels, positions, routes or steps.
It retains no state and never receives Rules, navigation, content, event buses,
callbacks, inventories, RNGs or persistence services.

Rules keeps worker identity allocation, kind fallback, deployment/source fields,
navigation queries, job/customer selection, ticket advancement, recipe/stock and
machine ownership, payment, events and save validation. Existing Rules facades
remain the integration points. Saved strings, key order and optional field
presence are unchanged; `duration` first appears when single work begins.

## Phase paths and inputs

Handoff follows `idle -> walk_pickup -> pickup/work -> walk_dropoff -> dropoff
-> idle`. Operation jobs can finish at work without a delivery walk. Rules chooses
the job and phase, resolves route endpoints, computes action seconds and advances
tickets before calling `finish_handoff`. `enter_handoff_action` does not decide
which phase or duration applies.

Single mode follows `idle -> walk -> work -> idle`, with `wait -> walk/work`
when a machine or stock becomes available. Chore and order decisions remain in
Rules. `wait_single` sets its supplied label; `standby_single` labels the worker
`待命` and chooses walk versus idle from the existing walking flag. Claiming an
order transfers the explicit step array and resets only order/steps/step/walking.

| Methods | Worker fields written |
| --- | --- |
| `create(id, kind, name, stats, position)` | Exact initial worker record; shallow copy of numeric stats; fresh job/ticket/steps/path |
| `place(worker, post, position)` | post, pos |
| `assign_path(worker, path)` | path, path_index (1 for multiple points, otherwise 0) |
| `begin_walk(worker, path, phase)` | path, path_index, phase, walking=true |
| `advance_walk(worker, distance)` | pos, path_index; walking=false on arrival |
| `arrive(worker)` | walking=false |
| `enter_handoff_action(worker, phase, seconds)` | walking=false, phase, action_left |
| `tick_handoff_action(worker, delta)` | action_left |
| `finish_handoff(worker)` | completed, carry_item/count, job, phase, task_label, walking |
| `cancel_assignment(worker)` | job, ticket, carry_item/count, phase, task_label, walking, path, path_index, action_left |
| `begin_single_work(worker, seconds)` | phase, timer, duration |
| `tick_single_work(worker, delta)` | timer |
| `finish_single_work(worker)` | phase=idle |
| `wait_single(worker, label)` | phase=wait, task_label |
| `standby_single(worker)` | phase, task_label |
| `claim_single_order(worker, order_id, steps)` | order, steps, step=0, walking=false |
| `finish_single_order(worker)` | order=-1, steps, carry_item/count |

`assign_path` avoids the `Script`/`Resource.set_path` native method binding
collision when the module is called through a preloaded script constant. The
17-method contract otherwise retains the planned inputs and behavior.

## Ownership and timing

Routes and steps are caller-supplied worker-owned values, with the same assignment
semantics as before. In particular, step arrays are assigned by reference. Cleanup
replaces job/ticket/steps containers where specified instead of clearing previous
aliases. Unrelated worker keys remain untouched, including extension fields.

Both modes share the old movement algorithm. It consumes positive distance across
segments, snaps when gap <= distance + 0.00001, preserves duplicate waypoints and
discards any leftover budget at the end. An empty route or index at the end is
already arrived even with zero distance. A coincident but unconsumed waypoint
requires positive budget. An epsilon snap can leave negative residual budget,
so a subsequent duplicate waypoint waits for another tick. Movement only stops
walking: Rules starts the arrival action and returns without ticking its timer.

Legacy single saves can have an empty route while walking. Rules recomputes that
route with `assign_path`; it does not reset the saved phase. The existing nearby
single arrival branch keeps its position and enters work without a movement tick.

Handoff timers clamp at zero and complete at <= 0.000001. Single timers subtract
without clamping and complete at <= 0, retaining possible negative values.
Finishing handoff increments completed and preserves ticket/path/index/action_left
and single history. Cancellation clears the common assignment and route fields,
retaining completed/post/position/deployment/stats and all single order/chore,
timer/steps/history. Inventory rollback and order reservation release happen in
Rules before cancellation.

Single work completion changes only phase before its business effects. During a
single sale callback the worker is idle with its old label/order/steps/carry and
timer/duration. Order cleanup follows the callback and retains the final step
index, target, label, route and timing history. Handoff sale callbacks still see
the dropoff job and carried goods before Rules removes the order and finishes the
worker. Deployment, placement and recall callbacks keep their existing order.
These transitions introduce no command eligibility or cancellation policy.

## Verification

`tests/test_worker_state.gd` covers literal records and mutation ownership,
movement budgets and edge cases, the separate timer thresholds, asymmetric
cleanup, real walking/work save continuation, legacy path restoration, immediate
arrival and synchronous lifecycle/sale callbacks. Stable real-play boundaries
also use the existing inventory diagnostics.

The bounded before/after probe is held in the task's SDD evidence workspace. Four
seed-42 scenarios (tea mobile/seated brewer, pancake and noodle) each run 5000
ticks plus 1000 after reset/reopen. Complete state checkpoints, unique phases,
command boundaries and synchronous callbacks are compared as binary records;
full state is not recorded at every tick. Production golden and scene tests
remain unchanged.
