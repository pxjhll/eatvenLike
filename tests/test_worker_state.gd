extends "res://tests/test_case.gd"
## Frozen v0 business regression; formal v1 coverage: test_first_shops_migration.

const MODULE := "res://game/rules/worker_state.gd"
const TEA: SpecShop = preload("res://tests/fixtures/legacy_shops/tea.tres")
const PANCAKE: SpecShop = preload("res://tests/fixtures/legacy_shops/pancake.tres")

func _module() -> Variant:
	if not ResourceLoader.exists(MODULE):
		check(false, "WorkerState module must exist")
		return null
	return load(MODULE)

func _history() -> Dictionary:
	# Every unrelated value is a sentinel; normalization or excessive cleanup loses it.
	return {"id": 7, "post": "boil", "pos": Vector2(3, 4), "deployed": true, "source": "test",
		"stats": {"work": 2.0}, "completed": 9, "fatigue": 0.4, "job": {"kind": "work"},
		"ticket": {"at": 2}, "carry_item": "cup", "carry_count": 3, "phase": "dropoff",
		"task_label": "交付", "walking": true, "path": PackedVector2Array([Vector2(3, 4), Vector2(5, 6)]),
		"path_index": 1, "action_left": 0.3, "target": "griddle", "timer": -0.03,
		"duration": 2.5, "order": 42, "steps": [{"point": "counter"}], "step": 8, "chore": "load:pot", "extra": {"keep": 1}}

func _expect_changes(before: Dictionary, changes: Dictionary) -> Dictionary:
	var expected := before.duplicate(true)
	for key in changes: expected[key] = changes[key]
	return expected

func test_factory_exact_saved_row_and_independent_containers() -> void:
	var state = _module()
	if state == null: return
	var stats := {"walk": 80.0, "work": 1.5, "carry": 2}
	var worker: Dictionary = state.create(7, "cat", "猫", stats, Vector2(2, 3))
	var expected := {"id": 7, "kind": "cat", "name": "猫", "stats": stats,
		"pos": Vector2(2, 3), "walking": false, "phase": "idle", "task_label": "idle",
		"carry_item": "", "carry_count": 0, "fatigue": 0.0, "completed": 0, "job": {}, "ticket": {},
		"post": "", "path": PackedVector2Array(), "path_index": 0, "action_left": 0.0, "deployed": false, "source": "",
		"target": "", "timer": 0.0, "order": -1, "steps": [], "step": 0, "chore": ""}
	check_eq(worker, expected, "exact factory row; optional duration absent")
	check_eq(worker.keys(), expected.keys(), "saved key order")
	var second: Dictionary = state.create(8, "cat", "猫", stats, Vector2.ZERO)
	worker.stats.walk = 99
	worker.job.x = 1
	worker.ticket.x = 2
	worker.steps.append("step")
	worker.path.append(Vector2.ONE)
	check_eq(stats.walk, 80.0, "stats copy belongs to worker")
	check_eq(second.stats.walk, 80.0, "worker stats independent")
	check_eq([second.job, second.ticket, second.steps, second.path], [{}, {}, [], PackedVector2Array()], "fresh mutable containers")
	check(not is_same(worker.job, worker.ticket), "job and ticket independent")

func test_place_assign_path_and_walk_preserve_history() -> void:
	var state = _module()
	if state == null: return
	var worker := _history()
	var before := worker.duplicate(true)
	state.place(worker, "counter", Vector2(9, 10))
	check_eq(worker, _expect_changes(before, {"post": "counter", "pos": Vector2(9, 10)}), "place only post/position")
	for path in [PackedVector2Array(), PackedVector2Array([Vector2.ONE]), PackedVector2Array([Vector2.ZERO, Vector2.ONE])]:
		before = worker.duplicate(true)
		state.assign_path(worker, path)
		check_eq(worker, _expect_changes(before, {"path": path, "path_index": 1 if path.size() > 1 else 0}), "assign_path retains phase/walking/position")
	before = worker.duplicate(true)
	var route := PackedVector2Array([Vector2(9, 10), Vector2(20, 10)])
	state.begin_walk(worker, route, "walk_pickup")
	check_eq(worker, _expect_changes(before, {"path": route, "path_index": 1, "phase": "walk_pickup", "walking": true}), "walk entry changes only route/index/phase/walking")
	state.arrive(worker)
	check_eq(worker, _expect_changes(before, {"path": route, "path_index": 1, "phase": "walk_pickup", "walking": false}), "arrival only stops walking")

func test_walk_multisegment_leftover_and_no_implicit_action() -> void:
	var state = _module()
	if state == null: return
	var worker := _history()
	worker.pos = Vector2.ZERO
	state.begin_walk(worker, PackedVector2Array([Vector2.ZERO, Vector2(10, 0), Vector2(10, 5)]), "walk")
	check(not state.advance_walk(worker, 12.0), "two units down final segment remains walking")
	check_eq([worker.pos, worker.path_index, worker.walking], [Vector2(10, 2), 2, true], "hand-derived multisegment result")
	check(state.advance_walk(worker, 3.0), "exact end arrives")
	check_eq([worker.pos, worker.path_index, worker.walking, worker.phase, worker.timer, worker.action_left], [Vector2(10, 5), 3, false, "walk", -0.03, 0.3], "arrival does not start action or tick timer")
	worker.pos = Vector2.ZERO
	state.begin_walk(worker, PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2(2, 0), Vector2(2, 0)]), "walk_dropoff")
	check(state.advance_walk(worker, 10.0), "duplicates and excess budget terminate")
	check_eq([worker.pos, worker.path_index], [Vector2(2, 0), 4], "residual distance discarded")

func test_walk_zero_distance_empty_index_end_and_epsilon() -> void:
	var state = _module()
	if state == null: return
	var worker := _history()
	state.begin_walk(worker, PackedVector2Array(), "walk")
	check(not state.advance_walk(worker, 0.0) and worker.walking, "empty route stays blocked even at zero budget")
	worker.pos = Vector2.ZERO
	state.begin_walk(worker, PackedVector2Array([Vector2.ZERO]), "walk")
	check(not state.advance_walk(worker, 0.0), "zero budget leaves unconsumed coincident waypoint")
	check_eq([worker.path_index, worker.walking], [0, true], "coincident waypoint not consumed")
	worker.path_index = 1
	check(state.advance_walk(worker, 0.0), "index at end already arrived")
	state.begin_walk(worker, PackedVector2Array([Vector2.ZERO, Vector2(1, 0)]), "walk")
	check(state.advance_walk(worker, 0.999995), "epsilon snaps gap just above budget")
	check_eq([worker.pos, worker.path_index], [Vector2(1, 0), 2], "epsilon exact target")
	worker.pos = Vector2.ZERO
	state.begin_walk(worker, PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2(1, 0)]), "walk")
	check(not state.advance_walk(worker, 0.999995), "epsilon overshoot exhausts budget before duplicate end")
	check_eq([worker.pos, worker.path_index, worker.walking], [Vector2(1, 0), 2, true], "negative residual retains final duplicate waypoint")
	worker.pos = Vector2.ZERO
	state.begin_walk(worker, PackedVector2Array([Vector2.ZERO, Vector2(1, 0)]), "walk")
	check(not state.advance_walk(worker, 0.99998), "outside epsilon keeps walking")
	check(worker.pos.is_equal_approx(Vector2(0.99998, 0)), "fractional move_toward")

func test_handoff_entries_timer_clamp_and_epsilon() -> void:
	var state = _module()
	if state == null: return
	var worker := _history()
	var before := worker.duplicate(true)
	state.enter_handoff_action(worker, "pickup", 0.1000005)
	check_eq(worker, _expect_changes(before, {"walking": false, "phase": "pickup", "action_left": 0.1000005}), "handoff entry preserves history")
	check(state.tick_handoff_action(worker, 0.1), "handoff finishes positive residue below epsilon")
	check(worker.action_left > 0.0, "positive residue preserved")
	worker.action_left = 0.100002
	check(not state.tick_handoff_action(worker, 0.1), "above epsilon incomplete")
	check(state.tick_handoff_action(worker, 0.2), "handoff overshoot finishes")
	check_eq(worker.action_left, 0.0, "handoff overshoot clamps")

func test_handoff_finish_and_cancel_replace_aliases_with_distinct_cleanup() -> void:
	var state = _module()
	if state == null: return
	for cancel in [false, true]:
		var worker := _history()
		var before := worker.duplicate(true)
		var job: Dictionary = worker.job
		var ticket: Dictionary = worker.ticket
		var steps: Array = worker.steps
		var unrelated := {"orders": [{"id": 42}], "stock": 9}
		var external_before := unrelated.duplicate(true)
		var changes := {"job": {}, "carry_count": 0, "carry_item": "", "phase": "idle", "task_label": "idle", "walking": false}
		if cancel:
			state.cancel_assignment(worker)
			changes.merge({"ticket": {}, "path": PackedVector2Array(), "path_index": 0, "action_left": 0.0})
		else:
			state.finish_handoff(worker)
			changes.completed = 10
		check_eq(worker, _expect_changes(before, changes), "exact asymmetric cleanup cancel=" + str(cancel))
		check_eq(job, {"kind": "work"}, "old job alias not cleared")
		check(not is_same(job, worker.job), "job replaced")
		check_eq(ticket, {"at": 2}, "old ticket alias not cleared")
		check(is_same(ticket, worker.ticket) == not cancel, "ticket retained only for finish")
		check(is_same(steps, worker.steps), "single history container retained")
		check_eq(unrelated, external_before, "external business collections unchanged")

func test_single_work_raw_negative_timer_and_zero_boundary() -> void:
	var state = _module()
	if state == null: return
	var worker := _history()
	var before := worker.duplicate(true)
	state.begin_single_work(worker, 0.1000005)
	check_eq(worker, _expect_changes(before, {"phase": "work", "timer": 0.1000005, "duration": 0.1000005}), "single entry retains label/order/carry/walking")
	check(not state.tick_single_work(worker, 0.1), "single positive residue below handoff epsilon still incomplete")
	check(state.tick_single_work(worker, 0.1), "single overshoot completes")
	check(worker.timer < -0.099, "single raw negative timer retained")
	before = worker.duplicate(true)
	state.finish_single_work(worker)
	check_eq(worker, _expect_changes(before, {"phase": "idle"}), "finish work only phase; sale observes history")
	worker.timer = 0.1
	check(state.tick_single_work(worker, 0.1), "exact zero completes")

func test_single_wait_standby_claim_and_order_finish_keep_last_history() -> void:
	var state = _module()
	if state == null: return
	var worker := _history()
	var before := worker.duplicate(true)
	state.wait_single(worker, "等锅")
	check_eq(worker, _expect_changes(before, {"phase": "wait", "task_label": "等锅"}), "wait only phase/label")
	for walking in [false, true]:
		worker.walking = walking
		before = worker.duplicate(true)
		state.standby_single(worker)
		check_eq(worker, _expect_changes(before, {"phase": "walk" if walking else "idle", "task_label": "待命"}), "standby follows walking")
	before = worker.duplicate(true)
	var steps := [{"point": "counter"}, {"point": "hand"}]
	var old_steps: Array = worker.steps
	state.claim_single_order(worker, 23, steps)
	check_eq(worker, _expect_changes(before, {"order": 23, "steps": steps, "step": 0, "walking": false}), "claim does not normalize timer/phase/label")
	check(is_same(worker.steps, steps), "explicit steps transferred by reference")
	worker.step = 1
	before = worker.duplicate(true)
	state.finish_single_order(worker)
	check_eq(worker, _expect_changes(before, {"order": -1, "steps": [], "carry_item": "", "carry_count": 0}), "order completion retains last index/target/label/timers")
	check_eq(steps, [{"point": "counter"}, {"point": "hand"}], "old owned steps alias not cleared")
	check_eq(old_steps, [{"point": "counter"}], "previous assignment not cleared")

func _open(rules: ShopRules) -> void:
	rules.gold = 1000000.0
	for i in 30:
		var next := rules.next_unlock()
		if next.is_empty(): break
		check_eq(rules.execute_command("unlock", {"id": next}).code, "ok", "legal unlock")
		for material in rules.boxes:
			if not rules.boxes[material] and rules.command_status("unlock_box", {"material": material}).code == "ok":
				check_eq(rules.execute_command("unlock_box", {"material": material}).code, "ok", "legal box")
	for i in 2:
		if rules.command_status("hire").code == "ok": check_eq(rules.execute_command("hire").code, "ok", "legal hire")
	for worker in rules.roster:
		if not worker.deployed: check_eq(rules.execute_command("deploy_worker", {"id": worker.id, "post": ""}).code, "ok", "legal deploy")

func test_rules_legacy_pathless_walk_preserves_phase_and_arrival_tick() -> void:
	var rules := ShopRules.new(PANCAKE, 42)
	_open(rules)
	for i in 400:
		rules.step(0.1)
		var worker: Dictionary = rules.workers[0]
		if not worker.walking or worker.order < 0: continue
		var saved := rules.to_dict()
		for row in saved.roster:
			if row.id == worker.id:
				row.path = PackedVector2Array()
				row.path_index = 0
				row.phase = "wait"
		var restored := ShopRules.new(PANCAKE, 42)
		check_eq(restored.load_dict(saved), "", "legacy pathless active walk accepted")
		var live: Dictionary = restored.workers[0]
		check_eq(live.phase, "wait", "load does not normalize legacy phase")
		var timer: float = live.timer
		restored._walk_single(live)
		check(not live.path.is_empty(), "legacy route recomputed")
		if live.walking: check_eq(live.phase, "wait", "route reconstruction does not enter walk")
		check_eq(live.timer, timer, "walking tick never decrements timer")
		for guard in 1000:
			if not live.walking: break
			restored._walk_single(live)
		check(not live.walking, "legacy route reaches destination within bound")
		check_eq(live.phase, "work", "arrival enters work")
		check_eq(live.timer, live.duration, "arrival tick leaves full work timer")
		check_eq(restored.inventory_diagnostics(), [], "stable legacy arrival inventory")
		return
	check(false, "actual active walking fixture found")

func test_rules_active_phases_save_load_continue_and_sale_callback_order() -> void:
	for shop in [TEA, PANCAKE]:
		var rules := ShopRules.new(shop, 42)
		_open(rules)
		var phases := {}
		var sales: Array = []
		var listener := func(_event: Dictionary) -> void:
			var matched := false
			for worker in rules.workers:
				if shop.fulfillment.handoff == "handoff" and worker.phase == "dropoff" and worker.job.get("kind", "") == "serve":
					matched = true
					check(worker.carry_count > 0 and not worker.job.is_empty(), "handoff sale before cleanup")
				elif shop.fulfillment.handoff == "single" and worker.order >= 0 and not worker.steps.is_empty() and worker.steps[worker.step].action == "hand" and worker.phase == "idle":
					matched = true
					check_eq(worker.task_label, worker.steps[worker.step].label, "single sale retains completion label")
					check(worker.timer <= 0.0 and worker.duration > 0.0, "single sale raw timer and history")
			check(matched, "synchronous sale sees completing worker")
			sales.append(rules.sold)
		rules.events.on("sale", listener)
		for tick in 2200:
			rules.step(0.1)
			check_eq(rules.inventory_diagnostics(), [], "stable real play " + shop.id)
			for worker in rules.workers:
				if worker.phase not in ["walk", "walk_pickup", "walk_dropoff", "pickup", "dropoff", "work"] or phases.has(worker.phase): continue
				phases[worker.phase] = true
				var saved := rules.to_dict()
				var clone := ShopRules.new(shop, 42)
				check_eq(clone.load_dict(saved), "", "active phase accepted " + worker.phase)
				check_eq(clone.to_dict(), saved, "active phase exact " + worker.phase)
				# Compare a restored simulation to the original live instance, so a
				# restore that silently normalizes phase/history cannot pass twice.
				for i in 7:
					clone.step(0.1)
					rules.step(0.1)
				check_eq(clone.to_dict(), rules.to_dict(), "active phase continuation " + worker.phase)
		check(not sales.is_empty(), "actual sale callback " + shop.id)
		check(phases.has("work"), "actual work save " + shop.id)
		if shop.fulfillment.handoff == "handoff":
			for phase in ["walk_pickup", "pickup", "walk_dropoff", "dropoff"]: check(phases.has(phase), "handoff save " + phase)
		rules.events.off("sale", listener)
		rules.reset(42)
		check_eq(rules.workers[0].phase, "idle", "reset factory phase")
		check(not rules.workers[0].has("duration"), "reset removes prior optional duration")
		_open(rules)
		for i in 600: rules.step(0.1)
		check(rules.sold > 0, "reopened business " + shop.id)

func test_rules_nearby_single_arrival_and_handoff_arrival_keep_full_duration() -> void:
	var single := ShopRules.new(PANCAKE, 42)
	_open(single)
	for i in 400:
		single.step(0.1)
		var worker: Dictionary = single.workers[0]
		if worker.order < 0 or not worker.chore.is_empty(): continue
		var step: Dictionary = worker.steps[worker.step]
		var goal := single.nav.point(step.point)
		worker.pos = goal + Vector2(0.25, 0)
		var pos: Vector2 = worker.pos
		single._go(worker, step.point, step.label)
		check_eq(worker.pos, pos, "nearby branch does not snap position")
		check(not worker.walking and worker.phase == "work", "nearby branch arrives immediately")
		check_eq(worker.timer, worker.duration, "immediate arrival no timer decrement")
		break
	check(single.workers[0].order >= 0, "nearby fixture found active order")
	var handoff := ShopRules.new(TEA, 42)
	_open(handoff)
	for i in 400:
		handoff.step(0.1)
		for worker in handoff.workers:
			if not worker.walking or worker.phase != "walk_pickup" or worker.id != 1 or worker.job.get("item", "") != "lemonade": continue
			worker.pos = worker.path[-1]
			worker.path_index = worker.path.size()
			handoff._update_worker(worker)
			check_eq(worker.phase, "pickup", "handoff arrives and enters action")
			# Tea's initial Cat has work=1 and lemonade's pour step is 2 seconds.
			check_eq(worker.action_left, 2.0, "handoff pour arrival no timer decrement")
			check_eq(handoff.inventory_diagnostics(), [], "stable handoff arrival inventory")
			return
	check(false, "handoff active walk fixture found")

func test_rules_placement_callbacks_keep_deploy_before_cancel_order() -> void:
	var rules := ShopRules.new(TEA, 42)
	_open(rules)
	var worker: Dictionary = rules.workers[1]
	var id: int = worker.id
	var seen: Array = []
	var listener := func(event: Dictionary) -> void:
		if event.name in ["recalled", "deployed", "placed"]: seen.append({"name": event.name, "row": worker.duplicate(true), "working": rules.workers.has(worker)})
	rules.events.on("*", listener)
	for i in 100: rules.step(0.1)
	check_eq(rules.execute_command("recall_worker", {"id": id}).code, "ok", "active recall")
	check_eq(seen[0].name, "recalled", "recall callback")
	check(not seen[0].working and not seen[0].row.deployed and seen[0].row.job.is_empty(), "recall after cleanup and removal")
	check_eq(rules.execute_command("place_worker", {"id": id, "post": "boil"}).code, "ok", "place undeployed")
	check_eq(seen.map(func(row: Dictionary) -> String: return row.name), ["recalled", "deployed", "placed"], "deployment before placement")
	check_eq(seen[1].row.post, "", "deployed callback sees prior post")
	check_eq([seen[2].row.post, seen[2].row.pos], ["boil", rules.nav.post("boil")], "placed callback sees new position")
	check_eq(rules.inventory_diagnostics(), [], "stable lifecycle inventory")
	rules.events.off("*", listener)
