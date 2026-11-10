# Order lifecycle implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development task by task.

**Goal:** Give customer/order collections and lifecycle transitions an explicit owner without changing random streams, save data or synchronous observations.
**Architecture:** RuleOrders owns ten saved fields and local record transitions. Rules keeps eligibility/query/RNG/event sequencing, Sales delegates only paid/leaving transitions while retaining its API. No host or callback is passed into the owner.
**Tech Stack:** Godot GDScript; literal owner/real Rules tests, isolated headless regression and frozen lifecycle/dispatch traces.
**Spec:** docs/superpowers/specs/2026-11-10-order-lifecycle.md

## Global Constraints

Use D:/Tes/eatventure on codex/order-lifecycle; no new worktrees/main writes/merges. Every engine D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe --headless with explicit APPDATA under D:/Tes/eatventure-analysis/order-lifecycle-userdata/session-lifecycle-userdata/<runner>. No local --import or visible-window probes. Preserve save format, assets, fonts and content. Owner no class_name/cycles/Rules-host-context-callback-SpecShop-nav-RNG-service dependencies/cache/serialization/new Rules construction. Sales may preload owner script only for its static customer transitions. Worker no subagents/staging/commits. Evidence D:/Tes/eatventure-analysis/order-lifecycle-pr/validation-records. Real-userdata manifest READY before first engine, verify unchanged after, never auto-restore. Baselineaed3f64 has336 tests and Godot4.7 CI42732251537 SUCCESS; do not rerun unchanged baseline. Archive own workflow only by hash-verified copy, no binary duplication; leave ignored siblings and do not retry blocked recursive deletion.

### Task 1: Order state owner and callback-safe lifecycle

**Files:** Create game/rules/rule_orders.gd, tests/test_order_lifecycle.gd and docs/order-lifecycle.md. Modify game/rules/shop_rules.gd only ten forwarded fields and the exact lifecycle call sites in spec; game/rules/rule_sales.gd only preload/static transition delegation; tests/run_all.gd suite registration. Existing sales tests and other owners unchanged. Scratch only this plan's workspace.

**Interfaces:** All ten exact fields, fifteen instance and two static APIs in spec. Owner before forwarding initialization, no new serialized fields/cache. Sales API unchanged. Integration examples:

```gdscript
# _customers_single: keep patience calculation and snapshot iteration in Rules.
for c in customers.duplicate():
    if _orders_state.advance_single_customer(c, STEP, patience):
        events.emit("lost", {})
    _orders_state.remove_leaving_single(c)
# _find_job_single after chores-first:
var c := _orders_state.claim_single()
if c.is_empty(): return false
WorkerState.claim_single_order(s, c.id, _order_steps(c))
```

- [ ] Read exact spec. BEFORE production edits adapt only external archived D:/Tes/eatventure-analysis/dispatch-policy-pr/validation-records/sdd-aed3f64/trace-runner.gd. Preserve four real scenarios/dispatch/machine/sales/save/lifecycle checks; add compact arrived/lost lifecycle records and first-kind full states. Require positive admits/rejections/timeouts; if needed add bounded legal scenario before old capture. Freeze actual baseline source/runner/provenance/data hashes, old reference output refusal and <=50MiB bound. No callback/data mutation by sampler or full every-tick snapshots.
- [ ] Before touching production, write the complete guarded literal and real Rules tests and observe behavioral assertion RED. Do not start from only test_module_exists then implement. Example independent tests:

```gdscript
var state = load("res://game/rules/rule_orders.gd").new()
var options := ["spicy"]
var customer: Dictionary = state.admit_single("dish",false,options)
check_eq(customer,{"id":1,"kind":"dish","addon":false,"state":"queue","wait":0.0,"claimed":false,"paid":0,"options":["spicy"]})
check(is_same(customer,state.customers[0]) and is_same(options,customer.options),"original aliases")
check(not state.advance_single_customer(customer,1.0,1.0),"exact patience is retained")
check(state.advance_single_customer(customer,0.1,1.0),"strict excess leaves")
check_eq([state.lost,state.queue,state.customers.size(),customer.state],[1,[],1,"leaving"],"event boundary before removal")
customer.state = "paid"
state.remove_leaving_single(customer)
check_eq(state.customers.size(),1,"callback revival retained")
```

Also literal every API/default/ramp/lookup/reservation/remove/diner/overflow/FIFO/static transition. Rules fixtures verify all ten property writes and resets/load acceptance/rejection, references and schema keys; admitted/lost/sale callbacks and claim/quote/cleanup sequencing; callback revival/current-array replacement; fixed/exponential RNG including flyer-first, full queue, zero weights/closed, addon and locked options. Derive expected state and RNG progression independently from current definitions/draw counts, not owner outputs. Existing sales test API remains unchanged. Record actual guarded RED with no parse/runtime errors.
- [ ] Implement minimal owner and thin Rules delegation at original positions. Preserve is_open/capacity/sampling queries and RNG statements. Loop timeout one row then emit then recheck/removal. No batch callbacks, idempotency guard, queue normalization or early cleanup. Sales calls static accept after credit and static leave before sold counts, without importing Rules or constructing owner. Document ownership, dual modes and callback order.
- [ ] Focused GREEN and changed-domain existing sales tests; inspect whitespace including untracked new files before final source freeze. Freeze all game/content/tests/new docs/GDScript runner hashes, notify parent READY/no more edits. Full suite once, golden literal -- --check, three scenes and final trace vs frozen old. Driver keeps literal `--`, actual command/APPDATA/exit/elapsed/hash and separate runtime/assertion fields. Parent owns final10 integrations after freeze; no duplicate passed checks. Retain failed setup evidence under separate names; any semantic change after freeze revalidates covering checks.
- [ ] Report .superpowers/sdd/2026-11-10-order-lifecycle/task-1-report.md target<=8KiB with files/API, commands/results/log/hash paths, true RED/GREEN chronology, full/golden/scenes/trace, positive lifecycle coverage and RNG/reentrant/reference reasoning. No subagents/staging/commits. Parent reads evidence, stages all named files including new files, cached whitespace check abort-on-error, commits, independent task spec+quality then strongest-model whole review.

## Parent gates

Preflight rows cover forwarding vs STATE_KEYS/BY_DATA_ID/reset/candidate load; Sales->OrderState static no-cycle dependency; timeout callback/removal/current-array semantics; RNG/query order and flyer sequencing; reserve/cancel/sale/worker timing; bounded baseline observer before production; independent freeze/integrations; new-file whitespace and original command/hash capture. Capture real-userdata manifest before engine. Parent10 config/layouts/extend/guide/audio/retry/lifecycle/commands/boundary/work-actions use separate APPDATA and upgraded runner capturing actual command and log hashes at original execution. No concurrent source writers. Complete reviews/fix wave if required, verify PR77/main, stack on codex/dispatch-policy while open or rebase only own commits from aed3f64 after dependency merges and revalidate human deltas. Push/create one PR, await exact-head Godot4.7 CI, no merges. Verify real-userdata unchanged and hash-copy only own workflow for archive.
