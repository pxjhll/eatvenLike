# Read-only numeric queries

`ShopRules` keeps its existing live numeric getters. Previews use the same formulas through a detached numeric context:

```gdscript
var next_batch: int = rules.preview("boil", func(query: RefCounted) -> int:
    return query.pot_batch("boil"))
var next_seconds: float = rules.preview("boil", func(query: RefCounted) -> float:
    return query.station_timing("boil").seconds)
```

Preview callbacks now receive one explicit argument. Migrate every zero-argument callback to read that argument; a closure reading `rules` or `ShopView.seconds()` will read the actual live value. There is no zero-argument compatibility fallback.

`rules.query_context(level_overrides: Dictionary = {})` captures only levels, modifier entries (including nested dish selectors), and tuning. It shares `SpecShop` as a **read-only definition**. Callers must not mutate that shared resource or its nested definitions while a context is retained. Contexts hold no live `ShopRules`, simulation state, workers, RNG, event bus, navigation, or persistence reference. No full rules instance is constructed and no state is serialized or restored.

```gdscript
var captured := rules.query_context()
var stronger := captured.query_context({"staff/front": 2})
var later: RefCounted = captured.preview("boil", func(query: RefCounted) -> RefCounted:
    return query)
```

Derived contexts start from their parent's captured values. Parent, child, retained contexts, and live rules own separate mutable dictionaries and entries. A later live upgrade, tuning edit, or modifier expiration does not update a retained context. Worker dictionaries are read as method arguments and never retained or modified. Quote, timing, and effective-stat results are fresh dictionaries.

Available queries: `level`, `tuned`, `speed`, `duration_mult`, `pot_batch`, `process_slots`, `raw_price`, `dish_price`, `dish_quote`, `order_price_single`, `manual_operation_seconds`, `station_timing`, `pot_seconds`, `machine_seconds`, `flyer_customers`, `flyer_cooldown`, `side_of`, `stat`, `walk_speed`, `skill`, `carry`, `effective_worker_stats`, plus nested `preview` and `query_context`. Contexts expose no simulation commands.

A valid preview increases the saved level by one, preserving staff's saved-level offset and the historical beyond-maximum level query behavior; numeric folding uses only the track's available effects. A missing track evaluates exactly once against an unchanged detached context. Null evaluator results are returned unchanged. Query evaluation needs no live-state cleanup, including if an evaluator fails.

Virtual and real upgrades share track lookup and modifier folding. Existing sources retain their insertion positions; a source without previous entries retains the existing append behavior. Event set/mul/add precedence, price parts and rounding, manual versus automatic timing, tuning, seated bonuses, couriers, and individual worker effects retain their current behavior. One-shot effects and unlocks are never executed by queries. `worker_stat_limits(worker)` evaluates maximum staff progression in a detached context, then floors each result at that worker's current effective stat.

No fields are added to saved state or content fingerprints.
