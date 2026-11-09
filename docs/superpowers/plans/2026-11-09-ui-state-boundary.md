# UI state boundary implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans task by task.

**Goal:** Route presentation writes through the active session and expose mutable state only as detached read models.
**Architecture:** Canonical controls + session dispatch; ShopView value-only projections; frame-local rendering and small fresh projections for guides/recording/dragging.
**Tech Stack:** Godot GDScript, headless engine and real-scene input fixtures.
**Spec:** `docs/superpowers/specs/2026-11-09-ui-state-boundary.md`

## Global Constraints

Use D:/Tes/eatventure on codex/ui-state-boundary; no worktrees/main writes/merges. Engine D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe --headless, explicitly set APPDATA under D:/Tes/eatventure-analysis/ui-state-boundary-userdata/session-lifecycle-userdata/<runner> before every engine. No --import/native-window probes. Helpers no class_name/cycles; preserve font, assets, arrival/dispatch/pricing, event ordering and saved state format/current main policies. No full Rules cloning/serialization for read models, no stale persistent frame cache. Worker agents do not spawn agents/stage/commit; parent coordinates.

### Task 1: Official controls, session dispatch and detached reads

**Files:** Modify `game/rules/shop_rules.gd`, `game/rules/rule_numbers.gd`, `game/rules/rule_command_result.gd`, `content/ui/rule_command_text.gd`, `game/app/shop_session.gd`, `game/rules/shop_view.gd`; optionally create `game/rules/rule_presentation_snapshot.gd`; create `tests/test_presentation_reads.gd`; modify `tests/run_all.gd`; add `docs/presentation-boundary.md` API section.

**Interfaces:** Produce exact control commands/session execute API and all ShopView APIs/fields enumerated in spec. Core tuning normalization/limits have one authority; UI may request snap or raw clamp. Add session_unavailable constant/catalog text. Existing business check/execute and String compatibility APIs stay intact. ShopView renderer/status formatter remains backward compatible. Public API signatures take scalar IDs/points and return data/scalars, never nav or live rows.

- [ ] Write actual failing tests for missing controls/session forwarding/read projections with safe API guards; add current-state baseline assertions for normalization/explicit keys and nested snapshot aliasing. Capture RED with runtime logger; no parse-only failure.
- [ ] Implement control validation/commits and active-session forwarding without changing save/startup diagnostic semantics. Cover all unknown/wrong/nonfinite/bool inputs, station/global keys, raw config precision versus snapped slider values, no events/timer changes, pre-start/failed/finished/jumped sessions and preserved warning.
- [ ] Implement data-only projections, moving guide selection logic verbatim into trusted read model and value-only nav/art/staff metadata access. Preserve order and existing missing-ID fallbacks. No whole-game serialization/new Rules. Include recording aggregates with actual queue/mood/idle/busy queries and detached progress maps.
- [ ] Tests must mutate nested copied jobs/stats/steps/paths/station maps/orders/customers/progress and compare live data/identities. Retain old snapshots across actual simulation/upgrades/reset and compare fresh ones for changed values. Use all3 shops and nonempty processing/queue fixtures. Check no live Object references in snapshot payloads. Add documented timing/performance observation only if useful, no invented speed threshold.
- [ ] Run focused RED/GREEN and full tests/run_all.gd once after source freeze. Report exact logs/commands/public fields and decisions to `.superpowers/sdd/2026-11-09-ui-state-boundary/task-1-report.md`; no commits/staging. Parent reviews before UI task.

### Task 2: Presentation consumers and owner-safe interactions

**Files:** Modify `presentation/shop/shop_play.gd`, `presentation/shop/shop_tuning.gd`, `presentation/shop/shop_recorder.gd`, `presentation/shop/guide_player.gd`, `presentation/shop/staff_drag.gd`, `presentation/shop/art_groups.gd`, `presentation/shop/hud/menu_page.gd`, `presentation/shop/hud/staff_page.gd`; other presentation only for concrete missed reader. Create `tests/test_presentation_boundary.gd`, `tests/render_presentation_boundary.gd`; modify `tests/run_all.gd`, `.github/workflows/tests.yml`; extend `docs/presentation-boundary.md`. Existing tests may be adjusted only where fixture intentionally mutated the newly detached scene helper; set up fixtures through session.rules explicitly instead.

**Interfaces:** Consume Task1 session execute and ShopView snapshots/value helpers. Scene can expose thin execute forwarding for widgets. all_staff() now returns detached fresh roster. Root captures one render snapshot per _refresh after stepping and passes it to visual update methods; private visual helper optional snapshot fallback must be fresh if direct calls retained. Other readers request small fresh projections. No persistent hidden frame cache. Scalars/immutable definition reads/event bus remain allowed.

- [ ] Write real RED for editing old scene.all_staff nested rows mutating Rules and menu/tuning bypassing a spy session; retain meaningful checks in final tests. A fresh snapshot after hire/placement/restart must reflect latest state, not cached earlier data.
- [ ] Migrate pause, slider, reset, config loading and all existing presentation execute_command calls to active session ownership. Preserve snap/load precision/log/save distinctions and use rule tuning limits for slider metadata. Invalid/inactive controls do not save/log/write ConfigFile. Preserve successful standard business feedback/debits.
- [ ] Replace all presentation runtime collection/private/live-row/nav accesses (including recorder sim alias and art groups) with explicit read-model APIs. Guides retain priorities and lost bookkeeping; recorder keeps cadence/format/aggregation, marker queue uses public actual queue. Customer caption uses public actual customer_interval. Keep render actor/customer/cup/seat order and navigation/drop semantics. Do not move fulfillment or broadly rewrite gameplay.
- [ ] Add real scene regression with isolated TestSession, spy forwarding, returned-snapshot mutation, actual clicks/drag/hire/restart and failed/closed session writes. Add fresh captured/fresh getter checks, tuning clamp/snap and exact raw config load, invalid config skipped without log/save, enabled/disabled services and real save roundtrip. Freeze processing immediately after add_child before awaiting readbacks. error_counter fatal; internal25s/CI30s bounds and disposable XDG path.
- [ ] Add narrow source boundary audit for presentation (aliases rules/sim/_rules(), live getters/nav/private calls and writes), plus behavior tests; allow actual public scalar queries/immutable definitions/event subscription, not an all-text ban. Add CI runner. Font/assets unchanged.
- [ ] Run focused, new live, one full suite after freeze and supported existing tea/extend/pancake/noodle --headless scripts. Parent owns remaining config/layout/golden/guide/audio/retry/lifecycle/workactions. Report exact evidence/any fixture-only changes to `.superpowers/sdd/2026-11-09-ui-state-boundary/task-2-report.md` and freeze; no staging/commits.

## Parent gates and publication

Feature base f97494c has229 tests and Godot4.7 CI42589294114 SUCCESS; no unchanged baseline repeat. Capture production6-file manifest before engine. Sequential task reviews, no concurrent source writers. Complete stable remaining integration and strongest-model whole-branch review, then scoped fixes if needed. Check #70 merge status; stack on codex/command-errors while open or rebase only own commits onto latest main, preserving/revalidating human changes. Create PR, follow CI to success, compare userdata and archive this plan's records under D:/Tes/eatventure-analysis/ui-state-boundary-pr/validation-records. Do not merge or retry known blocked recursive cleanup.
