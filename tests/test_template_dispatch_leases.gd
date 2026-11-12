extends "res://tests/test_case.gd"
const Fixture := preload("res://tests/fixtures/template_service.gd")
const Production := preload("res://tests/fixtures/template_shop.gd")
const Runtime := preload("res://game/rules/template/runtime.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")

func _runtime(template: Resource, policy: Dictionary) -> RefCounted:
	template.dispatch = policy
	var runtime := Runtime.new(Fixture.owner(), template)
	check_eq(runtime.last_error, "", "public follower/machine lease policy compiles")
	return runtime if runtime.last_error.is_empty() else null

func _finish_transfer(runtime: RefCounted, worker: int) -> void:
	for tick in 300:
		check_eq(runtime.runner.step(0.1), "", "real public transfer")
		if runtime.runner.idle(worker): break
	check(runtime.runner.idle(worker), "physical transfer finished")

func _claim_unit(runtime: RefCounted, worker: int, unit: int) -> void:
	check_eq(runtime.runner.transfer(worker, "pantry", "a_in", "raw_a", 1, 0.2, -1, unit), "", "claim unit through real inventory allocation")
	_finish_transfer(runtime, worker)

func test_exclusive_follower_keeps_main_and_side_production_and_delivery_with_one_employee() -> void:
	for mode in ["counter", "self_pickup", "table"]:
		var runtime := _runtime(Fixture.definition(mode, "employee"), {"affinity":"exclusive"})
		if runtime == null: return
		runtime.arrive(Fixture.request())
		runtime.arrive(Fixture.request())
		var actors := {}
		for tick in 3000:
			check_eq(runtime.step(0.1), "", "one common follower scheduler")
			for task in runtime.runner.tasks.values():
				if not String(task.scope).begins_with("order:"): continue
				if not actors.has(task.scope): actors[task.scope] = {}
				actors[task.scope][task.worker] = true
			if runtime.frame().guests[1].state == "gone": break
		check_eq(runtime.runner.owner.sold, 4, "both two-line orders complete")
		check_eq(actors.size(), 2, "both orders acquired public scope leases")
		for workers in actors.values(): check_eq(workers.size(), 1, "one employee follows main and side until handoff")
		check_eq(runtime.runner.dispatcher.snapshot().scopes, [], "delivered orders release followers")

func test_direct_requests_and_any_owner_transfers_cannot_bypass_exclusive_following_or_leave_failed_reservations() -> void:
	var runtime := _runtime(Production.linear(), {"affinity":"exclusive"})
	if runtime == null: return
	var first: Dictionary = runtime.request_production("drink")
	var second: Dictionary = runtime.request_production("drink")
	var a: int = runtime.runner.owner.workers[0].id
	var b: int = runtime.runner.owner.workers[1].id
	_claim_unit(runtime, a, first.id)
	var before: Dictionary = runtime.snapshot()
	check(not runtime.runner.transfer(b, "pantry", "a_in", "raw_a", 1, 0.2, -1, first.id).is_empty(), "other employee cannot acquire followed unit")
	check_eq(runtime.snapshot(), before, "failed follower request changes nothing")
	check(not runtime.runner.transfer(a, "pantry", "a_in", "raw_a", 1, 0.2, -1, second.id).is_empty(), "follower cannot start a second unit")
	check_eq(runtime.snapshot(), before, "no half reservation of second order")
	check(not runtime.runner.transfer(b, "a_in", "a_out", "raw_a", 1, 0.2).is_empty(), "ANY_OWNER does not erase real lot ownership")
	check_eq(runtime.snapshot(), before, "generic request cannot steal followed stock")
	check(not runtime.runner.transfer_bundle(b, [{"from":"a_in", "to":"a_out", "item":"raw_a", "count":1}], 0.2).is_empty(), "bundle cannot bypass follower by omitting owner")
	check_eq(runtime.snapshot(), before, "failed group reservation is atomic")

func test_preference_prioritizes_the_same_unit_without_becoming_an_exclusive_lock() -> void:
	var runtime := _runtime(Production.linear(), {"affinity":"prefer", "affinity_bonus":500.0, "scores":{"operate":0.0, "transfer":100.0}})
	if runtime == null: return
	runtime.request_production("drink")
	var followed: Dictionary = runtime.request_production("drink")
	var worker: Dictionary = runtime.runner.owner.workers[0]
	runtime.runner.owner.workers[1].deployed = false
	_claim_unit(runtime, worker.id, followed.id)
	runtime.step(0.1)
	var task: Dictionary = runtime.runner.tasks[worker.id]
	check_eq(task.kind, "operate", "affinity bonus outweighs another unit's higher base transfer score")
	check_eq(runtime.runner.inventory.claim(runtime.runner.machines.run(task.run).claim).owner, followed.id, "real continuation belongs to preferred unit")
	var other := _runtime(Production.linear(), {"affinity":"prefer"})
	var unit: Dictionary = other.request_production("drink")
	_claim_unit(other, other.runner.owner.workers[0].id, unit.id)
	check_eq(other.runner.transfer(other.runner.owner.workers[1].id, "a_in", "a_out", "raw_a", 1, 0.2, unit.id), "", "another employee may assist a preferred unit")

func test_recall_or_reassignment_releases_an_idle_followers_lease_for_another_employee() -> void:
	for reassign in [false, true]:
		var runtime := _runtime(Production.linear(), {"affinity":"exclusive"})
		if runtime == null: return
		var unit: Dictionary = runtime.request_production("drink")
		var worker: Dictionary = runtime.runner.owner.workers[0]
		var other: Dictionary = runtime.runner.owner.workers[1]
		_claim_unit(runtime, worker.id, unit.id)
		if reassign: worker.post = "a"
		else: worker.deployed = false
		check_eq(runtime.runner.step(0.1), "", "release idle lease on external roster change")
		check_eq(runtime.runner.transfer(other.id, "a_in", "a_out", "raw_a", 1, 0.2, unit.id), "", "another employee resumes the existing owned stock")
		check_eq(runtime.runner.dispatcher.snapshot().scopes[0].worker, other.id, "stable unit now belongs to new follower")

func test_shared_help_does_not_forget_the_owned_order_or_allow_another_follower_to_steal_it() -> void:
	var runtime := _runtime(Production.linear(), {"affinity":"exclusive", "help_while_waiting":true})
	if runtime == null: return
	var unit: Dictionary = runtime.request_production("drink")
	var a: int = runtime.runner.owner.workers[0].id
	var b: int = runtime.runner.owner.workers[1].id
	_claim_unit(runtime, a, unit.id)
	check_eq(runtime.runner.transfer(a, "pantry", "b_in", "raw_b", 1, 0.2, -1, -1), "", "follower may assist a shared chore")
	_finish_transfer(runtime, a)
	check_eq(runtime.runner.dispatcher.snapshot().scopes[0].scope, "unit:" + str(unit.id), "shared work preserves follower ownership")
	check(not runtime.runner.transfer(b, "a_in", "a_out", "raw_a", 1, 0.2).is_empty(), "assisting does not release followed material")

func _pot(help: bool = true) -> RefCounted:
	var template := Production.linear()
	template.machines.a.profile = {"load_seconds":0.2, "stir_points":[0.5], "stir_seconds":0.2, "unload_seconds":0.2}
	return _runtime(template, {"hold_machine":true, "help_while_waiting":help})

func _loaded_pot(runtime: RefCounted) -> int:
	var worker: Dictionary = runtime.runner.owner.workers[0]
	worker.pos = Vector2(200,100)
	var run: Dictionary = runtime.runner.machines.start("a", {}, {"drink":1}, 2.0)
	check_eq(runtime.runner.operate(worker.id, run.id, "a_in"), "", "public loading action acquires stage lease")
	for tick in 30:
		runtime.runner.step(0.1)
		if runtime.runner.idle(worker.id): break
	check_eq(runtime.runner.machines.run(run.id).phase, "processing", "employee is idle during automatic work")
	return run.id

func test_machine_holder_keeps_load_stir_unload_but_recall_releases_the_remaining_stages() -> void:
	var runtime := _pot()
	if runtime == null: return
	var id := _loaded_pot(runtime)
	var a: Dictionary = runtime.runner.owner.workers[0]
	var b: Dictionary = runtime.runner.owner.workers[1]
	for tick in 30:
		runtime.runner.step(0.1)
		if runtime.runner.machines.run(id).phase == "await_stir": break
	var before: Dictionary = runtime.snapshot()
	check(not runtime.runner.operate(b.id, id, "a_in").is_empty(), "other employee cannot steal the next machine stage")
	check_eq(runtime.snapshot(), before, "denied stir leaves stage and employee intact")
	check_eq(runtime.runner.operate(a.id, id, "a_in"), "", "original loader resumes stirring")
	for tick in 60:
		runtime.runner.step(0.1)
		if runtime.runner.machines.run(id).phase == "await_unload": break
	check_eq(runtime.runner.dispatcher.snapshot().machines[0].worker, a.id, "lease survives automatic wait")
	a.deployed = false
	runtime.runner.cancel(a.id)
	check_eq(runtime.runner.operate(b.id, id, "a_out"), "", "recall releases idle machine lease")
	_finish_transfer(runtime, b.id)
	check_eq(runtime.runner.inventory.quantity("a_out", "drink"), 1, "one physical output after ownership changes")
	check_eq(runtime.runner.dispatcher.snapshot().machines, [], "completed batch releases machine lease")

func test_waiting_machine_holder_only_assists_when_policy_allows_it() -> void:
	for help in [false, true]:
		var runtime := _pot(help)
		if runtime == null: return
		_loaded_pot(runtime)
		var a: int = runtime.runner.owner.workers[0].id
		var before: Dictionary = runtime.snapshot()
		var error: String = runtime.runner.transfer(a, "pantry", "b_in", "raw_b", 1, 0.2, -1, -1)
		check_eq(error.is_empty(), help, "shared assistance follows the configured wait policy")
		if not help: check_eq(runtime.snapshot(), before, "denied assistance leaves lease and inventory intact")

func test_followers_and_machine_leases_restore_atomically_and_reject_duplicate_or_unknown_owners() -> void:
	var runtime := _runtime(Production.linear(), {"affinity":"exclusive"})
	if runtime == null: return
	var unit: Dictionary = runtime.request_production("drink")
	_claim_unit(runtime, runtime.runner.owner.workers[0].id, unit.id)
	var saved: Dictionary = runtime.snapshot()
	var reopened := _runtime(Production.linear(), {"affinity":"exclusive"})
	check_eq(reopened.restore(saved), "", "restore idle follower reservation")
	for corruption in ["duplicate", "unknown", "worker"]:
		var broken: Dictionary = saved.duplicate(true)
		match corruption:
			"duplicate": broken.dispatch.scopes.append(broken.dispatch.scopes[0].duplicate(true))
			"unknown": broken.dispatch.scopes[0].scope = "order:999"
			"worker": broken.dispatch.scopes[0].worker = 999
		check(not reopened.restore(broken).is_empty(), "reject corrupt follower " + corruption)
		check_eq(reopened.snapshot(), saved, "failed lease restore adopts no actor state")
	var pot := _pot()
	var id := _loaded_pot(pot)
	var pot_saved: Dictionary = pot.snapshot()
	var resumed := _pot()
	check_eq(resumed.restore(pot_saved), "", "restore holder while employee waits for automatic processing")
	var broken: Dictionary = pot_saved.duplicate(true)
	broken.dispatch.machines[0].run = id + 100
	check(not resumed.restore(broken).is_empty(), "unknown machine run cannot create a lease")
	check_eq(resumed.snapshot(), pot_saved, "bad machine lease cannot replace inventory or actors")

func test_invalid_follow_policy_and_flags_are_rejected() -> void:
	var runtime := _runtime(Production.linear(), {"affinity":"prefer"})
	if runtime == null: return
	for policy in [{"affinity":"private_shop"}, {"affinity_bonus":-1.0}, {"hold_machine":1}, {"help_while_waiting":"yes"}]:
		var template := Production.linear()
		template.dispatch = policy
		check(not Compiler.compile(template).errors.is_empty(), "unsupported lease policy cannot be silently ignored")

func test_completed_source_unit_does_not_create_an_unrestorable_follower_when_moving_its_output() -> void:
	var template := Production.linear()
	template.recipes = {"cup":{"nodes":[{"id":"source", "capability":"source", "place":"pantry", "item":"raw_a"}],
		"output":{"node":"source", "item":"raw_a", "count":1}}}
	var runtime := _runtime(template, {"affinity":"exclusive"})
	if runtime == null: return
	var unit: Dictionary = runtime.request_production("cup")
	check_eq(runtime.runner.transfer(runtime.runner.owner.workers[0].id, "pantry", "a_out", "raw_a", 1, 0.2, -1, unit.id), "", "move already complete source output")
	var saved: Dictionary = runtime.snapshot()
	check_eq(runtime.restore(saved), "", "valid source transport is restorable")
	check_eq(saved.dispatch.scopes, [], "finished production does not acquire a stale follower lease")

func test_followed_service_restores_during_production_and_customer_carry_with_identical_remaining_work() -> void:
	for mode in ["counter", "self_pickup", "table"]:
		var runtime := _runtime(Fixture.definition(mode, "employee"), {"affinity":"exclusive", "hold_machine":true})
		if runtime == null: return
		runtime.arrive(Fixture.request())
		var found := false
		for tick in 500:
			runtime.step(0.1)
			if mode == "self_pickup": found = runtime.frame().held.has("customer:1")
			else:
				for task in runtime.runner.tasks.values():
					if task.kind == "operate" and String(task.scope).begins_with("order:"): found = true
			if found: break
		check(found, "save contains active follower or customer carrying")
		var saved: Dictionary = runtime.snapshot()
		var reopened := _runtime(Fixture.definition(mode, "employee"), {"affinity":"exclusive", "hold_machine":true})
		for key in ["gold", "revenue", "sold", "sale_carry"]: reopened.runner.owner._sales.set(key, runtime.runner.owner._sales.get(key))
		reopened.runner.owner.sold_by_dish = runtime.runner.owner.sold_by_dish.duplicate(true)
		var error: String = reopened.restore(saved)
		check_eq(error, "", "restore follower and stage leases with actor program")
		if not error.is_empty(): continue
		for tick in 2000:
			check_eq(runtime.step(0.1), "", "original follower trace")
			check_eq(reopened.step(0.1), "", "restored follower trace")
			if runtime.frame().guests[0].state == "gone" and reopened.frame().guests[0].state == "gone": break
		check_eq(reopened.snapshot(), runtime.snapshot(), "same remaining actions, stage clocks and lease release")
		check_eq(reopened.runner.owner.gold, runtime.runner.owner.gold, "no duplicate settlement")

func test_forged_task_scope_or_missing_active_machine_lease_is_rejected_before_adopting_actors() -> void:
	var runtime := _runtime(Production.linear(), {"affinity":"exclusive", "hold_machine":true})
	if runtime == null: return
	var unit: Dictionary = runtime.request_production("drink")
	for tick in 200:
		runtime.step(0.1)
		var operating := false
		for task in runtime.runner.tasks.values():
			if task.kind == "operate": operating = true
		if operating: break
	var before: Dictionary = runtime.snapshot()
	check(not before.dispatch.machines.is_empty(), "active manual operator has a stage lease")
	for corruption in ["task_scope", "follower", "machine"]:
		var broken: Dictionary = before.duplicate(true)
		match corruption:
			"task_scope": broken.runner.tasks[0].scope = "unit:999"
			"follower": broken.dispatch.scopes.clear()
			"machine": broken.dispatch.machines.clear()
		check(not runtime.restore(broken).is_empty(), "reject inconsistent " + corruption)
		check_eq(runtime.snapshot(), before, "failed scope validation preserves every live actor and service")

func test_one_employee_holding_two_automatic_batches_can_resume_either_without_mutual_wait_deadlock() -> void:
	var template := Production.linear()
	for machine in ["a", "b"]:
		template.machines[machine].profile = {"load_seconds":0.2, "stir_points":[0.5], "stir_seconds":0.2, "unload_seconds":0.2}
	var runtime := _runtime(template, {"hold_machine":true, "help_while_waiting":true})
	if runtime == null: return
	var first := _loaded_pot(runtime)
	var worker: Dictionary = runtime.runner.owner.workers[0]
	var second: Dictionary = runtime.runner.machines.start("b", {}, {"other_drink":1}, 2.0)
	check_eq(runtime.runner.operate(worker.id, second.id, "b_in"), "", "help by loading a second automatic batch")
	for tick in 100:
		runtime.runner.step(0.1)
		if runtime.runner.idle(worker.id) and runtime.runner.machines.run(second.id).phase == "await_stir": break
	check_eq(runtime.runner.machines.run(first).phase, "await_stir", "first batch also needs its holder")
	check_eq(runtime.runner.dispatcher.snapshot().machines.size(), 2, "both batches retained their common holder")
	check_eq(runtime.runner.operate(worker.id, first, "a_in"), "", "another held batch cannot block resuming one's own stage")
