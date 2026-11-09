# Presentation state boundary

`ShopSession.execute_command(command: String, arguments: Dictionary = {}) -> Dictionary`
is the presentation write entry point. It forwards only while the session has started,
has valid dependencies and has not committed finish/jump. Otherwise it returns
`session_unavailable` with the command name. Successful commands retain existing
startup/persistence diagnostics. Headless callers can still use
`ShopRules.command_status` / `execute_command` directly.

The canonical controls are `set_paused {paused: bool}` and
`set_tuning {key: String, value: int|float, snap: bool = false}`. Numbers must be finite
and booleans are rejected as numbers. Tuning accepts seat/customer/walk/work/price and
current station IDs. Unknown keys/arguments and invalid types return `invalid_argument`
atomically. `RuleNumbers` owns bounds 0.25–3.0 and step 0.05. Raw writes clamp only;
snapped writes apply `clampf(snappedf(value, 0.05), 0.25, 3.0)`. Every successful tuning
write stores an explicit key, including unchanged defaults. Results include previous,
value and changed (approximate numeric equality), plus key for tuning. Controls do not
emit events, save, log, charge currency or restart active timers.

`ShopView` returns fresh, deeply detached data on every call; there is no cached frame.
Capture one `render_snapshot()` after simulation for related render passes. Retained or
edited results cannot mutate the simulation, and later calls observe commands/reset.
Runtime snapshots contain no Objects. Shared read-only `SpecShop`/art definitions remain
outside snapshot payloads.

| API | Returned data |
| --- | --- |
| `render_snapshot()` | clock, gold, revenue, sold, lost, paused, stage_index, completed_at, shelf_count; workers, roster, stations, shelf_stock, orders, customers, queue, diners, belts, belt_items, seats; stage_queue_capacity |
| `roster_snapshot()` / `deployed_snapshot()` | Complete copied worker rows in existing iteration order, including stats/job/ticket/steps/path and timing data |
| `worker_snapshot(id: int)` / `customer_snapshot(id: int)` | Copied row; `{}` for an unknown ID |
| `deployed_count()` / `is_deployed(id: int)` | Scalar deployed count / ownership fact |
| `progress_snapshot()` | Independent levels and tune maps, preserving explicit and legacy tune keys |
| `activity_snapshot()` | clock, stage_index, gold, revenue, sold, lost, queue, queue_capacity, angry_count, staff_count, idle_count, machine_working, seat_count, seats_used, customer_interval |
| `guide_snapshot()` | lost, staff_count, seats_owned (purchased group count), any_angry, angry_cause, slow_machine |
| `staff_kind(id: String)` | id, display_name, role, description, copied stats; existing first-kind fallback |
| `art_visible(rule: String)` | Current always/station/belt/ingredient_box/box/flavor/wait_seats visibility |
| `post_point(id: String)` / `navigation_point(id: String)` | Vector2, preserving existing aliases/fallbacks |
| `walkable(point: Vector2, from: Vector2)` | Existing reachability query as a boolean |
| `tuning_limits()` | Fresh min/max/step map from central numeric metadata |

Activity uses actual rule queries for both fulfillment modes. Its machine_working map
contains pot IDs followed by automatic station IDs. Guide selection preserves existing
seat → staff → machine priority, first queued customer / oldest order selection and
machine fallbacks. Lost-customer history (`_lost_seen`) remains guide UI bookkeeping.
Existing ShopView status/message and numeric APIs remain compatible. Projections copy
only the requested runtime containers; they do not serialize or rebuild the game.

Presentation consumers use the boundary as follows:

- `shop_play.execute_command()` is a thin forwarding entry to its session; menu pause,
  tuning sliders/reset/config load, all business buttons and drag placement go through
  it. Slider commands request `snap: true`; valid finite config numbers request
  `snap: false`. A rejected write returns before tuning labels, recording or config
  persistence. Loading settings never records or writes the config/shop save. Changed
  slider writes retain existing tune-log behavior; pause retains existing save timing.
- Each root `_refresh()` captures one detached render frame and passes it to actors,
  cups, customers and dining in their existing order. Direct calls to the retained
  visual helpers obtain a fresh optional snapshot. `all_staff()` returns a fresh
  roster; drag hits/ghosts, staff cards and guide staffing use small fresh projections.
  No persistent frame cache exists.
- Art groups ask `art_visible()` and guides ask `guide_snapshot()` while retaining UI
  lost-customer history. Navigation/drop geometry uses value-only view queries.
  Recorder stores a `ShopView`, reads activity/progress projections, and keeps existing
  JSON fields, aggregation and 60-second cadence. Its `setup()` also accepts Rules for
  existing headless callers, immediately wrapping it in a view instead of retaining
  a simulation alias. The tuning marker and customer caption use actual public queue
  and interval values for both fulfillment modes.

`tests/test_presentation_boundary.gd` combines real detached-row/art behavior with a
supplementary narrow source guard. The guard follows Rules/sim/typed/simple aliases,
rejecting runtime container/live-row/private/navigation access and direct writes or
command dispatch. Public scalar queries, immutable shop definitions and event-bus
subscription remain allowed; it is not a GDScript security sandbox.
`tests/render_presentation_boundary.gd` exercises real production scenes with an
isolated owner spy, real mouse button clicks/body drag input, configuration and recording
services, retained/fresh frames, hire/restart/save roundtrip, and unavailable/closed
sessions. Runtime errors fail the runner; its internal timeout is 25 seconds and CI
bounds it at 30 seconds under disposable `session-lifecycle-userdata`.
