# Presentation state ownership boundary

User approved the next architecture PR: pause/tuning writes use official commands; presentation receives detached state instead of live mutable collections or private methods. Keep active business rules, visual layout/assets, existing commands/messages, save formats, source event order and current migration policies. Fulfillment/employee/inventory module splitting remains a later PR.

## Writes and lifetime

Extend the canonical command contract with `set_paused` requiring `paused: bool`, and `set_tuning` requiring `key: String`, finite numeric `value` (int or float, never bool), optional `snap: bool = false`. Unknown arguments/keys and wrong/nonfinite values return existing `invalid_argument` without mutation. Tuning keys are `seat`, `customer`, `walk`, `work`, `price`, plus every current station ID. Existing legacy saved tune entries are not dropped or reinterpreted.

Central bounds are min0.25/max3.0 and slider step0.05, shared by runtime and tuning UI metadata. With snap true normalize exactly `clampf(snappedf(value, 0.05), 0.25, 3.0)`; otherwise clamp only. Slider changes request snap true; config loading requests false, preserving valid unsnapped precision. Every successful tuning write stores its normalized value even when effectively unchanged, preserving explicit keys. Success params include `previous`, `value`, `changed` (using the existing approximate-equality logging rule), plus key where relevant. Pausing writes only the boolean. Do not add rule events, reset active timing, charge currency, save or log from these core controls.

Add `ShopSession.execute_command(command: String, arguments: Dictionary = {}) -> Dictionary`. It forwards to Rules only for an active, correctly configured session. Before start/blocked startup/after committed transition returns new `session_unavailable` code with command param and no rule mutation. Map that code to existing-font text in the neutral catalog. Do not clear existing persistence/startup warning diagnostics on successful business commands. Production presentation routes all rule writes through this owner (directly or a thin scene forwarding method); headless Rules commands remain supported.

Tuning logging, labels and ConfigFile persistence remain UI/service responsibilities: record changed slider values only, do not log/save while loading settings, skip bad settings independently, honor disabled persistence and successful-write checks. Pausing keeps its current refresh/save timing. Restart still resumes immediately and retains tuning through existing session behavior.

## Reads

ShopView is the trusted read-model boundary. Shared SpecShop/assets are read-only definitions; public scalar/numeric getters and the stable event bus remain permitted. Presentation may not directly read Rules' runtime dictionaries/arrays, return live workers/customers or access navigation objects/private rule methods. Internal Rules, App/session services and tests may still own/mutate state; this PR is an application boundary, not a security sandbox or removal of every public GDScript field.

Add data-only, deeply detached APIs, optionally implemented in `game/rules/rule_presentation_snapshot.gd` without class_name:

- `render_snapshot()`: clock/gold/revenue/sold/lost/paused/stage_index/completed_at/shelf_count, workers/roster/stations/shelf_stock/orders/customers/queue/diners/belts/belt_items/seats, and stage_queue_capacity. Preserve the current iteration order and worker/job/path/timing data required by visual consumers. No SpecEvent, Rules, nav, RNG, bus/log or other live objects in this data.
- `roster_snapshot()`, `deployed_snapshot()`, `worker_snapshot(id)`, `customer_snapshot(id)`: fresh detached rows/arrays; missing IDs return empty dictionaries. `deployed_count()` and `is_deployed(id)` return scalar values.
- `progress_snapshot()`: independent levels and tune maps, for logging/marking. `activity_snapshot()`: clock/stage_index/gold/revenue/sold/lost, queue/queue_capacity/angry_count, staff_count/idle_count, machine_working map keyed by pot+automatic station IDs, seat_count/seats_used/customer_interval. These are actual public rule query values, preserving log aggregation.
- `guide_snapshot()`: lost, staff_count, seats_owned, any_angry, angry_cause, slow_machine. Move existing queue/order/chain scans to the read model; preserve guide priorities/fallbacks and retain UI `_lost_seen` bookkeeping in the guide.
- `staff_kind(id)`: plain descriptor id/display_name/role/description/stats, preserving existing kind fallback. `art_visible(rule)`: current layout-group visibility query. `post_point(id)`, `navigation_point(id)`, `walkable(point, from)`: value-only navigation queries; never expose RuleNav.
- `tuning_limits()`: min/max/step metadata used by UI bounds. Existing message formatter/status fields and numeric query semantics remain intact.

Do not use to_dict/load_dict, binary serialization or fresh ShopRules construction to produce snapshots. Copy only requested runtime data; never copy logs/RNG/full simulation for an employee or frame. No persistent hidden snapshot cache. Root visual refresh captures one frame snapshot after simulation and passes it to related render functions. Fresh helper calls after commands/reset must observe latest state; retaining or editing a returned snapshot must never change live state. Consumers may use independent small projections rather than repeatedly creating a complete frame snapshot.

Migrate all presentation consumers: scene actors/cups/customers/dining/roster helpers, staff dragging/navigation, staff page, menu, tuning, guides, art groups and recorder (including its `sim` alias). ShopView may read runtime internals as projector owner. Presentation may retain ordinary read-only scalar queries, immutable shop definitions, explicit event subscription and canonical check methods. It must not use worker_by_id/customer live getters, Rules.nav, `_kind`, `_order_interval` or mutable collections through any alias.

The tuning customer-interval caption now uses public `customer_interval()` (actual mode semantics). The tuning marker's queue count uses actual `queue_size()` instead of handoff-only orders.size(), correcting the single-worker debug marker. Neither changes business arrival/queue behavior. Preserve recording JSON field names, cadence and aggregation otherwise.

## Evidence and delivery

Test raw/snap clamp precision, same-value explicit keys, validation atomically rejecting bad inputs, active timing preserved, no new events, pause/resume and inactive-session writes. Test snapshots across tea/pancake/noodle with nonvacuous work/orders/paths; mutate nested copies and retained snapshots across steps/upgrades/restart, and verify live bytes/aliases/RNG/events unchanged. Compare projections to actual state and preserve visual ordering. Check session diagnostics survive commands.

UI tests must show old all_staff() aliases live rows and old controls bypass an owner spy as actual RED. Then real controls/slider/config load/recorder/drag/hire/restart/leave must use official writes and fresh snapshots; inactive writes do not alter state/config/log. Add a narrow source boundary guard as supplementary coverage, not the only evidence. Existing successful tests, golden layout/business baselines and save/query/code regressions stay green.

Use D:/Tes/eatventure in place with no worktrees. Every engine --headless, explicit disposable APPDATA containing session-lifecycle-userdata, no local --import/visible-window probes. Independent task/whole reviews and Godot4.7 CI required. Stack on #70 if still open, otherwise rebase own changes onto latest main, preserving human edits. No merges; archive only this plan's records without retrying known policy-blocked recursive cleanup.
