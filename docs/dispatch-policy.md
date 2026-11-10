# Dispatch policy ownership and contracts

`game/rules/dispatch_policy.gd` is a stateless RefCounted script with eight static methods. It has no class_name, retained inputs, cache or save state. The only definition type it receives is the immutable `SpecDispatch`; worker/job/result dictionaries are explicit borrowed values.

| Policy API | Responsibility and identity |
| --- | --- |
| `transport_candidate` | Minimum of carry, available and free counts; nonpositive returns fresh empty. Constructs the legacy ordered fields. No shelf-specific cap. |
| `serve_candidate` | Mutates and returns the same job: count 1, order id, pour, then adds capped wait bonus. Nested aliases and other fields survive. |
| `exact_count` | Rejects empty/insufficient candidates with fresh empty; otherwise sets exact count on the same job, without new positivity checks. |
| `wait_bonus` | Minimum of configured cap and wait times configured rate; no lower clamp. |
| `score` | Original throughput/travel/fatigue arithmetic with denominator at least 0.1; no normalization or input mutation. |
| `consider` | Updates only caller-local best record for a strict score improvement, keeping original worker/job references. Initial score -INF means all -INF candidates select nothing. |
| `route_choice` | Filters empty and wrong endpoints; returns original first highest-priority reference. The first matching -INF candidate is selected. |
| `fallback_pot_choice` | First highest-priority nonempty option, returned as a shallow copy. Nested data stays aliased; ticket/priority attachment is independent at top level. |

Rules retains live supply/demand, seat and post eligibility, candidate enumeration, ticket planning, navigation, duration queries and execution. `_candidate` evaluates carry, available, then free before calling the factory. Only a successful shelf candidate queries cup mapping and the second per-dish capacity cap. Serve enrichment follows the existing seat decrement; serve adds to base priority, while successful follow jobs overwrite priority with follow base plus wait bonus before attaching the ticket.

`_allocate` retains its outer rounds and worker/job traversal. Both route lookups and unreachable filtering precede scoring. Only the literal `work` kind invokes the action-duration estimator; other kinds retain the two-hop estimate. Each round starts a fresh best record, reserves one winner, then regenerates candidates against changed inventory. The policy never reserves, walks, caches assignments or changes enumeration order. Strict improvement preserves the first worker and first job on ties.

`_run_belts` keeps cooldown updates, courier flag window, option generation, inventory reservation, take, shipment append and cooldown reset. Only route selection delegates. Its empty-first priority policy is deliberately separate from score-based selection; fallback is separate again because it requires a shallow copy. Single-worker dispatch and the Inventory, WorkerState, Sales, Completion and MachineProgress owners are unchanged.

`tests/test_dispatch_policy.gd` covers independent literal contracts and real Rules fixtures for query order, late shelf cap, serve seat/pour handling, scarce-stock greedy regeneration, reference ties, reachability, estimator branching, ticket fallback/resume and belt sequencing. Full regression, golden replay, scene integrations and a bounded frozen baseline trace validate unchanged behavior.
