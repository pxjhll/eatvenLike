# Shop configuration capabilities

`game/rules/shop_spec_validator.gd` is the authoritative machine-readable contract. Call `validate(shop, campaign)` before constructing runtime rules or reading a shop save; each diagnostic contains `code`, `path`, and `message`. `summary(errors)` formats those diagnostics. `capabilities(mode)` returns field policies with `status` (`supported`, `mode_fixed`, or `reserved`), allowed `values`, or the required reserved `default`. The helper does no loading, saving, scene construction, or ShopRules construction.

Session startup validates both the store definition and a separately injected rules definition before loading/quarantining a save or acknowledging `fresh_shop`. Scene startup additionally checks art before Session startup. Pure ShopRules remains usable directly by rule tests; callers of that low-level API are responsible for validating configuration.

正式三店现在必须通过 `SpecShop.runtime_template` 显式声明公共能力，`shop_spec_validator.gd` 会编译模板并要求服务和自动客流。经营推进统一为 `ShopRules._tick → Runtime.step`；`fulfillment.handoff` 不选择正式执行器。ShopSession/ShopPlay 自动消费该 Runtime，模板构造失败禁止启动或保存。

版本2业务存档把 outer 购买/钱包/RNG 与公共 runtime 的唯一活动状态分开保存。三种旧模式只在 `template/legacy_adoption.gd` 的一次性加载边界出现；正式执行不调用它们的 tick/context。公共能力配置、保存和迁移边界详见 `game/rules/template/README.md` 的 U06 节。

以下表格是保留的**旧资源字段与迁移协议**，其旧方法名对应测试历史参考引擎，不能作为新店运行时接口。作者校验暂时保留旧字段约束以保护现有内容；U07继续处理制作入口与门禁，不能据此恢复旧经营分流。

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

## Effect attachment and target contract

The validator checks where an effect is attached, including station, material, staff and flyer upgrade base/level effects, and immediate or choice-based event effects. Membership in `SpecEffect.KINDS` alone does not mean that every context executes that effect.

- Upgrade tracks refresh continuous modifiers; they never execute one-shot effects. `grant_gold`, `customer_wave`, and `unlock_staff_kind` are supported in events, including after a choice is accepted, and are rejected in upgrade tracks.
- `seats` has no modifier consumer. `unlock_recipe` and `shop_news` currently emit signals without implementing the declared gameplay change. These kinds are rejected in configured effects.
- `open_flavor` is allowed only as a station upgrade level's presentation label. It is not an event effect or an automatic unlock, and is not consumed from material/staff/flyer tracks or base effects. Actual material availability uses `requires_level`.
- `price` requires an empty target. Select dishes with `dishes` and optionally `price_part`; a station target is never queried by `raw_price`. A station/material track with no explicit dish scope inherits that station's `price_dishes`.
- Global consumers (`flow`, flyer counts/cooldowns, `event_chance`, `patience`, event gold and customer waves) require an empty effective target. For non-price upgrade effects, an omitted target inherits the station ID, staff track zone ID, or the flyer's empty global target, exactly as `_refresh_track` does.
- Staff attribute modifiers (`walk`, `work`, `carry`, `luck`) accept global empty targets, active `front`/`kitchen` zones, or canonical positive worker IDs such as `staff:1`. Kind IDs, bare numbers, zero/negative IDs, padded digits and alternate spellings do not match the runtime and are rejected. Future worker IDs may be declared before that worker is recruited. Staff-slot modifiers affect only the zoned front capacity, using the global or `front` target.
- Machine modifiers use an existing station target or the global empty target. Dish scopes and price-part selectors are reserved for price effects; adding them to another kind would suppress its runtime match.

## Data validation boundary

Staff regions are either unzoned (`staff.zones=[]`) or exactly the supported `front` and `kitchen` regions. Arbitrary, partial, or duplicate region declarations are rejected. In an unzoned shop, only the empty `stage.staff_slots[""]` key controls total staffing. `staff.front_base_slots` independently controls counter-post occupancy, including in unzoned shops that allow worker placement, so it remains configurable. In a zoned shop, only `stage.staff_slots["kitchen"]` controls stage capacity. Front capacity comes from `staff.front_base_slots` plus supported front/global `staff_slot` modifiers. A stage-level `front` key, an empty key in a zoned shop, or a named region key in an unzoned shop is rejected because the runtime does not read it.

The validator checks required nested resources, nonempty primary collections, collection-local IDs, null entries, finite numeric/vector/rectangle data, numeric domains, station block parameters, recipe/station/item references, upgrade effects and targets, stage menus/tasks/slots, staff recruitment, seats, flyers, connections, order options, event choices, guide structures, and layout aliases and grid shapes. Required stations must be reachable through initial availability, stage unlocks or companions. Single recipes/options cannot declare take or hand actions because the engine inserts them; conveyor declarations require handoff. Each stage needs at least one weighted recipe that can be produced by its available station graph. Handoff processing machines need defined outputs, and non-front recipes need a kitchen chain.

A weighted flavor group needs a valid fallback unless a flavor can be proven available at the earliest menu evaluation. Stage zero can be queried before opening; listing stations there does not prove they are initially unlocked. Later stages use their actual atomic unlock members and direct companions; if the opening station starts unlocked, the stage-zero purchase is not assumed. The proof also checks unpaid supply boxes, material level gates and the need for kitchen staff. It never assumes future purchases or hiring. The third fixture's later-stage flavors require neither material slots nor unpaid boxes, so its existing configuration remains valid.

Metadata stays extensible: guide/event condition vocabulary and display text are not parsed as arbitrary unknown machine parameters. Recognized station UI parameters include `facing`, `panel_title`, `frame_title`, `materials_label`, `unit`, and `slot_label`. Existing `dine_per_dish` and manual-operation declarations are retained as compatibility metadata; the Fulfillment/Dispatch tables are the exhaustive policy matrix in this change.

Compatibility includes the empty unzoned staff upgrade-track ID, front counter starting posts, and flavor metadata without material slots (as used by the third fixture). `open_flavor` effects supply upgrade presentation labels; actual material gating is `requires_level`. A dish ID is accepted for legacy label metadata as well as a material ID. No shop, dish, or station IDs are hardcoded.

This is a necessary structural contract, not an economic solvability proof or navigation reachability solver. Scene structure and art transforms belong to `presentation/shop/shop_scene_contract.gd`; actual business completion is covered by the rule and live fixture regressions. Tests do not re-record business baselines.

## Serve mode

`fulfillment.handoff = "serve"` is the third execution mode, used by the formal third shop (`content/shops/stirfry/shop.tres`). Rules live in `game/rules/serve_flow.gd`; all runtime state is the single saved key `serve`.

- **Flow.** Customers queue at the counter. A front worker takes the order only when a dine seat is free and assigns that seat; the customer then walks there (`customer_walk` px/s). The kitchen works the recipe as a dependency graph; the finished dish goes to the one `pickup` station; a front worker carries it to the seat. Eating starts only when the customer is seated **and** every order line is delivered. Payment (`on_deliver`, `dish_tenth_carry`) settles once per order when the last line arrives.
- **Entities.** guests, orders (`lines[{dish, qty, delivered}]`), units (one per portion), goods (every physical item: where it is, which unit owns it or `-1` = shared stock, which worker reserved it), jobs (per worker). People served, orders completed, items sold and people lost are separate counters.
- **Recipes.** `supply` and automatic `batch_pot` steps are sources (one product, no inputs). `hand` and staffed `combine` steps are work: they start only when all inputs are at that station for that unit and the station is free. By default, inputs for a step are fetched only after its work dependencies finish. Opt-in `prefetch_inputs` prepares independently available inputs per order while the work dependency check still blocks operation. Shared stock from a batch pot is reserved at claim time and becomes the unit's when picked up, so one portion is never taken twice. A dish whose final item comes straight from a source (e.g. soup) is passed from the source.
- **Roles.** Zoned shops: the counter post is front (take, serve, and flow1 front recipe production/transport); unposted kitchen workers flow (carry, work, pass); a worker seated at a machine only works that machine and never carries. Unzoned shops let unposted workers do everything.
- **Cancel.** Recall/re-place releases every reservation and the station; an item in hand goes back to where it was picked up and keeps its owner; nothing is created or destroyed.
- **Rejected for now:** manual-load/unload or stirred batch pots, automatic combine, topping/dispenser blocks, front recipes in flow0, more than one pickup, more than one seat group, conveyors, order options. Dispatch scores use `take / serve / carry / work / pass`.
- **Staff data.** `staff.starting_posts` gives each starting worker its own post (empty = flowing); hire costs are indexed by hires made, i.e. roster size minus starting workers (unchanged for one-worker shops).
- **Graybox.** `tools/serve_graybox/serve_graybox.tscn` draws the raw rule state (stations, shared stock, goods, workers, guests by state) for prototype review; it is not the game UI.

## Serve front production and item artwork

A front direct-sale recipe uses `fulfillment.flow_version=1`, `SpecDish.front=true`, and front-zone stations. A manual drink machine reuses `block="hand"`; all recipe steps stay in the front zone. Kitchen recipes must remain in the kitchen. Existing action/movement, goods reservation, pickup, cancellation and save semantics apply. The normal pickup/payment policy still determines delivery; a front-only main dish does not implicitly gain a kitchen soup addon. Tea and pancake keep their existing adapters.

Adding a recipe adds zero-count inventory slots to existing pickup/work stations during explicit content adoption. Same-content loads remain strict. Existing goods, reservations, timers, stages and active recipe identity are preserved; a flow0 reader protects flow1 saves. Additional equipment must not shift existing stage indices.

`SpecItem.icon` binds the actual product texture, including an AtlasTexture region. `SpecItem.art` retains legacy scene art priority when explicitly set. `ShopView.item_art`, `item_icon` and `icon_of` feed carried goods, tables, order bubbles and HUD icons from one resolver. Missing artwork uses a neutral tag placeholder, never another shop's drink. Bind every intermediate/raw item too; reuse approved prep art where appropriate. User-supplied original sprites must remain byte-identical. Scene art and layout follow the FigCraft confirmation process.

## Opt-in serve logistics and preparation

Serve flow1/shared actions support `dispatch.transport_helpers` (unique front/kitchen roles), `dispatch.preposition_work` and `dispatch.prefetch_inputs`. Native work is considered before assistance; counter staff also wait for approaching guests when a seat is available. Helpers execute only existing carry/pass jobs for another production region, using its existing inventory/claim ledger. A helper never acquires cooking work in the other region.

`prefetch_inputs` allows independently available ingredients to be brought to an order's downstream station before all work branches finish. It does not bypass production dependencies or ownership. `preposition_work` permits a cook to move to a workbench if every missing input already has an inbound transport reservation. The normal action context blocks operation until all actual goods arrive. If a carrier is recalled and the promise disappears, the speculative work lease is cancelled so the remaining employee can fetch inputs. `base_scores.continuation` optionally prioritizes units with completed manual steps over starting more units.

Defaults remain empty/false/zero and are omitted from fingerprints, preserving earlier shops and frozen saves. Enabling helpers requires zoned serve flow1 and actions1; preparation requires serve flow1/actions1. No gameplay state is stored in these flags, and no new inventory or movement implementation is introduced.
