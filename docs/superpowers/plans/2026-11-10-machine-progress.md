# Machine progress implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development task by task.

**Goal:** Separate automatic machine clocks and phase effects from ShopRules while preserving all numeric, save and ordering behavior.
**Architecture:** Stateless MachineProgress mutates explicit records; Rules owns topology/filter/output/duration queries and two-phase automatic start. Existing pure Inventory.stock supplies occupancy.
**Tech Stack:** Godot GDScript, headless literal and real-rule tests, bounded complete state/callback traces.
**Spec:** docs/superpowers/specs/2026-11-10-machine-progress.md

## Global Constraints

Use D:/Tes/eatventure on codex/machine-progress; no new worktrees/main writes/merges. Every engine D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe --headless with explicit APPDATA under D:/Tes/eatventure-analysis/machine-progress-userdata/session-lifecycle-userdata/<runner>. No local --import or visible-window probes. Preserve save format, assets, fonts and content. Helpers no class_name/cycles/Rules-host-context-callback-SpecShop-nav-RNG-service dependencies/cache/serialization/new Rules construction. Only pure Inventory.stock static dependency allowed. Worker no subagents/staging/commits. Evidence D:/Tes/eatventure-analysis/machine-progress-pr/validation-records. Capture real-userdata manifest before first engine, verify unchanged afterward, never restore real data automatically. Baseline2d37c78 has299 tests and Godot4.7 CI42715409080 SUCCESS; do not rerun unchanged baseline. Archive only this plan's workflow by hash-verified copy, no binary duplication; leave ignored siblings and do not retry blocked recursive deletion.

### Task 1: Explicit machine progression and two-phase automatic starts

**Files:** Create game/rules/machine_progress.gd, tests/test_machine_progress.gd and docs/machine-progress.md; modify game/rules/shop_rules.gd only machine update/facade/single pot loop and tests/run_all.gd suite registration. Runners/reports only in this plan's SDD workspace; external binary/log evidence in records.

**Interfaces:** All four exact static signatures and semantics in spec are binding: pause_for_stir, advance_handoff, begin_automatic, advance_single. Consume existing pure Inventory.stock(station). Leave Inventory, Completion, Sales, WorkerState unchanged. Rules integration:

```gdscript
var input_item := MachineProgress.advance_handoff(station, st.block, STEP,
    st.params.get("stir_points", []) if st.block == "batch_pot" else [])
if not input_item.is_empty():
    station.processing_item = input_item if st.block == "pickup" else _auto_output(key)
    MachineProgress.begin_automatic(station, machine_seconds(key))
```

- [ ] Read spec. Before production changes, adapt external D:/Tes/eatventure-analysis/fulfillment-completion-pr/validation-records/frozen-trace-runner.gd (never old ignored workspace). Use this task's records path/names and actual baseline2d37c78. Preserve its scenarios,321 actual unique sales/save/lifecycle coverage; add bounded machine phase counters + first-phase snapshots. Correct fixture only before final old capture; preserve dry-run evidence. Capture old provenance/runner/data hashes before edit, refuse overwrite, <=50MiB. Report positive pot heating/stir/awaiting_take, auto working, single cook/done; any missing coverage gets a focused scenario before old freeze, not a production change.
- [ ] Guard ResourceLoader.exists/load for missing module and run literal assertion RED. Hand-derived example:

```gdscript
var station := {"input":{"raw":3},"output":{"tea":1},"phase":"working","progress":0.5,
    "remaining":0.05,"duration":1.0,"processing":2,"processing_item":"tea","work_reserved":true,"extra":9}
check_eq(kernel.advance_handoff(station,"combine",0.1,[]),"raw")
check_eq(station.output,{"tea":3})
check_eq([station.processing,station.input.raw,station.processing_item,station.phase,station.progress,station.remaining], [3,0,"","ready",1.0,0.0])
station.processing_item = "tea"
kernel.begin_automatic(station,2.0)
check_eq([station.duration,station.remaining,station.progress,station.phase,station.extra,station.work_reserved],[2.0,2.0,0.0,"working",9,true])
```

Add literal tests for every spec boundary: first crossed unsorted stir points, exact crossing vs equal before, stir before completion, await/stir blocked, handoff epsilon/clamp, single<=0/no clamp/no progress, pickup/combine/input insertion order, idle/ready retention, no input vs running, unrelated fields and container identity. Real Rules fixtures observe _auto_output/machine_seconds in original consumed-input/bound-output/old-phase order; no queries for no-start/filter cases and single customer->pot->worker ordering. Derive expectations independently, not production calls as oracle. RED must be missing-module assertions without parse errors.
- [ ] Implement minimal exact kernel and Rules wiring, preserve facade and all loop/filter orders. Runtime module only pure Inventory.stock dependency. No eager duration/output queries; no normalization, new time policy or eligibility restrictions. Add suite to run_all and document module ownership plus handoff/single timing differences and the start protocol.
- [ ] Run focused GREEN; freeze final game/content/tests/new docs/runner file hashes before integration. Notify parent freeze READY with no further edits planned. Full run_all once, golden with explicit -- --check (retain actual original subprocess result; never synthesize exit status), tea/pancake/noodle scene regressions, final trace vs frozen old. Every result records exact command, APPDATA, exit, runtime errors and log hash. ErrorCounter/independent log scan required even exit0. No duplicate unchanged suite runs. Parent runs remaining10 integration groups separately.
- [ ] Write concise .superpowers/sdd/2026-11-10-machine-progress/task-1-report.md (target <=7KiB): files/API/decisions, exact command entrypoints/result/log paths, RED/GREEN/full/golden/scene/trace evidence, source/runner hashes and nonvacuous counts, numerical/query-order reasoning and concerns. Preserve failed setup logs separately; no source edits after freeze unless necessary, then revalidate covering checks. No subagents/staging/commits. Parent inspects evidence, stages all requested files including new files, git diff --cached --check abort-on-error, commits, generates task diff package and independent task spec+quality review followed by strongest-model whole review.

## Parent review and publication gates

Preflight rows: Task1 ownership vs immutable dependencies; loop/filter/query sequencing vs exact kernel calls; numeric boundary tests vs literal behavior; old trace/source chronology vs production changes; final source freeze vs parent integrations. All have consistent interfaces, no shared task writers. Real-userdata manifest READY before first engine. Parent final10 integration groups (config/layouts/extend/guide/audio/retry/lifecycle/commands/boundary/work-actions) use separate APPDATA and copied external runner. Independent task and whole reviews, one final scoped fix wave if needed. Verify remote PR75/main; stack on codex/fulfillment-completion while open, or rebase only own commits from2d37c78 if dependencies merged and revalidate human deltas. Push/create one PR, wait exact-head Godot4.7 CI success, no merges. Hash-verified copy archive only this plan's workflow, no deletion retries or binary duplication.
