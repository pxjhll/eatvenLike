extends "res://tests/test_case.gd"
const Fixture := preload("res://tests/fixtures/movement_shop.gd")
const Runner := preload("res://game/rules/template/capability_runner.gd")

func _runner(rules: ShopRules) -> RefCounted:
	var runner := Runner.new(rules)
	check(runner.has_method("transfer_bundle"), "whole-order transport must use real shared employee actions")
	if not runner.has_method("transfer_bundle"): return null
	rules.workers[0].post = ""
	rules.workers[0].pos = Vector2(180,180)
	for place in {"main":Vector2(180,180), "side":Vector2(400,180), "guest:1":Vector2(500,500)}:
		runner.define_place(place, {"main":Vector2(180,180), "side":Vector2(400,180), "guest:1":Vector2(500,500)}[place], 4)
	return runner

func _entries() -> Array:
	return [{"from":"main", "to":"guest:1", "item":"meal", "count":1, "owner":11},
		{"from":"side", "to":"guest:1", "item":"soup", "count":1, "owner":12}]

func _seed(runner: RefCounted) -> void:
	runner.inventory.seed("main", "meal", 1, 11)
	runner.inventory.seed("side", "soup", 1, 12)

func test_employee_collects_main_then_side_at_real_ports_before_one_whole_order_drop() -> void:
	for mode in ["handoff", "single", "serve"]:
		var rules := Fixture.opened(mode)
		var runner := _runner(rules)
		if runner == null: return
		_seed(runner)
		var worker: Dictionary = rules.workers[0]
		# These historical fixtures have different base capacities; explicitly
		# supply the two-item capability without modifying frozen shop resources.
		if rules.carry(worker) < 2:
			rules.apply_effect("event", "bundle_capacity", SpecEffect.make("carry", "add", 1.0))
		check_eq(runner.transfer_bundle(worker.id, _entries(), 0.4), "", "all modes request the same bundle action")
		check_eq(runner.frame().held, {}, "reservations have no hand icon")
		var first := false
		var second := false
		for tick in 600:
			check_eq(runner.step(0.1), "", "shared action step")
			if not first and worker.carry_count == 1:
				first = true
				check(worker.pos.is_equal_approx(Vector2(180,180)), "main pickup is at the main port")
				check_eq(runner.inventory.quantity("side", "soup", 12, true), 0, "side stays exclusively reserved")
			if not second and worker.carry_count == 2:
				second = true
				check(worker.pos.is_equal_approx(Vector2(400,180)), "second icon appears only at the side port")
			if runner.idle(worker.id): break
			check_eq(runner.inventory.quantity("guest:1"), 0, "no early partial delivery")
		check(first and second, "both real pickups occurred")
		check_eq(runner.inventory.quantity("guest:1"), 2, "main and side arrive together")
		check(worker.pos.is_equal_approx(Vector2(500,500)), "delivery is at the customer port")
		check_eq(runner.inventory.audit(), [], "one ledger after multi-stop action")

func test_recall_after_first_stop_returns_main_and_releases_side_once() -> void:
	var rules := Fixture.opened("handoff")
	var runner := _runner(rules)
	if runner == null: return
	_seed(runner)
	var worker: Dictionary = rules.workers[0]
	runner.transfer_bundle(worker.id, _entries(), 0.4)
	for tick in 100:
		runner.step(0.1)
		if worker.carry_count == 1: break
	check_eq(worker.carry_count, 1, "recall happens between collection stops")
	check_eq(runner.cancel(worker.id), "", "one shared cancellation")
	check_eq(runner.cancel(worker.id), "", "repeat is harmless")
	check_eq(runner.inventory.quantity("main", "meal", 11, true), 1, "main returned")
	check_eq(runner.inventory.quantity("side", "soup", 12, true), 1, "side released")
	check_eq(worker.carry_count, 0, "no hand icons after recall")
	check_eq(runner.inventory.audit(), [], "compensation conserves stock")

func test_restore_between_stops_resumes_remaining_collection_and_rejects_replayed_cursor() -> void:
	var rules := Fixture.opened("handoff")
	var runner := _runner(rules)
	if runner == null: return
	_seed(runner)
	var worker: Dictionary = rules.workers[0]
	runner.transfer_bundle(worker.id, _entries(), 0.4)
	for tick in 100:
		runner.step(0.1)
		if worker.carry_count == 1 and worker.pos.x > 180.0: break
	var saved: Dictionary = runner.snapshot()
	var reopened_rules := Fixture.opened("handoff")
	var reopened := _runner(reopened_rules)
	check_eq(reopened.restore(saved), "", "restore multi-stop action with partial hand")
	var broken: Dictionary = saved.duplicate(true)
	broken.actors[0].action.index = 0
	check(not reopened.restore(broken).is_empty(), "cannot replay first pickup")
	check_eq(reopened.snapshot(), saved, "failed restore changes no actors or stock")
	for tick in 600:
		reopened.step(0.1)
		if reopened.idle(worker.id): break
	check_eq(reopened.inventory.quantity("guest:1"), 2, "remaining stop completes once")
	check_eq(reopened.inventory.quantity("main"), 0, "main not copied")
	check_eq(reopened.inventory.audit(), [], "restored claims agree")

func test_insufficient_employee_capacity_or_different_drop_ports_creates_no_action_or_reservations() -> void:
	var rules := Fixture.opened("handoff")
	var runner := _runner(rules)
	if runner == null: return
	_seed(runner)
	var worker: Dictionary = rules.workers[0]
	var entries := _entries()
	entries[0].count = 2
	var before: Dictionary = runner.snapshot()
	check(not runner.transfer_bundle(worker.id, entries, 0.4).is_empty(), "capacity comes from actual employee")
	check_eq(runner.snapshot(), before, "invalid request changes nothing")
	entries = _entries()
	entries[1].to = "main"
	check(not runner.transfer_bundle(worker.id, entries, 0.4).is_empty(), "one physical drop cannot happen at two ports")
	check_eq(runner.snapshot(), before, "bad route changes nothing")
