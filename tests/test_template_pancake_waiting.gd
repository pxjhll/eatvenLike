extends "res://tests/test_case.gd"
const SHOP: SpecShop = preload("res://content/shops/pancake/shop.tres")
const TEMPLATE := preload("res://content/shops/pancake/shared_production.tres")
const Runtime := preload("res://game/rules/template/runtime.gd")

func _owner(all_open := false) -> ShopRules:
	var owner := ShopRules.new(SHOP.copy_for_editing(),42)
	owner.gold = 100000.0
	check_eq(owner.unlock("soy_milk"),"","open original shop")
	if all_open:
		owner.stage_index = 4
		for id in ["rear_equipment","fryer","topping","bag"]: check_eq(owner.unlock(id),"","open actual station")
		check_eq(owner.unlock_box("flour"),"","install actual ingredients")
		for index in 3: check_eq(owner.upgrade("topping"),"","open actual flavors")
	return owner

func _runtime(owner: ShopRules) -> RefCounted:
	var runtime := Runtime.new(owner,TEMPLATE)
	check_eq(runtime.last_error,"","actual waiting policy compiles on original navigation")
	check(runtime.service != null and runtime.service.waiting != null,"actual pancake resource declares waiting capabilities")
	return runtime if runtime.last_error.is_empty() and runtime.service != null and runtime.service.waiting != null else null

func test_actual_stage_and_purchased_cushion_capacity_matches_original_public_query() -> void:
	var owner := _owner()
	var runtime := _runtime(owner)
	if runtime == null: return
	check_eq(runtime.service.queue_capacity(),3,"opening has three standing places")
	var expected := [3,6,9,15,15]
	for stage in 5:
		owner.stage_index = stage
		if stage in [1,2,3]: check_eq(owner.buy_seat(),"","buy original 2/3/4 cushions through public command")
		check_eq(runtime.service.queue_capacity(),expected[stage],"real stage plus purchased waiting capacity")
		check_eq(runtime.service.queue_capacity(),owner.queue_capacity(),"new public policy matches original queue query")
	check_eq(owner.wait_seats(),9,"three purchases install all nine actual cushions")

func test_actual_nine_cushions_hold_fifteen_guests_without_queue_port_fallback() -> void:
	var owner := _owner(true)
	for index in 3: check_eq(owner.buy_seat(),"","install actual cushion batch")
	var runtime := _runtime(owner)
	if runtime == null: return
	for index in 15: check_eq(runtime.arrive([{"dish":"soy","qty":1}],[]).error,"","six standing and nine actual wait places")
	check_eq(runtime.arrive([{"dish":"soy","qty":1}],[]).error,"queue full","sixteenth guest is rejected")
	var leases: Array = runtime.service.snapshot().waiting.leases
	check_eq(leases.size(),9,"all nine real waiting places are reserved distinctly")
	for index in 9:
		var target := "wait:cushion/"+str(index)
		check_eq(runtime.service.customers.record(index+7).target,target,"overflow follows actual original cushion target")
		check_eq(runtime.service.customers._target(target).point,SHOP.layout.customer_points[target],"uses original scene geometry")
	check_eq(SHOP.layout.customer_queue.size(),8,"original geometry is not rewritten to fake extra queue ports")

func test_real_cushion_waiting_and_return_to_counter_restore_without_duplicate_payment() -> void:
	var owner := _owner(true)
	for index in 3: check_eq(owner.buy_seat(),"","install actual cushions")
	var runtime := _runtime(owner)
	if runtime == null: return
	check_eq(runtime.arrive([{"dish":"family","qty":1},{"dish":"soy","qty":1}],["bag"]).error,"","real follower order")
	var seated := false
	for tick in 2000:
		check_eq(runtime.step(0.1),"","walk to a real cushion and wait during cooking")
		if runtime.service.customers.ready(1,"wait:cushion/0"):
			seated = true
			break
	check(seated,"customer actually reaches original cushion while food cooks")
	if not seated: return
	var reopened_owner := _owner(true)
	for index in 3: check_eq(reopened_owner.buy_seat(),"","prepare matching outer purchased capacity")
	for key in ["gold","revenue","sold","sale_carry"]: reopened_owner._sales.set(key,owner._sales.get(key))
	reopened_owner.sold_by_dish = owner.sold_by_dish.duplicate(true)
	reopened_owner.rng.state = owner.rng.state
	var reopened := _runtime(reopened_owner)
	if reopened == null: return
	check_eq(reopened.restore(runtime.snapshot()),"","restore real cushion lease and live actor route")
	var called := false
	for tick in 5000:
		check_eq(runtime.step(0.1),"","continue real order")
		check_eq(reopened.step(0.1),"","continue restored real order")
		var guest: Dictionary = runtime.service.orders.guest(1)
		if guest.state == "waiting" and runtime.service.customers.record(1).target == "pickup": called = true
		if guest.state == "gone": break
	check(called,"actual employee delivery calls seated guest back to pickup")
	check_eq(runtime.service.orders.guest(1).state,"gone","actual guest receives goods and exits")
	check_eq(reopened.snapshot(),runtime.snapshot(),"same actors, queue, physical inventory and payment proofs")
	check_eq(reopened_owner.revenue,owner.revenue,"real revenue restored and settled once")
