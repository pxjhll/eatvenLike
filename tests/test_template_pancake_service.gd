extends "res://tests/test_case.gd"
const SHOP: SpecShop = preload("res://content/shops/pancake/shop.tres")
const TEMPLATE := preload("res://content/shops/pancake/shared_production.tres")
const Runtime := preload("res://game/rules/template/runtime.gd")

func _owner(all_open := true) -> ShopRules:
	var owner := ShopRules.new(SHOP.copy_for_editing(),42)
	owner.gold = 100000.0
	check_eq(owner.unlock("soy_milk"),"","open real shop")
	if all_open:
		owner.stage_index = 4
		for id in ["rear_equipment","fryer","topping","bag"]: check_eq(owner.unlock(id),"","prepare real device")
		check_eq(owner.unlock_box("flour"),"","buy real flour box")
		for index in 6: check_eq(owner.upgrade("topping"),"","open actual flavor catalog")
	return owner

func _runtime(all_open := true) -> RefCounted:
	var runtime := Runtime.new(_owner(all_open),TEMPLATE)
	check_eq(runtime.last_error,"","actual recipe resource composes common customer service")
	check(runtime.service != null,"real pancake resource needs service configuration")
	return runtime if runtime.last_error.is_empty() and runtime.service != null else null

func _finish(runtime: RefCounted, guest: int) -> void:
	for tick in 7000:
		check_eq(runtime.step(0.1),"","actual cooking and service tick")
		if runtime.service.orders.guest(guest).state == "gone": return
	check(false,"real customer receives goods and reaches exit")

func test_real_bagged_pancake_with_plain_soy_addon_is_delivered_and_paid_once() -> void:
	var runtime := _runtime()
	if runtime == null: return
	var owner: ShopRules = runtime.runner.owner
	var expected: int = owner.order_price_single({"kind":"ham","addon":true,"options":["bag"]})
	var gold := owner.gold
	check_eq(runtime.arrive([{"dish":"ham","qty":1},{"dish":"soy","qty":1}],["bag"]).error,"","real primary plus additive soy")
	_finish(runtime,1)
	var order: Dictionary = runtime.service.orders.order(1)
	check_eq(order.lines[0].recipe,"ham:bag","only primary is wrapped")
	check_eq(order.lines[1].recipe,"soy","addon stays ordinary soy")
	check_eq(order.income,expected,"same whole-order quote as the original pancake rules")
	check_eq(owner.gold,gold+expected,"exactly one real payment")
	check_eq(owner.sold_by_dish.get("ham",0),1,"one main physically delivered")
	check_eq(owner.sold_by_dish.get("soy",0),1,"one addon physically delivered")
	check_eq(runtime.runner.inventory.snapshot().created.bagged,1,"real bag process ran once")
	check_eq(runtime.runner.inventory.audit(),[],"all delivered goods retain transaction proofs")

func test_opening_menu_blocks_unbought_flour_and_closed_devices_without_passive_frying() -> void:
	var runtime := _runtime(false)
	if runtime == null: return
	var before: Dictionary = runtime.snapshot()
	check(not runtime.arrive([{"dish":"plain","qty":1}],[]).error.is_empty(),"locked griddle cannot sell pancakes")
	check_eq(runtime.snapshot(),before,"closed dish request changes no queue or inventory")
	check_eq(runtime.arrive([{"dish":"soy","qty":1}],[]).error,"","opening drink remains available")
	_finish(runtime,1)
	for run in runtime.runner.machines.snapshot().runs: check(run.machine != "fryer","locked fryer cannot produce stock during opening")
	check_eq(runtime.runner.inventory.quantity("crisps","crisp"),4,"initial crisps retained while device is closed")
	check_eq(runtime.runner.owner.unlock("rear_equipment"),"","open griddle normally")
	check(not runtime.arrive([{"dish":"plain","qty":1}],[]).error.is_empty(),"griddle alone cannot replace purchased flour")
	check_eq(runtime.runner.owner.unlock_box("flour"),"","normal public purchase")
	check_eq(runtime.arrive([{"dish":"plain","qty":1}],[]).error,"","buying flour activates actual menu eligibility")
	_finish(runtime,2)
	check_eq(runtime.runner.owner.sold_by_dish.get("plain",0),1,"newly available dish is really produced and sold")

func test_real_automatic_menu_matches_legacy_primary_addon_and_bag_rng_order() -> void:
	var runtime := _runtime()
	if runtime == null: return
	var owner: ShopRules = runtime.runner.owner
	var expected := RandomNumberGenerator.new()
	expected.state = owner.rng.state
	expected.randf() # next exponential interval is scheduled before spawning
	var primary: String = preload("res://game/rules/rule_sampling.gd").choose(owner.order_weights(),expected)
	var addon: bool = primary != "soy" and expected.randf() < 0.3
	var options: Array = ["bag"] if expected.randf()<0.4 else []
	runtime.set_service_open(true)
	for tick in 15: check_eq(runtime.step(0.1),"","real first arrival delay")
	var request: Array = runtime.service.orders.guest(1).request
	check_eq(request[0].dish,primary,"same stable menu order and group share")
	check_eq(request.size(),2 if addon else 1,"same addon draw")
	check_eq(request[0].options,options,"same option draw after addon")
	check_eq(owner.rng.state,expected.state,"same exact outer RNG consumption")

func test_real_service_restores_during_preparation_and_actual_employee_delivery() -> void:
	for checkpoint in ["load","delivery"]:
		var runtime := _runtime()
		if runtime == null: return
		runtime.arrive([{"dish":"family","qty":1},{"dish":"soy","qty":1}],["bag"])
		var reached := false
		for tick in 6000:
			check_eq(runtime.step(0.1),"","reach real service save boundary")
			if checkpoint == "load":
				for run in runtime.runner.machines.snapshot().runs:
					if run.machine == "rear_equipment" and run.phase == "load": reached = true
			else:
				for delivery in runtime.service.snapshot().deliveries:
					if delivery.phase == "staff": reached = true
			if reached: break
		check(reached,"actual service reached "+checkpoint)
		if not reached: return
		var reopened := _runtime()
		if reopened == null: return
		for key in ["gold","revenue","sold","sale_carry"]: reopened.runner.owner._sales.set(key,runtime.runner.owner._sales.get(key))
		reopened.runner.owner.sold_by_dish = runtime.runner.owner.sold_by_dish.duplicate(true)
		reopened.runner.owner.rng.state = runtime.runner.owner.rng.state
		check_eq(reopened.restore(runtime.snapshot()),"","real order snapshot resumes at "+checkpoint)
		_finish(runtime,1)
		_finish(reopened,1)
		check_eq(reopened.snapshot(),runtime.snapshot(),"same actual goods, employee and customer after restore")
		check_eq(reopened.runner.owner.gold,runtime.runner.owner.gold,"payment stays once after restore")
		check_eq(reopened.runner.owner.revenue,runtime.runner.owner.revenue,"outer revenue stays consistent after service restore")

func test_actual_stage_weights_and_flavor_unlocks_match_original_menu_without_legacy_execution() -> void:
	var runtime := _runtime(false)
	if runtime == null: return
	var owner: ShopRules = runtime.runner.owner
	var selection: Dictionary = TEMPLATE.service.selection
	# Compare the new declarative policy to the original pure menu query, without
	# advancing an old shop loop or copying its live inventory/order state.
	var compiled: Dictionary = preload("res://game/rules/template/menu_selection.gd").compile(selection,TEMPLATE.service.menu)
	check_eq(compiled.error,"","actual stage catalog compiles")
	for stage in 5:
		owner.stage_index = stage
		var station: String = ["soy_milk","rear_equipment","fryer","topping","bag"][stage]
		if not owner.station_unlocked(station): check_eq(owner.unlock(station),"","open actual stage device")
		if stage == 1: check_eq(owner.unlock_box("flour"),"","install actual input")
		check_eq(preload("res://game/rules/template/menu_selection.gd").weights(compiled.definition,owner),owner.order_weights(),"new stage weights match original menu: "+str(stage))
	for index in 3:
		check_eq(owner.upgrade("topping"),"","open actual flavor using public upgrade")
		check_eq(preload("res://game/rules/template/menu_selection.gd").weights(compiled.definition,owner),owner.order_weights(),"newly opened flavor splits the existing group share")
