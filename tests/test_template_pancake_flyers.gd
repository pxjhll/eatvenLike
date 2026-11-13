extends "res://tests/test_case.gd"
const TemplateOuter := preload("res://tests/fixtures/template_outer.gd")
const SHOP: SpecShop = preload("res://content/shops/pancake/shop.tres")
const TEMPLATE := preload("res://content/shops/pancake/shared_production.tres")
const Runtime := preload("res://game/rules/template/runtime.gd")

func _owner(all_open := false) -> ShopRules:
	var owner := TemplateOuter.owner(SHOP.copy_for_editing(),42)
	owner.gold = 100000.0
	check_eq(owner.unlock("soy_milk"),"","open actual shop")
	if all_open:
		owner.stage_index = 4
		for id in ["rear_equipment","fryer","topping","bag"]: check_eq(owner.unlock(id),"","open actual device")
		check_eq(owner.unlock_box("flour"),"","buy actual flour")
		for index in 3: check_eq(owner.upgrade("topping"),"","open actual flavors")
	return owner

func _runtime(owner: ShopRules) -> RefCounted:
	var runtime := Runtime.new(owner,TEMPLATE)
	check_eq(runtime.last_error,"","actual service compiles")
	check(runtime.service.flyers != null,"real pancake resource declares common flyer capability")
	return runtime if runtime.last_error.is_empty() and runtime.service.flyers != null else null

func test_actual_opening_flyer_wave_reuses_menu_queue_and_original_four_visitor_upgrade_base() -> void:
	var owner := _owner()
	var runtime := _runtime(owner)
	if runtime == null: return
	runtime.set_service_open(true)
	var expected := RandomNumberGenerator.new()
	expected.state = owner.rng.state
	expected.randf() # stable opening menu: only soy, still one primary draw
	check_eq(runtime.send_flyers(),"","send via new public command")
	check_eq(runtime.frame().flyers.pending,4,"original base upgrade sends four")
	check_eq(runtime.frame().flyers.cooldown,120.0,"original two-minute cooldown")
	check_eq(runtime.step(0.1),"","first actual flyer visitor")
	check_eq(runtime.service.orders.guest(1).request[0].dish,"soy","opening menu restrictions still apply")
	check_eq(owner.rng.state,expected.state,"no extra addon or locked bag random draw")
	check_eq(owner.flyer_left,0,"old flyer loop has no duplicate pending visitors")

func test_actual_flyer_purchase_changes_next_wave_without_overwriting_current_cooldown() -> void:
	var owner := _owner()
	var runtime := _runtime(owner)
	if runtime == null: return
	runtime.set_service_open(true)
	runtime.send_flyers()
	for tick in 10: check_eq(runtime.step(0.1),"","initial wave and cooldown")
	check_eq(owner.upgrade("flyer"),"","normal public flyer upgrade")
	check_eq(owner.flyer_customers(),5,"original first upgrade sends five")
	check_eq(owner.flyer_cooldown(),105.0,"original first upgrade cooldown")
	check(absf(runtime.frame().flyers.cooldown-119.0)<0.000001,"old two-minute cooldown keeps its committed remainder")
	var pending: int = runtime.frame().flyers.pending
	runtime.set_service_open(false)
	for tick in 1190: check_eq(runtime.step(0.1),"","unpaused cooldown runs while entry is closed")
	runtime.set_service_open(true)
	check_eq(runtime.send_flyers(),"","upgraded next wave")
	check_eq(runtime.frame().flyers.pending,pending+5,"new visitors append to still-pending old wave")
	check_eq(runtime.frame().flyers.cooldown,105.0,"new command uses upgraded cooldown")

func test_actual_flyer_primary_addon_and_bag_follow_original_outer_rng_order() -> void:
	var owner := _owner(true)
	var runtime := _runtime(owner)
	if runtime == null: return
	var expected := RandomNumberGenerator.new()
	expected.state = owner.rng.state
	var primary: String = preload("res://game/rules/rule_sampling.gd").choose(owner.order_weights(),expected)
	var addon: bool = primary!="soy" and expected.randf()<0.3
	var options: Array = ["bag"] if expected.randf()<0.4 else []
	runtime.set_service_open(true)
	runtime.send_flyers()
	check_eq(runtime.step(0.1),"","flyer uses same actual menu service")
	var request: Array = runtime.service.orders.guest(1).request
	check_eq(request[0].dish,primary,"same original weighted primary")
	check_eq(request.size(),2 if addon else 1,"same original addon roll")
	check_eq(request[0].options,options,"same original bag roll")
	check_eq(owner.rng.state,expected.state,"same number and order of random draws")
