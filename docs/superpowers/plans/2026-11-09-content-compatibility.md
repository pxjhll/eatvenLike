# Content compatibility implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Preserve saved progress through numeric content updates and protect incompatible originals.
**Spec:** `docs/superpowers/specs/2026-11-09-content-compatibility.md`
**Architecture:** A deterministic definition contract identifies compatible changes; ShopRules refreshes cached derived values on its isolated candidate; ShopSave guards migration/backup and ShopSession gates startup.
**Stack:** Godot GDScript; headless regression runner.

## Global Constraints

Work in `D:/Tes/eatventure` on `codex/content-save-compatibility`; no worktrees. Do not edit/push main or merge PRs. Every engine invocation must explicitly set APPDATA beneath `D:/Tes/eatventure-analysis/content-compatibility-userdata/session-lifecycle-userdata/<runner>`. Never use local `--import`. Preserve progress, RNG/log identity, live event bus, active recorded timings and non-upgrade effect timing/order. Diagnostics in game/presentation use ASCII or existing font glyphs. Helpers use preload paths without class_name. No subagents from implementation/review workers. Parent coordinates commits after test evidence. Scope excludes query/error/module refactoring.

### Task 1: Definition fingerprints and candidate value refresh

**Files:** Create `game/rules/shop_content_contract.gd`, `tests/test_content_rules.gd`; modify `game/rules/shop_rules.gd`, `tests/run_all.gd`.

**Interfaces:** Produce static `ShopContentContract.describe(shop: SpecShop) -> Dictionary` via preload, returning `{version: 1, gameplay: String, structure: String}` with lowercase 64-character hashes; `ShopRules.load_dict(data: Dictionary, refresh_content: bool = false) -> String`. Default stays exact; true refreshes only definition-derived values on validated candidate.

- [ ] Write failing tests for old upgrade and staff stats retention, fresh capacity updates, active recorded work/timing preservation in single/handoff, non-upgrade finite/permanent `set` precedence, newly introduced upgrade effects, no grant_gold replay, worker aliasing, RNG/log/bus preservation and repeated-refresh idempotence.
- [ ] Write contract tests: equal deep copies and reversed dictionary insertion order hash equally; numeric price/speed/stats/capacity/effect changes change gameplay only; mode/route/stage order/navigation geometry/IDs/track max changes change structure; UI names/icons/labels/audio/path changes do not change gameplay. Include stock keys and material identity.
- [ ] Run tests on a focused temporary runner under this plan workspace, using error_counter.gd; capture real assertion failures before implementation. Then implement canonical exported-resource traversal excluding presentation, plus explicit conservative structural projection. Include only gameplay Resource types; ignore script/engine properties. Arrays retain order, dictionaries canonicalize keys; navigation coordinates must be structural. Effect definitions and stats are rebalanceable, track IDs/level counts are structural.
- [ ] Implement optional refresh after `_restore_validated` and before adoption. Build current upgrade groups from saved levels, reinsert at their former source positions; remove absent sources, place newly effect-bearing groups before retained non-upgrades. Refresh stats from current worker kind; capacities from fresh defaults. Keep all other state fields unchanged.
- [ ] Run focused tests and existing save/state/numeric/tea/pancake tests; report commands, red/green evidence and decisions to `.superpowers/sdd/2026-11-09-content-compatibility/task-1-report.md`. Do not commit; parent commits and requests review.

### Task 2: Guarded store migration and retryable session startup

**Files:** Modify `game/rules/shop_save.gd`, `game/app/shop_session.gd`, `tests/test_state_validation.gd`, `tests/run_all.gd`, `tests/render_progress_retry.gd`; create `tests/test_content_save.gd`; extend `tests/test_session.gd` or `tests/test_scene_session.gd` if needed. Add `docs/content-save-compatibility.md`.

**Interfaces:** Consume Task 1 describe/load_dict contracts. Produce wrapper VERSION=2 accepting legacy v1; `ShopSave.load_error: Error`; overridable `_backup_before_content_update() -> Error` for failure injection. Backups are exact original sibling copies `.pre-content-*`, never a move. Session.start checks load_error before adopting candidate.

- [ ] Write failing tests for v1 valid refresh/invalid protection, changed numeric effects/prices/stats/capacity preservation, same-content exactness, topology/level shrink protection, future version/content protection, invalid same-content state quarantine, direct saves/fresh intent protection, file replaced between load/save, backup failure, failed save/retry and no mutation at load time. Use metadata from contract in existing state corruption fixtures so tests continue to target current format semantic corruption.
- [ ] Capture failing assertions using focused runner/error_counter. Implement parsing metadata/version classification, common before-load/write assessment, candidate refresh and exact-byte copy before migration overwrite. If saving fails after backup, original remains intact and retry works; detect external replacement each time. Legacy validation failure is incompatible. Current-format malformed data or same-content semantic failure remains corruption. Future errors block.
- [ ] Gate Session.start: hold returned candidate locally, on store.load_error != OK keep rules null and started false; retry must actually reload repaired file. Check direct save guard covers ProgressService.initialize_fresh without changing profile on failure.
- [ ] Extend the real-scene retry runner with an incompatible-content file: verify the visible blocker, scene/session rules null, processing stopped, autosave/focus/exit preserve original bytes; repair by restoring a compatible file and invoke retry on the same scene, then verify saved gold and resumed play. Keep every path isolated and runtime errors fatal.
- [ ] Run focused tests and full `tests/run_all.gd`, keeping runtime error_counter enabled. Document supported rebalance changes, conservative topology rejection, backup naming/retention and retry behavior. Report evidence to `.superpowers/sdd/2026-11-09-content-compatibility/task-2-report.md`. Do not commit; parent commits and requests review.

## Final integration

Parent runs full suite and CLI validate/layout/business golden checks, GUI tea/guide/extend/pancake/noodle/audio/retry/lifecycle/work-actions scripts with isolated APPDATA. Generate whole-branch review package; resolve review findings; compare production file manifest. Fetch remote state before publication and use stacked base `codex/shop-contracts` if PR #67 remains open, otherwise rebase only feature commits onto origin/main and revalidate changed integration. Push feature branch, create PR, check Godot4.7 CI. Archive only this plan workspace to `D:/Tes/eatventure-analysis/content-compatibility-pr/validation-records`.
