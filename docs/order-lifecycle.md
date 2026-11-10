# Order and customer lifecycle

`game/rules/rule_orders.gd` owns the ten existing order/customer state fields.
`ShopRules` forwards its public properties to the same live owner across reset
and validated load. Save keys and their order are unchanged; the owner itself is
never serialized. Arrays, dictionaries, rows and supplied option arrays retain
their original reference semantics. Each owner starts with separate containers.

In handoff mode the owner admits orders, advances their clock/waits, marks every
matching reservation, removes the first matching order, and maintains diners and
standing-order overflow. Rules still queries menu weights, seats and capacity,
draws random values, schedules flyers, reserves inventory and operates workers.
Handoff sale listeners run before order removal and worker cleanup. Diner seat
and duration queries still run before the diner is appended and sales counted.

In single mode the owner admits customers, rejects arrivals, claims only the FIFO
head, dequeues accepted customers and advances one customer's patience at a time.
Rules computes patience once and loops over the original customer snapshot.
For each timeout it transitions that row, removes its queue id, increments lost,
then emits `lost` synchronously while the row remains in `customers`. Only after
the callback does removal recheck the row's state and the owner's current array.
A callback may revive a row, replace arrays, reset or load. Newly added rows are
excluded from the existing iteration snapshot. Claimed rows never time out;
patience uses strict excess without an epsilon.

Rules retains eligibility checks, weighted dish selection, addon/option sampling
and interval draws in their existing order. Options are sampled before admission
updates the id or appends the row. Flyers precede normal single arrivals; full
queues reject before dish/addon/option draws, while exponential interval draws
still occur before the corresponding normal-arrival rejection. Handoff deadline
reset remains before its capacity check. Diner advancement remains before the
overflow eligibility and free-seat queries.

Sales retains its API and monetary arithmetic. It uses only the order module's
two static row transitions: `accept_single` sets paid/state after any take credit,
and `leave_single` sets leaving after delivery credit and before sold counters.
The order module imports no Rules, Sales, configuration, RNG, services or event
bus, and owns no callbacks or cached aliases. Rules remains responsible for all
query, event and worker-cleanup boundaries.

`tests/test_order_lifecycle.gd` covers literal owner APIs, forwarding/save schema,
reference identity, reentrant callbacks, reservation/sale ordering and independently
predicted RNG progression. Existing sales tests retain their original assertions.
