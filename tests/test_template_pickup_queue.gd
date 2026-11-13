extends "res://tests/test_case.gd"
const Runtime := preload("res://game/rules/template/runtime.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")
const Fixture := preload("res://tests/fixtures/template_service.gd")
const Contract := preload("res://game/rules/shop_content_contract.gd")

func _definition() -> Resource:
	var template := Fixture.definition("self_pickup")
	template.places["table2"] = {"port":Vector2(700,680)}
	template.service.seats["seat:dine/1"] = "table2"
	template.service["pickup_queue"] = {"ports":["pickup:0","pickup:1"]}
	template.service.eat_seconds = 20.0
	return template

func _owner(block_second := false) -> ShopRules:
	var owner := Fixture.owner()
	owner.shop.layout.customer_points["seat:dine/1"] = Vector2(700,700)
	owner.shop.layout.customer_points["pickup:0"] = Vector2(300,500)
	owner.shop.layout.customer_points["pickup:1"] = Vector2(580,500)
	if block_second: owner.shop.layout.customer_points["pickup:1"] = Vector2(1500,500)
	return owner

func _runtime(template: Resource = null, block_second := false) -> RefCounted:
	var runtime := Runtime.new(_owner(block_second),_definition() if template==null else template)
	check_eq(runtime.last_error,"","declared pickup waiting points compose common service")
	return runtime if runtime.last_error.is_empty() else null

func _arrive(runtime: RefCounted) -> void:
	for index in 2: check_eq(runtime.arrive([{"dish":"lemonade","qty":1}]).error,"","two ordinary guests")

func _advance(runtime: RefCounted, ticks: int) -> void:
	for tick in ticks: check_eq(runtime.step(0.1),"","advance actual pickup queue")

func _resumed(runtime: RefCounted, template: Resource) -> RefCounted:
	var owner := _owner()
	for key in ["gold","revenue","sold","sale_carry"]: owner._sales.set(key,runtime.runner.owner._sales.get(key))
	owner.sold_by_dish = runtime.runner.owner.sold_by_dish.duplicate(true)
	owner.rng.state = runtime.runner.owner.rng.state
	var reopened := Runtime.new(owner,template)
	check_eq(reopened.last_error,"","same outer actor and seat identities")
	check_eq(reopened.restore(runtime.snapshot()),"","restore derived pickup positions from actual phases")
	return reopened

func test_waiting_guests_target_different_declared_points_without_extra_stock_or_seat_state() -> void:
	var runtime := _runtime()
	if runtime==null: return
	_arrive(runtime)
	for tick in 100:
		check_eq(runtime.step(0.1),"","admit two seated orders")
		if runtime.service.orders.guest(2).order>0: break
	check_eq(runtime.service.customers.record(1).target,"pickup:0","first waiting guest goes to front slot")
	check_eq(runtime.service.customers.record(2).target,"pickup:1","next waiting guest goes to second slot")
	check_eq(runtime.frame().pickup_targets,{1:"pickup:0",2:"pickup:1"},"frame derives targets from order and delivery facts")
	check(not runtime.service.snapshot().has("pickup_queue"),"no second authoritative queue/lease snapshot")
	check(not runtime.runner.inventory.snapshot().places.has("pickup:0"),"customer position is not another inventory container")

func test_first_guest_collecting_then_carrying_frees_position_and_next_guest_physically_advances() -> void:
	var runtime := _runtime()
	if runtime==null: return
	_arrive(runtime)
	var saw_second := false
	var saw_collect := false
	var advanced := false
	for tick in 800:
		check_eq(runtime.step(0.1),"","real preparation, collection and queue advancement")
		if runtime.service.customers.record(2).get("target")=="pickup:1": saw_second = true
		for delivery in runtime.service.snapshot().deliveries:
			var guest: int = runtime.service.orders.order(delivery.order).guest
			if guest==1 and delivery.phase=="collect":
				saw_collect = true
				check_eq(runtime.service.customers.record(2).target,"pickup:1","reserved food does not prematurely free the first point")
			if guest==1 and delivery.phase=="carry":
				check_eq(runtime.service.customers.record(1).target,"seat:dine/0","whole order goes with first guest to owned seat")
				check_eq(runtime.service.customers.record(2).target,"pickup:0","actual pickup frees front point immediately")
				if not runtime.service.customers.ready(2,"pickup:0"):
					advanced = true
					check(saw_second and saw_collect,"both pre-pickup positions really exercised")
					check_eq(runtime.service.orders.order(runtime.service.orders.guest(2).order).lines[0].delivered,0,"movement does not deliver second order")
					return
	check(advanced,"next visitor actually walks forward")

func test_guest_uses_waiting_rank_even_when_seat_dictionary_order_is_reversed() -> void:
	var template := _definition()
	template.service.seats = {"seat:dine/1":"table2","seat:dine/0":"table"}
	var runtime := _runtime(template)
	if runtime==null: return
	_arrive(runtime)
	_advance(runtime,100)
	check_eq(runtime.service.orders.guest(1).seat,"seat:dine/1","fixture gives first guest a different table number")
	check_eq(runtime.service.customers.record(1).target,"pickup:0","pickup position is waiting rank, not table number")
	check_eq(runtime.service.customers.record(2).target,"pickup:1","second admitted guest retains second rank")

func test_unreachable_waiting_position_cannot_collect_at_some_other_point_or_teleport() -> void:
	var template := _definition()
	template.recipes.drink.nodes[1].seconds = 30.0
	template.recipes.side.nodes[1].machine = "b"
	var runtime := _runtime(template,true)
	if runtime==null: return
	runtime.arrive([{"dish":"lemonade","qty":1}])
	runtime.arrive([{"dish":"black_tea","qty":1}])
	var exercised := false
	for tick in 800:
		check_eq(runtime.step(0.1),"","preserve real movement gating")
		if runtime.service.customers.record(2).get("target")=="pickup:1" and runtime.production_output(2).get("complete",false):
			exercised = true
			check(not runtime.service.customers.ready(2,"pickup:1"),"blocked visitor did not arrive")
			for delivery in runtime.service.snapshot().deliveries: check(runtime.service.orders.order(delivery.order).guest!=2,"unreachable visitor has no fictitious collected bundle")
			break
	check(exercised,"actual second output ready while visitor lacks a route")

func test_mid_queue_restore_matches_during_wait_collect_and_advancing_to_new_target() -> void:
	for boundary in ["waiting","collect","advance"]:
		var template := _definition()
		var runtime := _runtime(template)
		if runtime==null: return
		_arrive(runtime)
		var reached := false
		for tick in 1000:
			check_eq(runtime.step(0.1),"","reach physical pickup lifecycle boundary")
			if boundary=="waiting": reached = runtime.service.customers.record(2).get("target")=="pickup:1"
			elif boundary=="collect":
				for delivery in runtime.service.snapshot().deliveries:
					if delivery.phase=="collect": reached = true
			else:
				var actor: Dictionary = runtime.service.customers.record(2)
				reached = actor.get("target")=="pickup:0" and actor.walking and runtime.service.orders.guest(2).order>0
			if reached: break
		check(reached,"real boundary reached: "+boundary)
		if not reached: return
		var reopened := _resumed(runtime,template)
		for tick in 500:
			check_eq(runtime.step(0.1),"","continuous physical queue")
			check_eq(reopened.step(0.1),"","restored physical queue")
		check_eq(reopened.snapshot(),runtime.snapshot(),"same derived positions, claims, meals and actors after "+boundary)
		check_eq(reopened.runner.owner.revenue,runtime.runner.owner.revenue,"same actual receipts")

func test_pickup_frame_is_detached_and_unknown_or_stale_target_restore_is_atomic() -> void:
	var runtime := _runtime()
	if runtime==null: return
	_arrive(runtime)
	_advance(runtime,100)
	var before: Dictionary = runtime.snapshot()
	var frame: Dictionary = runtime.frame()
	frame.pickup_targets[2] = "pickup:0"
	check_eq(runtime.snapshot(),before,"view edit cannot mutate target assignment")
	var invalid: Dictionary = before.duplicate(true)
	invalid.service.customers.customers[1].target = "pickup:0"
	check(not runtime.restore(invalid).is_empty(),"a stale queue target is inconsistent with authoritative order phases")
	check_eq(runtime.snapshot(),before,"failed adoption leaves stock and actors unchanged")

func test_invalid_duplicate_partial_and_unused_pickup_definitions_fail_closed() -> void:
	for raw in [{"ports":["pickup:0","pickup:0"]},{"ports":["pickup:0"]},{"ports":["pickup:0","pickup:1"],"callback":"move"}]:
		var template := _definition()
		template.service.pickup_queue = raw
		check(not Compiler.compile(template).errors.is_empty(),"invalid pickup definition rejected")
	var template := _definition()
	template.service.delivery = "table"
	template.service.pickup = ""
	check(not Compiler.compile(template).errors.is_empty(),"table service cannot silently consume pickup queue settings")
	template = _definition()
	template.service.pickup_queue.ports[1] = "pickup:missing"
	check(not Runtime.new(_owner(),template).last_error.is_empty(),"unknown customer waiting anchor rejected")
	var owner := _owner()
	owner.shop.layout.customer_points["pickup:1"] = owner.shop.layout.customer_points["pickup:0"]
	check(not Runtime.new(owner,_definition()).last_error.is_empty(),"duplicate physical points cannot pretend to separate people")

func test_missing_pickup_capability_keeps_original_common_target_and_compiler_identity() -> void:
	var template := Fixture.definition("self_pickup")
	var before: Dictionary = Compiler.compile(template).definition
	template.service["pickup_queue"] = {}
	check_eq(Compiler.compile(template).definition,before,"empty ability adds no compiled fields")
	var runtime := Runtime.new(Fixture.owner(),template)
	check_eq(runtime.last_error,"","old template remains valid")
	if not runtime.last_error.is_empty(): return
	check(not runtime.frame().has("pickup_targets"),"disabled ability adds no view fields")
	runtime.arrive([{"dish":"lemonade","qty":1}])
	_advance(runtime,50)
	check_eq(runtime.service.customers.record(1).target,"pickup","old default remains exact")

func test_pickup_point_order_is_structural_and_not_an_economic_tuning_field() -> void:
	var template := _definition()
	var before: Dictionary = Contract.describe_template(template)
	template.service.pickup_queue.ports.reverse()
	check(Contract.describe_template(template).structure!=before.structure,"moving rank to a different physical point changes route identity")

func test_later_ready_order_can_collect_from_its_own_slot_without_taking_front_guests_food() -> void:
	var template := _definition()
	template.recipes.drink.nodes[1].seconds = 30.0
	template.recipes.side.nodes[1].machine = "b"
	var runtime := _runtime(template)
	if runtime==null: return
	runtime.arrive([{"dish":"lemonade","qty":1}])
	runtime.arrive([{"dish":"black_tea","qty":1}])
	for tick in 800:
		check_eq(runtime.step(0.1),"","independent recipe finishes out of waiting order")
		for delivery in runtime.service.snapshot().deliveries:
			if runtime.service.orders.order(delivery.order).guest==2 and delivery.phase=="carry":
				check_eq(runtime.service.customers.record(2).target,"seat:dine/1","second guest goes to own table after taking own meal")
				check_eq(runtime.service.customers.record(1).target,"pickup:0","waiting first guest retains front position")
				check_eq(runtime.frame().pickup_targets,{1:"pickup:0"},"carrying second guest no longer occupies a waiting rank")
				check_eq(runtime.service.orders.order(runtime.service.orders.guest(1).order).lines[0].delivered,0,"first meal is neither stolen nor fabricated")
				var group: Dictionary = runtime.runner.inventory.bundle(delivery.bundle)
				for claim in group.claims: check_eq(runtime.runner.inventory.claim(claim).allocate_owner,2,"collected stock belongs to second production unit")
				return
	check(false,"second meal can leave before unfinished first meal")

func test_partially_timed_collection_pauses_while_guest_walks_forward_and_restores_exactly() -> void:
	var template := _definition()
	template.hop_seconds = 3.0
	template.places["pass"].initial = {"drink":1,"side":1}
	for row in [["drink","drink"],["side","side"]]:
		template.recipes[row[0]] = {"nodes":[{"id":"ready","capability":"source","place":"pass","item":row[1]}],
			"output":{"node":"ready","item":row[1],"count":1}}
	var owner := _owner()
	owner.shop.layout.customer_points["pickup:1"] = Vector2(340,500)
	var runtime := Runtime.new(owner,template)
	check_eq(runtime.last_error,"","direct shared pickup source with explicit collection clock")
	if not runtime.last_error.is_empty(): return
	for worker in owner.workers: worker.deployed = false
	runtime.arrive([{"dish":"lemonade","qty":1}])
	runtime.arrive([{"dish":"black_tea","qty":1}])
	for tick in 500:
		check_eq(runtime.step(0.1),"","reach partially collected guest advancing")
		var actor: Dictionary = runtime.service.customers.record(2)
		if actor.get("target")!="pickup:0" or not actor.walking: continue
		for delivery in runtime.service.snapshot().deliveries:
			if runtime.service.orders.order(delivery.order).guest!=2 or delivery.phase!="collect" or delivery.left>=3.0: continue
			var remaining: float = delivery.left
			var bundle: Dictionary = runtime.runner.inventory.bundle(delivery.bundle)
			check_eq(runtime.runner.inventory.claim(bundle.claims[0]).state,"reserved","no hand stock before completed collection at new target")
			check_eq(runtime.step(0.1),"","walk toward promoted waiting point")
			for current in runtime.service.snapshot().deliveries:
				if current.order==delivery.order: check_eq(current.left,remaining,"walking does not consume collection work")
			check_eq(runtime.restore(runtime.snapshot()),"","partial clock and promoted target restore together")
			return
	check(false,"two real collection clocks overlap before first departure")
