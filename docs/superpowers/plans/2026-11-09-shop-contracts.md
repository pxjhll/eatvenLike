# Shop Contracts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reject unsupported/invalid shop configuration before IO and prove a third data-only shop through the real presentation/session stack.

**Architecture:** Pure structured Spec validation plus a mode capability matrix, injectable Profile campaign, presentation preflight before Session.start, and an isolated third-shop scene/campaign integration fixture.

**Tech Stack:** Godot/GDScript, local4.6.3, CI4.7, PowerShell/Git/gh.

**Spec:** docs/superpowers/specs/2026-11-09-shop-contracts.md

## Global Constraints

- Work D:/Tes/eatventure, codex/shop-contracts from8bbc03d; no worktrees, merges, main writes. PR base codex/session-lifecycle while66 open.
- Preserve shipped economic outcomes, file formats, precise replay, progress/retry protections and session lifecycle. Never re-record golden baselines.
- No shop/station/dish IDs in generic rule/scene code. New helpers no class_name or preload cycles. No local --import (UID churn).
- Every engine process isolates APPDATA under D:/Tes/eatventure-analysis/shop-contracts-userdata/session-lifecycle-userdata, with separate runner subdirs; real Profile/tuning/log untouched.
- Disjoint owners: Task1 schema/capabilities/rules/Session/App and production declaration normalization; Task2 Profile+test campaign; Task3 presentation/fixture/CI/docs. NO agent commits/staging until parent coordinates.
- NOODLE shop.tres belongs Task3 (needs both display text/scene and declaration normalization). Task1 sends its required normalization to Task3, never edits it.

## Task 1: Rule configuration and capability contract

**Files:** new game/rules/shop_spec_validator.gd; game/rules/shop_rules.gd (single arrival branch only); game/app/shop_session.gd; game/app/app.gd; content/rules/spec_fulfillment.gd/spec_dispatch.gd comments; content/shops/tea/shop.tres and pancake/shop.tres inert declarations only; new tests/test_config_contracts.gd; tests/run_all.gd; docs/shop-capabilities.md.

**Interfaces:** `ShopSpecValidator.validate(shop:SpecShop,campaign:SpecCampaign=null)->Array[Dictionary]`, `capabilities(mode:String)->Dictionary`, `summary(errors:Array)->String`, code/path/message entries. Session start validates before store IO. `Session.shop_for(profile,target_id:String="")->SpecShop` consumes Task2 instance `profile.campaign`; App factory safely passes null Store if no valid shop instead of nil dereference. Task3 consumes validator API and optional shop_for target.

- [ ] Build complete consumed-field inventory (including aliases) and test mode matrix; unsupported or fixed-policy fields cannot be silently varied. Write behavioral RED cases for existing arrival no-op, duplicate/null IDs/resources, broken refs, nonfinite/range values and invalid field combinations. Real Session tests require original bytes unchanged before bad configuration can quarantine/write.

  ```gdscript
  var errors = Validator.validate(bad, campaign)
  check(errors.any(func(e): return e.path == "fulfillment.arrival"), "field path")
  check_eq(errors_log.take().size(),0,"no runtime error")
  check_eq(FileAccess.get_file_as_bytes(store.path),before,"no IO on invalid data")
  ```

- [ ] Implement resource/ID/numeric/reference/params/layout validation and one authoritative matrix with deterministic errors. Include all Fulfillment/Dispatch exported fields, with explicitly reserved default-only values. No runtime ShopRules construction inside validator.
- [ ] Implement single fixed arrival without RNG interval draws; preserve exponential code and handoff fixed baseline. Write actual varied/reproducible arrival and exact midgame continuation tests; reject unsupported handoff exponential.
- [ ] Normalize ignored production declarations only; communicate noodle changes (base_scores removal, leave_queue=after_take) to Task3. Preserve all effective values. Wire Session/App after Task2 Profile campaign API exists. Register new suites only when sibling files exist.
- [ ] Run focused schema/arrival/Session plus existing save/state/rule compatibility. Report task-1-report.md red-green/inventory/normalizations/commands/limits, freeze without commit. Parent full integration/review.

## Task 2: Instance campaign Profile contract

**Files:** game/app/profile.gd; new tests/test_profile_campaign.gd; new tests/fixtures/noodle/campaign.tres. Do not edit Session/Scene/run_all or noodle/shop.tres.

**Interfaces:** `Profile.new(path_=DEFAULT_PATH,campaign_:SpecCampaign=CAMPAIGN)`; public instance `campaign`, `available_shops()->Array[String]`, existing `next_shop` uses instance. Static `shops()` retains default production list. Task1 Session.shop_for and Task3 Scene/factory use these. JSON version/representation and candidate commits unchanged.

- [ ] Write RED for isolated custom campaign selecting/persisting/reloading noodle with real Profile; default static shops/campaign unchanged; next_shop filters unimplemented paths; invalid/null/empty campaign rejected without runtime/nil/index errors or file overwrite. Include future/corrupt external replacement write guards under custom campaign.

  ```gdscript
  var p = Profile.new(path,fixture_campaign)
  check_eq(p.select_shop("noodle"),OK,"fixture campaign supports third shop")
  check_eq(Profile.new(path,fixture_campaign).shop,"noodle","durable actual Profile")
  check(not "noodle" in Profile.shops(),"production unchanged")
  ```

- [ ] Implement minimal campaign injection and safe invalid-campaign checks. Internal shops/default city/select/finish/validate use instance; preserve default API and no general migration framework. Fixture campaign contains only third shop and remains in tests.
- [ ] Run focused custom/default Profile and original progress safety suite once sibling helpers ready; notify siblings API/file readiness. Report task-2-report.md with red/green and compatibility; freeze no commit/index edits.

## Task 3: Scene preflight and real third-shop onboarding

**Files:** new presentation/shop/shop_scene_contract.gd; presentation/shop/shop_play.gd; tests/fixtures/noodle/shop.tres and new shop_scene.tscn; tests/shop_test_session.gd optional explicit campaign argument; new tests/test_scene_contracts.gd; new tests/render_shop_noodle.gd; tests/test_noodle_shop.gd, test_font.gd; new tools/validate_shops.gd; .github/workflows/tests.yml; new docs/shop-onboarding.md. Do not edit Task1/Task2-owned files.

**Interfaces:** SceneContract.validate(shop,art)->Array[Dictionary]; prepare(shop)->Dictionary `{errors,art}`. Scene rules+art preflight before session.start, one adopted candidate, frees on any failure. Profile instance campaign navigation through Task1 Session.shop_for(profile,target) and Task2 available_shops; explicit factory campaign injection defaults to existing behavior.

- [ ] Write actual bad-scene startup RED (missing/non-Node2D art, Anchors/sortables/required interaction nodes, invalid transforms/metadata) and no Profile/store changes even if fresh_shop is set. Verify repair/retry and candidate disposal with ErrorCounter. Do not treat safe optional anchor fallbacks as mandatory.
- [ ] Implement pure presentation contract, safe preparation and startup error/retry wiring before IO; use instance campaign in next/jump. Preserve App session provenance reassembly and explicit fault dependency protections.
- [ ] Add independent graybox noodle scene with matching Nav/interaction/queue/wait/exit anchors. Set its scene_path. Normalize inert declarations requested by Task1 (remove single base_scores, leave_queue=after_take). Translate fixture-only UI text to ASCII, preserve business IDs/economy; update broth test to match action/station rather than human label and add font coverage for fixture.
- [ ] Build live third-shop regression using real Profile+fixture campaign+ShopSave+Session, full scene and actual inputs. Cover opening/sales/dish work/upgrade/staff panels/save/reopen/exact next-run state/restart/new business. Ensure default campaign unchanged and fixture excluded from production export. Add structural invalid cases and CLI validating production plus third fixture.
- [ ] CI bounded schema CLI and third-shop live step. Run focused contracts/font plus live noodle and existing startup/session/tea/pancake regressions. Notify Task1 test file exists for run_all. Document onboarding/capability/error paths. Report task-3-report.md, freeze no commit.

## Task 4: Integration, reviews, stacked PR

- [ ] Parent full suite, CLI, layout/baseline equality, existing GUI/audio/retry/lifecycle/work-actions and new noodle live regression in isolated data. Inspect new graybox scene screenshots at supported viewport sizes, fix actual presentation defects only. Confirm real user hashes unchanged and scoped diff.
- [ ] Commit explicit files, independent task spec/quality reviews and scoped owner fixes, then final whole-branch review. Run covering checks on changes.
- [ ] Push codex/shop-contracts; PR base codex/session-lifecycle with dependency66/65/64, accurate tests/limitations. Wait Godot4.7 CI success; no merge/main changes; archive only this plan workflow records outside repo.
