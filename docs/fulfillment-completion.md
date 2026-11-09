# Fulfillment completion and sales

`ShopRules` coordinates arrivals, dispatch, inventory, pricing queries, tickets and
events. `rule_sales.gd` owns the five monetary counters behind the existing Rules
properties. `fulfillment_completion.gd` applies local station and recipe-step
effects through five static functions; it owns no persistent state.

For handoff work, Rules takes the source when required, queries pot duration only
for pot_start, applies completion, then finishes the ticket and worker. Stir and
pot_take do not consume source. `_complete_topping` remains a forwarding facade.

For single-worker recipes, Rules finishes the work phase first. Pot load queries
duration; unload queries batch and capacity. These numeric formulas depend on
shop parameters, modifiers and tuning, so evaluation before station mutation
does not depend on the old or new phase. The kernel clears the chore and station
user while preserving unrelated timing and stock fields.

Take removes the customer from the queue before quoting and accepting payment,
then advances only the step index. Other recipe steps retain exclusive ownership
for an adjacent step at the same station, release it otherwise, and update carry
only when holds is nonempty. Terminal hand stays in Rules: settlement and the
synchronous sale event precede WorkerState order cleanup, followed by return.

Sales retains both payment policies, fractional handoff carry, addon counting and
the distinct handoff/single event payloads. Diner handling precedes handoff count,
which precedes price evaluation. Events observe credited counters and the current
assignment before cleanup. Save keys, commands, eligibility and exactly-once
ordinary execution remain unchanged; no new idempotency policy is introduced.

Both helpers receive only values or the dictionaries they mutate. They have no
Rules, event, navigation, RNG, service, serialization or global-cache dependency.
Inventory reservations and WorkerState transitions retain their existing owners.
