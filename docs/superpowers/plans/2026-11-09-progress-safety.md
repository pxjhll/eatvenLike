# Progress Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve player progress across failed transitions and malformed/future saves, then open an independently reviewed stacked PR.

**Architecture:** Profile commits candidate data only after successful writes; an application progress service orders cross-file transitions and fresh-shop initialization. A standalone semantic state validator and staged restore keep invalid saves from mutating live rules.

**Tech Stack:** Godot/GDScript, local4.6.3 console, CI4.7, Git/GitHub CLI.

**Spec:** docs/superpowers/specs/2026-11-09-progress-safety.md

## Global Constraints

- Work in D:/Tes/eatventure, codex/progress-safety from8803810; no worktrees.
- Independent stacked PR base codex/ui-number-consistency while PR64 remains open; no merge or push to main.
- Keep economic/content data, old baseline outcomes and format compatibility intact.
- Never run new probes against real user Profile, shop saves, tuning or playlog; use temporary paths and injected dependencies.
- No shop-specific identifiers in generic rule code. New helper scripts may be preloaded without class_name to avoid import/cache churn.
- Two implementation tasks have disjoint file ownership; only Task2 owns tests/run_all.gd and registers both new suites once both files exist. Agents must not commit other owners' in-progress edits.

## Task 1: Profile commits and transition safety

**Files:** game/app/profile.gd; new game/app/progress_service.gd; presentation/shop/shop_play.gd; new tests/test_profile_safety.gd; optionally tests/render_shop_pancake.gd and docs/progress-safety.md. Do not edit ShopRules, ShopSave or run_all owned by Task2.

**Interfaces:** Keep Profile.save()->Error. Make finish_shop(record:Dictionary)->Error transactional and expose corresponding candidate-based target-shop and fresh-shop acknowledgement operations. Progress service consumes Profile and ShopSave.save_game/delete, returns explicit errors/results; scene lifecycle advances only on success. Existing successful callers that ignore finish_shop's result remain source-compatible. ShopSave.delete currently returns void, so post-commit deletion is cleanup, never a reason to retry/double-record an already committed transition.

- [ ] Write tests/test_profile_safety.gd extending tests/test_case.gd. Cover failed Profile persistence with byte-identical disk and unchanged to_dict; repeated successful finish has one intended record per accepted operation; version99 and version-type rejection; existing version1 and compatible missing version.
- [ ] Add transition fault regressions using unique temporary profile/shop paths, including the original scenario:

  ```gdscript
  var before := profile.to_dict()
  var old_bytes := FileAccess.get_file_as_bytes(store.path)
  # Inject repository/write failure and invoke the actual progress operation.
  check(result != OK, "Profile写失败必须中止切店")
  check_eq(profile.to_dict(), before, "内存不提前提交")
  check_eq(FileAccess.get_file_as_bytes(store.path), old_bytes, "当前店进度保留")
  check(signals.is_empty(), "失败不发切店信号")
  ```

- [ ] Run only the new suite/live scene cases and record expected red failures. Do not let an out-of-bounds red scene hang indefinitely.
- [ ] Implement candidate writes, explicit version/read state and future-version write guards. Keep Profile JSON representation stable and errors useful to the scene.
- [ ] Implement the progress coordinator, route finish/jump/fresh-shop initialization through it. Save new shop before acknowledging fresh_shop, block failed initialization from playing/autosaving, support retry without losing existing files.
- [ ] Run focused tests to green and self-review all crash/write-failure boundaries. Write task-1-report.md with API details, exact commands/results and unresolved limits. Do not commit until parent authorizes the combined commit after both owners are stable.

## Task 2: Semantic validator and staged state restore

**Files:** new game/rules/shop_state_validator.gd; game/rules/shop_rules.gd; game/rules/shop_save.gd; new tests/test_state_validation.gd; tests/run_all.gd. Do not edit Profile, progress_service, shop_play or Task1 tests.

**Interfaces:** ShopRules.load_dict(data:Dictionary)->String retains empty-on-success semantics, but rejected data never mutates current rules. Validator is read-only and reusable, and may consume SpecShop plus a canonical default shape. Successful restoration preserves deployment aliasing, navigation and RNG/modifier/event state and rebinds any transferred internal listener to the live rules. ShopSave.load_game supplies last_error plus existing backup protections.

- [ ] Write negative cases for rng=[], wrong seed types, malformed roster/worker refs, invalid path/step indexes, invalid station counts and invalid order collections. Start from real to_dict to avoid testing unrelated missing fields. Include valid staged roundtrip cases for both shipped shops and the third fixture.
- [ ] Test real ShopSave payload with correct format/base64/hash but illegal business state. Require an informative error and fresh safe rules, and preserve/quarantine original bytes. Capture ErrorCounter to prove no hidden runtime errors.
- [ ] Observe red failures with a focused external runner. The original rng-empty case must fail for the actual partial-load bug, not a test typo.
- [ ] Implement semantic validation before mutation and complete temporary restoration before adoption. Do not over-restrict valid dynamic runtime state or change removed/added ID compatibility. Keep legacy zero-duration recovery working.
- [ ] Register both new suites in run_all only after Task1 file exists; run focused suites and existing save/added-removed-ID/whole-shop roundtrip coverage. Write task-2-report.md with actual coverage and commands. Do not commit until both owners are stable and parent authorizes a combined commit.

## Task 3: Integration, review and stacked PR

- [ ] Parent runs the complete suite once on the stable combined tree, plus isolated GUI fault checks and the existing5shop GUI/audio scripts. Validate real user files are not written.
- [ ] Check layout/baseline equality and glyph coverage; visually inspect only any new startup-failure/retry screen.
- [ ] Commit scoped changes and generate one combined implementation diff. Independently review spec compliance/code quality, resolve concrete findings with covering tests, then perform final whole-branch review.
- [ ] Push codex/progress-safety, create PR against codex/ui-number-consistency with explicit dependency on PR64 and truthful local/CI results. Inspect CI without merging main or the parent PR.
