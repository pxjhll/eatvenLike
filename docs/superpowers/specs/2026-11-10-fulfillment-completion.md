# Fulfillment settlement and completion

## Intent

Continue the approved architecture sequence after WorkerState. Extract sales state and completion effects from ShopRules without changing simulation, saved data, commands, pricing, or callbacks. Arrivals and dispatch stay in Rules. One PR stacks on codex/worker-transitions (7c3fe62) while PR74 remains open.

## Boundaries

`game/rules/rule_sales.gd` extends RefCounted without class_name and owns gold: float, revenue: float, sold: int, sold_by_dish: Dictionary, sale_carry: float. Rules initializes `_sales` before its forwarding properties and keeps its existing names, types, STATE_KEYS, BY_DATA_ID and `_sale_carry` save key. Reset and candidate load address the current owner through the properties; no cached dictionary or duplicate counters. Other money writes still use the same Rules properties.

Exact Sales APIs:

* `count_handoff(dish: String, count: int) -> void`: increment sold then sold_by_dish[dish].
* `credit_handoff(job: Dictionary, unit_price: float) -> Dictionary`: earned = unit_price * job.count + sale_carry; income = floori(earned + 0.0001); sale_carry = maxf(0.0, earned - income); credit gold and revenue. Return {dish: job.item, count: job.count, income: income}.
* `accept_single(customer: Dictionary, quoted_price: int, pay_on_take: bool) -> void`: credit gold/revenue iff pay_on_take; set paid and state="paid".
* `complete_single(customer: Dictionary, addon_dish: String, pay_on_take: bool) -> Dictionary`: credit customer.paid iff not pay_on_take; state="leaving"; increment sold_by_dish[customer.kind] with int conversion, sold; if addon and kind != addon_dish also increment addon dish and sold. Return {dish: customer.kind, income: customer.paid}.

Rules owns seat/diner handling, price queries, queue removal, event emission and WorkerState cleanup. Handoff counts occur AFTER diner handling and BEFORE dish_price. Single take erases queue BEFORE order_price_single. Single hand emits sale BEFORE finish_single_order. No idempotency token or new eligibility guard: ordinary execution remains exactly once. Event payload shapes remain distinct for handoff/single.

`game/rules/fulfillment_completion.gd` extends RefCounted without class_name and exposes static APIs:

* `consumes_handoff_source(job: Dictionary) -> bool`: true for pot_start and work; false for stir/pot_take (valid operation kinds).
* `complete_handoff_work(station: Dictionary, job: Dictionary, pot_seconds: float) -> void`: pot_start sets processing=count, duration=pot_seconds, remaining=duration, progress=0, phase=heating; stir sets phase=heating only; pot_take adds processing to first output key, sets processing=0, phase=ready, progress=1; work calls complete_topping and sets phase=ready/progress=1. All set work_reserved=false; retain all other fields.
* `complete_topping(station: Dictionary, job: Dictionary) -> void`: nonempty processing_item adds count to that output and clears processing_item; otherwise adds count to input[job.item].
* `complete_single_chore(worker: Dictionary, station: Dictionary, load: bool, duration: float, batch: int, capacity: int) -> void`: load sets phase=cook/duration/remaining; unload sets stock=min(capacity,stock+batch), phase=idle; both clear station.user=-1 and worker.chore="", retain other fields.
* `advance_single_step(worker: Dictionary, station: Dictionary, exclusive: bool) -> void`: current step action take only increments worker.step. For other nonterminal recipe steps, retain user for adjacent step at same station; otherwise release if exclusive. If holds nonempty set carry_item=holds/carry_count=1. Increment step. Terminal hand is handled by Rules and never passed here.

Rules keeps `_take(job)` BEFORE pot duration query/completion, and `_finish(worker)` AFTER completion. `_complete_topping` stays as compatibility facade. Rules calls finish_single_work first. Pure numeric queries for chore duration/batch may be evaluated before mutation; verify no station-phase dependency. Avoid querying unused arguments. No helper retains Rules, callbacks, bus, SpecShop, navigation, RNG, services, global cache or mutable singleton. No serialization/whole Rules clone inside production helpers. Inventory and WorkerState remain unchanged.

## Verification and scope

Before production edits freeze a bounded old trace runner/source provenance from 7c3fe62, tea mobile/seated plus pancake/noodle seed42, legal funded commands and meaningful work/sales. Check complete state checkpoints, phases, command/save/load/reset/reopen behavior and synchronous callback state; capture per-order sale identity and monetary snapshots. No full every-tick snapshot; each trace <=50MiB. Frozen old data is never overwritten. Compare byte equality as boolean, emit short diagnostics on failure.

Add independent literal tests: carry/floor epsilon and cumulative money, both pay modes, addon dedup, forwarding/replacement/reset/load, exact event payload/order; all operation kinds, topping branches, load/unload/cap, adjacent exclusive steps/take/holds and unrelated-field retention. Guard missing modules with assertion RED rather than preload parse errors. Runtime logger errors fail even if process exits zero. Include tests in run_all. Full final suite, golden and tea/pancake/noodle scene smokes plus final parent integration groups. Reuse passed exact-source evidence rather than rerun unchanged suites.

Use D:/Tes/eatventure on codex/fulfillment-completion; no new worktrees/main writes/merges. Every engine D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe --headless with explicit APPDATA under D:/Tes/eatventure-analysis/fulfillment-completion-userdata/session-lifecycle-userdata/<runner>. No local --import or visible-window probes. Preserve save format, assets, fonts and content. Record real-userdata file manifest before first engine and verify unchanged afterward; never auto-restore real data. Evidence D:/Tes/eatventure-analysis/fulfillment-completion-pr/validation-records. Archive only this plan's workflow with hash-verified copy; leave ignored sibling workspaces and do not retry recursive deletion.
