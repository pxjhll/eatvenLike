# Stable business command results

User approved the next architecture PR: remove UI dependence on Chinese error wording. Preserve current business behavior, prompt text, numeric calculations, read-only queries, save formats and session policies. Persistence APIs already return Godot Error values and are outside this business-command migration.

## Canonical contract

`ShopRules.command_status(command: String, arguments: Dictionary = {}) -> Dictionary` is read only. `execute_command(command: String, arguments: Dictionary = {}) -> Dictionary` validates and checks the same command, then performs its existing mutations exactly once on success. Results are fresh data dictionaries `{code: String, params: Dictionary}`. `code == "ok"` is the only success condition; no message/boolean is needed to infer success. Params are detached data, never live worker/station/resource references. Include `params.command` for command-specific presentation. Checks, invalid requests and failed execution leave business state, RNG, events and object identities unchanged.

Canonical command names and arguments:

| Command | Required arguments | Optional arguments |
| --- | --- | --- |
| unlock | id: String | none |
| unlock_box | material: String | none |
| upgrade | key: String | none |
| buy_seat / send_flyers / hire | none | none |
| deploy_worker | id: int | post: String = "" |
| place_worker | id: int, post: String | point: Vector2 = Vector2.INF |
| recall_worker | id: int | none |
| buy_connection | id: String | none |
| answer_event | choice: int | none |

Reject unknown commands, missing/unknown arguments, wrong types and invalid non-sentinel coordinates without runtime errors. Negative integer IDs/choices remain domain checks, preserving existing failure precedence. Empty post and `staff/` are legitimate unzoned inputs. Default Vector2.INF is the existing placement sentinel; otherwise coordinates must be finite.

Stable codes: `ok`, `unknown_command`, `invalid_argument`, `unknown_station`, `station_already_unlocked`, `station_not_unlockable`, `shop_not_open`, `stage_required`, `insufficient_gold`, `unknown_box`, `box_already_unlocked`, `station_required`, `box_required`, `station_level_required`, `no_upgrade`, `max_level`, `seats_full`, `seat_stage_required`, `flyer_active`, `flyer_cooldown`, `hire_exhausted`, `staff_full`, `front_full`, `kitchen_full`, `unknown_worker`, `not_seatable`, `post_occupied`, `reassignment_disabled`, `invalid_post`, `position_unreachable`, `worker_already_waiting`, `event_missing`, `invalid_event_choice`. Presentation-only invalid drag geometry uses `ui_drop_rejected` with `params.reason` (the existing anchor/UI reason token), never a human sentence as a success flag.

Parameter names: gold errors use `required`; stage dependencies use `stage` (current stage index); station dependencies use `station`; box dependencies use `material`; machine level requirements use `station` and `required_level`; capacity errors use `count`; flyer active/cooldown use `seconds`; worker errors use `id`; invalid requests use `argument` and `command`. Add target IDs as useful. Checker ordering and command no-op behavior remain exactly current: e.g. deploying an already-deployed worker succeeds without emitting another event. Auto deployment chooses the same post as before; successful check metadata can carry resolved `post` for execution.

Connection-specific codes are `unknown_connection` (missing or disabled) and `connection_already_built`, both carrying `id`. They preserve the existing distinct failures without treating a connection as a station or an argument-type error.

## Presentation and compatibility

Business checks/commits return codes directly and never classify human text. Central message templates/formatting live in `content/ui/rule_command_text.gd`, a neutral content dependency usable by both UI read models and compatibility tools. It formats code+params with optional SpecShop name resolution and per-code template overrides. It must preserve current Chinese messages, including command-specific occupied-post wording. No domain import of presentation scripts.

Old String command APIs and `*_error`, `role_room`, `placement_error` remain thin compatibility adapters to canonical execution/checking plus the shared formatter. Canonical methods never call those adapters. This avoids a simultaneous rewrite of historical replay tooling and tests; production UI uses only canonical results. No new callers should adopt the String adapters.

ShopView adds `status` alongside display-only `error` on relevant cards/rows (and `upgrade_status` beside `upgrade_error` for flyer). `connection_rows()` likewise adds `status`. `ShopView.command_message(status)` formats display text and supports an optional injected `message_formatter: Callable`, with `(status, shop)` arguments; default formatting uses the content catalog. A formatter that returns translated, unrelated or even empty failure text must never change affordability, material states, drag validity, buttons, event consumption or saving decisions.

Migrate ShopView, scene commands/frames, station/staff buttons, guides and staff dragging to codes. Retain current drag-only hints, geometry constraints, placement ordering and front-capacity wording, now represented separately from validity. Keep special UI text such as full-cultivation labels where appropriate. UI can display error strings, but cannot use their prefix/emptiness/equality to decide success or operation availability. Existing numeric room/product guards that are independent of error text may remain when needed to preserve behavior.

## Verification and delivery

Test every command's success and representative rejection, parameter values and priority; check/execute rejection is atomic; valid canonical results match existing independent business outcomes and adapters. Legacy text stays compatible. Unknown/malformed requests are safe and detached results cannot mutate live state. Avoid wrapper/helper-only comparison tests.

For UI, demonstrate failures with stable codes and localized/empty messages: locked-box state, insufficient-gold button caption/disable, guides, drag hints/validity and success/failure persistence. A trap subclass whose String adapters count/return poison messages should detect any remaining production dependence. Use real isolated scenes where interaction is relevant. Extend font coverage to the new message catalog; do not replace the licensed font.

Work in D:/Tes/eatventure, no worktrees. All engines explicitly set disposable APPDATA containing session-lifecycle-userdata; no local --import. Preserve current main, including human migration/performance edits. Independent task/whole reviews, full regression/golden/GUI checks and Godot4.7 CI are required. Stack on #69 only while it is open; otherwise rebase own commits onto latest main. No PR merges. Archive this plan's records without retrying previously policy-blocked recursive cleanup.
