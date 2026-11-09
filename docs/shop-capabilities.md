# Shop configuration capabilities

`game/rules/shop_spec_validator.gd` is the authoritative machine-readable contract. Call `validate(shop, campaign)` before constructing runtime rules or reading a shop save; each diagnostic contains `code`, `path`, and `message`. `summary(errors)` formats those diagnostics. `capabilities(mode)` returns field policies with `status` (`supported`, `mode_fixed`, or `reserved`), allowed `values`, or the required reserved `default`. The helper does no loading, saving, scene construction, or ShopRules construction.

Session startup validates both the store definition and a separately injected rules definition before loading/quarantining a save or acknowledging `fresh_shop`. Scene startup additionally checks art before Session startup. Pure ShopRules remains usable directly by rule tests; callers of that low-level API are responsible for validating configuration.

## Fulfillment: every exported field

S = supported behavior; F = mode policy, reject other declarations; R = unused in this mode, retain the stated resource default.

| Field | single | handoff | Consumer / policy evidence |
|---|---|---|---|
| `handoff` | F `single` | F `handoff` | `_tick` selects execution engine |
| `taker` | F `follower` | F `front` | `_find_job_single`, `_jobs` implement these roles |
| `dine_rule` | F `takeaway_only` | F `seat_first` | Single queues; `_add_order` assigns available seats. `share` is unsupported |
| `pay_at` | S `on_take`, `on_deliver` | F `on_deliver` | `_finish_work_single`, handoff serving completion |
| `price_rounding` | F `order_round` | F `dish_tenth_carry` | Single `order_price_single`; handoff dish quote and sale carry |
| `leave_queue` | F `after_take` | F `after_deliver` | Single take completion removes queue entry; handoff delivery removes order |
| `wait_area` | F `wait_seats` | F empty | Single paid/waiting representation and `wait_seats` |
| `leave_who` | F `queued_unclaimed` | F `none` | `_customers_single` only expires unclaimed queued customers |
| `arrival` | S `fixed`, `exponential` | F `fixed` | `_arrivals_single`, `_tick_handoff` |
| `addon_dish` | S optional dish ID | R empty | `_spawn_single`, `_order_steps`, `order_price_single`, sold counts |
| `addon_chance` | S 0-1 | R 0 | `_spawn_single` uses the `f` alias |
| `addon_first` | S boolean | R true | `_order_steps` orders primary and additional recipe |
| `takeaway_station` | R empty | S optional station ID | `_add_order`, `_tick_handoff` switch waiting customers to takeaway |
| `mood_seconds` | S zero or two ordered thresholds | S same | `order_mood`, also called for single customers by the view |
| `seated_patience` | R 1 | S nonnegative | `order_mood`; only handoff orders have a seat index |
| `leave_after` | S nonnegative; 0 disables | R 0 | `_customers_single` |
| `ramp_start` | R 1 | S 0-1 | `ramp` uses alias `f`; handoff `_add_order` advances ramp |
| `ramp_orders` | R 0 | S nonnegative | `ramp`, `_add_order`; single does not advance ramp |
| `opening_customers` | R 0 | S nonnegative | `unlock` immediately adds orders when the handoff order list is empty |
| `first_customer_delay` | S nonnegative | R 0 | `unlock` sets the single arrival timer |

Single `after_pay` is a compatibility alias only with `pay_at=on_take`. With `on_deliver`, it would misdescribe actual queue departure and is rejected. Production single data now declares `after_take`.

Fixed single arrivals use the configured interval, quantized by the existing 0.1-second simulation step. They draw no random arrival interval. Exponential single arrivals retain `-log(1.0 - rng.randf() * 0.999) * interval` at the original point before customer creation. Handoff scheduling is unchanged. RNG state and the next-arrival timer remain in the existing save format.

## Dispatch: every exported field

| Field | single | handoff | Consumer / policy evidence |
|---|---|---|---|
| `base_scores` | R `{}` | S known task keys | `_score`; chore/follow/follow_step/load/load_short/pot_short_bonus/serve/stir/to_process/to_rack/topping |
| `wait_bonus_per_second` | R 0 | S nonnegative | `_jobs`, `_new_ticket_job` |
| `wait_bonus_cap` | R 0 | S nonnegative | Same capped waiting bonus |
| `shortage_bonus` | R 0 | R 0 | No consumer |
| `shortage_per` | R 0 | R 0 | No consumer; actual pot shortage uses `base_scores.pot_short_bonus` |
| `shortage_cap` | R 0 | R 0 | No consumer |
| `travel_penalty` | R 0 | S nonnegative | `_allocate` uses alias `d` |
| `merge` | F `fixed` | F `carry` | Single follows one customer; `_new_ticket_job` merges adjacent matching dishes to worker capacity |
| `merge_cap` | F 1 | F 1 | Single one-order policy; no configurable handoff cap |
| `resume_from_stock` | R true | S boolean | `_start_stage` |
| `help_while_waiting` | F true | F true | Single pot chores; handoff `_follow_jobs` offers pot jobs while ticket waits |
| `chores_first` | S boolean | R false | `_find_job_single` |
| `leave_seated_segments` | F true (neutral declaration) | F true | Handoff worker jobs/ticket ownership exclude staffed segments; not a configurable toggle |
| `throughput_weight` | R 0 | S nonnegative | `_allocate`, alias `d` |
| `fatigue_weight` | R 0 | S 0-1 | `_allocate`, alias `d` |
| `fatigue_gain` | R 0 | S nonnegative | `_tick_handoff` |
| `fatigue_recover` | R 0 | S nonnegative | `_tick_handoff` |
| `hop_seconds` | R 0 | S nonnegative | Carry pickup/dropoff and `_allocate` estimated duration |
| `ticket_give_up` | R 0 | S nonnegative | `_drop_stuck_tickets`; 0 immediately abandons a blocked ticket |

Changing unused fields is rejected, not advertised as tuning. The normalization removes Tea's unused shortage values and Pancake's unused scores/resume/seated overrides. It changes no effective economic or timing value.

## Data validation boundary

The validator checks required nested resources, nonempty primary collections, collection-local IDs, null entries, finite numeric/vector/rectangle data, numeric domains, station block parameters, recipe/station/item references, upgrade effects and targets, stage menus/tasks/slots, staff recruitment, seats, flyers, connections, order options, event choices, guide structures, and layout aliases and grid shapes. Required stations must be reachable through initial availability, stage unlocks or companions. Single recipes/options cannot declare take or hand actions because the engine inserts them; conveyor declarations require handoff. Each stage needs at least one weighted recipe that can be produced by its available station graph. Handoff processing machines need defined outputs, and non-front recipes need a kitchen chain.

Metadata stays extensible: guide/event condition vocabulary and display text are not parsed as arbitrary unknown machine parameters. Recognized station UI parameters include `facing`, `panel_title`, `frame_title`, `materials_label`, `unit`, and `slot_label`. Existing `dine_per_dish` and manual-operation declarations are retained as compatibility metadata; the Fulfillment/Dispatch tables are the exhaustive policy matrix in this change.

Compatibility includes the empty unzoned staff upgrade-track ID, front counter starting posts, and flavor metadata without material slots (as used by the third fixture). `open_flavor` effects supply upgrade presentation labels; actual material gating is `requires_level`. A dish ID is accepted for legacy label metadata as well as a material ID. No shop, dish, or station IDs are hardcoded.

This is a necessary structural contract, not an economic solvability proof or navigation reachability solver. Scene structure and art transforms belong to `presentation/shop/shop_scene_contract.gd`; actual business completion is covered by the rule and live fixture regressions. Tests do not re-record business baselines.
