# Stable command errors implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans task by task.

**Goal:** Separate business outcomes from UI wording with stable command codes and detached parameters.
**Architecture:** Canonical check/execute APIs own decisions; shared neutral message content serves UI and legacy adapters; production UI consumes status codes.
**Tech Stack:** Godot GDScript, isolated headless regression and real-scene input fixtures.
**Spec:** `docs/superpowers/specs/2026-11-09-command-errors.md`

## Global Constraints

Use D:/Tes/eatventure on codex/command-errors; no worktrees/main changes/merges. Every engine process explicitly APPDATA under D:/Tes/eatventure-analysis/command-errors-userdata/session-lifecycle-userdata/<runner>, engine D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe, --headless, no --import. New helpers use preload paths without class_name, avoid cycles. Keep existing human text and font glyphs; include new catalog in font scan. Preserve command order/debits/events/IDs, query purity, serialization and current main's save policies. Workers do not spawn agents, stage or commit; parent owns review/commits/publication. No visible-window probes for this nonvisual refactor; supported CI/headless inputs are the validation contract.

### Task 1: Canonical business results and legacy adapters

**Files:** Create `game/rules/rule_command_result.gd`, `content/ui/rule_command_text.gd`, `tests/test_command_results.gd`; modify `game/rules/shop_rules.gd`, `tests/run_all.gd`, `tests/test_font.gd`; add `docs/command-results.md` core API section.

**Interfaces:** Result helper exposes named constants for all spec codes and `is_ok(status: Dictionary) -> bool`, fresh success/failure factories and argument validation helpers as needed. `ShopRules.command_status(command, arguments={}) -> Dictionary`, `execute_command(command, arguments={}) -> Dictionary`; message catalog `format(status: Dictionary, shop: SpecShop = null, overrides: Dictionary = {}) -> String`. Follow exact command names/argument and parameter names/code list in spec. `connection_rows` gains status while retaining legacy error text. Existing public String signatures remain unchanged and delegate toward canonical APIs, never the reverse.

- [ ] Write failing tests first with guarded missing-API checks to avoid parse-only RED. Exercise concrete insufficient-gold/locked-stage statuses, malformed requests without mutation, canonical execution paying/emitting once and caller-result isolation. Capture actual RED with error_counter under this plan workspace.
- [ ] Add code/parameter/priority coverage for all11 commands, both staff modes, negative/unknown IDs, missing/wrong/extra arguments, placement sentinel/finiteness, full/cooldown/event failures, deploy no-op and auto post choice. Use actual Rules state and commands; existing tests remain independent legacy behavior checks. Verify status/check failures preserve bytes and important aliases/log/RNG identities.
- [ ] Refactor business checks to produce codes+params, centralize check/execute validation and perform each old commit once after success. Role room/placement helpers also become code-based. Keep original condition order and messages, including deploy-vs-place occupied-post text via stable command metadata. Do not use String error decoding or presentation imports to implement canonical outcomes.
- [ ] Move command text templates/resolution to neutral content catalog. Legacy wrappers format canonical results so existing replay tools still work. Add catalog literals to font scan. Document canonical command examples, schema and temporary legacy adapters.
- [ ] Run focused RED/GREEN, covering rule/view/save/query tests and full tests/run_all.gd once after source freeze. Parent won't repeat an unchanged full run. Report commands, outputs and any compatibility decisions to `.superpowers/sdd/2026-11-09-command-errors/task-1-report.md`; freeze all source without stage/commit.

### Task 2: Code-driven UI and localization-safe interaction

**Files:** Modify `game/rules/shop_view.gd`, `presentation/shop/shop_play.gd`, `presentation/shop/staff_drag.gd`, `presentation/shop/guide_player.gd`, `presentation/shop/hud/station_sections.gd`, `presentation/shop/hud/staff_page.gd`; create `tests/test_command_ui.gd` and `tests/render_command_contracts.gd`; modify `tests/run_all.gd`, `.github/workflows/tests.yml` only to add new real-scene runner (resolve actual workflow filename); extend `docs/command-results.md`. Other UI files only if concrete command-result callsite requires it.

**Interfaces:** Consume Task1 command/result/catalog APIs. ShopView constructor retains current positional Rules argument, adds optional `message_formatter: Callable = Callable()`; property injection supported for real-scene fixture. `command_message(status)` uses injected `(status, shop)` formatter or catalog. All relevant rows add status; flyer adds upgrade_status. Display-only error fields remain. UI-only geometry rejection uses ui_drop_rejected code with reason token, and its specialized labels remain presentation-owned.

Integration correction: Task2 may edit `ShopRules.connection_rows()` to compute one canonical status and format its retained legacy error field directly with CommandText. Production row generation must not invoke the String adapter `connection_error`; the live trap exposes that otherwise-hidden dependency.

- [ ] Capture meaningful UI RED: feed an insufficient_gold status with unrelated/empty error text into actual unlock section; old code selects wrong caption or enables failure. Check locked material state independently of translated error prefix. Add trap String adapters to detect production UI still calling legacy APIs; do not globally change templates or weaken existing assertions.
- [ ] Migrate read-model checks/state branches and every production command execution/affordability/success/save branch to status codes. Preserve cost/room product guards, current feedback and guide rules. Search all production consumers for business error-prefix and error-emptiness protocol use, including drag ghost/release/draw, event answers, frames and staff controls.
- [ ] Add UI unit tests and real scene runner with isolated TestSession. Test translated/empty formatter outputs do not change disabled states, box_closed state, material behavior, guides or drag validity; actual success changes gold/progress and saves once, failures do neither. Trap adapters must remain unused by canonical internals and production path. Keep single-frame scene freezing before readback comparisons.
- [ ] Add new runner to existing CI alongside progress/lifecycle tests with bounded timeout and disposable data if needed. Keep expected runtime errors fatal using error_counter. No font or asset replacements.
- [ ] Run focused new tests, full suite once after code freeze, new live runner and existing tea/extend/pancake/noodle GUI scripts with --headless. Parent owns remaining CLI/guide/audio/retry/lifecycle/work-actions checks. Document UI status fields/formatter overrides and scope of legacy adapters. Report evidence to `.superpowers/sdd/2026-11-09-command-errors/task-2-report.md`; no stage/commit.

## Parent integration and delivery

Baseline feature base fb36efd has215 tests and Godot4.7 CI42582272165 SUCCESS; no unchanged baseline repeat. Capture production manifest before first engine. Review Task1 before Task2; shared run_all/docs files edited sequentially. Run remaining integration on frozen source, preserve/inspect main updates and revalidate integration if rebased. Whole-branch strongest-model review, scoped fixes as needed, then push/create PR, follow Godot4.7 CI through completion, compare manifest and archive this plan's records under D:/Tes/eatventure-analysis/command-errors-pr/validation-records. Do not merge PR or retry old blocked recursive deletion.
