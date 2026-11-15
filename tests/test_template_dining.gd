extends "res://tests/test_case.gd"
const Fixture := preload("res://tests/fixtures/template_service.gd")
const Runtime := preload("res://game/rules/template/runtime.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")
const Contract := preload("res://game/rules/shop_content_contract.gd")

func _definition() -> Resource:
	var template := Fixture.definition()
	template.service.orders.queue_release = "after_delivery"
	template.service.erase("eat_seconds")
	template.service["dining"] = {"group":"dine","order":["seat:dine/0","seat:dine/1"],
		"stages":[{"standing":2,"seconds":20.0},{"standing":1,"seconds":30.0},{"standing":2,"seconds":30.0}],
		"takeaway":{"requires":{"stations":["seal"]},"variants":{"black_tea":"packed"}}}
	var packed: Dictionary = template.recipes.side.duplicate(true)
	packed.nodes[1].produces = {"packed_side":1}
	packed.output.item = "packed_side"
	template.recipes["packed"] = packed
	return template

func _owner() -> ShopRules:
	var owner := Fixture.owner()
	owner.shop.seat_groups[0].start = 1
	owner.shop.seat_groups[0].step = 1
	owner.shop.seat_groups[0].steps.clear()
	owner.shop.seat_groups[0].costs.assign([10])
	owner.seats.dine = 1
	owner.unlocked.lemonade = true
	owner.unlocked.seal = false
	owner.shop.layout.customer_points["seat:dine/1"] = Vector2(700,700)
	return owner

func _runtime(template: Resource = null) -> RefCounted:
	var runtime := Runtime.new(_owner(),_definition() if template==null else template)
	check_eq(runtime.last_error,"","counter dining composes shared service")
	return runtime if runtime.last_error.is_empty() else null

func _arrive(runtime: RefCounted, dish := "lemonade") -> int:
	var result: Dictionary = runtime.arrive([{"dish":dish,"qty":1}])
	check_eq(result.error,"","real customer arrival")
	return int(result.id)

func _advance(runtime: RefCounted, ticks: int) -> void:
	for tick in ticks: check_eq(runtime.step(0.1),"","advance actual common service")

func _restore(runtime: RefCounted, template: Resource) -> RefCounted:
	var owner := _owner()
	var original: RefCounted = runtime.runner.owner
	owner.seats = original.seats.duplicate()
	owner.unlocked = original.unlocked.duplicate()
	owner.stage_index = original.stage_index
	owner.levels = original.levels.duplicate()
	owner.nav.set_open(owner.unlocked)
	for key in ["gold","revenue","sold","sale_carry"]: owner._sales.set(key,original._sales.get(key))
	owner.sold_by_dish = original.sold_by_dish.duplicate(true)
	owner.rng.state = original.rng.state
	var resumed := Runtime.new(owner,template)
	check_eq(resumed.last_error,"","restore owner matches declared dining context")
	if not resumed.last_error.is_empty(): return null
	check_eq(resumed.restore(runtime.snapshot()),"","restore actual seat, motion, inventory and fulfillment together")
	return resumed

func test_arrival_leases_only_purchased_seat_and_starts_one_shared_order_before_seating() -> void:
	var runtime := _runtime()
	if runtime==null: return
	var id := _arrive(runtime)
	var guest: Dictionary = runtime.service.orders.guest(id)
	check_eq(guest.seat,"seat:dine/0","arrival leases first purchased seat")
	check_eq(guest.state,"waiting","production order exists while walking to the seat")
	check_eq(runtime.service.customers.record(id).target,guest.seat,"walks to wait at own dining seat")
	check(not runtime.service.customers.ready(id,guest.seat),"seat lease does not teleport visitor")
	check_eq(runtime.snapshot().units.size(),1,"one real production unit")
	check_eq(runtime.service.queue_capacity(),3,"standing capacity plus live seated waiting order")
	check_eq(runtime.service.snapshot().dining.routes,[{"guest":id,"takeaway":false}],"dining records only route choice; the seat lease stays in Orders")

func test_closed_takeaway_keeps_standing_visitors_unaccepted_until_a_seat_really_opens() -> void:
	var runtime := _runtime()
	if runtime==null: return
	_arrive(runtime)
	var second := _arrive(runtime,"black_tea")
	var third := _arrive(runtime)
	check_eq(runtime.service.orders.guest(second).order,-1,"full seats cannot promise a production route")
	check_eq(runtime.service.orders.guest(second).request[0].recipe,"side","dish choice frozen while route is pending")
	check_eq(runtime.service.customers.record(second).target,"queue:0","seated guest does not occupy a standing port")
	check_eq(runtime.service.customers.record(third).target,"queue:1","second standing visitor uses next physical port")
	check_eq(runtime.arrive([{"dish":"lemonade","qty":1}]).error,"queue full","standing plus leased seat is the true queue limit")
	check_eq(runtime.snapshot().units.size(),1,"pending route creates no speculative units")

func test_public_seat_purchase_admits_oldest_pending_visitor_without_resampling_or_overbooking() -> void:
	var runtime := _runtime()
	if runtime==null: return
	_arrive(runtime)
	var second := _arrive(runtime,"black_tea")
	var third := _arrive(runtime)
	var before_rng: int = runtime.runner.owner.rng.state
	runtime.runner.owner.gold = 10000.0
	check_eq(runtime.runner.owner.buy_seat(),"","purchase next real dining seat through public command")
	_advance(runtime,1)
	check_eq(runtime.service.orders.guest(second).seat,"seat:dine/1","oldest pending customer gets purchased seat")
	check_eq(runtime.service.orders.guest(third).order,-1,"same seat cannot admit two visitors")
	check_eq(runtime.service.orders.guest(second).request[0].dish,"black_tea","selected dish remains unchanged")
	check_eq(runtime.runner.owner.rng.state,before_rng,"seat purchase and routing add no menu draws")

func test_takeaway_unlock_resolves_pending_recipe_once_and_does_not_rewrite_seated_order() -> void:
	var runtime := _runtime()
	if runtime==null: return
	var seated := _arrive(runtime,"black_tea")
	var second := _arrive(runtime,"black_tea")
	runtime.runner.owner.gold = 10000.0
	check_eq(runtime.runner.owner.unlock("boil"),"","unlock the public prerequisite for sealing")
	check_eq(runtime.runner.owner.unlock("seal"),"","actual public takeaway unlock")
	# Legacy command opening side effects are outside this route transaction;
	# U06 must remove them before formal entry switches to the new runtime.
	var before_rng: int = runtime.runner.owner.rng.state
	_advance(runtime,1)
	check_eq(runtime.service.orders.guest(seated).request[0].recipe,"side","dining recipe remains unsealed")
	var request: Dictionary = runtime.service.orders.guest(second).request[0]
	check_eq(request.recipe,"packed","standing request resolves declared sealed graph")
	check_eq(request.item,"packed_side","delivery expects the graph's actual output")
	check_eq(runtime.snapshot().units.size(),2,"only one production created for the resolved order")
	check_eq(runtime.runner.owner.rng.state,before_rng,"route change adds no random draw")
	runtime.runner.owner.unlocked.seal = false
	_advance(runtime,1)
	check_eq(runtime.service.orders.guest(second).request[0],request,"already accepted route is frozen after gate closes")

func test_seated_guest_is_called_to_counter_only_after_a_real_delivery_claim_and_eats_after_return() -> void:
	var runtime := _runtime()
	if runtime==null: return
	var id := _arrive(runtime)
	var saw_seated := false
	var saw_call := false
	var saw_return := false
	for tick in 1200:
		check_eq(runtime.step(0.1),"","actual make, collect, handoff and return")
		var guest: Dictionary = runtime.service.orders.guest(id)
		var actor: Dictionary = runtime.service.customers.record(id)
		if guest.state=="waiting" and actor.target==guest.seat and runtime.service.customers.ready(id,guest.seat): saw_seated = true
		if guest.state=="waiting" and actor.target=="pickup":
			saw_call = true
			check(not runtime.service.snapshot().deliveries.is_empty(),"counter call derives from an actual stock claim")
		if guest.state=="served" and actor.target==guest.seat:
			saw_return = true
			check_eq(guest.meal_left,20.0,"meal duration frozen at handoff while return walk does not consume it")
		if guest.state=="eating":
			check(runtime.service.customers.ready(id,guest.seat),"only actual seating starts eating")
			check(saw_seated and saw_call and saw_return,"all three physical boundaries exercised")
			check_eq(runtime.runner.owner.sold,1,"single delivery counts sale once")
			return
	check(false,"visitor returned to eat")

func test_staff_cannot_drop_or_charge_while_called_customer_is_still_walking() -> void:
	var runtime := _runtime()
	if runtime==null: return
	# Slow customer through common movement units while keeping a long approach
	# from the seat; the staff port stays at the counter.
	var id := _arrive(runtime)
	var saw_held := false
	for tick in 1200:
		check_eq(runtime.step(0.1),"","staff and visitor approach actual handoff")
		var deliveries: Array = runtime.service.snapshot().deliveries
		if deliveries.is_empty(): continue
		var guest: Dictionary = runtime.service.orders.guest(id)
		var group: Dictionary = runtime.runner.inventory.bundle(deliveries[0].bundle)
		if runtime.runner.inventory.claim(group.claims[0]).state=="held" and not runtime.service.customers.ready(id,"pickup"):
			saw_held = true
			check_eq(runtime.runner.owner.revenue,0.0,"no premature payment")
			check_eq(runtime.service.orders.order(guest.order).lines[0].delivered,0,"no delivery proof before both actors arrive")
		if guest.state=="served": break
	check(saw_held,"fixture exercised staff holding goods before customer arrival")

func test_takeaway_uses_same_counter_delivery_and_leaves_without_claiming_a_table() -> void:
	var runtime := _runtime()
	if runtime==null: return
	runtime.runner.owner.unlocked.seal = true
	_arrive(runtime)
	var id := _arrive(runtime,"black_tea")
	check_eq(runtime.service.orders.guest(id).seat,"","overflow reserves no hidden table")
	for tick in 1600:
		check_eq(runtime.step(0.1),"","real takeaway service")
		var guest: Dictionary = runtime.service.orders.guest(id)
		if guest.state=="served": check_eq(runtime.service.customers.record(id).target,"exit","takeaway walks to exit after counter receipt")
		if guest.state=="gone":
			check(runtime.service.orders.order(guest.order).paid,"ordinary shared receipt paid")
			check_eq(runtime.runner.owner.sold_by_dish.black_tea,1,"sale belongs to original dish, not packaging item")
			return
	check(false,"takeaway customer left through actual exit")

func test_save_restore_matches_continuous_service_at_pending_waiting_called_returning_and_eating_boundaries() -> void:
	for boundary in ["pending","waiting","called","served","eating"]:
		var template := _definition()
		var runtime := _runtime(template)
		if runtime==null: return
		var id := _arrive(runtime)
		_arrive(runtime,"black_tea")
		var reached: bool = boundary=="pending"
		for tick in 1500:
			if reached: break
			check_eq(runtime.step(0.1),"","reach actual lifecycle boundary")
			var guest: Dictionary = runtime.service.orders.guest(id)
			var actor: Dictionary = runtime.service.customers.record(id)
			reached = (guest.state==boundary and (boundary!="waiting" or runtime.service.customers.ready(id,guest.seat))) or (boundary=="called" and guest.state=="waiting" and actor.target=="pickup")
		check(reached,"actual boundary reached: "+boundary)
		if not reached: return
		var resumed := _restore(runtime,template)
		if resumed==null: return
		for tick in 500:
			check_eq(runtime.step(0.1),"","continuous service")
			check_eq(resumed.step(0.1),"","resumed service")
		check_eq(resumed.snapshot(),runtime.snapshot(),"same seats, units, stock, meals and motion after "+boundary)
		check_eq(resumed.runner.owner.revenue,runtime.runner.owner.revenue,"same shared payment after "+boundary)

func test_meal_duration_is_committed_at_handoff_and_free_seat_is_reused_when_eating_finishes() -> void:
	var runtime := _runtime()
	if runtime==null: return
	var first := _arrive(runtime)
	var second := _arrive(runtime)
	for tick in 1600:
		check_eq(runtime.step(0.1),"","reach counter receipt")
		if runtime.service.orders.guest(first).state=="served": break
	check_eq(runtime.service.orders.guest(first).state,"served","return walk is observable")
	runtime.runner.owner.stage_index = 1
	for tick in 1000:
		check_eq(runtime.step(0.1),"","finish previously committed meal")
		var guest: Dictionary = runtime.service.orders.guest(first)
		if guest.state=="eating": check(guest.meal_left<=20.0,"later stage does not replace old meal with thirty seconds")
		if guest.state=="leaving":
			check_eq(runtime.service.orders.guest(second).seat,"seat:dine/0","finished meal releases seat before former diner reaches exit")
			return
	check(false,"meal completed and released seat")

func test_tampered_seat_route_and_movement_restore_fail_without_mutating_live_state() -> void:
	var runtime := _runtime()
	if runtime==null: return
	_arrive(runtime)
	var before: Dictionary = runtime.snapshot()
	for kind in ["unowned","route","motion"]:
		var invalid: Dictionary = before.duplicate(true)
		if kind=="unowned": invalid.service.orders.guests[0].seat = "seat:dine/1"
		elif kind=="route": invalid.service.orders.guests[0].seat = ""
		else: invalid.service.customers.customers[0].target = "pickup"
		check(not runtime.restore(invalid).is_empty(),"reject unrelated seat, missing dining route or unmatched target")
		check_eq(runtime.snapshot(),before,"failed restore preserves actual actors and stock")

func test_invalid_dining_configuration_and_outer_purchase_state_are_rejected() -> void:
	for patch in [{"order":["seat:dine/1"]},{"group":""},{"stages":[{"standing":0,"seconds":20.0}]},{"callback":"old_handoff"},{"takeaway":{"requires":{"stations":["seal"]},"variants":{"unknown":"packed"}}}]:
		var template := _definition()
		for key in patch: template.service.dining[key] = patch[key]
		check(not Compiler.compile(template).errors.is_empty(),"invalid dining capability")
	var template := _definition()
	template.service.delivery = "table"
	template.service.handoff_port = ""
	check(not Compiler.compile(template).errors.is_empty(),"counter dining cannot silently become table delivery")
	var runtime := _runtime()
	if runtime==null: return
	var before: Dictionary = runtime.snapshot()
	runtime.runner.owner.seats.dine = 99
	check(not runtime.step(0.1).is_empty(),"owned seats outside declared purchase capacity rejected")
	check_eq(runtime.snapshot(),before,"invalid outer purchase context does not advance anything")

func test_dining_duration_is_numeric_but_seat_order_queue_capacity_and_variants_are_structural() -> void:
	var template := _definition()
	var before: Dictionary = Contract.describe_template(template)
	template.service.dining.stages[0].seconds = 25.0
	check_eq(Contract.describe_template(template).structure,before.structure,"meal clock is tunable")
	check(Contract.describe_template(template).gameplay!=before.gameplay,"meal clock remains gameplay identity")
	template.service.dining.stages[0].standing = 1
	check(Contract.describe_template(template).structure!=before.structure,"physical queue capacity remains structural")

func test_takeaway_route_restores_after_gate_closure_without_replanning_packaging() -> void:
	var template := _definition()
	var runtime := _runtime(template)
	if runtime==null: return
	runtime.runner.owner.unlocked.seal = true
	_arrive(runtime)
	var id := _arrive(runtime,"black_tea")
	_advance(runtime,40)
	runtime.runner.owner.unlocked.seal = false
	var resumed := _restore(runtime,template)
	if resumed==null: return
	for tick in 600:
		check_eq(runtime.step(0.1),"","continue frozen takeaway")
		check_eq(resumed.step(0.1),"","resume frozen takeaway")
	check_eq(resumed.snapshot(),runtime.snapshot(),"closed gate does not replan accepted recipe or seat")
	check_eq(resumed.service.orders.guest(id).request[0].recipe,"packed","accepted sealed graph is retained")

func test_impossible_restored_meal_duration_is_rejected_before_actor_adoption() -> void:
	var runtime := _runtime()
	if runtime==null: return
	var id := _arrive(runtime)
	for tick in 1000:
		check_eq(runtime.step(0.1),"","reach return walk")
		if runtime.service.orders.guest(id).state=="served": break
	check_eq(runtime.service.orders.guest(id).state,"served","actual delivered meal not yet started")
	var before: Dictionary = runtime.snapshot()
	var invalid: Dictionary = before.duplicate(true)
	invalid.service.orders.guests[0].meal_left = 10000.0
	check(not runtime.restore(invalid).is_empty(),"a meal clock above every declared stage and tuning limit is impossible")
	check_eq(runtime.snapshot(),before,"rejected clock does not adopt inventory or actors")

func test_pending_route_resolution_cannot_replace_food_quantity_options_or_accepted_request() -> void:
	var runtime := _runtime()
	if runtime==null: return
	var first := _arrive(runtime)
	var pending := _arrive(runtime,"black_tea")
	var before: Dictionary = runtime.snapshot()
	for field in ["dish","qty","options"]:
		var request: Array = runtime.service.orders.guest(pending).request
		if field=="dish": request[0].dish = "lemonade"
		elif field=="qty": request[0].qty = 2
		else: request[0].options = ["invented"]
		check(not runtime.service.orders.resolve_request(pending,request).is_empty(),"route resolver only changes recipe and physical output identity")
		check_eq(runtime.snapshot(),before,"failed resolution is atomic")
	check(not runtime.service.orders.resolve_request(first,runtime.service.orders.guest(first).request).is_empty(),"accepted order cannot be re-resolved")
