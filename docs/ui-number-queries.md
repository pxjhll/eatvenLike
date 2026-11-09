# UI numeric query contracts

`ShopRules` owns gameplay calculations. UI consumers query `ShopView`; they must not rebuild modifier stacks or change the game's settlement policy to match a label.

## Employee attributes

`ShopRules.effective_worker_stats(worker)` returns `walk`, `work` and integer `carry`, using `walk_speed`, `skill` and `carry`. It includes the worker's region, seated bonuses, targeted modifiers and live tuning. `worker.stats` remains the base data.

`ShopView.worker_card(worker).stats` contains those effective values. `cultivation` describes the purchased upgrades for `side_of(worker)` and the total available for that region/shop; `cultivation_scope` names the region/shop track. It is shared cultivation, not an individual employee level. Personal `level` is no longer exposed by the card. `stat_text` displays up to two decimal places without trailing zeros.

`ShopRules.worker_stat_limits(worker)` computes this employee's stats with its regional cultivation track completed, under the current tuning and other modifiers. It temporarily previews the track and restores both level and modifier order exactly. Each maximum is at least the current effective value. `worker_card.stat_limits` supplies the normalization for the bars; no universal gameplay stat caps are invented. A fully cultivated employee can fill a bar regardless of species or shop, and an employee with future growth does not hit an obsolete fixed cap.

## Operation time

`ShopRules.manual_operation_seconds(station_id, base_seconds, worker = {}, fixed = false)` is the query used by manual recipe execution and handoff work jobs. Omitting the worker means operation skill 1. Fixed recipe actions ignore station speed/duration upgrades but still accept the station's time tuning. A batch pot's manual pickup likewise ignores its cooking upgrade. The automatically timed cooking operation still uses `pot_seconds`.

`ShopRules.station_timing(id)` returns `seconds`, untuned `base_seconds`, `automatic` and a semantic `unit` (`cooking_batch`, `batch`, `item`, or `operation`). Automatic combine machines work per batch; manual combine stations use a manual operation. A single-order station's representative operation is its first non-fixed recipe step, including repeats, then its first option step if no recipe step exists. This deliberately excludes other steps, walking, waiting and employee skill: it is never a complete service/order estimate. Station parameter time is the fallback. Existing pot load/unload preparation chores retain their fixed runtime behavior.

`ShopView.station_timing` localizes the unit, `seconds` is a compatibility accessor, and `timing_text` produces the short baseline label used in tuning. A real employee's action can be shorter or longer than the baseline because of skill; it must be obtained using that employee in the manual query. Automatic process-slot throughput retains the existing `machine_seconds` semantics.

Single-order cooking captures `duration` when the pot starts. Progress uses that duration, so later upgrades/tuning affect subsequent pots. On loading an old active pot whose duration is zero or missing, `load_dict` captures `max(remaining, current pot_seconds)` once. No old save can reveal its original starting duration; this fallback remains stable after tuning. The display also has a defensive current-duration fallback for directly constructed legacy state.

## Prices and settlement

`ShopRules.dish_quote(dish_id)` returns:

- `calculated`: the existing `dish_price` result, including all current modifiers and price tuning.
- `policy`: the existing fulfillment `price_rounding` string.
- `solo_payment`: present for whole-order rounding only; the exact `order_price_single` result for one dish with no addon or options.

For `order_round`, option multipliers and an addon are combined before rounding the total. Adding individually rounded solo payments is incorrect; use `order_price_single` with the actual order. For `dish_tenth_carry`, `calculated` preserves tenths and real deliveries accumulate the fractional carry. Such a quote deliberately has no fixed solo-payment field, because the current carry affects each receipt.

`ShopView.price_preview(key).now/next` keep their existing calculated-price meaning, including `next = -1` at maximum level. `quote_now/quote_next` carry the full quote (at maximum, both refer to the current quote); `payment_now/payment_next` are separate fields for exact solo payments when applicable. `partial` says the shown upgrade has effects on a price part. The UI labels that as a partial-price bonus without presenting a mixed product of whole-dish and part modifiers as one whole-dish multiplier. Concrete upgraded totals always come from `rules.preview`.

`quote_text` distinguishes calculated whole-order prices from solo receipts and explains tea's fractional carry. `quote_primary` keeps upgrade comparison cells short (solo receipt or dish unit price). `quote_change` shows the calculated before/after and solo receipt before/after once, with a single no-options/carry explanation. `price_text` preserves a meaningful decimal in material rows. Unlock cards show current effective quotes; fixed resource descriptions/notes are marked as base descriptions, so their static base prices are not mistaken for current quotes.

## Regression entry points

Run `tests/run_all.gd` for nine numeric consistency cases alongside the existing suites. The cases exercise real cultivation/upgrades, recipe arrival timers, complete delivery with tuning, single-order receipts, tea carry, and active-pot save restoration. `tests/render_shop_pancake.gd` additionally checks live staff numbers/cultivation and timing labels/sliders in an isolated scene. Tests do not read or change real player saves/tuning.
