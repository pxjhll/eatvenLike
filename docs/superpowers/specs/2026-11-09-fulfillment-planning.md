# Fulfillment planning boundary

The user asked to continue the architecture sequence after PR71. This step separates definition-based fulfillment planning from the live simulation. It is a behavior-preserving internal refactor, stacked on PR71 while that PR is open. Work in D:/Tes/eatventure on codex/fulfillment-planning, without another worktree, main writes or merges.

## Scope and alternatives

Extract the existing role/chain derivation and single-order step expansion into a pure, stateless module. Keeping them embedded leaves the next fulfillment changes coupled to the entire simulation. Moving the complete single/handoff executors now would also move employee navigation, inventory reservations and payment state, expanding the compatibility surface. A definition planner is the first independently testable boundary.

Do not introduce a generic Rules/context/host object, callbacks into the simulation, a new mutable state owner, an engine strategy registry or a persistent plan cache. Employee execution, arrivals/random draws, reservation/stock bookkeeping, pricing/settlement, event emission and save restoration remain with their current owners.

## Module and interfaces

Create game/rules/fulfillment_plan.gd, extending RefCounted, without class_name. Its only public APIs are static:

- derive(shop: SpecShop) -> Dictionary. Fields: counter_id, supply_id, pickup_id; pots, autos, seatables, dish_ids, front_dishes, kitchen_dishes; chains, station_output, station_input.
- single_steps(shop: SpecShop, counter_id: String, order: Dictionary) -> Array.

derive preserves the existing definition iteration order and selection rules: the last counter, first supply, last processing pickup, batch pots, nonmanual combine stations, seatable stations and front/kitchen dish partitions. Chain inclusion excludes supply/pickup/counter and front-zone stations. A station appears at most once in each chain. Input selection keeps the first consumed item already produced earlier in that dish; station input selection is first-write across all dishes. Per station/dish output keeps the existing last-produced overwrite behavior. These details preserve dispatch and inventory semantics even for valid definitions with multiple candidates.

single_steps preserves the exact existing row shapes, fields and ordering: counter take; optional addon before or after the main dish; every original dish step; selected option steps in requested order; counter hand. Do not duplicate an addon when the main dish is that addon. Keep payment-dependent labels, take/hand seconds, repeated operation seconds, first produced item as holds, fixed/into_machine/put_down flags, layout action aliases and option station fallback. Missing option IDs or null option steps remain skipped, as in the old implementation. Do not filter, reorder or randomly select options in the planner.

Both APIs only read their inputs, allocate fresh data-only arrays/dictionaries and return no Resource, Rules, RNG, bus or other Object. Returned nested data may be edited or retained without changing shop definitions, customer input, live Rules or later results. Definition Resources remain shared read-only inputs. No binary serialization, to_dict/load_dict or new ShopRules construction in production planning. There is no hidden state/cache, so a later call observes the current definition values.

## Integration and compatibility

ShopRules preloads the planner. _derive_roles assigns the derived fields while preserving the existing typed Array[String] fields. _order_steps remains the existing facade and delegates to single_steps. The old private _option helper can move into the planner if its only caller moves; do not keep duplicate parsing implementations. Keep the execution call sites and all public numeric, command, compatibility and snapshot APIs intact.

No STATE_KEYS/BY_DATA_ID, state representation, content fingerprint, saved format or migration changes. No presentation, service, asset/font, economy, arrival, queue, timing or event-order changes. The existing _cup and _auto_output paths and validator remain unchanged. Existing active worker steps from a save continue as recorded; do not rebuild them from current plans during loading.

## Evidence

Before production edits, capture a deterministic old-engine trace for tea, pancake and noodle using explicit disposable APPDATA. Use real Rules, seeds and legal unlock/box/hire/deploy/upgrade/control commands, exercising active work, sales, queues, a mid-run tune change and save/load continuation. Checkpoints include complete to_dict data (including RNG, events, roster identities by IDs and in-flight steps) and command results. Make each shop nonvacuous: actual sales and observed active work. After extraction run the exact same probe and compare complete checkpoint data, not just gold/sales. Keep old/new trace files and comparison evidence outside the checkout; do not regenerate the old reference after editing production.

Commit meaningful direct planner tests with independent literal expectations for synthetic definition edge cases and representative production/third-shop plans. First capture assertion RED for the absent standalone module with safe existence guards and no parse/runtime failure. Test nested output/input isolation, separate calls, retained plans, addon order/dedup, payment mode, layout aliases, option fallback/missing steps, flags/repeats and derive ordering/first/last rules. Rules facade-to-planner equality alone is insufficient: assert independently expected routes/fields, plus unchanged live state/RNG/event data after planning. Register in tests/run_all.gd.

Freeze source before final validation. Run focused GREEN and one full suite locally, the existing pancake golden check and tea/pancake/noodle real-scene regressions. Parent runs remaining integration or uses exact-source evidence from the worker without duplication. Independent task review, strongest-model whole-branch review and Godot4.7 CI are required before delivery. Stack on codex/ui-state-boundary while PR71 is open; if dependencies merge, preserve human changes and rebase only this feature's commits.

## Environment and delivery

Every engine invocation uses D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe --headless and explicitly sets APPDATA under D:/Tes/eatventure-analysis/fulfillment-planning-userdata/session-lifecycle-userdata/<runner>. No local --import or visible-window probes. Runtime errors collected through tests/error_counter.gd are failures even if an engine exit code is zero. Capture/compare production userdata before/after; never restore it automatically.

Records: D:/Tes/eatventure-analysis/fulfillment-planning-pr/validation-records. Do not modify old ignored SDD workspaces. Archive only this plan's records by verified copy; do not retry the previously rejected recursive cleanup. No merge or shared-branch push.
