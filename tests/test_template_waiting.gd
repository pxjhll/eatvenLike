extends "res://tests/test_case.gd"
const Runtime := preload("res://game/rules/template/runtime.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")
const Fixture := preload("res://tests/fixtures/template_service.gd")

func _definition(delivery := "counter") -> Resource:
	var template := Fixture.definition(delivery,"employee")
	template.dispatch = {"affinity":"exclusive"}
	template.service["waiting"] = {"group":"test_wait","ports":["wait:test_wait/0","wait:test_wait/1"],
		"line":[Vector2(100,500),Vector2(100,560),Vector2(100,620),Vector2(100,680)],
		"stages":[{"standing":1,"seats":0},{"standing":2,"seats":2}],"retain_after_take":delivery=="counter"}
	return template

func _owner() -> ShopRules:
	var owner := Fixture.owner()
	var group := SpecSeatGroup.new()
	group.id = "test_wait"
	group.purpose = "wait"
	group.start = 0
	group.steps.assign([2])
	group.costs.assign([10])
	owner.shop.seat_groups.append(group)
	owner.seats.test_wait = 0
	owner.nav.layout.customer_points["wait:test_wait/0"] = Vector2(700,700)
	owner.nav.layout.customer_points["wait:test_wait/1"] = Vector2(800,700)
	return owner

func _runtime(template: Resource) -> RefCounted:
	var runtime := Runtime.new(_owner(),template)
	check_eq(runtime.last_error,"","waiting is a public service policy")
	return runtime if runtime.last_error.is_empty() else null

func _arrive(runtime: RefCounted) -> Dictionary:
	return runtime.arrive([{"dish":"lemonade","qty":1}])

func _advance(runtime: RefCounted, ticks: int) -> void:
	for tick in ticks: check_eq(runtime.step(0.1),"","common queue/waiting movement")

func test_stage_queue_capacity_and_owned_waiting_seats_control_real_admission() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	check_eq(_arrive(runtime).error,"","one opening queue place")
	check_eq(_arrive(runtime).error,"queue full","opening standing capacity is one, not layout length")
	runtime.runner.owner.stage_index = 1
	runtime.runner.owner.seats.test_wait = 2
	for index in 3: check_eq(_arrive(runtime).error,"","expanded standing plus purchased seats")
	check_eq(_arrive(runtime).error,"queue full","fifth guest exceeds two standing plus two waiting places")
	var customers: Array = runtime.service.customers.snapshot().customers
	check_eq(customers[2].target,"wait:test_wait/0","overflow uses first actual waiting port")
	check_eq(customers[3].target,"wait:test_wait/1","different customer gets a distinct seat")

func test_seated_queue_head_is_called_to_admission_and_both_actors_must_arrive() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	runtime.runner.owner.stage_index = 1
	runtime.runner.owner.seats.test_wait = 2
	for index in 4: _arrive(runtime)
	var called := false
	for tick in 1800:
		check_eq(runtime.step(0.1),"","call seated overflow after earlier guests")
		var guest: Dictionary = runtime.service.orders.guest(3)
		if guest.claimed>0:
			called = true
			check_eq(runtime.service.customers.record(3).target,"queue:0","called guest really walks back to admission")
			if not runtime.service.customers.ready(3,"queue:0"): check_eq(guest.order,-1,"employee cannot finish taking before guest arrives")
		if guest.order>0: break
	check(called,"real seated queue guest was claimed")
	check(runtime.service.orders.guest(3).order>0,"seated head eventually accepts a real order")

func test_accepted_guest_waits_at_stable_seat_until_actual_delivery_calls_it_back() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	runtime.runner.owner.stage_index = 1
	runtime.runner.owner.seats.test_wait = 2
	_arrive(runtime)
	var waiting := false
	var called := false
	for tick in 1000:
		check_eq(runtime.step(0.1),"","wait during real production")
		var guest: Dictionary = runtime.service.orders.guest(1)
		var actor: Dictionary = runtime.service.customers.record(1)
		if guest.state=="waiting" and runtime.service.snapshot().deliveries.is_empty():
			waiting = true
			check_eq(actor.target,"wait:test_wait/0","paid/admitted guest keeps waiting place while cooking")
		if not runtime.service.snapshot().deliveries.is_empty():
			called = true
			check_eq(actor.target,"pickup","real delivery calls guest to handoff")
			if not runtime.service.customers.ready(1,"pickup"):
				for line in runtime.service.orders.order(guest.order).lines: check_eq(line.delivered,0,"cannot commit drop while guest is still walking")
		if guest.state=="gone": break
	check(waiting and called,"both waiting and actual return were exercised")
	check_eq(runtime.service.orders.guest(1).state,"gone","real service still finishes")
	check_eq(runtime.service.snapshot().waiting.leases,[],"departure releases waiting capacity")

func test_waiting_policy_reuses_counter_and_table_without_turning_wait_seats_into_dining_seats() -> void:
	for delivery in ["counter","table"]:
		var runtime := _runtime(_definition(delivery))
		if runtime == null: return
		runtime.runner.owner.stage_index = 1
		runtime.runner.owner.seats.test_wait = 2
		_arrive(runtime)
		_advance(runtime,800)
		check_eq(runtime.service.orders.order(1).state,"delivered","same public actions finish "+delivery)
		check_eq(runtime.service.snapshot().waiting.leases,[],"waiting lease is independent from dining lease")

func test_existing_waiting_seats_survive_capacity_reduction_without_duplication() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	runtime.runner.owner.stage_index = 1
	runtime.runner.owner.seats.test_wait = 2
	for index in 4: _arrive(runtime)
	var before: Array = runtime.service.snapshot().waiting.leases
	runtime.runner.owner.seats.test_wait = 0
	check_eq(_arrive(runtime).error,"queue full","shrinking cannot accept extra guests")
	# No time advancement is needed to demonstrate capacity reduction preserves identities.
	check_eq(runtime.service.snapshot().waiting.leases,before,"held waiting leases stay until guest leaves")
	_advance(runtime,1000)
	check_eq(runtime.service.snapshot().waiting.leases,[],"old reservations drain normally")

func test_waiting_restore_preserves_seat_targets_and_rejects_duplicate_or_orphan_leases() -> void:
	var template := _definition()
	var runtime := _runtime(template)
	if runtime == null: return
	runtime.runner.owner.stage_index = 1
	runtime.runner.owner.seats.test_wait = 2
	for index in 4: _arrive(runtime)
	_advance(runtime,30)
	var saved: Dictionary = runtime.snapshot()
	var reopened := _runtime(template)
	if reopened == null: return
	reopened.runner.owner.stage_index = 1
	reopened.runner.owner.seats.test_wait = 2
	check_eq(reopened.restore(saved),"","restore actual waiting movement and leases")
	for tick in 800:
		check_eq(runtime.step(0.1),"","continue original waiting")
		check_eq(reopened.step(0.1),"","continue restored waiting")
	check_eq(reopened.snapshot(),runtime.snapshot(),"same queue, customer movements and real production")
	for corruption in ["duplicate","orphan","delivery"]:
		var broken: Dictionary = saved.duplicate(true)
		if corruption == "orphan": broken.service.waiting.leases[0].guest = 999
		elif corruption == "duplicate": broken.service.waiting.leases.append(broken.service.waiting.leases[0].duplicate())
		else: broken.service.deliveries.append({"order":999,"bundle":999,"phase":"staff","left":0.0})
		var before: Dictionary = reopened.snapshot()
		check(not reopened.restore(broken).is_empty(),"invalid waiting identity rejected")
		check_eq(reopened.snapshot(),before,"failed adoption keeps current actors and inventory")

func test_waiting_candidate_queries_are_read_only_and_pause_preserves_leases_and_motion() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	runtime.runner.owner.stage_index = 1
	runtime.runner.owner.seats.test_wait = 2
	for index in 4: _arrive(runtime)
	var before: Dictionary = runtime.snapshot()
	for worker in runtime.runner.owner.workers: runtime.candidates_for(worker.id)
	check_eq(runtime.snapshot(),before,"candidate queries cannot call a seated guest or reserve a chair")
	check_eq(runtime.step(10.0,true),"","pause")
	check_eq(runtime.snapshot(),before,"pause includes wait leases and movements")

func test_invalid_waiting_ports_groups_and_unused_fields_fail_closed() -> void:
	for patch in [{"callback":"assign"},{"line":[]},{"ports":["queue:0"]},{"stages":[{"standing":0,"seats":2}]}]:
		var template := _definition()
		for key in patch: template.service.waiting[key] = patch[key]
		check(not Compiler.compile(template).errors.is_empty(),"bad waiting definition is rejected")
	var unknown := _definition()
	unknown.service.waiting.group = "missing"
	check(not Runtime.new(_owner(),unknown).last_error.is_empty(),"unknown purchase group is explicit error")

func test_unreachable_called_customer_blocks_delivery_and_recall_returns_real_goods() -> void:
	var owner := _owner()
	owner.stage_index = 1
	owner.seats.test_wait = 2
	# Customer can reach admission but cannot reach the handoff x=300. Staff
	# retains its independent, unchanged navigation profile.
	owner.nav.layout.actor_areas.customer = [Rect2i(0,0,4,32)]
	var runtime := Runtime.new(owner,_definition())
	check_eq(runtime.last_error,"","a missing route is a runtime wait, not a teleport")
	if not runtime.last_error.is_empty(): return
	_arrive(runtime)
	_advance(runtime,800)
	var order: Dictionary = runtime.service.orders.order(1)
	check_eq(order.lines[0].delivered,0,"employee cannot remotely hand food to an unreachable customer")
	check(not order.paid,"blocked actual delivery earns no money")
	check(not runtime.service.customers.ready(1,"pickup"),"customer truly has no handoff route")
	var carrier := -1
	for task in runtime.runner.tasks.values():
		if task.kind=="bundle" and task.to=="guest:1": carrier = task.worker
	check(carrier>0,"employee really reserved/collected the actual delivery")
	if carrier>0: check_eq(runtime.runner.cancel(carrier),"","recall blocked delivery through public cancellation")
	check_eq(runtime.runner.inventory.audit(),[],"recall returns the same goods and releases physical claims")
	check_eq(runtime.service.snapshot().waiting.leases.size(),1,"waiting place remains reserved for still-active guest")

func test_claimed_seated_admission_restores_before_guest_arrives_at_counter() -> void:
	var template := _definition()
	var runtime := _runtime(template)
	if runtime == null: return
	runtime.runner.owner.stage_index = 1
	runtime.runner.owner.seats.test_wait = 2
	for index in 4: _arrive(runtime)
	var reached := false
	for tick in 1800:
		check_eq(runtime.step(0.1),"","reach a real admission call")
		if runtime.service.orders.guest(3).claimed>0 and not runtime.service.customers.ready(3,"queue:0"):
			reached = true
			break
	check(reached,"seated overflow guest was called but is still walking")
	if not reached: return
	var reopened := _runtime(template)
	if reopened == null: return
	reopened.runner.owner.stage_index = 1
	reopened.runner.owner.seats.test_wait = 2
	for key in ["gold","revenue","sold","sale_carry"]: reopened.runner.owner._sales.set(key,runtime.runner.owner._sales.get(key))
	reopened.runner.owner.sold_by_dish = runtime.runner.owner.sold_by_dish.duplicate(true)
	reopened.runner.owner.rng.state = runtime.runner.owner.rng.state
	check_eq(reopened.restore(runtime.snapshot()),"","restore waiting lease, admission claim and walking employee/customer")
	for tick in 900:
		check_eq(runtime.step(0.1),"","continue original call")
		check_eq(reopened.step(0.1),"","continue restored call")
	check_eq(reopened.snapshot(),runtime.snapshot(),"same eventual queue, delivery and departure")
	check_eq(reopened.runner.owner.revenue,runtime.runner.owner.revenue,"restore cannot duplicate collected money")

func test_table_admission_releases_waiting_place_and_is_restorable_in_the_same_tick() -> void:
	var template := _definition("table")
	template.service.admission = "automatic"
	template.service.admission_port = ""
	var runtime := _runtime(template)
	if runtime == null: return
	runtime.runner.owner.stage_index = 1
	runtime.runner.owner.seats.test_wait = 2
	_arrive(runtime)
	for tick in 600:
		check_eq(runtime.step(0.1),"","reach first completed table admission")
		if runtime.service.orders.guest(1).state == "waiting": break
	check_eq(runtime.service.customers.record(1).target,"seat:dine/0","accepted guest heads to dining place immediately")
	var reopened := _runtime(template)
	if reopened == null: return
	reopened.runner.owner.stage_index = 1
	reopened.runner.owner.seats.test_wait = 2
	check_eq(reopened.restore(runtime.snapshot()),"","save at exact acceptance tick has a coherent customer destination")
