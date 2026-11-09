# Inventory ownership and reservations

`game/rules/rule_inventory.gd` owns the existing `stations`, `shelf_stock`,
`shelf_count`, `shelf_reserved_in`, `shelf_reserved_out` and `generated` state.
Each `ShopRules` instance creates its own owner before its forwarding properties
are used. Existing field names, dictionary assignment and nested mutations stay
available; save keys, types and restoration policy are unchanged. Reset replaces
the current maps through those same properties, and atomic load adopts the
validated candidate's maps without caching old dictionaries.

The owner is a no-argument `RefCounted`. It has no shop specification, Rules,
worker, order, RNG, event or callback dependencies. Passed job dictionaries are
read-only inputs and are never stored. `SHELF` and `RACK` constants originate
there; Rules retains aliases.

Handoff transfers use `reserve`, `take`, `deliver` and `cancel`. Reservation
leaves physical goods unchanged; pickup releases the source claim; delivery
adds goods and releases the destination claim. Cancellation returns carried
goods to the original source or releases an unpicked source claim, then releases
the destination/work claim. Supply pickup increments `generated`; cancelling
carried supply goods reverses that increment. Calls represent one transition,
so callers must not repeat a completed transition. Counters are not clamped or
silently repaired.

Work and pot-start operations consume station input; ordinary transfers consume
output. Pot-take and stir claim work without reserving source goods. Processing
and active manual-work phases survive source refresh. `stock`, `is_operation`
and `refresh_after_pickup` are shared static helpers. `deliver` receives an
already normalized item: Rules maps cups for shelf/pickup destinations and keeps
raw keys for rack/other stations. Belts reserve and take through this same owner
while preserving their timing and shipment order.

Rules still owns ticket/flavor selection, worker paths and phases, order flags,
machine conversions, demand/capacity queries and single-mode execution. Machine
code shares the owner's current station dictionaries; ownership does not imply
that every recipe conversion goes through transfer methods.

Tests assert conservation for explicit local transfer/cancel lifecycles.
Generated materials, processed items and sold dishes cannot be summed as a
global conservation law: recipes and batches transform both keys and quantities,
and single-mode pots may begin with stock.
