extends "res://tests/test_case.gd"
const Fixture := preload("res://tests/fixtures/movement_shop.gd")
const Schema := preload("res://game/rules/shop_spec_validator.gd")
const Flow := preload("res://game/rules/serve_flow.gd")

func definition() -> SpecShop:
	var shop := Fixture.definition("serve")
	shop.fulfillment.flow_version = 1
	shop.fulfillment.addon_chance = 1.0
	shop.dispatch.action_version = 1
	var item := SpecItem.new()
	item.id = "front_drink"
	item.display_name = "前台饮品"
	shop.items.append(item)
	var station := SpecStation.new()
	station.id = "front_machine"
	station.display_name = "前台出品机"
	station.block = "hand"
	station.zone = "front"
	station.starts_unlocked = true
	station.params = {"seconds":3.0,"users":1}
	shop.stations.append(station)
	shop.layout.points[station.id] = Vector2(1000,200)
	var step := SpecStep.new()
	step.station = station.id
	step.action = "pour"
	step.seconds = 3.0
	step.produces = {item.id:1}
	step.label = "前台制作"
	var dish := SpecDish.new()
	dish.id = "front_drink"
	dish.display_name = "前台饮品"
	dish.item = item.id
	dish.front = true
	dish.price_parts = {"base":6.0}
	dish.steps.assign([step])
	shop.dishes.append(dish)
	for stage in shop.stages: stage.order_weights = {dish.id:1.0}
	return shop

func opened() -> ShopRules:
	var shop := definition()
	var rules := ShopRules.new(shop,42)
	rules.gold = 1000000.0
	rules.unlock(shop.goals.opening_station)
	for unused in shop.stages.size():
		var next := rules.next_unlock()
		if next.is_empty(): break
		rules.unlock(next)
	return rules

func test_serve_front_recipe_reuses_work_actions_and_requires_matching_production_region() -> void:
	var shop := definition()
	check_eq(Schema.validate(shop),[],"flow1 serve can opt into an existing front hand operation")
	shop.fulfillment.flow_version = 0
	check(not Schema.validate(shop).is_empty(),"legacy protocol cannot accidentally enable front recipes")
	shop.fulfillment.flow_version = 1
	shop.dish("front_drink").steps[0].station = "wok_a"
	check(not Schema.validate(shop).is_empty(),"a front recipe cannot silently depend on kitchen work")

func test_front_worker_produces_and_delivers_without_using_kitchen_or_kitchen_addons() -> void:
	var rules := opened()
	var made := 0
	var front_ticks := 0
	var wrong_roles := {}
	var extra_lines := false
	for tick in 1800:
		rules.step(0.1)
		for worker: Dictionary in rules.workers:
			var job := Flow.job_of(rules,worker)
			if job.is_empty() or int(job.unit)<0: continue
			var unit := Flow.unit(rules,int(job.unit))
			if unit.get("dish","")!="front_drink": continue
			if Flow.role(rules,worker)!="front": wrong_roles[worker.id] = Flow.role(rules,worker)
			front_ticks += 1
		for order: Dictionary in rules.serve.orders:
			if order.lines.size()!=1: extra_lines = true
		made = int(rules.sold_by_dish.front_drink)
		if made>=2: break
	check(front_ticks>0,"front employee executes actual work and transport")
	check_eq(wrong_roles,{},"kitchen never reserves a front-only drink")
	check(not extra_lines,"front-only sale cannot be held by a kitchen soup addon")
	check(made>=2,"front-only machine completes repeated real sales")
	check_eq(ShopRules.new(rules.shop).load_dict(rules.to_dict()),"","front sale state independently restores")

func test_cancelled_front_carry_returns_exact_good_and_does_not_duplicate_income() -> void:
	var rules := opened()
	var found := false
	for tick in 1800:
		rules.step(0.1)
		for worker: Dictionary in rules.workers:
			var job := Flow.job_of(rules,worker)
			if job.get("kind","")!="pass" or int(worker.carry_count)!=1: continue
			var id: int = job.good
			var revenue := rules.revenue
			check_eq(rules.recall_worker(worker.id),"","front employee can be recalled mid delivery")
			var good := Flow._good(rules,id)
			check_eq(good.at,"front_machine","uncommitted product returns to its source")
			check_eq(good.res,-1,"recall releases the actual inventory reservation")
			check_eq(rules.revenue,revenue,"recall does not credit income")
			check_eq(rules.deploy_worker(worker.id,rules.counter_id),"","front employee resumes counter role")
			found = true
			break
		if found: break
	check(found,"actual front production reached carried goods")
	rules.run(120.0)
	check(rules.sold_by_dish.front_drink>0,"recalled product is eventually sold")
	check_eq(ShopRules.new(rules.shop).load_dict(rules.to_dict()),"","recall leaves a valid resumable ledger")

func test_front_actions_save_and_continue_exactly_during_work_and_delivery() -> void:
	var rules := opened()
	var seen := {}
	for tick in 1800:
		rules.step(0.1)
		for worker: Dictionary in rules.workers:
			var job := Flow.job_of(rules,worker)
			if job.is_empty() or not worker.has("action"): continue
			if Flow.role(rules,worker)!="front": continue
			var kind := String(worker.action.steps[worker.action.index].kind)
			if seen.has(kind): continue
			seen[kind] = true
			var state := rules.to_dict()
			var clone := ShopRules.new(rules.shop)
			check_eq(clone.load_dict(state),"","front action restores: "+kind)
			check_eq(clone.to_dict(),state,"front action keeps inventory, reservation and timer: "+kind)
			for step in 30:
				rules.step(0.1)
				clone.step(0.1)
			check_eq(clone.to_dict(),rules.to_dict(),"front action continues identically: "+kind)
		if seen.size()>=5: break
	for kind in ["move","operate","pickup","transport","drop"]:
		check(seen.has(kind),"real front job reached "+kind)

func test_front_delivery_waits_for_a_real_route_without_creating_a_sale() -> void:
	var rules := opened()
	for tick in 1800:
		rules.step(0.1)
		for worker: Dictionary in rules.workers:
			var job := Flow.job_of(rules,worker)
			if job.get("kind","")!="pass" or worker.carry_count!=1: continue
			var id := int(job.good)
			var point: Vector2 = worker.pos
			var revenue := rules.revenue
			rules.shop.layout.obstacles = [Rect2(780,0,40,1280)]
			rules.nav.set_open(rules.unlocked)
			rules.run(2.0)
			check_eq(worker.pos,point,"front carrier cannot cross a blocked delivery route")
			check_eq(Flow._good(rules,id).at,"hand:"+str(worker.id),"same produced drink remains in hand")
			check_eq(rules.revenue,revenue,"blocked delivery cannot credit a sale")
			check_eq(ShopRules.new(rules.shop).load_dict(rules.to_dict()),"","blocked front delivery is resumable")
			rules.shop.layout.obstacles.clear()
			rules.nav.set_open(rules.unlocked)
			rules.run(90.0)
			check(rules.sold_by_dish.front_drink>0,"front delivery resumes when a route is available")
			return
	check(false,"real carried front drink was captured")

func test_mixed_menu_keeps_front_and_kitchen_work_independent() -> void:
	var rules := opened()
	for stage in rules.shop.stages:
		stage.order_weights = {"front_drink":1.0,"tomato_rice":1.0}
	var wrong_roles := {}
	for tick in 6000:
		rules.step(0.1)
		for worker: Dictionary in rules.workers:
			var job := Flow.job_of(rules,worker)
			if job.is_empty() or int(job.unit)<0: continue
			var unit := Flow.unit(rules,int(job.unit))
			if unit.is_empty(): continue
			var front := rules.shop.dish(unit.dish).front
			var role := Flow.role(rules,worker)
			if (front and role!="front") or (not front and role!="kitchen"):
				wrong_roles[worker.id] = role
		if rules.sold_by_dish.front_drink>=2 and rules.sold_by_dish.tomato_rice>=2: break
	check_eq(wrong_roles,{},"mixed orders respect each production region")
	check(rules.sold_by_dish.front_drink>=2,"front drink sells alongside kitchen food")
	check(rules.sold_by_dish.tomato_rice>=2,"kitchen food is not starved by front production")
	check_eq(ShopRules.new(rules.shop).load_dict(rules.to_dict()),"","mixed menu remains resumable")

func test_formal_stirfry_has_front_drink_without_shifting_existing_stages() -> void:
	var shop: SpecShop = load("res://content/shops/stirfry/shop.tres")
	var legacy: SpecShop = load("res://tests/fixtures/stirfry_modularity/legacy_shop.tres")
	var station := shop.station("plum_dispenser")
	var dish := shop.dish("plum_juice")
	check(station!=null and dish!=null,"third shop authors its own front machine and drink")
	if station==null or dish==null: return
	check(station.starts_unlocked and station.zone=="front" and station.block=="hand","basic front equipment reuses the shared hand operation")
	check(dish.front and dish.steps.size()==1 and dish.steps[0].station==station.id,"front drink has an independent production chain")
	check(not station.tracks.is_empty(),"front machine has real purchasable upgrades")
	check_eq(shop.fulfillment.flow_version,1,"formal shop explicitly opts into front recipe support")
	check_eq(shop.stages.size(),legacy.stages.size(),"existing stage count is unchanged")
	for i in shop.stages.size():
		check_eq(shop.stages[i].id,legacy.stages[i].id,"existing saved stage indices stay valid")
		check(shop.stages[i].order_weights.get(dish.id,0)>0,"front drink can sell in every stage")
	var art: Node2D = load(shop.scene_path).instantiate()
	var counter := art.get_node("Sortables/ServiceCounter")
	check_eq(counter.station_slots.get("drink",""),station.id,"authored counter exposes a reusable drink port")
	var machine: Sprite2D = counter.get_node_or_null("Visual/Slots/drink/PlumMachine")
	check(machine!=null,"front machine is a real scene sprite")
	if machine!=null:
		check(machine.texture is AtlasTexture,"machine reuses its original batch atlas")
		var register: Sprite2D = counter.get_node("Visual/Register")
		check(machine.position.x<register.position.x,"user requested machine left and register in the middle")
	art.free()

func test_added_recipe_adopts_existing_station_slots_without_mutating_saved_progress() -> void:
	var current: SpecShop = load("res://content/shops/stirfry/shop.tres")
	var old := current.copy_for_editing()
	old.fulfillment.flow_version = 0
	old.items.assign(old.items.filter(func(item: SpecItem) -> bool: return item.id!="plum_juice"))
	old.dishes.assign(old.dishes.filter(func(dish: SpecDish) -> bool: return dish.id!="plum_juice"))
	old.stations.assign(old.stations.filter(func(station: SpecStation) -> bool: return station.id!="plum_dispenser"))
	old.layout.points.erase("plum_dispenser")
	for stage in old.stages: stage.order_weights.erase("plum_juice")
	var previous := ShopRules.new(old,42)
	previous.unlock("wok_a")
	var found := false
	for tick in 1800:
		previous.step(0.1)
		if previous.serve.jobs.is_empty(): continue
		var saved := previous.to_dict()
		var original := saved.duplicate(true)
		var migrated := ShopRules.new(current)
		check(not migrated.load_dict(saved).is_empty(),"ordinary load refuses missing existing pickup slots")
		check_eq(migrated.load_dict(saved,true),"","content adoption fills newly introduced recipe slots")
		check_eq(saved,original,"adoption leaves the supplied old snapshot unchanged")
		check_eq(migrated.clock,previous.clock,"existing simulation time survives")
		check_eq(migrated.gold,previous.gold,"existing money survives")
		check_eq(migrated.serve.goods,previous.serve.goods,"existing goods and reservations survive")
		check_eq(migrated.serve.jobs,previous.serve.jobs,"existing jobs survive")
		check_eq(migrated.stations.window.input.plum_juice,0,"new recipe starts with no fabricated output")
		check(migrated.station_unlocked("plum_dispenser"),"new basic front station becomes available")
		var resumed := ShopRules.new(current)
		check_eq(resumed.load_dict(migrated.to_dict()),"","adopted action state restores independently")
		for step in 100:
			migrated.step(0.1)
			resumed.step(0.1)
		check_eq(resumed.to_dict(),migrated.to_dict(),"old active job continues exactly after recipe adoption")
		found = true
		break
	check(found,"a real pre-front active job was migrated")
