extends "res://tests/test_case.gd"
const PATH := "res://content/shops/stirfry/shared_production.tres"
const SHOP: SpecShop = preload("res://content/shops/stirfry/shop.tres")
const Runtime := preload("res://game/rules/template/runtime.gd")

func _template() -> Resource:
	check(ResourceLoader.exists(PATH),"actual third shop needs explicit production and service data")
	return load(PATH).duplicate_deep(Resource.DEEP_DUPLICATE_ALL) if ResourceLoader.exists(PATH) else null

func _owner() -> ShopRules:
	var owner := ShopRules.new(SHOP.copy_for_editing(),42)
	owner.gold = 1000000.0
	for index in SHOP.stages.size(): check_eq(owner.unlock(SHOP.sold_at(index)),"","prepare actual shop stage via public unlock")
	return owner

func _runtime(template: Resource) -> RefCounted:
	var runtime := Runtime.new(_owner(),template)
	check_eq(runtime.last_error,"","actual seven-dish graph composes common service")
	return runtime if runtime.last_error.is_empty() else null

func _take(runtime: RefCounted) -> void:
	for tick in 1000:
		check_eq(runtime.step(0.1),"","actual front employee takes order")
		if runtime.service.orders.guest(1).order>0: return
	check(false,"front employee completed admission")

func _finish(runtime: RefCounted) -> void:
	for tick in 6000:
		check_eq(runtime.step(0.1),"","actual production, staging and self-pickup")
		if runtime.service.orders.guest(1).state=="gone": return
	check(false,"actual customer collected whole order, ate and left")

func test_real_resource_keeps_self_pickup_and_declares_seven_dishes_six_stages_and_purchase_pool() -> void:
	var template := _template()
	if template==null: return
	check_eq(template.recipes.size(),7,"all authored recipes preserved")
	check_eq(template.service.menu.size(),7,"all menu products mapped")
	check_eq(template.service.delivery,"self_pickup","retain actual third-shop fulfillment")
	check_eq(template.service.selection.at,"admission","food chosen after employee work")
	check_eq(template.service.seating.order.size(),16,"complete purchasable seat pool")
	check_eq(template.service.seating.stages.size(),6,"six actual queue and meal stages")
	var runtime := _runtime(template)
	if runtime==null: return
	check_eq(runtime.service.queue_capacity(),6,"actual queue capacity instead of all eight layout ports")
	check_eq(runtime.service.seating.seats(runtime.runner.owner).size(),6,"only six initial seats are available")

func test_actual_idle_counter_helps_kitchen_logistics_but_stays_for_approaching_guest() -> void:
	var template := _template()
	if template==null: return
	var runtime := _runtime(template)
	if runtime==null: return
	var front: Dictionary = runtime.runner.owner.workers[1]
	check_eq(front.post,"counter","actual posted front employee")
	runtime.request_production("tomato_rice")
	runtime.request_production("tomato_rice")
	var candidates: Array = runtime.candidates_for(front.id)
	check(not candidates.is_empty(),"front can assist available kitchen transport")
	for candidate in candidates: check(candidate.kind in ["transfer","bundle"],"helper never cooks in the kitchen")
	if not candidates.is_empty(): check(candidates[0].kind=="bundle" and candidates[0].entries.size()>1,"actual kitchen inputs reuse common compatible batch transport")
	runtime.arrive([])
	check_eq(runtime.candidates_for(front.id),[],"approaching unselected visitor holds front at counter")

func test_plum_juice_is_made_by_front_employee_and_never_draws_or_produces_implicit_soup() -> void:
	var template := _template()
	if template==null: return
	template.service.selection.stages[5].weights = {"plum_juice":1.0}
	template.service.selection.addon.share = 1.0
	var runtime := _runtime(template)
	if runtime==null: return
	var expected := RandomNumberGenerator.new()
	expected.state = runtime.runner.owner.rng.state
	expected.randf()
	check_eq(runtime.arrive([]).error,"","unselected actual visitor")
	_take(runtime)
	check_eq(runtime.service.orders.guest(1).request.size(),1,"front-only order has no kitchen addon")
	check_eq(runtime.runner.owner.rng.state,expected.state,"only primary draw; no skipped soup probability draw")
	var saw_front := false
	for tick in 1500:
		check_eq(runtime.step(0.1),"","front makes actual plum juice")
		for worker in runtime.runner.owner.workers:
			if worker.post=="counter" and not runtime.runner.idle(worker.id):
				var task: Dictionary = runtime.runner.tasks[worker.id]
				if task.kind=="operate" and runtime.runner.machines.run(task.run).machine=="plum_dispenser": saw_front = true
		if runtime.service.orders.guest(1).state=="gone": break
	check(saw_front,"counter employee actually used the common dispenser operation")
	check_eq(runtime.runner.owner.sold_by_dish.plum_juice,1,"real drink sale")
	check_eq(runtime.runner.owner.sold_by_dish.soup,0,"no unwanted soup sale")
	check_eq(runtime.snapshot().units.size(),1,"no hidden second production unit")

func test_actual_rice_and_soup_merge_use_whole_customer_pickup_then_paid_meal() -> void:
	var template := _template()
	if template==null: return
	template.service.selection.stages[5].weights = {"tomato_rice":1.0}
	template.service.selection.addon.share = 1.0
	var runtime := _runtime(template)
	if runtime==null: return
	runtime.arrive([])
	_take(runtime)
	var guest: Dictionary = runtime.service.orders.guest(1)
	check_eq(guest.request.size(),2,"same-service food order adds the declared soup")
	check_eq(guest.request[0].dish,"tomato_rice","main remains first")
	check_eq(guest.request[1].dish,"soup","soup is separate owned line")
	_finish(runtime)
	check_eq(runtime.runner.owner.sold_by_dish.tomato_rice,1,"two-input rice-and-topping main was really delivered")
	check_eq(runtime.runner.owner.sold_by_dish.soup,1,"soup physically collected and consumed")
	check_eq(runtime.runner.owner.sold,2,"no double-counted addon or merge branches")
	check(runtime.service.orders.order(guest.order).paid,"common whole-order delivery receipt")
	check_eq(runtime.runner.inventory.audit(),[],"single authoritative inventory conserves both lines")

func test_real_stage_menu_weights_match_existing_queries_and_front_drink_qualification() -> void:
	var template := _template()
	if template==null: return
	var runtime := _runtime(template)
	if runtime==null: return
	for stage in 6:
		runtime.runner.owner.stage_index = stage
		check_eq(runtime.service.menu_weights(),runtime.runner.owner.order_weights(),"configured actual weights and recipe gates match current stage")

func test_actual_queue_restore_before_sampling_keeps_empty_request_rng_and_future_order() -> void:
	var template := _template()
	if template==null: return
	var runtime := _runtime(template)
	if runtime==null: return
	runtime.arrive([])
	for tick in 10: check_eq(runtime.step(0.1),"","unselected visitor approaches real counter")
	var before_rng: int = runtime.runner.owner.rng.state
	check_eq(runtime.restore(runtime.snapshot()),"","actual unresolved queue and employee state restore")
	check_eq(runtime.runner.owner.rng.state,before_rng,"restore consumes no food draw")
	check_eq(runtime.service.orders.guest(1).request,[],"still unselected before admission")
	_take(runtime)
	check(not runtime.service.orders.guest(1).request.is_empty(),"one real frozen request after resumed employee work")

func test_real_pickup_queue_declares_all_existing_waiting_points_in_original_rank_order() -> void:
	var template := _template()
	if template==null: return
	check(template.service.has("pickup_queue"),"actual self-pickup scene needs explicit waiting point configuration")
	if not template.service.has("pickup_queue"): return
	var expected: Array = []
	for index in 16: expected.append("pickup:"+str(index))
	check_eq(template.service.pickup_queue.ports,expected,"reuse every original customer anchor in waiting rank order")
	for port in expected: check(SHOP.layout.customer_points.has(port),"no invented art or geometry point")

func test_real_drink_then_meal_customers_wait_separately_then_advance_and_complete_common_pickup() -> void:
	var template := _template()
	if template==null: return
	check(template.service.has("pickup_queue"),"real customer waiting points must be enabled")
	if not template.service.has("pickup_queue"): return
	template.service.selection.stages[4].weights = {"plum_juice":1.0}
	template.service.selection.stages[5].weights = {"tomato_rice":1.0}
	template.service.selection.addon.share = 0.0
	var runtime := _runtime(template)
	if runtime==null: return
	runtime.runner.owner.stage_index = 4
	for index in 2: runtime.arrive([])
	var saw_second := false
	var saw_advance := false
	for tick in 3000:
		check_eq(runtime.step(0.1),"","real drink service at original scene pickup positions")
		if runtime.service.orders.guest(1).order>0: runtime.runner.owner.stage_index = 5
		var second: Dictionary = runtime.service.customers.record(2)
		if second.get("target")=="pickup:1": saw_second = true
		if saw_second and second.get("target")=="pickup:0": saw_advance = true
		if runtime.service.orders.guest(2).state=="gone": break
	check(saw_second and saw_advance,"second guest physically uses two successive original waiting points")
	check_eq(runtime.service.orders.guest(2).state,"gone","both customers really finish pickup, meals and departure")
	check_eq(runtime.runner.owner.sold_by_dish.plum_juice,1,"first real drink sold once")
	check_eq(runtime.runner.owner.sold_by_dish.tomato_rice,1,"next real meal sold once")
	check_eq(runtime.runner.owner.sold_by_dish.soup,0,"pickup queue never creates an unrelated addon")
	check_eq(runtime.runner.inventory.audit(),[],"queue geometry adds no inventory backend")

func test_real_frame_exposes_the_same_configured_queue_capacity_as_admission() -> void:
	var template := _template()
	if template==null: return
	var runtime := _runtime(template)
	if runtime==null: return
	check_eq(runtime.frame().get("queue_capacity"),6,"display receives real six-person service limit instead of eight layout ports")
	check_eq(runtime.frame().get("queue_capacity"),runtime.service.queue_capacity(),"view and admission share one derived capacity")

func test_real_posted_wok_employee_cooks_while_floating_helper_can_feed_and_plate() -> void:
	var template := _template()
	if template==null: return
	check(template.dispatch.has("station_posts"),"actual third shop needs declared wok posts")
	if not template.dispatch.has("station_posts"): return
	template.service.selection.stages[5].weights = {"tomato_rice":1.0}
	template.service.selection.addon.share = 0.0
	var owner := _owner()
	var seated := -1
	for worker in owner.workers:
		if worker.post!="counter": seated = worker.id
	check_eq(owner.place_worker(seated,"wok_a"),"","post real cook at wok A")
	check_eq(owner.hire(),"","recruit shared logistics and plating helper")
	for worker in owner.roster:
		if not worker.deployed: check_eq(owner.deploy_worker(worker.id),"","deploy helper")
	var runtime := Runtime.new(owner,template)
	check_eq(runtime.last_error,"","posted wok data composes common production")
	if not runtime.last_error.is_empty(): return
	runtime.arrive([])
	var saw_operation := false
	for tick in 3000:
		check_eq(runtime.step(0.1),"","post owner cooks, helper feeds and combines")
		for task in runtime.runner.tasks.values():
			if task.kind=="operate" and runtime.runner.machines.run(task.run).machine=="wok_a":
				saw_operation = true
				check_eq(task.worker,seated,"floating cook cannot steal posted wok work")
		if runtime.service.orders.guest(1).state=="gone": break
	check(saw_operation,"real dish uses shared posted-machine operation")
	check_eq(owner.sold_by_dish.tomato_rice,1,"material feeding, two-input plating and self-pickup still finish")
