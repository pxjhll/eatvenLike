# UI Number Consistency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make displayed attributes, prices and operation times agree with the same rules used to execute gameplay, then open a reviewed PR.

**Architecture:** ShopRules owns effective attributes, manual operation duration and price quotes. ShopView formats and previews those queries, and HUD/tuning components consume its snapshots. Existing economic rules and recipe data remain unchanged.

**Tech Stack:** Godot GDScript; local console engine D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe; project CI Godot 4.7; GitHub CLI.

**Spec:** docs/superpowers/specs/2026-11-09-ui-number-consistency.md

## Global Constraints

- Work in D:/Tes/eatventure on codex/ui-number-consistency without creating worktrees.
- Preserve and include all eight pre-existing modified files from the prior four approved bug fixes.
- No shop-specific identifiers in generic rule code; no changes to gameplay data, prices or rounding rules to make a test pass.
- Keep tests isolated from real player saves, logs and tuning configuration.
- User authorized pushing this feature branch and creating a PR; never merge or push main.

## Task 1: Numeric interfaces, consumers and regression coverage

This is one integrated deliverable: the new queries and both consumers must change together so a reviewer can validate that UI and execution share the same source.

**Files:**
- Modify game/rules/shop_rules.gd, game/rules/shop_view.gd.
- Modify presentation/shop/hud/staff_page.gd, station_sections.gd if needed, and presentation/shop/shop_tuning.gd.
- Add tests/test_numeric_consistency.gd and register it in tests/run_all.gd.
- Extend tests/render_shop_tea.gd and/or tests/render_shop_pancake.gd for actual visible label values.
- Add developer-facing query contract documentation under docs/; update the existing user-facing guide only if it documents changed semantics.

**Interfaces:** Existing stat, walk_speed, skill, carry, raw_price, dish_price, order_price_single and preview remain the actual calculation primitives. Add coherent queries for effective employee stats, manual operation seconds, station timing snapshots and dish quotes. ShopView owns display text, rounding labels, unit descriptions and preview fields. Existing price_preview.now/next continue to describe calculated prices so existing rule baselines remain meaningful; add named settlement fields rather than silently repurposing them.

- [ ] Write test_numeric_consistency.gd using tests/test_case.gd and current tea/pancake resources. Check that cultivating a worker changes both worker_card.stats and the real stat queries; that manual machine knobs alter actual step timers; that ShopView/tuning timing matches the same operation calculation; and that new quotes match actual payouts.

  Minimum concrete assertions include:

  ```gdscript
  rules.upgrade("staff/")
  check_eq(view.worker_card(rules.workers[0]).stats.walk,
      rules.walk_speed(rules.workers[0]), "卡片显示当前有效移速")
  # Create a real recipe step and call the execution arrival handler.
  # Compare worker.timer with the shared duration query at tune=1 and tune=3.
  check_eq(view.price_preview("supply/tea_leaf").next, 31.5,
      "保留小数报价；实际原料行不能截断为31")
  ```

- [ ] Execute only the new test methods with an external focused runner, then the GUI script with new label assertions; record the expected failures before implementation. Existing regression scripts in D:/Tes/eatventure-worktree-backups/audit_ui_* and audit_timing_20261109_* provide reproducible cases, not permanent test dependencies.
- [ ] Implement the shared rule queries and route actual manual execution through them. Handle fixed actions and batch-pot pickup separately according to the spec. Store and use captured cook duration, including a fallback for older zero-duration saved state.
- [ ] Route ShopView, tuning descriptions and staff cards through the queries. Show cultivation progress rather than the unimplemented personal Lv1. Fix precision, price-part scope and integer-order quote labels. Use real operation/recipe metadata and unit labels instead of shop-name conditions.
- [ ] Run the focused tests and GUI label assertions to green. Self-review actual runtime and preview formulas; document any API names chosen differently from this plan.

## Task 2: Integration review and PR

**Files:** All changes relative to e4b8380; no extra feature work.

- [ ] Run tests/run_all.gd and the five render_shop_tea/pancake/guide/extend/audio.gd scripts using the local engine.
- [ ] Run tools/sync_shop_layouts.gd -- --check and tests/baselines/record_rules.gd -- --check; preserve data and base gameplay outcomes.
- [ ] Verify font glyph coverage and visually inspect the changed staff/pricing/tuning pages when layout changes warrant it.
- [ ] Review git diff --check, request independent specification and code-quality review, resolve actionable findings and run covering tests after any changes.
- [ ] Commit the scoped changes, fetch origin/main, push codex/ui-number-consistency and create a PR against main with a concrete problem/behavior description and truthful local verification details, including local engine version.
