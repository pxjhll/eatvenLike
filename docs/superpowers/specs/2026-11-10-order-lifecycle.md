# Order and customer lifecycle owner

## Intent and ownership

Continue the approved customer/order lifecycle work after PR77. One PR stacks on codex/dispatch-policy at aed3f64cae7fd42e4f6bd1484c56d8f4c169c1cb while PR77 is open. Preserve behavior, numeric policy, random consumption, callbacks, references and save schema; this is not a newly confirmed defect fix.

`game/rules/rule_orders.gd` extends RefCounted without class_name. It owns ten existing saved values: orders:Array=[], diners:Array=[], customers:Array=[], queue:Array=[], lost:int=0, next_order:int=1, next_customer_id:int=1, order_clock:float=0.0, next_customer:float=0.0, order_ramp:Dictionary={}. Each instance has independent mutable containers. No Rules/host/context/callback, SpecShop, RNG, event bus, navigation, services, cache or serialization dependencies, and no whole Rules construction/clone.

Rules creates `_orders_state` before forwarded properties. Existing public/saved names retain their exact types and forward to the corresponding owner field; `_next_order`, `_next_customer_id`, `_order_clock` and `_next_customer` map to the names without the underscore. STATE_KEYS, its order, BY_DATA_ID and schema remain unchanged. Reset/load assign through current owner properties; never replace the live owner or cache arrays/maps. No new saved owner object. Purchased seat-group counts and flyer state remain in Rules.

## Exact instance APIs

* `admit_handoff(dish: String, seat: int, takeaway: bool, weights: Dictionary, ramp_orders: int, takeaway_open: bool) -> Dictionary`: in weights key order, order_ramp[dish_key]=mini(int(get(key,0))+1,ramp_orders); likewise takeaway ramp if open. Append {id:next_order,wait:0.0,reserved:false,dish:dish,takeaway:takeaway,seat:seat}, increment next_order, return original appended row. Preserve field/key order and no new eligibility check.
* `advance_handoff(delta: float) -> void`: order_clock+=delta, then each order.wait+=delta in existing order.
* `handoff_order(id: int) -> Dictionary`: first matching original row or fresh empty dictionary.
* `set_handoff_reserved(id: int, reserved: bool) -> void`: update every matching row, no early break or other effects.
* `remove_handoff(id: int) -> void`: remove the first matching row using existing order, then stop; no other effect.
* `add_diner(seat: int, dish: String, seconds: float) -> void`: append {seat:seat,dish:dish,left:seconds} with legacy key order.
* `advance_diners(delta: float) -> void`: reverse-index loop subtracts delta; remove at left<=0.000001. Preserve current array identity and remaining rows/history.
* `overflow_to_takeaway(free_seats: int) -> void`: ordered loop skips reserved, already takeaway or seat>=0. Eligible standing rows consume local free_seats when >0; otherwise set takeaway=true. No capacity query or clamping.
* `admit_single(kind: String, addon: bool, options: Array) -> Dictionary`: create {id:next_customer_id,kind:kind,addon:addon,state:"queue",wait:0.0,claimed:false,paid:0,options:options}, increment ID before appending the original row to customers and id to queue; return row. Retain supplied options reference and exact key order.
* `reject_single() -> void`: lost+=1 only.
* `single_customer(id: int) -> Dictionary`: first matching original row or fresh empty dictionary.
* `claim_single() -> Dictionary`: if queue empty return fresh empty; find queue[0] via single_customer, return empty if claimed; otherwise set claimed=true and return original row. Do not search later rows, dequeue, validate/normalize an invalid queue or touch worker state.
* `advance_single_customer(customer: Dictionary, delta: float, patience: float) -> bool`: only queue state increments wait. If patience>0 and wait>patience and not claimed, set state="leaving", erase id from current queue, increment lost and return true. Otherwise false. Does not remove from customers or emit anything. No epsilon.
* `remove_leaving_single(customer: Dictionary) -> void`: recheck current supplied row state; if leaving erase it from the owner's CURRENT customers array. Must occur after synchronous lost callback, not in a batched transition before callbacks.
* `dequeue_single(id: int) -> void`: current queue.erase(id) only, retaining array identity.

Exact static APIs (same module, no owner construction):

* `accept_single(customer: Dictionary, paid: int) -> void`: set paid then state="paid", retaining all other fields/aliases.
* `leave_single(customer: Dictionary) -> void`: set state="leaving" only.

## Integration and observable ordering

Rules retains `_pick_dish`, order weights, interval formulas, addon/option sampling, flyer scheduling and queue/seat/menu eligibility. RNG calls remain in the existing branches/order, including rejection short circuits, fixed vs exponential arrivals, flyer before normal arrivals, addon short circuits and locked option skipping. The owner never draws random values or reads configuration.

`_tick_handoff` calls advance_handoff exactly at the old clock/wait statements, after flyer entry and before interval checks. Deadline reset stays before capacity checking. Diner advancement stays after worker allocation/belts and before overflow eligibility/free-seat query. Overflow mutation receives that already queried budget. `_add_order` retains is_open/weight total/no-draw rejection, dish sampling and seating queries, then admit_handoff, then arrived event. `_spawn_single` retains full-queue check before all sampling, calls reject_single then lost for rejection; otherwise keep dish/addon/options draw order, admit_single, then arrived. Option sampling sees the old ID/no new row exactly as before; verify sampling is independent of ID reads before moving row construction into admission.

`_customers_single` computes patience once, iterates customers.duplicate() as before, calls advance_single_customer for that row, emits lost iff true, then remove_leaving_single. Callback can observe the departed row still in customers, absent from queue, with incremented lost. It can change the row or replace arrays/reset/load: removal rechecks current state/current owner array afterward. Do not collect all transitions then emit. Newly added rows are excluded by the initial iteration snapshot.

`customer` and `_order_by_id` remain facades. `_find_job_single` keeps chores-first, then claim_single BEFORE evaluating _order_steps/WorkerState/navigation. Take dequeues before order_price_single. `_reserve` marks handoff reserved after inventory reserve and before worker job/walk; `_cancel_job` clears after inventory cancel and before worker cleanup. Serve dropoff removes handoff order AFTER sale callback and BEFORE worker cleanup. `_record_sale` adds diner after seat/seat_seconds queries and before sales count/price/event.

Sales keeps its public API and monetary arithmetic. It preloads OrderState solely for the static record transitions: accept_single replaces paid/state assignments at the same point AFTER credit; complete_single calls leave_single AFTER credit and BEFORE sold counts. No cycle: rule_orders imports no Sales or Rules. Existing test_sales expectations must pass without weakening or changing them. Other Inventory/WorkerState/DispatchPolicy/Completion/MachineProgress owners remain unchanged.

## Verification

Before production edits freeze actual aed3f64 provenance and a bounded old trace, adapting only external D:/Tes/eatventure-analysis/dispatch-policy-pr/validation-records/sdd-aed3f64/trace-runner.gd. Retain four real seed42/5000+1000 scenarios, unique sales, dispatch/machine/command/save/lifecycle coverage. Add every arrived/lost callback as compact lifecycle state (records/queue/IDs/lost/ramp/clocks/RNG and event) plus full snapshots only first event kind per scenario. Require positive admissions/rejections/departures; add a bounded focused legal patience/capacity scenario BEFORE old freeze if normal scenarios lack it. Capture callback-before-removal behavior and preserve frozen old/runner/provenance hashes. Each trace<=50MiB, no full every-tick/event states, no overwrite or byte-array dumps; compare whole binaries after.

Write full guarded behavioral tests BEFORE any helper/production edit, then observe assertion RED (not existence-only coverage or preload parse failure). Literal tests cover every owner API, initial instance independence, key order and alias identity, ramp limits/zero, reverse diner epsilon, negative/zero overflow budgets, FIFO claimed-head behavior, strict patience/no-timeout for claimed/paid, post-callback removal and static transitions. Rules tests cover all ten forwarding fields/reset/accepted and rejected load, unchanged save keys, event/query/worker cleanup order, reentrant lost callback mutation, arrays replaced during callback, fixed/exponential RNG and rejection/option short circuits. Existing sales tests remain unchanged and passing. Runtime logger errors must fail even exit0.

Full final suite once, literal golden `-- --check`, tea/pancake/noodle scenes, final trace, and parent10 independent integration groups. Every actual subprocess record retains command array, cwd/APPDATA, exit, elapsed, stdout/stderr hashes and separate runtime/assertion diagnostics. Validate Godot user-argument separator BEFORE execution. Capture parent command/hash metadata at original execution, not reconstructed later. New/untracked files get whitespace checks before freeze and parent staged check before commit. Reuse exact-source evidence; no redundant passed runs.

## Global Constraints

Use D:/Tes/eatventure on codex/order-lifecycle; no new worktrees/main writes/merges. Every engine D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe --headless with explicit APPDATA under D:/Tes/eatventure-analysis/order-lifecycle-userdata/session-lifecycle-userdata/<runner>. No local --import or visible-window probes. Preserve save format, assets, fonts and content. Owner no class_name/cycles/Rules-host-context-callback-SpecShop-nav-RNG-service dependencies/cache/serialization/new Rules construction. Sales may preload owner script only for its static customer transitions. Worker no subagents/staging/commits. Evidence D:/Tes/eatventure-analysis/order-lifecycle-pr/validation-records. Real-userdata manifest READY before first engine, verify unchanged after, never auto-restore. Baselineaed3f64 has336 tests and Godot4.7 CI42732251537 SUCCESS; do not rerun unchanged baseline. Archive own workflow only by hash-verified copy, no binary duplication; leave ignored siblings and do not retry blocked recursive deletion.
