# Worker transitions implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans task by task.

**Goal:** Centralize worker record transitions and share path advancement with identical saved/runtime behavior.
**Architecture:** Stateless WorkerState mutates explicit worker data; Rules owns navigation, decisions, stock/order/machine effects and events. Handoff and single transitions retain their distinct timing/cleanup contracts.
**Tech Stack:** Godot GDScript, headless literal and real-rule tests, before/after state+event callback traces.
**Spec:** docs/superpowers/specs/2026-11-09-worker-transitions.md

## Global Constraints

Use D:/Tes/eatventure on codex/worker-transitions; no worktrees/main writes/merges. Every engine D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe --headless, explicit APPDATA D:/Tes/eatventure-analysis/worker-transitions-userdata/session-lifecycle-userdata/<runner>. No local --import/native-window probes. Helper no class_name/cycles/Rules-host-context-callback-SpecShop-nav-RNG-service dependency/cache/serialization/new Rules construction. Keep phase strings, worker fields/presence/alias and save contracts, business/recipe/dispatch/RNG/event ordering and assets/font/content intact. Baseline9a38db7(PR73OPEN) has265 tests/CI42640211903 SUCCESS; do not repeat unchanged baseline. Worker no subagents/staging/commits. Records D:/Tes/eatventure-analysis/worker-transitions-pr/validation-records.

### Task 1: Explicit worker lifecycle entries and shared movement

**Files:** Create game/rules/worker_state.gd and tests/test_worker_state.gd; modify game/rules/shop_rules.gd selected worker writes/facades/path loops only, tests/run_all.gd; add docs/worker-transitions.md. Trace/focused/golden logger runners only in this plan's SDD workspace.

**Interfaces:** Implement all17 exact static WorkerState signatures/semantics in spec Exact transition APIs. The explicit data dependencies and field-retention rules are binding. Integration examples:

```gdscript
func _new_worker(kind_id: String, id := -1) -> Dictionary:
    var kind := _kind(kind_id)
    var worker_id := id if id > 0 else _next_staff
    _next_staff = maxi(_next_staff, worker_id + 1)
    return WorkerState.create(worker_id, kind_id, kind.display_name, kind.stats,
        nav.point(shop.layout.spawn_point))

func _walk(worker: Dictionary, destination: Vector2, phase: String) -> void:
    WorkerState.begin_walk(worker, nav.path(worker.pos, destination), phase)

func _work_single(worker: Dictionary, seconds: float) -> void:
    WorkerState.begin_single_work(worker, seconds)
```

- [ ] BEFORE production edits create the bounded old trace with frozen runner/provenance and output-overwrite refusal. Four real scenarios (tea mobile/seated brewer, pancake/noodle), seed42, funded legal commands,5000+1000 ticks. Full checkpoints/unique phases/command states plus synchronous callback snapshots as spec; counters each tick only, no full every-tick capture, <=50MiB binary. Require actual sales/work/movement/single waits and handoff legal recall/placement; active save at2500 and reset/reopen. Correct only fixture before final old capture; report all observed coverage and provenance. If a genuine preexisting behavior defect appears, give controller minimal reproduction before changing semantics.
- [ ] Write guarded missing-module assertion RED, not a preload parse failure. Derive expectations independently from hand-checked inputs and current fixture definitions. Example motion: [Vector2(0,0),Vector2(10,0),Vector2(10,5)] from0; advance12 => pos(10,2),index2,walkingtrue; advance3 => pos(10,5),index3,walkingfalse. Test zero distance with unconsumed zero-length waypoint versus index-at-end separately and epsilon snap. No expectations computed by WorkerState itself.
- [ ] Test exact factory row/default fields (duration absent initially), separate containers/stats; replace-versus-clear cleanup aliases; finish_handoff retains ticket/path/index/action_left/history but increments completed, cancel clears common fields without touching business collections/single history. Single raw timer can end negative and uses zero completion threshold; handoff clamps and uses1e-6. Test wait/standby/claim/finish preserve unrelated fields, last step/timer/target history and label timing. Module never modifies data outside explicit worker record, apart from intentional owned route/steps references as documented.
- [ ] Implement stateless module and replace selected Rules writes. Shared advance_walk must preserve both original loops including epsilon, duplicate waypoints, leftover budget and early-return timing. Legacy empty single paths use set_path, not begin_walk. Keep ticket/job/customer/station/inventory/payment logic and command/event order in Rules. No generic state normalization, mode-merging, new invalid-command policies or save validation tightening.
- [ ] Run focused GREEN with runtime logger. Replay the identical old probe and compare every complete recorded state/command/callback payload, native binary comparison/hash permitted; old reference never overwritten. Add actual Rules tests around active walking/work, legacy pathless route restoration, callbacks and stable inventory diagnostics; no copied old production engine/source in committed tests.
- [ ] Self-review and document phase graphs, explicit inputs, mutation ownership and asymmetric timing/cleanup rules. SOURCE FREEZE notify parent before final tests. Run one full tests/run_all.gd; unchanged tests/baselines/record_rules.gd -- --check with runtime logger; tests/render_shop_tea.gd, render_shop_pancake.gd, render_shop_noodle.gd. Parent separately owns remaining10 integration groups including render_work_actions, no duplicate passed suites.
- [ ] Detailed report .superpowers/sdd/2026-11-09-worker-transitions/task-1-report.md: exact interfaces/files/decisions, RED/GREEN/full/trace/scene commands and absolute logs/results/runtime errors, old-source provenance and callback/phase coverage/nonvacuous counts, trace size/hash, source freeze and concerns. No stage/commit/subagents. Parent reads evidence/stages/checks (including new untracked-file EOF whitespace)/commits, independent task review then strongest-model whole review.

## Parent gates and publication

Real-userdata manifest READY before first engine and unchanged afterward; never restore production data. Parent owns plan preflight/ledger/commit/review/fix loops and remaining final integrations after freeze. No concurrent production writers. Verify remote PR73/main state, stack on codex/inventory-reservations while open or rebase only own commits after dependency merges; preserve/revalidate human deltas. Push own feature branch/create one PR, wait for exact-head Godot4.7CI success, no merges. Hash-verified copy archive only this plan's workflow, retain external evidence once, leave prior ignored workspaces and do not retry blocked recursive deletion.
