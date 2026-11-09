# Fulfillment definition planning

`game/rules/fulfillment_plan.gd` is a stateless preload helper extending
`RefCounted`, without a global `class_name`. It reads the current `SpecShop`
definition and caller order values. Its public static APIs are:

- `derive(shop: SpecShop) -> Dictionary`: counter/supply/pickup IDs; pots,
  autos, seatables, dish IDs and front/kitchen partitions; chains and station
  input/output mappings.
- `single_steps(shop: SpecShop, counter_id: String, order: Dictionary) -> Array`:
  the existing single-worker take, dish/addon, selected options and hand rows.

Every call returns fresh caller-owned arrays and dictionaries containing data
only. Definitions remain shared read-only inputs; changing a returned nested
container cannot change definitions or another result. There is no cache, so a
later call sees later definition changes while an earlier result retains its
values. The order requires `kind` and `addon`; `options` defaults to an empty
array. As before, the counter and requested dishes must exist, and the shop must
have fulfillment/layout definitions. Definition validity remains the validator's
responsibility.

Derivation follows definition iteration order. It selects the last counter,
first supply and last pickup with `process_seconds`. Only nonmanual combines
enter autos; batch pots and seatable stations retain definition order. Each
dish chain excludes missing stations, supplies, pickups, counters and front-zone
stations, and includes each remaining station once. A station input is the first
consumed item already produced earlier in the dish; its first assignment across
all dishes wins. Output mappings retain the last produced key for each
station/dish, including later steps at the same station. Front/kitchen dish
partitions use the dish's `front` flag independently of station zones.

Step expansion preserves all original row fields and ordering. The configured
addon runs before or after the main dish and is not duplicated when it is itself
the main dish. Options retain requested order and duplicates; unknown options
and options without steps are skipped. An option step's empty station falls back
to the option station. A layout alias matching `station.action` makes that alias
key the row point; otherwise the station is the point. Seconds are the definition
seconds multiplied by repeat; holds is the first produced key, or empty. Fixed,
into-machine and put-down flags remain intact. Counter labels depend on payment
mode, with the original take/hand seconds and their smaller row shapes.

`ShopRules` keeps typed role arrays and uses `assign` when accepting the plan.
Its `_order_steps` facade delegates to this module. Live execution, random option
selection, inventory/reservations, price/payment, events and persistence remain
with their existing owners. Saved in-flight worker steps continue as stored;
loading does not reconstruct them from current definitions. There are no state
key, fingerprint, save format or migration changes.

`tests/test_fulfillment_plan.gd` checks standalone synthetic definitions with
literal expectations, the real pancake route, addon/payment/option cases,
ownership, fresh reads, and all three shops' unchanged definitions, orders,
live state, RNG and event log. A separate ignored validation probe captured full
old/new three-shop state traces before and after extraction, including active
work, sales, legal commands and save/load continuation. Those binary traces
match exactly.
