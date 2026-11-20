extends "res://tests/test_case.gd"
const TemplateOuter := preload("res://tests/fixtures/template_outer.gd")
const PATH := "res://content/shops/stirfry/shared_production.tres"
const PREVIOUS: SpecShop = preload("res://content/examples/modular_shop.tres")
const OLD_LAYOUT: SpecLayout = preload("res://tests/fixtures/legacy_shops/current/stirfry/shop.tres").layout
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
	check_eq(owner.hire(),"","pay for the kitchen worker")
	check_eq(owner.deploy_worker(owner.roster.back().id),"","deploy the floating kitchen worker")
	return owner

func _runtime(template: Resource) -> RefCounted:
	var runtime := Runtime.new(_owner(),template)
	check_eq(runtime.last_error,"","actual eight-dish graph composes common service")
	return runtime if runtime.last_error.is_empty() else null

func _take(runtime: RefCounted) -> void:
	for tick in 1000:
		check_eq(runtime.step(0.1),"","real guest moves into automatic admission")
		if runtime.service.orders.guest(1).order>0: return
	check(false,"arrival produced an order without a front employee action")

func _finish(runtime: RefCounted) -> void:
	for tick in 6000:
		check_eq(runtime.step(0.1),"","actual production, staging and table service")
		if runtime.service.orders.guest(1).state=="gone": return
	check(false,"actual customer received the whole order, ate and left")

func test_opening_and_pantry_upgrades_unlock_one_wok_at_a_time() -> void:
	var rules := ShopRules.new(SHOP.copy_for_editing(),42)
	var view := ShopView.new(rules)
	check_eq(rules.roster.size(),1,"start with only the front employee")
	check_eq(rules.workers[0].post,"counter","opening employee operates the front counter")
	check_eq(rules.unlock("plum_dispenser"),"","open with the exact starting funds")
	check_eq(rules.gold,0.0,"opening cost is charged")
	check_eq(rules.menu(),["plum_juice"],"drink-only opening")
	check_eq(rules.next_unlock(),"wok_a","first major purchase is the wok")
	for second in 260:
		if rules.gold>=100.0: break
		rules.run(1.0)
	check_eq(rules.sold_by_dish.plum_juice,10,"opening front employee can earn both equipment costs from ten sales")
	check(rules.station_unlocked("plating"),"handoff is available from opening")
	check(SHOP.station("plating").tracks.is_empty(),"handoff has no upgrades")
	check(not rules.unlock("rice_cooker").is_empty(),"rice cooker follows the first wok")
	var balance := rules.gold
	check_eq(rules.unlock("wok_a"),"","buy first wok")
	check_eq(rules.gold,balance-80.0,"wok costs eighty coins")
	check(not rules.station_unlocked("rice_cooker") and not rules.station_unlocked("pantry") and not rules.station_unlocked("wok_b"),"wok purchase opens only the wok")
	check_eq(rules.menu(),["plum_juice"],"wok alone cannot sell rice")
	check_eq(rules.next_unlock(),"rice_cooker","rice has its own purchase")
	balance = rules.gold
	check_eq(rules.unlock("rice_cooker"),"","buy independent rice cooker")
	check_eq(rules.gold,balance-20.0,"rice cooker costs twenty coins")
	check_eq(rules.workers.size(),2,"the first kitchen worker is granted and deployed")
	check_eq(rules.hire_cost(),30,"gift does not advance the paid hire schedule")
	check(rules.menu().has("plain_fried_rice"),"rice and wok A are enough for plain fried rice")
	for second in 180:
		if rules.sold_by_dish.plain_fried_rice>0: break
		rules.run(1.0)
	check(rules.sold_by_dish.plain_fried_rice>0,"gifted kitchen worker makes and sells plain fried rice")
	check_eq(rules.next_unlock(),"pantry","the pantry is the next separate unlock")
	rules.gold = 1000.0
	check(not rules.unlock("wok_b").is_empty(),"cannot skip directly to the second wok")
	check_eq(rules.unlock("pantry"),"","buy the pantry")
	check(rules.menu().has("egg_fried_rice") and not rules.menu().has("yangzhou_rice"),"opening the pantry enables only ham fried rice")
	check_eq(SHOP.dish("egg_fried_rice").display_name,"火腿炒饭","the saved dish ID now presents ham fried rice")
	check_eq(SHOP.station("pantry").material("egg_rice_raw").display_name,"火腿丁","the existing pantry slot now supplies diced ham")
	var pantry: Dictionary = view.station("pantry")
	check_eq(pantry.level,1,"new pantry starts at level one")
	check("track" in pantry.sections and "recipes" not in pantry.sections,"cabinet uses a single machine upgrade with material prices underneath")
	var upgrade: Dictionary = pantry.get("track",{})
	check_eq(upgrade.get("cost"),80,"the machine card uses the existing progression price")
	check("扬州炒饭" in String(upgrade.get("effect","")),"cabinet previews its next dish")
	check_eq(rules.unlock("pantry"),"","upgrade the pantry for Yangzhou fried rice")
	check(rules.menu().has("yangzhou_rice"),"Yangzhou fried rice can be ordered with the first wok")
	check(not rules.menu().has("tomato_rice"),"covered rice still requires wok B")
	check_eq(rules.unlock("wok_b"),"","unlock wok B separately")
	check(rules.menu().has("tomato_rice"),"second wok offers its first covered rice")
	check(not rules.menu().has("pepper_rice"),"pepper covered rice still needs the pantry upgrade")
	check_eq(rules.unlock("pantry"),"","unlock pepper recipe")
	check_eq(rules.unlock("pantry"),"","unlock Kung Pao recipe")
	check_eq(view.station("pantry").level,4,"only the pantry unlocks the final two recipes")
	for id in ["wok_a","wok_b"]:
		check(not view.station(id).sections.has("recipes"),"wok only exposes its equipment upgrades")

func test_pork_rib_soup_is_a_standalone_purchase() -> void:
	var rules := ShopRules.new(SHOP.copy_for_editing(),42)
	rules.gold = 1000.0
	for id in ["plum_dispenser","wok_a","rice_cooker"]: check_eq(rules.unlock(id),"","open the prerequisite equipment")
	check(not rules.unlock("soup_pot").is_empty(),"pot needs the egg fried rice stage")
	check_eq(rules.unlock("pantry"),"","unlock egg fried rice")
	check_eq(rules.next_unlock(),"pantry","optional pot does not appear in progression")
	for id in ["pantry","wok_b","pantry","pantry"]: check_eq(rules.unlock(id),"","finish unlocking mains without the soup pot")
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
	check_eq(template.restocks.rice_cooker.batch.base,4,"four servings per base batch")
	check_eq(template.places["rice_cooker:out"].initial,{"rice":4},"initial cooked rice is already in stock")
	check_eq(template.places["rice_cooker:out"].capacity,8,"base rice inventory cap")
	check(SHOP.background_music!=null,"formal shop supplies music to the shared audio player")
	for station_id in ["wok_a","wok_b"]:
		for level in SHOP.station(station_id).tracks[0].levels:
			for effect in level.effects:
				check(effect.kind in ["speed","batch"],station_id + " upgrades work speed and same-recipe capacity")

func test_rice_upgrade_changes_real_batch_quantity_duration_and_capacity() -> void:
	var rules := ShopRules.new(SHOP.copy_for_editing(),42)
	rules.gold = 1000.0
	for id in ["plum_dispenser","wok_a","rice_cooker"]: check_eq(rules.unlock(id),"","buy the rice cooker independently")
	check_eq(rules.upgrade("rice_cooker"),"","upgrade through the shared machine command")
	rules.run(1.0)
	var run_id: int = rules.runtime._restocks.snapshot().runs.rice_cooker
	check(run_id>0,"the upgraded steamer actually runs")
	if run_id<1: return
	var run: Dictionary = rules.runtime.runner.machines.run(run_id)
	var claim: Dictionary = rules.runtime.runner.inventory.claim(run.claim)
	check_eq(claim.produces,{"rice":6},"first upgrade cooks six bowls")
	check(is_equal_approx(float(run.duration),30.0/1.12),"first upgrade reduces the real cook clock")
	check_eq(rules.runtime.runner.inventory.snapshot().places["rice_cooker:out"].capacity,12,"matching inventory capacity is applied")

func _previous_shop() -> SpecShop:
	var old_shop: SpecShop = load("res://tests/fixtures/legacy_shops/current/stirfry/shop.tres").copy_for_editing()
	var template := PREVIOUS.runtime_template.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
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
	check_eq(loaded.hire_cost(),old_rules.hire_cost(),"retaining the old free employee does not count as a paid hire")
	check_eq(loaded.current_stage().id,"pepper","migrate to the stage that retains the already owned dishes")
	check(loaded.station_unlocked("soup_pot"),"owners keep the former mandatory soup pot")
	check_eq(ShopView.new(loaded).station("pantry").level,3,"migrated menu gives the corresponding pantry level")
	check(loaded.runtime.service.menu_weights().has("egg_fried_rice"),"previous fried rice remains in the order pool")
	check_eq(loaded.runtime.runner.machines.snapshot().runs,saved.runtime.runner.machines.runs,"already started jobs retain their times")
	check_eq(loaded.runtime._definition.restocks.rice_cooker.seconds,30.0,"new rice batches use the new timing")

func test_real_resource_uses_table_service_and_declares_eight_dishes_and_purchase_pool() -> void:
	var template := _template()
	if template==null: return
	check_eq(template.service.previous_recipes.size(),6,"old hot dishes and soup remain available to saved orders")
	check_eq(template.service.menu.size(),8,"all menu products mapped")
	check_eq(template.service.delivery,"table","front employee delivers to the seated customer")
	check_eq(template.service.selection.at,"admission","food chosen on admission")
	check_eq(template.service.seating.order.size(),16,"complete purchasable seat pool")
	check_eq(template.service.seating.stages.size(),SHOP.stages.size(),"one queue and meal stage per progression stage")
	var runtime := _runtime(template)
	if runtime==null: return
	check_eq(runtime.service.queue_capacity(),6,"actual queue capacity instead of all eight layout ports")
	check_eq(runtime.service.seating.seats(runtime.runner.owner).size(),6,"only six initial seats are available")

func test_table_guests_face_inward_and_previous_progress_still_loads() -> void:
	var template := _template()
	if template == null: return
	var previous := PREVIOUS.copy_for_editing()
	previous.id = SHOP.id
	previous.layout = OLD_LAYOUT
	for index in 16:
		var port := "table/%d" % index
		var pose: Dictionary = template.presentation.poses["seat:" + port]
		check_eq(pose.offset,Vector2(0,18),"only the seated pose sits lower, at " + port)
		check_eq(pose.port,"Seats/" + port,"seated pose is attached to its own chair")
		check_eq(pose.facing,2 if index % 2 == 0 else 6,"diner faces the table from " + port)
		var before: Vector2 = previous.layout.customer_points["seat:" + port]
		var after: Vector2 = SHOP.layout.customer_points["seat:" + port]
		check_eq(after-before,Vector2(-26 if index % 2 == 0 else 26,0),"seat approach follows the chair at " + port)
	var old_rules := ShopRules.new(previous,42)
	check_eq(old_rules.unlock("plum_dispenser"),"","open the previous shop")
	var checked := {"walking":false,"eating":false}
	for tick in 1300:
		old_rules.run(0.1)
		var actor: Dictionary = old_rules.runtime.service.customers.record(1)
		if not String(actor.get("target","")).begins_with("seat:"): continue
		var phase := "walking" if actor.walking else "eating"
		if checked[phase]: continue
		if phase=="eating" and old_rules.runtime.service.orders.guest(1).state!="eating": continue
		var saved := old_rules.to_dict()
		check(SHOP.previous_progression.other_templates.has(saved.template.structure),"previous seating revision is covered by save migration")
		var restored := ShopRules.new(SHOP.copy_for_editing(),42)
		var error := restored.load_dict(saved,true)
		check_eq(error,"","previous save loads with guest " + phase)
		if not error.is_empty(): break
		check_eq(restored.stage_index,old_rules.stage_index,"keep the purchased stage")
		check_eq(restored.gold,old_rules.gold,"keep the saved wallet")
		var migrated: Dictionary = restored.runtime.service.customers.record(1)
		check_eq(migrated.motion.goal,SHOP.layout.customer_points[actor.target],"guest has the new approach point")
		check_eq(migrated.walking,actor.walking,"guest keeps walking or remains seated")
		for elapsed in 1200:
			restored.run(0.1)
			if restored.runtime.service.orders.guest(1).state=="gone": break
		check_eq(restored.runtime.service.orders.guest(1).state,"gone","restored guest finishes the meal and leaves")
		checked[phase] = true
		if checked.values().all(func(done: bool) -> bool: return done): break
	check(checked.walking and checked.eating,"both active save phases were exercised")
	var worker_id: int = old_rules.workers[0].id
	var old_position := Vector2(375,1110)
	check_eq(old_rules.place_worker(worker_id,"",old_position),"","place a worker beside the original chair")
	var restored := ShopRules.new(SHOP.copy_for_editing(),42)
	check(not restored.nav.can_stand(old_position,"staff"),"the moved chair now blocks that position")
	check_eq(restored.load_dict(old_rules.to_dict(),true),"","save with a worker inside a moved footprint loads")
	check(restored.nav.can_stand(restored.worker_by_id(worker_id).pos,"staff"),"worker resumes at a clear position")

func test_public_save_keeps_mid_cook_order_on_the_original_recipe() -> void:
	var previous := PREVIOUS.copy_for_editing()
	previous.id = SHOP.id
	previous.layout = OLD_LAYOUT
	var owner := ShopRules.new(previous,42)
	owner.gold = 400.0
	for id in ["plum_dispenser","wok_a"]: check_eq(owner.unlock(id),"","open the old covered-rice line")
	var guest_id := -1
	for tick in 800:
		owner.run(0.1)
		for guest in owner.runtime.service.orders.snapshot().guests:
			if guest.state=="waiting" and not guest.request.is_empty() and guest.request[0].dish=="tomato_rice":
				guest_id = guest.id
				break
		if guest_id>0 and owner.runtime.runner.machines.snapshot().runs.any(func(run: Dictionary) -> bool:
				return run.machine=="wok_a" and run.phase=="operate"): break
	check(guest_id>0,"old save contains an open order")
	if guest_id<1: return
	var stored := owner.to_dict()
	check(stored.runtime.runner.machines.runs.any(func(run: Dictionary) -> bool:
		return run.machine=="wok_a" and run.phase=="operate"),"old save cuts a live wok operation")
	var restored := ShopRules.new(SHOP.copy_for_editing(),42)
	var error := restored.load_dict(stored,true)
	check_eq(error,"","current shop restores the live original recipe")
	if not error.is_empty(): return
	check_eq(restored.gold,owner.gold,"saved balance stays intact")
	check(restored.station_unlocked("rice_cooker") and restored.station_unlocked("wok_b"),"the paid dish remains possible in the reordered progression")
	check_eq(restored.runtime.service.orders.guest(guest_id).request[0].recipe,"tomato_rice","accepted dish retains its original recipe")
	check_eq(restored.runtime.runner.machines.snapshot().runs,stored.runtime.runner.machines.runs,"an active wok keeps its existing timer")
	check_eq(restored.runtime._definition.service.menu.tomato_rice,"tomato_rice_v2","new orders select the current recipe")
	for elapsed in 1600:
		restored.run(0.1)
		if restored.runtime.service.orders.guest(guest_id).state=="gone": break
	check_eq(restored.runtime.service.orders.guest(guest_id).state,"gone","original hot dish remains fulfillable")

func test_actual_idle_counter_never_picks_up_kitchen_logistics() -> void:
	var template := _template()
	if template==null: return
	var runtime := _runtime(template)
	if runtime==null: return
	var front: Dictionary = runtime.runner.owner.workers[0]
	check_eq(front.post,"counter","actual posted front employee")
	runtime.request_production(template.service.menu.tomato_rice)
	runtime.request_production(template.service.menu.tomato_rice)
	check_eq(runtime.candidates_for(front.id),[],"front counter offers no kitchen tasks while idle")
	runtime.arrive([])
	check_eq(runtime.candidates_for(front.id),[],"front counter offers no admission or kitchen tasks for an approaching visitor")
	for tick in 500:
		check_eq(runtime.step(0.1),"","automatic admission advances")
		if runtime.service.orders.guest(1).order>0: return
		check(runtime.runner.tasks.get(front.id,{}).get("kind")!="interact","no front admission action")
	check(false,"customer received an order")


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
	var saw_counter_delivery := false
	for tick in 1500:
		check_eq(runtime.step(0.1),"","front makes actual plum juice")
		for worker in runtime.runner.owner.workers:
			if worker.post=="counter" and not runtime.runner.idle(worker.id):
				var task: Dictionary = runtime.runner.tasks[worker.id]
				if task.kind=="operate" and runtime.runner.machines.run(task.run).machine=="plum_dispenser": saw_front = true
				if task.to=="guest:1":
					check_eq(task.from,"plum_dispenser:out","front hands the drink straight from the dispenser")
					check(runtime.service.customers.ready(1,"pickup:0"),"drink customer waits at the front counter")
					saw_counter_delivery = true
		if runtime.service.orders.guest(1).state=="gone": break
	check(saw_front,"counter employee actually used the common dispenser operation")
	check(saw_counter_delivery,"counter employee actually hands over the drink")
	check_eq(runtime.runner.owner.sold_by_dish.plum_juice,1,"real drink sale")
	check_eq(runtime.runner.owner.sold_by_dish.soup,0,"no unwanted soup sale")
	check_eq(runtime.snapshot().units.size(),1,"no hidden second production unit")

func test_actual_rice_and_soup_reach_the_table_together_with_the_front_employee() -> void:
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
	check_eq(runtime.runner.owner.sold_by_dish.soup,1,"soup is physically served and consumed")
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
	check(not runtime.service.orders.guest(1).request.is_empty(),"one real frozen request after resuming the queue")

func test_previous_pickup_queue_retains_all_the_original_waiting_points() -> void:
	var template := _template()
	if template==null: return
	check(template.service.has("pickup_queue"),"actual self-pickup scene needs explicit waiting point configuration")
	if not template.service.has("pickup_queue"): return
	var expected: Array = []
	for index in 16: expected.append("pickup:"+str(index))
	check_eq(template.service.pickup_queue.ports,expected,"reuse every original customer anchor in waiting rank order")
	for port in expected: check(SHOP.layout.customer_points.has(port),"no invented art or geometry point")

func test_front_employee_collects_and_delivers_staged_food_after_save_reload() -> void:
	var template := _template()
	template.service.selection.stages[-1].weights = {"tomato_rice":1.0}
	template.service.selection.addon.share = 1.0
	var runtime := _runtime(template)
	if runtime==null: return
	var owner: ShopRules = runtime.runner.owner
	var front_id: int = owner.workers[0].id
	runtime.arrive([])
	_take(runtime)
	var guest: Dictionary = runtime.service.orders.guest(1)
	var seat: String = guest.seat
	var saw_kitchen := false
	var saw_upper_drop := false
	var saw_lower_pickup := false
	var saw_deliver := false
	var restored := false
	for tick in 1600:
		check_eq(runtime.step(0.1),"","advance the complete rice and soup service")
		for task in runtime.runner.tasks.values():
			if task.to=="plating:out":
				saw_kitchen = true
				check(task.worker!=front_id,"the kitchen places finished dishes on the handoff table")
				var cook := owner.worker_by_id(task.worker)
				if cook.phase=="dropoff":
					saw_upper_drop = true
					check_eq(cook.pos,template.places["plating:out"].drop_port,"kitchen actually drops at the upper port")
			if task.to!="guest:1": continue
			saw_deliver = true
			check_eq(task.worker,front_id,"only the front employee takes food to the guest")
			check(runtime.service.customers.ready(1,seat),"guest waits at the assigned table")
			for pick in task.picks: check_eq(pick.from,"plating:out","front employee takes each item from the handoff table")
			var front := owner.worker_by_id(front_id)
			if front.phase=="pickup":
				saw_lower_pickup = true
				check_eq(front.pos,template.places["plating:out"].port,"front actually picks up at the lower port")
		var worker := owner.worker_by_id(front_id)
		if saw_deliver and worker.carry_count>0 and not restored:
			var saved: Dictionary = runtime.snapshot()
			check_eq(runtime.restore(saved),"","employee carry and both order lines restore while in flight")
			check_eq(runtime.snapshot(),saved,"restore does not move the tray or duplicate stock")
			restored = true
		if runtime.service.orders.guest(1).state=="gone": break
	check(saw_kitchen and saw_deliver and restored,"saw cooking handoff, front delivery and active readback")
	check(saw_upper_drop and saw_lower_pickup,"same stock is handed off at two distinct ports")
	check_eq(runtime.service.orders.guest(1).state,"gone","served guest finishes the meal")
	check_eq(owner.sold_by_dish.tomato_rice,1,"pay for the covered rice once")
	check_eq(owner.sold_by_dish.soup,1,"pay for the soup once")
	check_eq(runtime.runner.inventory.audit(),[],"serving and restore conserve stock")

func _before_staff_and_wok_expansion() -> SpecShop:
	var previous := SHOP.copy_for_editing()
	var pantry := Vector2(190,365)
	previous.layout.points.pantry = pantry
	var obstacle: int = previous.layout.obstacle_stations.find("pantry")
	previous.layout.obstacles[obstacle] = Rect2(45,385,125,65)
	previous.runtime_template.places["pantry:out"].port = pantry
	previous.runtime_template.dispatch.port_queues["pantry:out"] = [Vector2(250,365),Vector2(250,425),Vector2(250,485)]
	previous.runtime_template.dispatch.port_queues.erase("counter")
	previous.staff.second_front_slot_after = ""
	for index in 2: previous.stages[index].staff_slots["kitchen"] = 2
	for wok in ["wok_a","wok_b"]: previous.runtime_template.machines[wok].production_batch.erase("reserve_on_feed")
	return previous


func _previous_staff_service() -> SpecShop:
	var shop := _before_staff_and_wok_expansion()
	var template: Resource = shop.runtime_template
	template.service.pickup_queue.erase("mixed_line")
	for pose in template.presentation.poses.values(): pose.offset = Vector2.ZERO
	for key in ["return_posts","roaming_idle","port_queues","collect_at_drop_last"]: template.dispatch.erase(key)
	template.places["pantry:out"].port = Vector2(200,660)
	shop.layout.customer_queue.assign([Vector2(215,950),Vector2(290,950),Vector2(365,950),Vector2(443,975),Vector2(443,1045),Vector2(443,1115),Vector2(443,1185),Vector2(443,1255)])
	shop.stages[2].grant_worker = ""
	template.places["plating:out"].erase("drop_port")
	template.service.admission = "employee"
	template.service["admission_port"] = "counter"
	template.service["admission_seconds"] = 1.0
	template.dispatch.posts.counter["interact"] = ["counter"]
	template.dispatch.scores["admit"] = 400.0
	var kitchen: Dictionary = template.dispatch.roles.staff
	template.dispatch["assistance"] = {"posts":{"counter":{
		"transfer_from":kitchen.transfer_from.duplicate(),
		"transfer_to":kitchen.transfer_to.duplicate(),
		"wait_for_admission":true}}}
	var first_wok: SpecStage = shop.stages[1]
	shop.stages[1] = shop.stages[2]
	shop.stages[2] = first_wok
	return shop

func test_previous_rice_purchase_and_admission_survive_the_new_opening() -> void:
	var old := ShopRules.new(_previous_staff_service(),42)
	old.gold = 120.0
	check_eq(old.unlock("plum_dispenser"),"","open with the original progression")
	check_eq(old.unlock("rice_cooker"),"","old progression buys rice before the wok")
	for tick in 450:
		old.run(0.1)
		if old.runtime.runner.tasks.values().any(func(task: Dictionary) -> bool: return task.kind=="interact"): break
	var saved := old.to_dict()
	check_eq(saved.template.structure,"8dcc3a9b707a4218dd1278f8c1fa0f56b9f25833141d6e454cd00978a5bc8194","exact previous service")
	check(saved.runtime.runner.tasks.any(func(task: Dictionary) -> bool: return task.kind=="interact"),"save interrupts a real admission")
	var restored := ShopRules.new(SHOP,42)
	var error := restored.load_dict(saved,true)
	check_eq(error,"","restore the pending admission")
	if not error.is_empty(): return
	check_eq(restored.gold,old.gold,"keep the old balance")
	check(restored.station_unlocked("rice_cooker"),"keep the rice cooker already purchased")
	check_eq(restored.next_unlock(),"wok_a","pay only for the first wok")
	check_eq(restored.unlock("wok_a"),"","purchase the missing equipment")
	check_eq(restored.next_unlock(),"pantry","already-owned rice stage is skipped")
	check_eq(restored.gold,old.gold-80.0,"purchase does not charge for rice again")
	for tick in 350:
		restored.run(0.1)
		if restored.sold>0: break
	check_eq(restored.sold_by_dish.plum_juice,1,"the queued opening guest is served once")

func test_previous_front_kitchen_carry_is_returned_and_reassigned() -> void:
	var old := ShopRules.new(_previous_staff_service(),42)
	old.gold = 1000.0
	for id in ["plum_dispenser","rice_cooker","wok_a"]: check_eq(old.unlock(id),"","open old independent stations")
	var unit: int = old.runtime.request_production("plain_fried_rice").id
	var carried := false
	for tick in 350:
		old.step(0.1)
		var task: Dictionary = old.runtime.runner.tasks.get(old.workers[0].id,{})
		if task.get("from")=="rice_cooker:out" and old.workers[0].carry_count>0:
			carried = true
			break
	check(carried,"the former kitchen help was carrying real stock")
	if not carried: return
	var restored := ShopRules.new(SHOP,42)
	var error := restored.load_dict(old.to_dict(),true)
	check_eq(error,"","restore rolls back obsolete assistance")
	if not error.is_empty(): return
	check_eq(restored.workers[0].carry_count,0,"front employee releases kitchen stock")
	check_eq(restored.runtime.runner.inventory.audit(),[],"held rice is accounted for")
	check_eq(restored.hire(),"","hire the replacement kitchen worker")
	check_eq(restored.deploy_worker(restored.roster.back().id),"","deploy in the kitchen")
	for tick in 650:
		restored.step(0.1)
		if restored.runtime.production_output(unit).get("complete",false): break
	check(restored.runtime.production_output(unit).get("complete",false),"kitchen continues the existing production unit")
	check_eq(restored.runtime_error,"","reassigned production is valid")

func test_public_save_moves_an_active_handoff_drop_to_the_upper_port() -> void:
	var old := ShopRules.new(_previous_staff_service(),42)
	old.gold = 1000.0
	for id in ["plum_dispenser","rice_cooker","wok_a"]: check_eq(old.unlock(id),"","open old independent stations")
	check_eq(old.hire(),"","hire the kitchen worker")
	check_eq(old.deploy_worker(old.roster.back().id),"","deploy in the kitchen")
	old.runtime.service._policy.selection.stages[2].weights = {"plain_fried_rice":1.0}
	old.runtime.service.arrivals._state.left = 10000.0
	check_eq(old.runtime.arrive([]).error,"","real guest orders fried rice")
	var dropping := false
	for tick in 850:
		old.step(0.1)
		var kitchen: Dictionary = old.workers[1]
		var task: Dictionary = old.runtime.runner.tasks.get(kitchen.id,{})
		if task.get("to")=="plating:out" and kitchen.phase=="dropoff":
			dropping = true
			break
	check(dropping,"old save interrupts a drop at the bottom of the table")
	if not dropping: return
	var order: Dictionary = old.runtime.service.orders.order(old.runtime.service.orders.guest(1).order)
	var unit: int = order.lines[0].units[0].unit
	var restored := ShopRules.new(SHOP,42)
	var saved := old.to_dict()
	saved.outer.levels["plating"] = 3
	var error := restored.load_dict(saved,true)
	check_eq(error,"","restore a saved in-flight handoff")
	if not error.is_empty(): return
	check_eq(restored.gold,old.gold+30.0,"refund both paid levels of the removed upgrade track")
	check_eq(restored.load_dict(restored.to_dict()),"","migrated handoff saves under the current rules")
	check_eq(restored.gold,old.gold+30.0,"refund cannot repeat")
	var saw_upper := false
	for tick in 150:
		restored.step(0.1)
		var kitchen: Dictionary = restored.workers[1]
		if kitchen.phase=="dropoff" and kitchen.target=="plating:out":
			saw_upper = kitchen.pos==SHOP.runtime_template.places["plating:out"].drop_port
		if restored.runtime.production_output(unit).get("complete",false): break
	check(saw_upper,"same held meal reaches the new upper drop position")
	check_eq(restored.runtime.runner.inventory.quantity("plating:out","plain_fried_rice",unit),1,"preserve the exact staged meal")

func test_latest_pickup_save_finishes_old_order_and_serves_new_drinks_at_counter() -> void:
	var previous := _previous_staff_service()
	var template: Resource = previous.runtime_template
	for key in ["delivery_ready","staff_handoff","previous_pickup"]: template.service.erase(key)
	template.service.delivery = "self_pickup"
	template.service.menu.soup = "soup"
	template.service.previous_recipes.erase("soup")
	template.recipes.erase("soup_handoff")
	template.dispatch.posts.counter.transfer_to.erase("guest:*")
	var old := ShopRules.new(previous,42)
	check_eq(old.unlock("plum_dispenser"),"","open the previous released order flow")
	var in_flight := false
	for tick in 600:
		old.run(0.1)
		if old.runtime.service.snapshot().deliveries.any(func(row: Dictionary) -> bool: return row.phase=="carry"):
			in_flight = true
			break
	check(in_flight,"the old guest really has the meal in hand")
	if not in_flight: return
	var saved := old.to_dict()
	check_eq(saved.template.structure,"64ebcc3d5ed5044889c05c8c5cb8f959d993e826251c7a5a177ce3dfffcafc17","load a snapshot from the exact pushed revision")
	var restored := ShopRules.new(SHOP.copy_for_editing(),42)
	var error := restored.load_dict(saved,true)
	check_eq(error,"","the previous carry stays valid through migration")
	if not error.is_empty(): return
	var service: RefCounted = restored.runtime.service
	var boundary: int = saved.runtime.service.orders.next_order
	check_eq(service.snapshot().pickup_before,boundary,"only already accepted orders use the previous window")
	check_eq(service.snapshot().deliveries,saved.runtime.service.deliveries,"migration preserves the physical in-flight order")
	var saw_new := false
	for tick in 1400:
		restored.run(0.1)
		for guest in service.orders.active_snapshot().guests:
			if guest.order<boundary: continue
			var actor: Dictionary = service.customers.record(guest.id)
			if guest.state=="waiting":
				check(String(actor.target).begins_with("pickup:"),"new drink customer waits at the counter")
				check(not service.uses_customer_pickup(guest.order),"new guest waits for employee handover")
				saw_new = true
		if service.orders.guest(1).state=="gone" and saw_new and restored.sold>1: break
	check(saw_new and restored.sold>1,"front employee delivers after the migration")
	check_eq(service.orders.guest(1).state,"gone","the old self-pickup order is also completed")
	check_eq(restored.runtime_error,"","mixed old and new routes coexist")
	var current := restored.to_dict()
	check_eq(restored.load_dict(current),"","current save preserves both routes on a subsequent load")

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
	template.service.selection.stages[-1].weights = {"egg_fried_rice":1.0}
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
	check_eq(owner.sold_by_dish.egg_fried_rice,1,"posted cook and logistics still deliver a two-phase fried rice")

func test_staff_cultivation_changes_real_work_walk_and_carry_by_role() -> void:
	var owner := _owner()
	var front: Dictionary = owner.workers[0]
	var kitchen: Dictionary = owner.workers[1]
	var before := owner.effective_worker_stats(kitchen)
	var front_before := owner.effective_worker_stats(front)
	var front_walk := owner.walk_speed(front)
	var kitchen_walk := owner.walk_speed(kitchen)
	check_eq(owner.upgrade("staff/kitchen"),"","buy kitchen walking improvement")
	check_eq(owner.upgrade("staff/kitchen"),"","buy kitchen work improvement")
	check_eq(owner.upgrade("staff/kitchen"),"","buy kitchen carry improvement")
	check(is_equal_approx(owner.walk_speed(kitchen),kitchen_walk*1.2),"movement uses the kitchen bonus")
	check(is_equal_approx(owner.manual_operation_seconds("wok_a",5.0,kitchen),5.0/(before.work*1.25)),"wok uses the upgraded worker clock")
	check_eq(owner.carry(kitchen),before.carry+1,"inventory carrier gains one place")
	check_eq(owner.effective_worker_stats(front),front_before,"kitchen upgrade affects the kitchen role")
	check_eq(owner.upgrade("staff/front"),"","buy front walking improvement")
	check(is_equal_approx(owner.walk_speed(front),front_walk*1.2),"front walking upgrade applies to delivery")

func test_opening_gift_and_base_prices() -> void:
	var rules := ShopRules.new(SHOP.copy_for_editing(),42)
	check_eq(rules.dish_price("plum_juice"),10.0,"opening drink base price")
	check_eq(rules.dish_price("plain_fried_rice"),11.0,"plain fried rice base price")
	check_eq(rules.dish_price("egg_fried_rice"),12.0,"egg fried rice base price")
	check_eq(rules.dish_price("tomato_rice"),13.0,"first covered rice base price")
	rules.gold = 112.0
	for id in ["plum_dispenser","wok_a","rice_cooker"]:
		check_eq(rules.unlock(id),"","buy the opening equipment")
	check_eq(rules.gold,0.0,"no additional coins for the kitchen employee")
	check_eq(rules.workers.size(),2,"opening gift joins the active team")
	check_eq(rules.hire_cost(),30,"the gift does not use a paid hire tier")
	check(rules.menu().has("plain_fried_rice"),"hot orders immediately become available")
	check(not rules.unlock("rice_cooker").is_empty(),"cannot collect the opening gift again")
	check_eq(rules.workers.size(),2,"repeat purchase has no side effects")

func test_first_paid_recruit_fills_the_new_front_slot() -> void:
	var rules := ShopRules.new(SHOP.copy_for_editing(),42)
	rules.gold = 142.0
	for id in ["plum_dispenser","wok_a"]:
		check_eq(rules.unlock(id),"","open the front drink service")
	check_eq(rules.front_slots(),2,"two front slots during drink service")
	check_eq(rules.kitchen_slots(),0,"the kitchen waits for a rice supply")
	check_eq(rules.hire(),"","pay 30 gold for the first recruit")
	var recruit: Dictionary = rules.roster.back()
	check_eq(rules.execute_command("deploy_worker",{"id":recruit.id,"from_hire":true}).code,"ok","use the staff screen deployment")
	check_eq(recruit.post,rules.counter_id,"the recruit immediately serves at the counter")
	check_eq(rules.unlock("rice_cooker"),"","open the kitchen")
	check_eq(rules.front_slots(),2,"opening the kitchen retains two front slots")
	check_eq(rules.kitchen_staff(),1,"the free bear keeps its kitchen assignment")
	check_eq(rules.gold,0.0,"the front slot needs no additional purchase")
	rules.run(1.0)
	check(recruit.pos.distance_to(rules.workers[0].pos)>30.0,"both front workers have distinct standby spots")
	var reopened := ShopRules.new(SHOP.copy_for_editing(),42)
	check_eq(reopened.load_dict(rules.to_dict()),"","save the expanded front staff")
	check_eq(reopened.front_slots(),2,"the slot follows rice cooker progress")
	check_eq(reopened.worker_by_id(recruit.id).post,reopened.counter_id,"the recruit stays at the front")
	check_eq(reopened.place_worker(recruit.id,""),"","the player can still reassign the recruit")
	check_eq(reopened.kitchen_staff(),2,"the reassigned recruit joins the kitchen")

func test_pantry_ingredient_upgrades_are_independent() -> void:
	var rules := ShopRules.new(SHOP.copy_for_editing(),42)
	rules.gold = 1000.0
	for id in ["plum_dispenser","wok_a","rice_cooker","pantry"]:
		check_eq(rules.unlock(id),"","open the pantry")
	check_eq(rules.upgrade("pantry/egg_rice_raw"),"","upgrade egg fried rice seasoning")
	check(is_equal_approx(rules.dish_price("egg_fried_rice"),13.0),"only the egg fried rice earns the seasoning price bonus")
	check_eq(rules.dish_price("plain_fried_rice"),11.0,"no seasoning bonus on plain fried rice")
	check(not rules.upgrade("pantry/yangzhou_raw").is_empty(),"locked seasoning cannot be upgraded")
	check_eq(rules.unlock("pantry"),"","cabinet level unlocks the next seasoning")
	check_eq(rules.upgrade("pantry/yangzhou_raw"),"","unlocked seasoning now has its own price upgrade")

func test_front_worker_returns_to_counter_after_delivery_and_can_reload_on_the_way() -> void:
	var template := _template()
	template.service.selection.stages[-1].weights = {"plain_fried_rice":1.0}
	var runtime := _runtime(template)
	if runtime==null: return
	var front: Dictionary = runtime.runner.owner.workers[0]
	var counter: Vector2 = runtime.runner.owner.nav.post("counter")
	runtime.arrive([])
	for tick in 600:
		check_eq(runtime.step(0.1),"","deliver the meal to its seat")
		if runtime.service.orders.order(1).get("state") != "delivered": continue
		check(front.walking and runtime.runner.idle(front.id),"front immediately starts walking back after handing over the order")
		check_eq(front.get("motion",{}).get("goal"),counter,"front returns to the assigned counter post")
		var saved: Dictionary = runtime.snapshot()
		check_eq(runtime.restore(saved),"","return trip survives save and load")
		for remainder in 500:
			check_eq(runtime.step(0.1),"","complete the saved return walk")
			if front.pos == counter: break
		check_eq(front.pos,counter,"front reaches the counter")
		return
	check(false,"meal was delivered by the front worker")

func test_workers_wait_at_distinct_positions_for_the_same_port() -> void:
	var runtime := _runtime(_template())
	if runtime==null: return
	var runner: RefCounted = runtime.runner
	var first: Dictionary = runner.owner.workers[1]
	var second: Dictionary = runner.owner.workers[2]
	check_eq(runner.transfer(first.id,"pantry:out","wok_a:in","egg_rice_raw",1,0.5,-1,-1),"","assign the first worker to pick from the pantry")
	check_eq(runner.transfer(second.id,"pantry:out","wok_a:in","egg_rice_raw",1,0.5,-1,-1),"","assign the second worker to the same pantry")
	var work_point: Vector2 = runner.ports["pantry:out"]
	var wait_point: Vector2 = runner.dispatcher._definition.port_queues["pantry:out"][0]
	check_eq(first.motion.goal,work_point,"first assignment approaches the work port")
	check_eq(second.motion.goal,wait_point,"second assignment moves to a separate waiting position")
	var snap: Dictionary = runner.snapshot()
	check_eq(runner.restore(snap),"","queued route and stock claims restore")
	var saw_second := false
	for tick in 300:
		check_eq(runner.step(0.1),"","sequential pickups and drops advance")
		check(not (first.pos==work_point and second.pos==work_point),"employees never collect from the same point concurrently")
		if second.phase=="pickup":
			saw_second = true
			check_eq(second.pos,work_point,"the next employee moves up when the port clears")
		if runner.idle(first.id) and runner.idle(second.id): break
	check(saw_second,"the second worker reached the work port")
	check_eq(runner.inventory.quantity("wok_a:in","egg_rice_raw"),2,"both pickups reached the wok")

func test_wok_keeps_other_orders_out_from_the_first_rice_pickup_until_the_food_is_done() -> void:
	var template := _template()
	var runtime := _runtime(template)
	if runtime==null: return
	check_eq(runtime.runner.inventory.seed("rice_cooker:out","rice",2).error,"","provide rice for two orders")
	var first: int = runtime.request_production("egg_fried_rice_v2").id
	var second: int = runtime.request_production("plain_fried_rice").id
	var saw_incoming := false
	for tick in 900:
		check_eq(runtime.step(0.1),"","advance both orders with two kitchen workers")
		var stock: RefCounted = runtime.runner.inventory
		if "finish" not in runtime.unit(first).done:
			check_eq(stock.incoming("wok_a:in","rice",second),0,"no second rice delivery has been assigned")
			check_eq(stock.quantity("wok_a:in","rice",second),0,"the other order has not deposited rice")
		if not saw_incoming and stock.incoming("wok_a:in","rice",first)>0:
			saw_incoming = true
			check(not runtime.unit(first).running.has("heat"),"the first rice dispatch precedes heating")
			check_eq(runtime.restore(runtime.snapshot()),"","restore the incoming rice reservation before heating")
		if runtime.ready(first) and runtime.ready(second): break
	check(saw_incoming,"the rice was dispatched by an employee")
	check(runtime.ready(first) and runtime.ready(second),"both distinct orders still cook and reach the handoff")

func test_previous_pantry_pickup_resumes_at_the_new_outside_port() -> void:
	var previous := _before_staff_and_wok_expansion()
	var pantry: Vector2 = previous.layout.points.pantry
	var old := ShopRules.new(previous,42)
	old.gold = 1000.0
	for id in ["plum_dispenser","wok_a","rice_cooker","pantry"]:
		check_eq(old.unlock(id),"","open the previous cabinet")
	var old_cook: Dictionary = old.workers[1]
	for tick in 1800:
		old.step(0.1)
		if old_cook.get("motion",{}).get("goal")!=pantry or not old_cook.walking: continue
		var reopened := ShopRules.new(SHOP.copy_for_editing(),42)
		check_eq(reopened.load_dict(old.to_dict(),true),"","restore the previous takeout walk with its inventory claim")
		var new_cook: Dictionary = reopened.worker_by_id(old_cook.id)
		check_eq(new_cook.get("motion",{}).get("goal"),Vector2(220,365),"active route follows the new outside work point")
		for remaining in 900:
			reopened.step(0.1)
			if reopened.sold_by_dish.egg_fried_rice>0: break
		check_eq(reopened.runtime_error,"","relocated production keeps advancing")
		check(reopened.sold_by_dish.egg_fried_rice>0,"pickup resumed and the meal was sold")
		return
	check(false,"the older employee walked toward the cabinet")

func test_fried_rice_waits_in_wok_while_worker_walks_to_pantry() -> void:
	var template := _template()
	template.service.selection.stages[-1].weights = {"egg_fried_rice":1.0}
	template.service.selection.addon.share = 0.0
	var runtime := _runtime(template)
	if runtime==null: return
	var owner: ShopRules = runtime.runner.owner
	for worker in owner.workers.duplicate():
		if worker.id not in [owner.workers[0].id,owner.workers[1].id]: owner.recall_worker(worker.id)
	for i in 3: check_eq(owner.upgrade("staff/kitchen"),"","train the floating worker to carry both items")
	runtime.arrive([])
	var saw_pantry := false
	for tick in 900:
		check_eq(runtime.step(0.1),"","make fried rice with a single kitchen worker")
		var cook: Dictionary = owner.workers[1]
		if cook.phase in ["walk","pickup"] and cook.target=="pantry:out":
			saw_pantry = true
			check_eq(cook.carry_count,0,"worker goes to collect seasoning empty-handed")
			check_eq(runtime.runner.inventory.quantity("wok_a:out","fried_rice_base"),1,"the cooked rice base remains at the wok")
		check(cook.carry_item!="fried_rice_base","rice never enters the worker's hands at the wok")
		if owner.sold_by_dish.egg_fried_rice>0: break
	check(saw_pantry and owner.sold_by_dish.egg_fried_rice==1,"real fried rice was seasoned and served")
	var claims: Array = runtime.runner.inventory.snapshot().claims
	check(not claims.any(func(claim: Dictionary) -> bool: return claim.kind=="transfer" and claim.item=="fried_rice_base"),"no take-out and put-back transfer was even scheduled")

func test_double_yangzhou_batch_keeps_both_rice_portions_in_the_wok() -> void:
	var runtime := _runtime(_template())
	if runtime==null: return
	var shop: ShopRules = runtime.runner.owner
	for level in 3: check_eq(shop.upgrade("wok_a"),"","upgrade the wok to its two-portion level")
	check_eq(runtime.runner.inventory.seed("rice_cooker:out","rice",2).error,"","stage two portions of rice")
	var first: int = runtime.request_production("yangzhou_rice_v2").id
	var second: int = runtime.request_production("yangzhou_rice_v2").id
	for tick in 900:
		check_eq(runtime.step(0.1),"","cook both portions")
		if runtime.ready(first) and runtime.ready(second): break
	check(runtime.ready(first) and runtime.ready(second),"both portions reach the handoff")
	var first_run: Dictionary = runtime.unit(first).running
	var second_run: Dictionary = runtime.unit(second).running
	check(first_run.has("finish") and first_run.get("finish")==second_run.get("finish"),"both portions share the final wok operation")
	var claims: Array = runtime.runner.inventory.snapshot().claims
	check(not claims.any(func(claim: Dictionary) -> bool: return claim.kind=="transfer" and claim.item=="fried_rice_base"),"no rice transfer occurs even as a double batch")
	check_eq(runtime.runner.inventory.audit(),[],"retention conserves both orders")


func test_previous_save_with_rice_in_hand_restores_it_to_the_wok() -> void:
	var previous := SHOP.copy_for_editing()
	for recipe in ["egg_fried_rice_v2","yangzhou_rice_v2"]:
		previous.runtime_template.recipes[recipe].machine_reservation.erase("retain_inputs")
	var old := ShopRules.new(previous,42)
	old.gold = 100000.0
	for id in ["plum_dispenser","wok_a","rice_cooker","pantry"]:
		check_eq(old.unlock(id),"","open the old restaurant")
	var unit: int = old.runtime.request_production("egg_fried_rice_v2").id
	for tick in 1500:
		old.step(0.1)
		var claims: Array = old.runtime.runner.inventory.snapshot().claims
		if not claims.any(func(claim: Dictionary) -> bool: return claim.kind=="transfer" and claim.item=="fried_rice_base" and claim.state=="held" and claim.owner==unit): continue
		var restored := ShopRules.new(SHOP.copy_for_editing(),42)
		var error := restored.load_dict(old.to_dict(),true)
		check_eq(error,"","restore a save made during the old take-out action")
		if not error.is_empty(): return
		var inventory: RefCounted = restored.runtime.runner.inventory
		check_eq(inventory.quantity("wok_a:out","fried_rice_base",unit),1,"rice in the employee's hand returns to its original wok")
		for remainder in 1000:
			restored.step(0.1)
			if restored.runtime.ready(unit): break
		check(restored.runtime.ready(unit),"the same order finishes after restoring")
		check_eq(restored.runtime_error,"","continued wok operation reports no errors")
		check_eq(inventory.audit(),[],"no rice is lost or duplicated")
		return
	check(false,"the previous version actually had a cook take the rice out")


func test_customers_walk_to_the_right_queue_head_before_taking_a_seat() -> void:
	var template := _template()
	template.service.selection.stages[-1].weights = {"plain_fried_rice":1.0}
	var runtime := _runtime(template)
	if runtime==null: return
	var owner: ShopRules = runtime.runner.owner
	for id in range(1,3):
		check_eq(runtime.arrive([]).id,id,"send two customers into the shop")
	var points := owner.nav.layout.customer_queue
	for i in range(1,6):
		check(points[i].x<points[i-1].x and points[i].y==points[0].y,"queue extends to the left of the right-side counter")
	check_eq(runtime.service.customers.record(1).target,"queue:0","first customer goes to the counter before taking a seat")
	check_eq(runtime.service.customers.record(2).target,"queue:1","second customer joins at the left")
	check_eq(runtime.service.orders.guest(1).seat,"","free seats do not skip the queue")
	for tick in 350:
		check_eq(runtime.step(0.1),"","advance the entrance walk")
		if runtime.service.orders.guest(1).order>0: break
	check_eq(runtime.service.customers.record(1).target,"seat:table/0","first customer takes the available seat from queue head")

func test_counter_pickup_and_new_arrivals_use_one_line() -> void:
	var template := _template()
	template.service.selection.stages[-1].weights = {"plum_juice":1.0}
	var runtime := _runtime(template)
	if runtime==null: return
	runtime.arrive([])
	runtime.arrive([])
	runtime.arrive([])
	_take(runtime)
	check_eq(runtime.step(0.1),"","synchronize the mixed line after admission")
	check_eq(runtime.service.customers.record(1).target,"pickup:0","the drink customer stays at the shared head")
	check_eq(runtime.service.customers.record(2).target,"queue:1","the waiting drink occupies the first physical position")
	check_eq(runtime.service.customers.record(3).target,"queue:2","later arrivals use distinct positions in the same line")
	var saved: Dictionary = runtime.snapshot()
	check_eq(runtime.restore(saved),"","active mixed queue restores exactly")
	for tick in 600:
		check_eq(runtime.step(0.1),"","the shared head advances as drinks are served")
		if runtime.service.orders.guest(2).order>0: break
	check_eq(runtime.service.orders.order(1).state,"delivered","the customer at the head gets the drink first")
	check(runtime.service.orders.guest(2).order>0,"the next guest reaches the head and orders")

func test_old_split_positions_reload_into_the_mixed_line() -> void:
	var previous := _before_staff_and_wok_expansion()
	previous.runtime_template.service.pickup_queue.erase("mixed_line")
	previous.layout.customer_queue.clear()
	for rank in 8: previous.layout.customer_queue.append(Vector2(640-78*rank,950))
	var old := ShopRules.new(previous,42)
	check_eq(old.unlock("plum_dispenser"),"","open the old counter")
	old.runtime.service.arrivals._state.left = 10000.0
	for index in 3: old.runtime.arrive([])
	_take(old.runtime)
	old.step(0.1)
	check_eq(old.runtime.service.customers.record(2).target,"queue:0","previous rules assigned the same physical head twice")
	var saved := old.to_dict()
	check_eq(saved.template.structure,"5ef4e1493f4a521cb3bfe9a9c2ad1144ff02161400a426c113d673d48f29875c","save represents the previous deployed layout")
	var restored := ShopRules.new(SHOP.copy_for_editing(),42)
	check_eq(restored.load_dict(saved,true),"","previous save accepts the new queue layout")
	check_eq(restored.runtime.service.customers.record(1).target,"pickup:0","retain the active pickup at the head")
	check_eq(restored.runtime.service.customers.record(2).target,"queue:1","guide the next arrival toward its new position")
	check_eq(restored.runtime.service.customers.record(3).target,"queue:2","preserve order across the migration")
	check_eq(restored.load_dict(restored.to_dict()),"","reassigned movement survives ordinary reload")

func test_preexisting_kitchen_training_survives_the_new_unlock_requirement() -> void:
	var previous := SHOP.copy_for_editing()
	previous.staff.training_requires.clear()
	var old := ShopRules.new(previous,42)
	old.gold = 1000.0
	for id in ["plum_dispenser","wok_a"]: check_eq(old.unlock(id),"","open the drink stage before the kitchen")
	check_eq(old.upgrade("staff/kitchen"),"","previous versions let a player buy training early")
	var bought := old.level("staff/kitchen")
	var saved := old.to_dict()
	var restored := ShopRules.new(SHOP.copy_for_editing(),42)
	check_eq(restored.load_dict(saved,true),"","restore the earlier store without modifying paid levels")
	check_eq(restored.level("staff/kitchen"),bought,"keep previously purchased cultivation")
	check_eq(restored.command_status("upgrade",{"key":"staff/kitchen"}).code,"station_required","further training waits for the rice cooker")
	check_eq(restored.unlock("rice_cooker"),"","unlock the kitchen on the restored store")
	check_eq(restored.command_status("upgrade",{"key":"staff/kitchen"}).code,"ok","the next training purchase becomes available")
	check_eq(restored.level("staff/kitchen"),bought,"opening the kitchen resumes the player's previous level")


func test_previous_opening_recruit_is_retained_at_the_register() -> void:
	var previous := SHOP.copy_for_editing()
	previous.staff.second_front_slot_after = "rice_cooker"
	previous.stages[0].staff_slots["kitchen"] = 2
	var old := ShopRules.new(previous, 42)
	old.gold = 100.0
	check_eq(old.unlock("plum_dispenser"), "", "open old drink counter")
	check_eq(old.hire(), "", "hire under the old opening rules")
	var recruit: int = old.roster.back().id
	check_eq(old.deploy_worker(recruit), "", "paid hire starts in the old kitchen")
	old.step(0.1)
	var current := ShopRules.new(SHOP, 42)
	check_eq(current.load_dict(old.to_dict(), true), "", "adopt previous staff assignments")
	check_eq(current.worker_by_id(recruit).post, current.counter_id, "same employee now works at register")
	check_eq(current.gold, old.gold, "no additional hire cost")
	current.step(0.1)
	check_eq(current.load_dict(current.to_dict()), "", "new assignment survives reload")
