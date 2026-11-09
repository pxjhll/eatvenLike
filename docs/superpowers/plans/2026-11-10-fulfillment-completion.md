# Fulfillment completion implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development task by task.

**Goal:** Make sales state and completion effects independently understandable/testable while preserving every runtime/save behavior.
**Architecture:** Sales owns five counters; a stateless completion kernel mutates explicit records; Rules sequences external effects and emits events.
**Tech Stack:** Godot GDScript; headless literal/regression tests and frozen before/after trace.
**Spec:** docs/superpowers/specs/2026-11-10-fulfillment-completion.md

## Global Constraints

Use D:/Tes/eatventure on codex/fulfillment-completion; no new worktrees/main writes/merges. Every engine D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe --headless with explicit APPDATA under D:/Tes/eatventure-analysis/fulfillment-completion-userdata/session-lifecycle-userdata/<runner>. No local --import or visible-window probes. Preserve save format, assets, fonts and content. Helpers no class_name/cycles/Rules-host-context-callback-SpecShop-nav-RNG-service dependencies/cache/serialization/new Rules construction. Inventory and WorkerState unchanged. Worker no subagents/staging/commits. Records D:/Tes/eatventure-analysis/fulfillment-completion-pr/validation-records. Record real-userdata manifest before first engine, never restore it. Baseline7c3fe62 has277 tests and CI42648428945 SUCCESS; do not rerun unchanged baseline.

### Task 1: Sales state owner

**Files:** Create game/rules/rule_sales.gd and tests/test_sales.gd; modify game/rules/shop_rules.gd sales fields/three settlement branches and tests/run_all.gd. Scratch runners only in this plan's workspace.

**Interfaces:** Implement all four exact Sales signatures in spec. Own gold/revenue/sold/sold_by_dish/sale_carry. Rules `_sales` initialized before forwarding properties including `_sale_carry`; preserve current serialization/reset/load and money command callers. Return payloads, never emit inside helper.

- [ ] Read spec in full. BEFORE production edits freeze old trace and runner/provenance. Adapt external archived D:/Tes/eatventure-analysis/worker-transitions-pr/validation-records/old-trace-runner.gd (do not read old ignored workspace), fixing fixture only before final capture. Four real scenarios tea mobile/seated, pancake/noodle, seed42,5000+1000 ticks; include legal commands, sales/work/waits, belts, recall/place, active save at2500, reset/reopen, complete checkpoints and synchronous callbacks. Add monetary counters, current job/order id in callbacks; assert repeated normal-order settlement absent with nonzero sales. Capture <=50MiB trace; output overwrite refusal; frozen runner and source hashes in records. Full every-tick states prohibited. Runtime logger errors fail.
- [ ] Write guarded assertion RED using ResourceLoader.exists/load for missing module. Literal sample:

```gdscript
var sales = load("res://game/rules/rule_sales.gd").new()
sales.sold_by_dish = {"tea": 0}
sales.count_handoff("tea", 3)
check_eq(sales.credit_handoff({"item":"tea", "count":3}, 1.25), {"dish":"tea", "count":3, "income":3})
check_eq([sales.gold, sales.revenue, sales.sold, sales.sale_carry], [3.0,3.0,3,0.75])
```

Also test floor epsilon/clamp/cumulative carry, two independent owners, both single pay modes/addon dedup and exact payload keys, Rules forwarded dictionary assignment/reset/candidate load, synchronous event ordering and price-query order (if using subclasses keep fixture isolated). Use hand-derived expectations, not production functions as oracle. Run focused RED with no missing-preload parse errors.
- [ ] Implement owner and thin Rules forwarding. Preserve seat before count before price, queue removal before quote, sale emission before worker cleanup. Example integration:

```gdscript
_sales.count_handoff(job.item, job.count)
events.emit("sale", _sales.credit_handoff(job, dish_price(job.item)))
```

- [ ] Focused GREEN plus existing inventory/worker/numeric/save/single/handoff test groups covering touched behavior; compare frozen full trace, report coverage/money/unique order counts. Full suite reserved for final Task2 source. No duplicate passed checks on unchanged source.
- [ ] Write .superpowers/sdd/2026-11-10-fulfillment-completion/task-1-report.md with files/interfaces/decisions, exact commands/output logs/exit codes/runtime errors, RED/GREEN, old runner/source/data hashes, nonvacuous coverage, trace equality/size and concerns. No stage/commit/subagents. Parent inspects evidence, stages including new files, git diff --cached --check (abort on error), commits, generates diff package, independent spec+quality review.

### Task 2: Completion kernel

**Files:** Create game/rules/fulfillment_completion.gd and tests/test_fulfillment_completion.gd; modify game/rules/shop_rules.gd completion branches/facade and tests/run_all.gd; add docs/fulfillment-completion.md describing boundaries and unchanged behavior.

**Interfaces:** Consume Task1 Sales APIs and current Rules properties unchanged. Implement all five exact static completion signatures in spec. Rules owns stock `_take`, numeric queries, ticket progression, events, WorkerState calls.

- [ ] Read spec; inspect Task1 report for final interfaces. Guarded assertion RED for missing kernel. Literal examples:

```gdscript
var station := {"output":{"tea":2},"processing":3,"phase":"waiting","progress":0.4,"work_reserved":true,"remaining":7.0}
kernel.complete_handoff_work(station, {"kind":"pot_take"}, 0.0)
check_eq(station, {"output":{"tea":5},"processing":0,"phase":"ready","progress":1.0,"work_reserved":false,"remaining":7.0})
```

Cover pot_start/stir/pot_take/work, source consumption predicate, topping output/input and unrelated fields; load/unload with cap and untouched history; exclusive adjacent/released steps, holds empty/nonempty, take index-only and terminal hand integration. Expectations literal/hand-derived. Run focused RED.
- [ ] Implement kernel/integrate exact sequencing. `_complete_topping` forwards kernel; take source before pot_seconds/completion; finish worker after. Single finish_single_work remains first; chore args only query duration for load, batch/cap for unload; verify RuleNumbers pot functions don't depend on station.phase. Take uses kernel index-only, hand returns after existing settlement/event/WorkerState path. Example:

```gdscript
if Completion.consumes_handoff_source(job): _take(job)
Completion.complete_handoff_work(station, job, pot_seconds(job.src) if job.kind == "pot_start" else 0.0)
_finish(worker)
```

- [ ] Focused GREEN, full run_all once on frozen final source; golden and tea/pancake/noodle scene smokes; compare same frozen trace from Task1, no overwrite of old reference. Record source hashes, command/exit/runtime-error and bounded counts. All engines headless/isolated APPDATA, runtime errors fail even exit0. Parent will run remaining10 integration groups after freeze; do not duplicate them.
- [ ] Write .superpowers/sdd/2026-11-10-fulfillment-completion/task-2-report.md with files/API, timing/dependency reasoning, RED/GREEN/full/trace/scenes/golden evidence paths and source freeze/concerns. No stage/commit/subagents. Parent checks/stages/checks/commits, independent spec+quality review, strongest-model whole review and one scoped final fix wave if necessary.

## Parent publication gates

Ledger preflight matrix includes Task1/Task2 shared Rules/run_all interface, each task's internal consistency, ownership/load/reset and event/query sequencing. Review exact evidence, retain tests with new files checked at staging. Final parent integration groups (config/layouts/extend/guide/audio/retry/lifecycle/commands/boundary/work-actions) using copied external runner with separate APPDATA. Verify all real-userdata hashes unchanged. Inspect PR73/74/main; stack new PR on codex/worker-transitions while open, rebase only own commits if dependencies merged, preserve human changes. Push feature branch/create one PR, follow exact-head Godot4.7 CI to success; no merges. Hash-verified copy archive only own workflow, no deletion retries or binary duplication.
