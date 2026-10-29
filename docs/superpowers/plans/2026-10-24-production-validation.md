# PXJ-22 / PXJ-23 validation plan

**Goal:** Close the concrete coverage gaps recorded in the Linear audit without changing the playable bakery balance or presentation.

**Spec:** Architecture Contract v1.1; PXJ-22 and PXJ-23 acceptance criteria and the approved 2026-10-24 audit comments.

**Architecture:** Use real GameSim, Production and Workforce with deterministic test-only definitions. Keep test fixtures under tests/fixtures; register suites in the existing headless runner. Production code changes require a failing regression first.

**Tech Stack:** Godot 4.7, GDScript, existing plugin-free test runner.

## Constraints and review focus

- Retain one owner per business state, immutable definitions and command-based changes.
- Exercise MANUAL production, not merely front-hall service.
- Verify a single employee can serve both COOP ovens and remains free during baking.
- New machine and staff IDs must work without a dispatch change.
- Use real bread-to-sliced-bread recipes; the existing toast counter alias is not evidence.
- Backpressure must propagate through buffers and resume after stock consumption.
- No new live balance, UI, art, paid dependencies or merges to main.

## Task 1: Workforce coverage (PXJ-22)

Files: tests/test_workforce.gd, tests/fixtures/production_cases.gd, tests/run_all.gd.

- [x] Add deterministic manual fixtures and tests for no staff, assigned staff, 1x/2x efficiency, and transfer during a running step without duplicate consumption/output.
- [x] Add a single-worker/two-COOP-oven test with explicit evidence that both ovens are serviced and baking releases the employee.
- [x] Use arbitrary IDs in fixtures to exercise data-driven dispatch.
- [x] Run import and the entire suite. For existing behavior, verify representative tests reject temporary behavioral mutations, then restore production unchanged.

## Task 2: Logistics coverage (PXJ-23)

Files: tests/test_logistics.gd, shared test fixture, tests/run_all.gd.

- [x] Add a real dough-to-bread-to-slices chain and two configurable slicers; verify outputs, parallel routing and conservation.
- [x] Fill a bounded shelf; verify upstream buffers stop accepting, no material disappears, then consume stock and verify recovery.
- [x] Verify empty inventory refuses reservations and does not create stock; record deterministic simulation frequency/entity scale.
- [x] Run the full suite and mutation checks. Fix production only if a regression fails on unchanged code.

## Delivery

- [ ] Review the diff, run project inspection and the entire Godot suite; record commands and actual outcomes.
- [ ] Push the tests and this plan to a dedicated branch based on upstream main, create a draft PR and check CI.
- [ ] Update the existing Linear tasks with evidence, distinguishing branch validation from merged delivery.

Execution: same-session implementation, as approved in chat. The existing contract and audit supply the design; no new gameplay design is introduced.

## Review and validation record

- Godot 4.7 baseline: 24 cases, zero failures. Expanded suite: 32 cases.
- Eight temporary behavioral mutations were rejected by the relevant new tests, then restored: automatic MANUAL work, ignored efficiency, claiming old-zone work during transfer, skipping the second COOP station, ignoring shelf capacity, slicing without consuming bread, failing to activate the second slicer, and premature completion on reassignment.
- Independent review found the original transfer test lacked intermediate timing evidence. It now checks the same request remains unfinished at 3 seconds, completes at 4 seconds, then requires the 2-second walk. The premature-completion mutation proves these assertions fail for the intended bug.
- Review also identified an overbroad reservation comment. Its wording now describes empty stock and overlapping orders; same-order retry idempotency is not a newly claimed coverage item.
- Logistics fixture scale: 10 Hz, 5 stations, 6 belt segments, 600 ticks. Synthetic 60-second sliced outputs: 56 with one slicer, 112 with two. These are test-fixture results, not live balance or performance claims.
- Runtime production code, live content and presentation remain unchanged. A real slicing recipe is exercised in test definitions; playable stage-2 content is still a separate content task.
