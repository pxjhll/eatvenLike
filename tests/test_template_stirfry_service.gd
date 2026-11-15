extends "res://tests/test_case.gd"
const TemplateOuter := preload("res://tests/fixtures/template_outer.gd")
const PATH := "res://content/shops/stirfry/shared_production.tres"
const SHOP: SpecShop = preload("res://content/shops/stirfry/shop.tres")
const Runtime := preload("res://game/rules/template/runtime.gd")

func _template() -> Resource:
	check(ResourceLoader.exists(PATH),"actual third shop needs explicit production and service data")
	return load(PATH).duplicate_deep(Resource.DEEP_DUPLICATE_ALL) if ResourceLoader.exists(PATH) else null

func _owner() -> ShopRules:
	var owner := TemplateOuter.owner(SHOP.copy_for_editing(),42)
	owner.gold = 1000000.0
	for index in SHOP.stages.size(): check_eq(owner.unlock(SHOP.sold_at(index)),"","prepare actual shop stage via public unlock")
	check_eq(owner.unlock("soup_pot"),"","opt in to soup for the service fixture")
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

func test_opening_and_pantry_upgrades_unlock_one_wok_at_a_time() -> void:
	var rules := ShopRules.new(SHOP.copy_for_editing(),42)
	var view := ShopView.new(rules)
	check_eq(rules.next_unlock(),"plum_dispenser","guide starts at the front drink machine")
	check(not rules.unlock("wok_a").is_empty(),"wok A requires the shop to open")
	check_eq(rules.unlock("plum_dispenser"),"","open with the exact starting funds")
	check_eq(rules.gold,0.0,"opening cost is charged")
	check_eq(rules.menu(),["plum_juice"],"drink-only opening")
	check(not rules.station_unlocked("wok_a") and not rules.station_unlocked("wok_b"),"both woks stay closed on opening")
	for second in 180:
		if rules.gold >= 80.0: break
		rules.run(1.0)
	check(rules.gold>=80.0 and rules.sold_by_dish.plum_juice==10,"ten real drink sales fund the first wok")
	check(not rules.unlock("wok_b").is_empty(),"cannot skip to wok B even with enough gold")
	check_eq(rules.unlock("wok_a"),"","open the first hot-food line")
	check(rules.station_unlocked("wok_a") and not rules.station_unlocked("wok_b"),"first kitchen phase only has wok A")
	check(rules.runtime.service.menu_weights().has("tomato_rice"),"the first cover rice dish can be ordered")
	check_eq(rules.next_unlock(),"pantry","guide points to the pantry")
	check(not view.station("wok_a").sections.has("recipes"),"wok A only shows its station controls")
	var pantry: Dictionary = view.station("pantry")
	check(pantry.sections.has("recipes"),"actual pantry panel shows recipe upgrades")
	check_eq(pantry.level,1,"pantry starts at level one")
	check_eq(pantry.get("recipes",[]).map(func(row: Dictionary) -> String: return row.dish),
		["pepper_rice","egg_fried_rice","kungpao_rice","yangzhou_rice"],"pantry shows the four stages in acquisition order")
	check(not rules.unlock("wok_b").is_empty(),"wok B requires the preceding pantry level")
	rules.gold = 79.0
	check(not rules.unlock("pantry").is_empty(),"upgrade requires enough coins")
	rules.gold = 80.0
	check_eq(rules.unlock("pantry"),"","buy the next pantry level")
	check_eq(rules.gold,0.0,"charge the exact upgrade price")
	check_eq(view.station("pantry").level,2,"purchased stage determines pantry level")
	check(rules.runtime.service.menu_weights().has("pepper_rice"),"upgrade adds the dish to the real order pool")
	check_eq(rules.next_unlock(),"wok_b","next machine still unlocks in order")
	rules.gold = 1000.0
	check(not rules.unlock("pantry").is_empty(),"egg recipe cannot be bought before wok B")
	check_eq(rules.unlock("wok_b"),"","unlock the second wok separately")
	check(not view.station("wok_b").sections.has("recipes"),"wok B only shows its station controls")
	check(not rules.runtime.service.menu_weights().has("egg_fried_rice"),"equipment alone does not add fried rice")
	check_eq(rules.unlock("pantry"),"","upgrade the pantry to add egg fried rice")
	check_eq(view.station("pantry").level,3,"pantry shows new level")
	check(rules.runtime.service.menu_weights().has("egg_fried_rice"),"fried rice can now be ordered")
	check(not rules.runtime.service.menu_weights().has("yangzhou_rice"),"later fried rice stays locked")

func test_pork_rib_soup_is_a_standalone_purchase() -> void:
	var rules := ShopRules.new(SHOP.copy_for_editing(),42)
	rules.gold = 1000.0
	for id in ["plum_dispenser","wok_a","pantry","wok_b"]: check_eq(rules.unlock(id),"","open the prerequisite equipment")
	check(not rules.unlock("soup_pot").is_empty(),"pot needs the egg fried rice stage")
	check_eq(rules.unlock("pantry"),"","unlock egg fried rice")
	check_eq(rules.next_unlock(),"pantry","optional pot does not appear in progression")
	check_eq(rules.unlock("pantry"),"","unlock kung pao without buying soup")
	check_eq(rules.unlock("pantry"),"","unlock the last main without the pot")
	check(not rules.station_unlocked("soup_pot"),"pot stays closed after the final main")
	var card := ShopView.new(rules).station("soup_pot")
	check_eq(card.unlock.dish,"排骨汤","optional purchase previews the actual soup")
	check_eq(card.unlock.dish_price,14.0,"pork rib soup base price")
	check_eq(rules.runtime._definition.service.selection.addon.share,0.4,"forty percent addon chance")
	var stage := rules.stage_index
	rules.gold = 219.0
	check(not rules.unlock("soup_pot").is_empty(),"cannot buy below the price")
	rules.gold = 220.0
	check_eq(rules.unlock("soup_pot"),"","buy the optional station through the public command")
	check_eq(rules.gold,0.0,"charge the equipment once")
	check_eq(rules.stage_index,stage,"standalone purchase does not move the main stage")
	check(not rules.unlock("soup_pot").is_empty(),"repeat optional purchase is rejected")
	var restored := ShopRules.new(SHOP.copy_for_editing(),42)
	check_eq(restored.load_dict(rules.to_dict()),"","optional unlock can be saved")
	check(restored.station_unlocked("soup_pot"),"saved optional unlock remains owned")

func test_third_shop_uses_the_drink_and_batch_clock_baseline() -> void:
	var template := _template()
	if template==null: return
	check_eq(template.recipes.plum_juice.nodes[0].seconds,2.0,"two-second pour in shared production")
	check_eq(template.restocks.rice_cooker.seconds,30.0,"automatic rice batch uses the tea-shop clock")
	check_eq(template.restocks.rice_cooker.produces,{"rice":4},"four servings per base batch")
	check_eq(template.places["rice_cooker:out"].initial,{"rice":4},"initial cooked rice is already in stock")
	check_eq(template.places["rice_cooker:out"].capacity,8,"base rice inventory cap")
	check(SHOP.background_music!=null,"formal shop supplies music to the shared audio player")
	for station_id in ["wok_a","wok_b"]:
		for level in SHOP.station(station_id).tracks[0].levels:
			for effect in level.effects:
				check_eq(effect.kind,"speed",station_id + " current upgrade changes cook time, not dish price")

func _previous_shop() -> SpecShop:
	var old_shop: SpecShop = load("res://tests/fixtures/legacy_shops/current/stirfry/shop.tres").copy_for_editing()
	var template := _template()
	template.recipes.plum_juice.nodes[0].seconds = 3.0
	template.restocks.rice_cooker.seconds = 60.0
	var soup_stage: Dictionary = template.service.selection.stages[4].duplicate(true)
	soup_stage.interval = 9.23
	template.service.selection.stages.insert(5,soup_stage)
	template.service.selection.stages.remove_at(3)
	template.service.selection.stages.remove_at(0)
	template.service.selection.stages[0].interval = 20.0
	template.service.selection.stages[1].interval = 13.33
	template.service.selection.stages[2].interval = 10.91
	template.service.seating.stages.resize(6)
	var gates: Dictionary = template.service.selection.gates
	for id in ["egg_fried_rice","pepper_rice","kungpao_rice","yangzhou_rice"]: gates[id].erase("levels")
	gates.pepper_rice["stage"] = 1
	gates.kungpao_rice["stage"] = 4
	gates.yangzhou_rice["stage"] = 5
	old_shop.runtime_template = template
	return old_shop

func test_previous_third_shop_preserves_purchases_and_in_progress_rice() -> void:
	var old_rules := ShopRules.new(_previous_shop(),42)
	var loaded := ShopRules.new(SHOP.copy_for_editing(),42)
	check_eq(loaded.load_dict(old_rules.to_dict(),true),"","previous unopened shop can be migrated")
	check_eq(loaded.next_unlock(),"plum_dispenser","old unopened shop starts on the new opening")
	check_eq(loaded.gold,12.0,"old unopened shop can afford opening")
	old_rules.gold = 1000.0
	for id in ["wok_a","wok_a","wok_b"]: check_eq(old_rules.unlock(id),"","purchase with the previous progression")
	check_eq(old_rules.unlock("soup_pot"),"","buy the former mandatory soup pot")
	old_rules.run(3.0)
	var saved := old_rules.to_dict()
	check_eq(saved.template.structure,SHOP.previous_progression.template_structure,"test uses the exact previous runtime structure")
	check_eq(loaded.load_dict(saved,true),"","load a shop with already owned fried rice")
	check_eq(loaded.gold,old_rules.gold,"saved coins survive the update")
	check_eq(loaded.stage_index,4,"previous wok B buyers keep the already owned recipe")
	check(loaded.station_unlocked("soup_pot"),"owners keep the former mandatory soup pot")
	check_eq(ShopView.new(loaded).station("pantry").level,3,"migrated menu gives the corresponding pantry level")
	check(loaded.runtime.service.menu_weights().has("egg_fried_rice"),"previous fried rice remains in the order pool")
	check_eq(loaded.runtime.runner.machines.snapshot().runs,saved.runtime.runner.machines.runs,"already started jobs retain their times")
	check_eq(loaded.runtime._definition.restocks.rice_cooker.seconds,30.0,"new rice batches use the new timing")

func test_real_resource_keeps_self_pickup_and_declares_seven_dishes_and_purchase_pool() -> void:
	var template := _template()
	if template==null: return
	check_eq(template.recipes.size(),7,"all authored recipes preserved")
	check_eq(template.service.menu.size(),7,"all menu products mapped")
	check_eq(template.service.delivery,"self_pickup","retain actual third-shop fulfillment")
	check_eq(template.service.selection.at,"admission","food chosen after employee work")
	check_eq(template.service.seating.order.size(),16,"complete purchasable seat pool")
	check_eq(template.service.seating.stages.size(),SHOP.stages.size(),"one queue and meal stage per progression stage")
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
	template.service.selection.stages[-1].weights = {"plum_juice":1.0}
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
	template.service.selection.stages[-1].weights = {"tomato_rice":1.0}
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
	for stage in SHOP.stages.size():
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

func test_real_drink_then_meal_customers_use_free_waiting_positions_and_complete_common_pickup() -> void:
	var template := _template()
	if template==null: return
	check(template.service.has("pickup_queue"),"real customer waiting points must be enabled")
	if not template.service.has("pickup_queue"): return
	template.service.selection.stages[4].weights = {"plum_juice":1.0}
	template.service.selection.stages[-1].weights = {"tomato_rice":1.0}
	template.service.selection.addon.share = 0.0
	var runtime := _runtime(template)
	if runtime==null: return
	runtime.runner.owner.stage_index = 4
	for index in 2: runtime.arrive([])
	var saw_second := false
	var saw_advance := false
	var saw_front := false
	for tick in 3000:
		check_eq(runtime.step(0.1),"","real drink service at original scene pickup positions")
		if runtime.service.orders.guest(1).order>0: runtime.runner.owner.stage_index = SHOP.stages.size()-1
		var second: Dictionary = runtime.service.customers.record(2)
		if second.get("target")=="pickup:1": saw_second = true
		if saw_second and second.get("target")=="pickup:0": saw_advance = true
		if second.get("target")=="pickup:0":
			saw_front = true
			var first_carrying := false
			for delivery in runtime.service.snapshot().deliveries:
				if delivery.order==runtime.service.orders.guest(1).order and delivery.phase in ["carry","drop"]: first_carrying = true
			check(first_carrying or runtime.service.orders.guest(1).state in ["served","eating","leaving","gone"],"front point is reused only after the first customer actually collects their order")
		if runtime.service.orders.guest(2).state=="gone": break
	check(saw_front and (not saw_second or saw_advance),"second guest uses the free front point and advances if it had to wait behind the first guest")
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
	template.service.selection.stages[-1].weights = {"tomato_rice":1.0}
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
