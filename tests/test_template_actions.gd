extends "res://tests/test_case.gd"
const Fixture := preload("res://tests/fixtures/movement_shop.gd")
const PATH := "res://game/rules/template/capability_runner.gd"

func _runner(rules: ShopRules) -> RefCounted:
	check(ResourceLoader.exists(PATH), "public inventory capabilities must run through real actor actions")
	if not ResourceLoader.exists(PATH): return null
	var runner: RefCounted = load(PATH).new(rules)
	check_eq(runner.define_place("source", Vector2(180,180), 8), "", "source port")
	check_eq(runner.define_place("target", Vector2(500,180), 8), "", "target port")
	return runner

func test_real_movement_and_pickup_display_share_the_same_contract_across_templates() -> void:
	for mode in ["handoff", "single", "serve"]:
		var rules := Fixture.opened(mode)
		var runner := _runner(rules)
		if runner == null: return
		var worker: Dictionary = rules.workers[0]
		worker.post = ""
		worker.pos = Vector2(500,500)
		runner.inventory.seed("source", "ingredient", 5)
		var expected := mini(5, rules.carry(worker))
		check_eq(runner.transfer(worker.id, "source", "target", "ingredient", 5, 1.0), "", "same public transfer request for " + mode)
		check_eq(runner.frame().held, {}, "walking to source does not display a held item")
		var picked := false
		for tick in 600:
			runner.step(0.1)
			if not picked and runner.inventory.quantity("hand:"+str(worker.id), "ingredient") > 0:
				picked = true
				check(worker.pos.is_equal_approx(Vector2(180,180)), "pickup occurs at the actual source port")
				check_eq(worker.carry_count, expected, "actor receives the real employee capacity")
				var position: Vector2 = worker.pos
				var stock: Dictionary = runner.inventory.snapshot()
				runner.step(100.0, true)
				check_eq(worker.pos, position, "pause freezes actual movement")
				check_eq(runner.inventory.snapshot(), stock, "pause cannot complete a drop")
			if runner.idle(worker.id): break
		check(picked, "real employee physically picked up material in " + mode)
		check_eq(runner.inventory.quantity("target", "ingredient"), expected, "same public drop commits after arrival")
		check_eq(worker.carry_count, 0, "actor hand clears after drop")
		check_eq(runner.frame().draws, [], "waiting stock never spawns loose scene icons")
		check_eq(runner.inventory.audit(), [], "actor action conserves the authoritative ledger")

func test_recall_during_transport_returns_goods_and_clears_motion_once() -> void:
	var rules := Fixture.opened("handoff")
	var runner := _runner(rules)
	if runner == null: return
	var worker: Dictionary = rules.workers[0]
	worker.post = ""
	worker.pos = Vector2(180,180)
	runner.inventory.seed("source", "tea", 3)
	runner.transfer(worker.id, "source", "target", "tea", 2, 1.0)
	for tick in 100:
		runner.step(0.1)
		if worker.carry_count > 0: break
	check_eq(worker.carry_count, 2, "precondition: carried material exists")
	check_eq(runner.cancel(worker.id), "", "recall uses common cancellation")
	check_eq(runner.cancel(worker.id), "", "repeated recall harmless")
	check_eq(runner.inventory.quantity("source", "tea"), 3, "all material returned once")
	check_eq(worker.carry_count, 0, "hand cleared")
	check(not worker.walking and not worker.has("motion") and not worker.has("action"), "cancel releases path and program")
	check_eq(runner.inventory.audit(), [], "no leaked claims")

func test_shared_employee_upgrade_changes_real_transfer_batch_size() -> void:
	var rules := Fixture.opened("handoff")
	var runner := _runner(rules)
	if runner == null: return
	var worker: Dictionary = rules.workers[0]
	worker.post = ""
	worker.pos = Vector2(180,180)
	runner.inventory.seed("source", "tea", 5)
	rules.apply_effect("event", "carry_test", SpecEffect.make("carry", "add", 1.0))
	runner.transfer(worker.id, "source", "target", "tea", 5, 0.6)
	for tick in 300:
		runner.step(0.1)
		if runner.idle(worker.id): break
	check_eq(runner.inventory.quantity("target", "tea"), 3, "capacity upgrade is consumed by the actual action, not only the UI")

func test_no_route_blocks_the_action_without_remote_pickup_or_direct_line_fallback() -> void:
	var rules := Fixture.opened("handoff")
	var runner := _runner(rules)
	if runner == null: return
	var worker: Dictionary = rules.workers[0]
	worker.post = ""
	worker.pos = Vector2(180,180)
	runner.define_place("unreachable", Vector2(3000,3000), 3)
	runner.inventory.seed("unreachable", "tea", 2)
	runner.transfer(worker.id, "unreachable", "target", "tea", 2, 0.6)
	var before: Vector2 = worker.pos
	for tick in 20: runner.step(0.1)
	check_eq(worker.pos, before, "blocked actor stays in place")
	check_eq(worker.carry_count, 0, "blocked actor cannot pick up remotely")
	check_eq(worker.action.status, "blocked", "shared executor reports missing route")
	check_eq(runner.cancel(worker.id), "", "blocked claim can be cancelled")
	check_eq(runner.inventory.quantity("unreachable", "tea", -1, true), 2, "cancel releases unreachable source reservation")

func test_manual_machine_uses_the_same_actor_action_executor_and_machine_clock() -> void:
	var rules := Fixture.opened("handoff")
	var runner := _runner(rules)
	if runner == null: return
	var worker: Dictionary = rules.workers[0]
	worker.post = ""
	worker.pos = Vector2(180,180)
	runner.inventory.seed("source", "raw", 1)
	runner.machines.configure("device", "source", "target", {"manual":true})
	var operation: Dictionary = runner.machines.start("device", {"raw":1}, {"meal":1}, 2.0)
	check_eq(runner.operate(worker.id, operation.id, "source"), "", "employee requests a public machine stage")
	for tick in 100:
		runner.step(0.1)
		if runner.idle(worker.id): break
	check_eq(runner.inventory.quantity("target", "meal"), 1, "real manual action produces through shared transaction")
	check_eq(worker.phase, "idle", "operation releases actor")
	check_eq(runner.machines.audit(), [], "actor and machine agree")

func test_operation_cannot_be_assigned_to_an_unrelated_port() -> void:
	var rules := Fixture.opened("handoff")
	var runner := _runner(rules)
	if runner == null: return
	var worker: Dictionary = rules.workers[0]
	worker.post = ""
	runner.inventory.seed("source", "raw", 1)
	runner.machines.configure("device", "source", "target", {"manual":true})
	var operation: Dictionary = runner.machines.start("device", {"raw":1}, {"meal":1}, 2.0)
	check(not runner.operate(worker.id, operation.id, "target").is_empty(), "an arbitrary valid container is not the machine's operation port")
	check(runner.idle(worker.id), "invalid port cannot acquire the actor")
	check_eq(runner.operate(worker.id, operation.id, "source"), "", "the declared device input port remains usable")
	runner.cancel(worker.id)

func test_employee_work_upgrade_changes_the_real_machine_operation_clock() -> void:
	var rules := Fixture.opened("handoff")
	var runner := _runner(rules)
	if runner == null: return
	var worker: Dictionary = rules.workers[0]
	worker.post = ""
	worker.pos = Vector2(180,180)
	rules.apply_effect("event", "work_test", SpecEffect.make("work", "mul", 2.0))
	runner.inventory.seed("source", "raw", 1)
	runner.machines.configure("device", "source", "target", {"manual":true})
	var operation: Dictionary = runner.machines.start("device", {"raw":1}, {"meal":1}, 4.0)
	runner.operate(worker.id, operation.id, "source")
	var work_ticks := 0
	for tick in 100:
		if runner.machines.run(operation.id).phase == "operate": work_ticks += 1
		runner.step(0.1)
		if runner.idle(worker.id): break
	check_eq(work_ticks, 20, "work rate two halves the real manual operation time")

func test_pickup_duration_and_shared_drop_duration_are_distinct_capability_parameters() -> void:
	var rules := Fixture.opened("handoff")
	var runner := _runner(rules)
	if runner == null: return
	var worker: Dictionary = rules.workers[0]
	worker.post = ""
	worker.pos = Vector2(180,180)
	runner.inventory.seed("source", "raw", 1)
	runner.transfer(worker.id, "source", "target", "raw", 1, 0.2, -2, -2, 1.0)
	var pickup_ticks := 0
	var drop_ticks := 0
	for tick in 100:
		if worker.phase == "pickup": pickup_ticks += 1
		if worker.phase == "dropoff": drop_ticks += 1
		runner.step(0.1)
		if runner.idle(worker.id): break
	check_eq(pickup_ticks, 10, "source fetch takes the declared one second")
	check_eq(drop_ticks, 2, "drop uses the shared hop duration")

func test_saved_carrier_resumes_the_original_action_and_cannot_pick_up_twice() -> void:
	var rules := Fixture.opened("handoff")
	var runner := _runner(rules)
	if runner == null: return
	var worker: Dictionary = rules.workers[0]
	worker.post = ""
	worker.pos = Vector2(180,180)
	runner.inventory.seed("source", "tea", 3)
	runner.transfer(worker.id, "source", "target", "tea", 2, 0.6)
	for tick in 100:
		runner.step(0.1)
		if worker.carry_count > 0 and worker.pos.x > 180.0: break
	check(worker.carry_count == 2 and worker.walking, "snapshot is taken during real transport")
	var saved: Dictionary = runner.snapshot()
	var reopened_rules := Fixture.opened("handoff")
	reopened_rules.workers[0].post = ""
	var reopened := _runner(reopened_rules)
	check_eq(reopened.restore(saved), "", "restore cursor, movement and authoritative inventory together")
	for tick in 300:
		reopened.step(0.1)
		if reopened.idle(worker.id): break
	check_eq(reopened.inventory.quantity("source", "tea"), 1, "source is not picked a second time")
	check_eq(reopened.inventory.quantity("target", "tea"), 2, "same two goods arrive")
	check_eq(reopened_rules.workers[0].carry_count, 0, "restored actor finishes the original drop")

func test_corrupt_action_cursor_or_hand_is_rejected_without_changing_live_actors() -> void:
	var rules := Fixture.opened("handoff")
	var runner := _runner(rules)
	if runner == null: return
	var worker: Dictionary = rules.workers[0]
	worker.post = ""
	worker.pos = Vector2(180,180)
	runner.inventory.seed("source", "tea", 3)
	runner.transfer(worker.id, "source", "target", "tea", 2, 0.6)
	for tick in 100:
		runner.step(0.1)
		if worker.carry_count > 0: break
	var original: Dictionary = runner.snapshot()
	var broken: Dictionary = original.duplicate(true)
	broken.actors[0].carry_count = 9
	check(not runner.restore(broken).is_empty(), "hand display must agree with authoritative carried stock")
	check_eq(runner.snapshot(), original, "failed adoption cannot partially mutate the live actor")
	broken = original.duplicate(true)
	broken.actors[0].action.index = 0
	check(not runner.restore(broken).is_empty(), "cursor cannot replay a pickup already committed")
	check_eq(runner.snapshot(), original, "failed cursor adoption is atomic")
	broken = original.duplicate(true)
	broken.tasks[0].profile = "customer"
	broken.actors[0].motion.profile = "customer"
	check(not runner.restore(broken).is_empty(), "a saved employee cannot adopt a different access role")
	check_eq(runner.snapshot(), original, "bad access profile cannot replace actor state")
