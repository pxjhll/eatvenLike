# Machine progression

`game/rules/machine_progress.gd` owns local station clock updates and their phase/inventory effects. Its four static functions mutate the supplied dictionary in place. It retains no state and uses only the pure `Inventory.stock()` query. Existing stock maps, reservations and history keep their identities.

`ShopRules` owns station declaration order, automatic/pickup/unlock eligibility, recipe output selection and duration queries. `_pause_for_stir()` remains a forwarding facade. The single pot loop stays between customer updates and worker updates.

## Automatic start protocol

1. `advance_handoff(station, block, delta, stir_points)` advances an existing batch, then consumes the first positive input in dictionary insertion order if another automatic batch can start. It returns that input key, or an empty string for no start. Pickup consumes one; other automatic stations consume the whole selected count.
2. Rules binds `processing_item` to the input for pickup, or queries its recipe output. Output queries therefore observe consumed input and the previous output binding. Rules then queries duration; that query observes consumed input, the selected output and the previous phase/timing.
3. `begin_automatic(station, seconds)` stores duration and remaining, resets progress and sets `working`. The new batch receives elapsed time on the next tick.

Completion and selection may occur in the same tick. No-start paths perform no recipe output or duration query. Eligibility stays in Rules.

## Clock differences

Handoff clamps remaining to zero, recomputes progress and completes at `remaining <= 0.000001`. For batch pots, `pause_for_stir()` uses the first crossed point in the given order, with strict `before < point` and inclusive new progress. It stops before completion, restores remaining from the point and sets `stir`. Pots retain their processing batch at `awaiting_take`; automatic machines release output and clear their binding before selecting another input. Empty automatic stock resets phase/progress to idle; retained stock keeps historical phase/progress.

`advance_single(station, delta)` acts only on `cook`: subtract raw delta and set `done` at `remaining <= 0`. It neither clamps remaining nor recalculates progress, and it has no output or stock effect. Duration values are supplied unchanged; the kernel adds no normalization or new numeric policy.

Literal boundary and real Rules sequencing tests live in `tests/test_machine_progress.gd`, registered in `tests/run_all.gd`.
