# Drag Staff to Seated or Mobile Posts Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development; complete and review simulation assignment and real GUI drag integration.

**Goal:** Drag an animal onto a manual workstation to seat it; drag onto walkable blank ground to release it into mobile work.

**Architecture:** TeaPlaytestSim owns worker post assignment, task eligibility and deferred reassignment. ArtPlaytestLayout supplies manual post hit areas, separate operator/courier points and legal floor drops. The view previews a drag without teleporting simulation state; only valid release calls the simulation.

**Tech Stack:** Godot 4.6.3, current reference art, current playable prototype.

**Spec:** docs/design/staff-task-logistics.md section 坐班与流动, plus user's confirmed direct-drag interaction.

## Constraints

- Existing art, furniture positions, old GameSim and saved progress remain unchanged.
- Current job completes before a role change moves the worker. Carried stock and reservations are never discarded.
- Only boil and topping accept seated operators, one person per post; automatic machines reject the drop.
- A seated worker executes only its post's operation tasks, waiting at its operation point between jobs. Mobile workers continue delivery and operate unseated posts.
- Assignment locks precede ability/fatigue scoring. Fatigue never unseats a worker.
- Invalid drops and occupied posts leave the previous assignment intact; ESC cancels a drag.

## Shared interface

Layout adds POST_POINTS/POST_RECTS and drop_target(point)->Dictionary. Targets are {kind:post,post:boil|topping,point:Vector2}, {kind:mobile,post:"",point:Vector2}, or {kind:invalid,reason:String}.

Sim adds assign_post(worker_id:int, post:String, destination:Vector2=Vector2.INF)->String: empty string means accepted; English errors invalid_worker, invalid_post, occupied_post, blocked_ground, unreachable. post_owner(post:String,exclude_id:int=-1)->int returns -1 if none. Every worker has post:String="", assignment_pending:bool=false; accepted busy changes reserve the target post immediately, preserve the in-flight atomic job, then move physically. Idle changes also move physically; no teleport.

Worker phases may add reposition; task labels take_post/move_free/brew_start/brew_take. POST_POINTS are operator locations; POINTS remain courier interaction points. Existing APIs and fields remain compatible.

## Task 1 — Simulation (delegate)

- [x] Add failing tests: idle post assignment and release, exclusion by locked post, occupied/automatic invalid assignment, multiworker output with one seated operator, handoff while carrying/work, soft fatigue never unlocks, full conservation.
- [x] Separate boil manual start/unload operation from mobile raw/tea transport, so seated boil actually has stationary work. Topping already has manual operation.
- [x] Implement role filtering and deferred movement; extend audit for unique ownership. Preserve current transport behavior.
- [x] Re-run old and new simulation tests, adjust old tests only where new boil manual phases require checking the intended topping task explicitly.

## Task 2 — Art interaction (parent)

- [x] Drag from animal body or its employee card. Require a movement threshold so normal click still selects; empty employee card click still hires.
- [x] Draw a ghost, highlight manual post and operator target; legal floor gets a green marker, invalid drops get red feedback.
- [x] Release calls assign_post; current actor reappears at its true simulated position and completes any outstanding job. ESC/invalid/outside drop cancels cleanly.
- [x] Show seated/mobile and pending handoff in employee card, station ownership in badge, and lack-of-mobile warning. Keep fatigue and previous buttons functional.
- [x] Support mouse and touch, and preserve coordinate mapping in small/landscape viewport.

## Task 3 — Verify and document

- [x] Real GUI input tests drag body/card onto both posts and legal floor, reject occupied/automatic/blocked drops, cancel drag, and observe task/stock continuity.
- [x] Verify one mobile worker still completes the whole workflow, and seated+mobile teams continue selling.
- [x] Full regression and real renderer tests; capture actual seated/mobile state and update planning/QA status.
- [x] Independent review and fixes. Do not commit or push unless requested.
