# Session Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Explicit session dependencies and safe unified restarts, delivered as an independently reviewed PR stacked on PR65.

**Architecture:** ShopSession owns rule/persistence lifecycle and explicit service options. App lazily assembles production sessions; tests use isolated factories. Rules retain a stable event bus, while the presentation resets all transient UI through one restart path.

**Tech Stack:** GDScript, local Godot4.6.3, CI Godot4.7, PowerShell, Git/gh.

**Spec:** docs/superpowers/specs/2026-11-09-session-lifecycle.md

## Global Constraints

- D:/Tes/eatventure on codex/session-lifecycle from06f6355; no worktrees, no merges/main writes. Stacked PR base codex/progress-safety while65 is open.
- Preserve economy/content, file formats, exact replays, all PR65 failure protections and baseline outcomes.
- Every engine process sets isolated APPDATA; all tests inject isolated paths. No --import locally (avoids unrelated SVG UID churn).
- No new class_name/cache dependency cycles. Keep logic independent of presentation. Tuning and recording are independent of tutorial playback.
- User explicitly chose restart resumes business; preserve seen guides, tuning and speed.
- Disjoint ownership: Task1 owns core Session/App/RuleEvents/ShopRules and tests/test_session.gd + tests/run_all.gd. Task2 owns scene/UI/recorder/tuning/guide, test factory, scene tests/migration, CI and documentation. Agents do not commit until parent coordinates.

## Task 1: Core session contract and stable events

**Files:** new game/app/shop_session.gd; game/app/app.gd; game/rules/rule_events.gd; game/rules/shop_rules.gd; new tests/test_session.gd; tests/run_all.gd.

**Interfaces:** constructor `ShopSession.new(profile_:RefCounted,store_:ShopSave,rules_:ShopRules=null)`. Fields `profile`, `store`, `rules`, `guide_enabled=false`, `persist_tuning=false`, `recording_enabled=false`, `tuning_path=""`, `recording_path=""`, `speed=1.0`, `guides_seen=[]`, `last_error=""`, `transition_committed=false`, `started=false`; `signal restarted`. Methods `start()->Error`, `restart()->Error`, `save(guides:Array=[])->Error`, `finish(record:Dictionary)->Error`, `jump(target:String,guides:Array=[])->Error`; production path constants and data-driven static `shop_for(profile)->SpecShop`. App `create_session()->RefCounted` uses lazy `profile` property. Task2 consumes exactly this contract.

- [ ] Write tests for unchanged bus identity/subscriptions through multiple reset, successful restore, rejected restore and idempotent listeners. Check one sale/unlock callback per event after repeated reset, exact log restoration and no stale candidate callback.

  ```gdscript
  var bus = rules.events
  var seen: Array = []
  bus.on("probe", func(data:Dictionary): seen.append(data))
  rules.reset()
  rules.reset()
  check(rules.events == bus, "stable bus")
  rules.events.emit("probe")
  check_eq(seen.size(), 1, "subscription survives once")
  ```

- [ ] Add Session start/save/finish/jump/fresh failure/retry tests using temporary Profile/Store, preserving bytes and no duplicate commits. Check disabled service defaults, invalid enabled empty paths, restart resumes, tuning/speed/guides preserved, no Profile change, restarted once. Test App lazy construction without touching real paths.
- [ ] Run focused suite to behavioral RED with ErrorCounter and isolated APPDATA. Store exact command/output in task report.
- [ ] Implement stable RuleEvents reset/on semantics and staged adoption preserving live bus. Implement Session with ProgressService delegation; explicit dependencies only. Implement lazy App profile and production factory. Do not change economic state or add lifecycle events to saved logs.
- [ ] Register tests/test_session.gd; register Task2 test_scene_session.gd after that file exists. Run new suite + existing rules/save/state/profile suites and baseline compatibility. Report task-1-report.md with red/green, API, edge cases; freeze owned files without committing.

## Task 2: Explicit scene assembly, restart UI, isolated fixtures

**Files:** presentation/shop/shop_play.gd; presentation/shop/shop_tuning.gd; presentation/shop/shop_recorder.gd; presentation/shop/guide_player.gd; optional presentation/shop/hud/popup_queue.gd and restart_page.gd; new tests/shop_test_session.gd; new tests/test_scene_session.gd; new tests/render_session_lifecycle.gd; existing tests/render_progress_retry.gd, render_shop_*.gd, render_work_actions.gd, test_profile_safety.gd; .github/workflows/tests.yml; new docs/session-lifecycle.md. Do not edit Task1-owned core or run_all.

**Interfaces:** consumes Task1 Session contract above. Scene exposes `session:RefCounted`; rules/store/profile stay aliases after successful start, with scene legacy partial injection rejected before any App fallback. Scene `restart` cancels drag before Session.restart and resets transient UI before safe save. Guide gains one restart method preserving seen IDs and enabled state, clearing transient fields. Tuning gains injected `file_path`; Recorder disabled mode gates all reads/writes/delete/export.

- [ ] Create isolated test-session helper that can be used before scene tree entry, with stable namespace reuse and explicit service booleans; supports injected store/profile/rules. Tests set `scene.session` explicitly.

  ```gdscript
  scene.session = TestSession.make(spec, namespace, provided_rules, provided_store, provided_profile)
  scene.session.guide_enabled = true
  # Tutorial can be enabled without recording or tuning persistence.
  check(not scene.session.recording_enabled, "independent services")
  ```

- [ ] Add failing unit/live regressions for production-file sentinels, guide/record/tuning independence, disabled recorder read/clear/export, explicit session vs partial injection, restart paused false, clean popup/guide/drag state, preserved settings and recorded sample timing. Use actual scene/real ShopSave faults, not mirrored mock assertions. Observe expected RED before implementing.
- [ ] Integrate scene through Session start/save/finish/jump and preserve retry/exit guards. Replace inferred guide flags/persistent defaults with explicit Session config. Implement one restart path resetting counters, transients and UI; stable audio subscription should receive events once.
- [ ] Inject tuning paths and protect disabled Recorder operations. Migrate all repository shop scene construction to the common isolated test factory, including prior progress-safety fault tests and work-action captures. Preserve all original meaningful checks, update assertions to the explicit production/test contract. No default App Profile reads in fixtures.
- [ ] Add bounded render_session_lifecycle.gd CI step; add focused docs describing production factory, test factory and restart contract. Run focused/live regression + five shop GUI/audio tests + startup retry with isolated APPDATA, checking font coverage and no runtime warnings/errors. Report task-2-report.md, freeze files without committing.

## Task 3: Integration, independent review, PR

- [ ] Parent runs stable full suite, layouts and baseline, six existing GUI/retry scripts plus new lifecycle script; inspect changed UI only if visuals change. Compare real user-data hashes and confirm clean scoped diff.
- [ ] Commit explicit files; generate review packages. Independent task spec/code-quality review, owner fixes and scoped re-review as needed, then final whole-branch review. Run covering checks on fixes.
- [ ] Push codex/session-lifecycle, create PR targeting codex/progress-safety with dependency65/64 and actual evidence. Monitor Godot4.7 CI to completion without merging. Archive only this plan's ignored workflow records outside repo after completion.
