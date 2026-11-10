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

`ShopRules.inventory_diagnostics()` is an opt-in, read-only inspection of the
current inventory, deployed workers, in-flight belts and orders. It is never
called by the simulation tick, command processing or save validation. It neither
repairs counters nor changes which existing saves are accepted. The standalone
`InventoryAudit.inspect(inventory, workers, belt_items, orders, mode, supply_id,
counter_id)` needs no Rules, shop, callbacks or serialization. It assumes the
existing live data shape; the save schema validator remains responsible for
malformed types and missing fields.

Each call returns a fresh Array of data-only `{code, path, expected, actual}`
rows, in deterministic current-state iteration order. The Array and its rows
can be retained or edited without changing live state or future results.

| Code | Meaning and example path | Expected / actual |
| --- | --- | --- |
| `negative_inventory` | Negative goods or counters: `generated`, `shelf_stock.cup`, `stations.machine.input.cup`, `workers[0].carry_count`, `belt_items[0].count` | Zero / original numeric value, including negative fractions |
| `shelf_count_mismatch` | `shelf_count` disagrees with item stock | Sum of shelf items / stored count |
| `reservation_mismatch` | `shelf_reserved_in`, `shelf_reserved_out`, `stations.machine.reserved_in`, `stations.machine.reserved_out.cup` | Independently reconstructed quantity / stored quantity |
| `work_reservation_mismatch` | `stations.machine.work_reserved` | Whether an operation claims the station / stored bool |
| `multiple_work_claims` | `stations.machine.work_reserved` | One allowed owner / actual operation job count |
| `order_reservation_mismatch` | `orders[0].reserved` (current Array index) | Whether a serve job claims this order ID / stored bool |
| `source_over_reserved` | `shelf_stock.cup`, `stations.machine.input.cup` or `stations.machine.output.cup` | Available physical goods in that item/pool / unpicked claimed quantity |

Both modes check nonnegative generated/shelf counters, shelf items, station
input/output/reserved_out/reserved_in/processing/stock/capacity, worker carry
counts and shipment counts, plus the shelf total. Single-mode execution uses
different job fields, so it stops at these basic checks.

In handoff mode, deployed workers with unfinished jobs independently establish
claims. Only unpicked jobs reserve source goods; supply, pot-take and stir need
no source stock. Work/pot-start source from input, transport from output. The
audit checks each pool and item separately rather than allowing transformed or
unrelated goods to cover a shortage. Stored and expected reservation keys are
both checked, including stale positive keys. Operations own work flags; serve
jobs own order flags. Unfinished transfers reserve their destination except the
counter, including carried goods and belts whose source pickup already
completed. These checks describe local ownership, not a global recipe,
capacity or generated-minus-sales equation.
