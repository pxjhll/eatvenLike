# Dispatch policy implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development task by task.

**Goal:** Separate dispatch candidate construction, ranking and tie policy from live queries and reservations.
**Architecture:** Stateless DispatchPolicy receives explicit candidate facts and immutable SpecDispatch. Rules keeps greedy per-round enumeration, routing/stock queries and execution. Borrowed references retain legacy identity.
**Tech Stack:** Godot GDScript, headless independent literals/real Rules fixtures and bounded before/after dispatch trace.
**Spec:** docs/superpowers/specs/2026-11-10-dispatch-policy.md

## Global Constraints

Use D:/Tes/eatventure on codex/dispatch-policy; no new worktrees/main writes/merges. Every engine D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe --headless with explicit APPDATA under D:/Tes/eatventure-analysis/dispatch-policy-userdata/session-lifecycle-userdata/<runner>. No local --import or visible-window probes. Preserve save format, assets, fonts and content. Policy no class_name/cycles/Rules-host-context-callback-SpecShop-nav-RNG-service dependencies/cache/serialization/new Rules construction; immutable SpecDispatch input only. Worker no subagents/staging/commits. Evidence D:/Tes/eatventure-analysis/dispatch-policy-pr/validation-records. Real-userdata manifest READY before first engine, verify unchanged afterward, never auto-restore. Baselineb708241 has320 tests and Godot4.7 CI42722672230 SUCCESS; do not rerun unchanged baseline. Archive own workflow only with hash-verified copy, no binary duplication; leave ignored siblings and do not retry blocked recursive deletion.

### Task 1: Candidate factories and streamed winner selection

**Files:** Create game/rules/dispatch_policy.gd, tests/test_dispatch_policy.gd and docs/dispatch-policy.md. Modify game/rules/shop_rules.gd only _candidate, serve enrichment in _jobs, _exact facade, applicable _new_ticket_job fallback/bonus, _allocate ranking, _run_belts choice; tests/run_all.gd suite registration. Existing owners and numeric formulas unchanged. Scratch only this plan's SDD workspace.

**Interfaces:** Implement all eight exact APIs in spec: transport_candidate, serve_candidate, exact_count, wait_bonus, score, consider, route_choice, fallback_pot_choice. Rules locals:

```gdscript
var best := {"score": -INF, "worker": {}, "job": {}}
# Original per-candidate eligibility, path and duration calculations precede:
DispatchPolicy.consider(best, worker, job,
    DispatchPolicy.score(d, worker, job, travel, work_time))
# Original end-of-round execution follows:
if best.job.is_empty(): break
_reserve(best.worker, best.job)
```

- [ ] Read exact spec. BEFORE production edits freeze actual b708241 source provenance and old trace. Adapt only external archive D:/Tes/eatventure-analysis/machine-progress-pr/validation-records/sdd-b708241/trace-runner.gd. Preserve real four-scenario/machine/business/lifecycle coverage; append compact all-reservation decisions and belt shipments plus first-kind complete snapshots. _reserve override records job before super (ticket later erased); no live state mutation in sampler. Each reservation/tick must not duplicate full state. Report positive reservations/tickets/belts. Refuse overwrite, <=50MiB, frozen runner/hash/provenance, no byte dumps. Correct only fixtures before final old capture.
- [ ] Write guarded missing-module assertion RED. Literal examples and independent expectations:

```gdscript
var dispatch := SpecDispatch.new()
dispatch.throughput_weight = 4.0
dispatch.travel_penalty = 1.0
dispatch.fatigue_weight = 0.4
check_eq(policy.score(dispatch,{"fatigue":0.25},{"count":3,"priority":10.0},2.0,4.0),9.0)
var job: Dictionary = policy.transport_candidate("load","supply","pot","raw",4,3,2,7.0)
check_eq(job,{"kind":"load","src":"supply","dst":"pot","item":"raw","count":2,"priority":7.0,"belt":"","order_id":-1})
var best := {"score":-INF,"worker":{},"job":{}}
var worker := {"id":1}
policy.consider(best,worker,job,-3.0)
policy.consider(best,{"id":2},{"other":1},-3.0)
check(is_same(best.worker,worker) and is_same(best.job,job),"first tie retains original references")
```

Cover all spec literal and real Rules cases: count/query ordering/shelf second cap, serve count/pour/order/bonus+ vs follow overwrite, exact_count identity/rejection, score denominator/weights/fatigue/negative, initial-INF and ties, route filters/no-copy, fallback shallow-copy aliases. Real greedy fixture must make first reservation change available inventory so next round chooses differently; observe worker/job tie order and unreachable and work-only estimator queries. New-ticket fixture and belt pipeline fixture cover integration. Do not use policy output as oracle or add permissive mocks hiding runtime errors. Run guarded RED with actual process result/runtime errors recorded.
- [ ] Implement helper and minimal wiring. Preserve two greedy loop levels and every query/filter/iteration order; score/consider only after route/work cost. _candidate queries carry→available→free, shelf query only for nonempty shelf candidate. Serve enrichment after seats_left handling. Fallback only when applicable, same shallow-copy policy; follow priority/wait attachment after success. Belt only choice loop extracted. No cache, command eligibility change, UI or save edits. Add suite and ownership/tie documentation.
- [ ] Run focused GREEN, freeze final game/content/tests/new-doc/GDScript-runner hashes, notify parent READY/no source edits. Run full once, literal golden -- --check with actual retained metadata, three scenes and final trace vs old. Parent runs remaining10 groups (separate APPDATA) after freeze; do not duplicate. Ensure driver argument arrays keep literal `--` via REMAINDER/direct list before engine runs, no record-mode baseline write. Runtime errors fail regardless of process exit; preserve setup failures separately and use new log names for justified retries.
- [ ] Report .superpowers/sdd/2026-11-10-dispatch-policy/task-1-report.md target<=7KiB: files/API, exact entrypoints/results/logs/hashes, RED/GREEN/full/golden/scenes/trace, source/runner provenance, nonvacuous reserve/ticket/belt counts, tie/query/reference reasoning and concerns. No subagents/staging/commits. Parent inspects actual evidence, stages named files including new ones, git diff --cached --check abort-on-error, commits, generates package, independent task spec+quality review then strongest-model whole review.

## Parent gates

Preflight checks each shared interface within Task1: factories vs shelf/seat cap query order; score/consider vs per-round reservation regeneration; route selection vs fallback distinct reference/initial policies; immutable SpecDispatch vs no host context; old sampler vs production chronology; final freeze vs independent integrations. Real-userdata manifest READY before engines and unchanged after. Final10 groups config/layouts/extend/guide/audio/retry/lifecycle/commands/boundary/work-actions from external copied runner. No concurrent production writers. Task/whole reviews and one scoped final fix wave if necessary. Inspect PR76/main; stack on codex/machine-progress while open, rebase only own commits after dependency merge from b708241 and revalidate human deltas. Push/create one PR, await exact-head Godot4.7 CI success, no merges. Hash-verified copy of own workflow only, no deletion retries or duplicate binaries.
