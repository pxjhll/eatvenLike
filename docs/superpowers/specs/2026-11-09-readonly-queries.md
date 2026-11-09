# Read-only numeric queries

User approved continuing the architecture sequence. This PR implements only query purity: upgrade previews and worker stat limits must never borrow live levels or modifiers, even transiently. Error-code migration, broad UI ownership changes and fulfillment-module splitting stay deferred.

## Design

Use detached numeric query contexts rather than constructing/restoring full ShopRules, swapping live references, or copying formulas into a preview-only implementation. Extract shared numeric formulas and upgrade modifier folding into small helpers without class_name. Runtime and detached queries use the same formulas, preserving operation order, integer conversion, rounding, tuning, worker-region/seated/courier semantics and modifier precedence. Live getters remain available with their existing signatures.

`ShopRules.query_context(level_overrides: Dictionary = {}) -> RefCounted` captures only current levels, modifier entries and tuning with detached nested mutable data. SpecShop remains a shared read-only definition. The context has no reference to live ShopRules, workers, RNG, events, navigation or persistence. It exposes pure numeric query methods and nested preview/context derivation; it exposes no business commands. It must not create a fresh ShopRules or serialize/restore full simulation state.

`ShopRules.preview(key: String, evaluator: Callable) -> Variant` keeps its method name but now invokes `evaluator(context)` with one explicit argument. All repository callers must migrate from closures capturing live rules to the supplied query context. There is no legacy zero-argument fallback that temporarily mutates live state. Existing UI values and direct getter signatures remain unchanged. Missing-track previews still evaluate once using an unchanged detached context; valid next-level previews preserve current level-offset and max-level behavior.

The query context exposes at least `level`, `tuned`, `speed`, `duration_mult`, `pot_batch`, `process_slots`, `raw_price`, `dish_price`, `dish_quote`, `order_price_single`, `manual_operation_seconds`, `station_timing`, `pot_seconds`, `machine_seconds`, `flyer_customers`, `flyer_cooldown`, `side_of`, `stat`, `walk_speed`, `skill`, `carry`, `effective_worker_stats`, and nested `preview`/`query_context` with the same detached semantics. New override contexts derive from the parent snapshot, not current live state. Returned quote/timing/stat dictionaries are fresh.

`worker_stat_limits(worker)` calculates the current value, evaluates saved staff progression at its maximum in a detached context, then applies the existing per-stat floor at the current value. Unzoned staff keys, missing tracks, seated multipliers, tuning and event/individual effects retain current behavior. Worker dictionaries are read only and no worker command/state is copied or replayed.

Upgrade folding and source placement use one shared helper for real upgrades, content migrations and virtual upgrades. Preserve the exact existing placement rule, including sources that previously had no modifier entries. Never replay one-shot effects or unlock anything during queries. No new fields enter serialized state or content fingerprints; existing v1/v2 migration safeguards and exact same-content resume remain valid.

## Required verification

- Observe live state from inside a preview evaluator: serialized bytes, levels object, mods object, entries array and entry dictionaries, RNGs, bus/history and worker aliases stay unchanged both during and after calls. This must fail against the original temporary-mutation implementation, not only assert final restored values.
- Cover repeated, nested, missing-track, max-level and null-return evaluators; parent/child virtual level isolation and retained contexts after live changes to levels, tuning and modifier values. Reentrant normal live reads must see actual levels throughout.
- Compare previews against real upgrades on independent rules for tea, pancake and noodle fixture: full/partial/fractional prices and payment policy; manual/fixed/pot timing; batches, processing slots, flyer settings; timed/permanent set/mul/add ordering and newly effect-bearing sources. Assert one-shot rewards, gold, stock and unlocks never change.
- Verify worker caps for zoned/unzoned, seated/mobile/courier and no-track cases without replacing live arrays or mutating workers. Keep current effective stats as minimum.
- Run existing numeric, rule, view, save, content migration and session regressions; business/layout golden checks and real UI fixtures. Engine processes use disposable APPDATA containing session-lifecycle-userdata. Preserve the production userdata manifest exactly.

## Delivery

Work in D:/Tes/eatventure, no worktrees. New PR stacks on #68 while it remains open. Do not merge PRs or push main. Run independent task and whole-branch reviews, publish feature PR, follow Godot4.7 CI through completion. Archive only this plan's validation records; do not retry previously policy-blocked recursive cleanup of prior plan directories.
