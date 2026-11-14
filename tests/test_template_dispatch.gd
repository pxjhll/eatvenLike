extends "res://tests/test_case.gd"
const TemplateOuter := preload("res://tests/fixtures/template_outer.gd")
const Fixture := preload("res://tests/fixtures/template_service.gd")
const Production := preload("res://tests/fixtures/template_shop.gd")
const Runtime := preload("res://game/rules/template/runtime.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")

func _policy() -> Dictionary:
	return {"posts":{"a":{"operate":["a"], "transfer_from":[], "transfer_to":[], "interact":[]}}}

func _runtime(template: Resource) -> RefCounted:
	check(template.get("dispatch") != null, "production and service need one declarative permission policy")
	if template.get("dispatch") == null: return null
	template.set("dispatch", _policy())
	var runtime := Runtime.new(Fixture.owner(), template)
	check_eq(runtime.last_error, "", "valid dispatch template")
	return runtime

func test_posted_worker_only_operates_declared_device_while_floating_worker_completes_common_service() -> void:
	for delivery in ["counter", "self_pickup", "table"]:
		var runtime := _runtime(Fixture.definition(delivery, "employee"))
		if runtime == null: return
		var chef: Dictionary = runtime.runner.owner.workers[0]
		chef.post = "a"
		runtime.arrive(Fixture.request())
		var worked := false
		for tick in 2400:
			check_eq(runtime.step(0.1), "", "same scheduler and capability runner")
			if runtime.runner.tasks.has(chef.id):
				worked = true
				var task: Dictionary = runtime.runner.tasks[chef.id]
				check_eq(task.kind, "operate", "posted chef cannot take orders, carry or serve")
				if task.kind == "operate": check_eq(runtime.runner.machines.run(task.run).machine, "a", "posted device")
			if runtime.frame().guests[0].state == "gone": break
		check(worked, "posted employee performed real work")
		check_eq(runtime.runner.owner.sold, 2, "floating worker handles other capabilities")
		check_eq(runtime.frame().guests[0].state, "gone", "customer completes full service")

func test_denied_transfer_bundle_and_admission_reserve_no_goods_or_employee_actions() -> void:
	var runtime := _runtime(Fixture.definition())
	if runtime == null: return
	var chef: Dictionary = runtime.runner.owner.workers[0]
	chef.post = "a"
	var before: Dictionary = runtime.snapshot()
	check(not runtime.runner.transfer(chef.id, "pantry", "a_in", "raw_a", 1, 0.6).is_empty(), "same permission gate for ordinary transfer")
	check_eq(runtime.snapshot(), before, "denied transfer is atomic")
	check(not runtime.runner.transfer_bundle(chef.id, [{"from":"pantry", "to":"a_in", "item":"raw_a", "count":1}], 0.6).is_empty(), "same permission gate for bundles")
	check_eq(runtime.snapshot(), before, "denied bundle has no child reservations")
	check(not runtime.runner.interact(chef.id, "front", 0.6, "admit", 1).is_empty(), "same permission gate for service admission")
	check_eq(runtime.snapshot(), before, "denied admission does not acquire employee")

func test_declared_role_can_transport_without_cooking_and_cannot_bypass_gate_by_direct_operation_request() -> void:
	var template := Production.linear()
	check(template.get("dispatch") != null, "public role capability policy exists")
	if template.get("dispatch") == null: return
	template.set("dispatch", {"roles":{"staff":{"transfer_from":["*"], "transfer_to":["*"], "operate":[]}}})
	var runtime := Runtime.new(Fixture.owner(), template)
	var unit: Dictionary = runtime.request_production("drink")
	for tick in 100: runtime.step(0.1)
	check(not runtime.ready(unit.id), "transport-only role cannot operate the prepared machine")
	check_eq(runtime.runner.inventory.quantity("a_in", "raw_a", unit.id), 1, "permitted real transport still runs")
	var run: Dictionary = runtime.runner.machines.snapshot().runs[0]
	var before: Dictionary = runtime.snapshot()
	check(not runtime.runner.operate(runtime.runner.owner.workers[0].id, run.id, "a_in").is_empty(), "direct public request cannot bypass dispatch eligibility")
	check_eq(runtime.snapshot(), before, "denied operation changes neither actor nor machine")

func test_reassignment_during_carry_compensates_once_before_any_further_action_can_commit() -> void:
	var runtime := _runtime(Fixture.definition())
	if runtime == null: return
	var worker: Dictionary = runtime.runner.owner.workers[0]
	worker.pos = Vector2(180,480)
	runtime.runner.inventory.seed("front", "box", 1)
	runtime.runner.transfer(worker.id, "front", "table", "box", 1, 0.6)
	for tick in 50:
		runtime.runner.step(0.1)
		if worker.carry_count == 1: break
	check_eq(worker.carry_count, 1, "reassignment happens while physically carrying")
	worker.post = "a"
	check_eq(runtime.runner.step(0.1), "", "permission revocation releases old task")
	check_eq(runtime.runner.inventory.quantity("front", "box"), 1, "goods return to source")
	check_eq(worker.carry_count, 0, "no obsolete carried icon")
	runtime.runner.step(0.1)
	check_eq(runtime.runner.inventory.quantity("front", "box"), 1, "no duplicate compensation")
	check_eq(runtime.runner.inventory.audit(), [], "one shared cancellation path")

func test_restored_action_must_still_be_authorized_by_outer_current_post() -> void:
	var runtime := _runtime(Fixture.definition())
	if runtime == null: return
	var worker: Dictionary = runtime.runner.owner.workers[0]
	runtime.runner.inventory.seed("front", "box", 1)
	runtime.runner.transfer(worker.id, "front", "table", "box", 1, 0.6)
	var saved: Dictionary = runtime.snapshot()
	worker.post = "a"
	check(not runtime.restore(saved).is_empty(), "valid cursor cannot grant a capability forbidden to current post")
	check_eq(runtime.snapshot(), saved, "failed adoption does not cancel or partially replace live actor")

func test_reassignment_releases_machine_before_its_clock_advances_for_the_removed_operator() -> void:
	var runtime := _runtime(Production.definition())
	if runtime == null: return
	var worker: Dictionary = runtime.runner.owner.workers[0]
	worker.pos = Vector2(300,100)
	var run: Dictionary = runtime.runner.machines.start("b", {}, {"b":1}, 5.0)
	runtime.runner.operate(worker.id, run.id, "b_in")
	for tick in 20:
		runtime.runner.step(0.1)
		if runtime.runner.machines.run(run.id).phase == "operate": break
	var remaining: float = runtime.runner.machines.run(run.id).remaining
	worker.post = "a"
	check_eq(runtime.runner.step(1.0), "", "revoke mismatched operation")
	check_eq(runtime.runner.machines.run(run.id).phase, "await_operate", "machine waits for permitted operator")
	check_eq(runtime.runner.machines.run(run.id).remaining, remaining, "removed operator contributes no further work")

func test_unknown_permissions_devices_and_ports_are_explicit_compile_errors() -> void:
	var template := Production.linear()
	check(template.get("dispatch") != null, "strict dispatch schema exists")
	if template.get("dispatch") == null: return
	for policy in [{"callback":"custom_shop"}, {"roles":{"staff":{"operate":["missing"]}}},
		{"posts":{"a":{"transfer_from":["missing"]}}}, {"roles":{"staff":{"magic":true}}}]:
		template.set("dispatch", policy)
		check(not Compiler.compile(template).errors.is_empty(), "unknown permission cannot be ignored or fall back")

func test_changing_access_region_revokes_old_route_even_when_both_roles_allow_the_task() -> void:
	var shop: SpecShop = Fixture.owner().shop.copy_for_editing()
	shop.staff.zones.assign(["front", "kitchen"])
	for profile in ["front", "kitchen"]: shop.layout.actor_areas[profile] = shop.layout.actor_areas["staff"].duplicate()
	var owner := TemplateOuter.owner(shop, 42)
	var worker: Dictionary = owner.workers[0]
	worker.post = owner.counter_id
	worker.pos = Vector2(180,480)
	var runtime := Runtime.new(owner, Fixture.definition())
	check_eq(runtime.last_error, "", "shared geometry declares both regions")
	runtime.runner.inventory.seed("front", "box", 1)
	runtime.runner.transfer(worker.id, "front", "table", "box", 1, 0.6)
	for tick in 50:
		runtime.runner.step(0.1)
		if worker.carry_count == 1: break
	check_eq(runtime.runner.tasks[worker.id].profile, "front", "original assignment uses front access")
	worker.post = ""
	check_eq(runtime.runner.access_profile(worker), "kitchen", "current role has changed")
	check_eq(runtime.runner.step(0.1), "", "revoke stale access before movement")
	check(runtime.runner.idle(worker.id), "old task is released even though generic capability remains allowed")
	check_eq(runtime.runner.inventory.quantity("front", "box"), 1, "old carried goods compensated")
	check(not worker.has("motion") and not worker.walking, "old region route cannot continue")
