extends "res://tests/test_case.gd"
const DATA: SpecShop = preload("res://content/shops/stirfry/shop.tres")
const LEGACY: SpecShop = preload("res://tests/fixtures/stirfry_modularity/legacy_shop.tres")
const STATES := "res://tests/fixtures/stirfry_modularity/legacy_states.json"
const Contract := preload("res://presentation/shop/shop_scene_contract.gd")
const Flow := preload("res://game/rules/serve_flow.gd")
const Customers := preload("res://game/rules/customer_movement.gd")
var nodes: Array[Node] = []
var files: Array[String] = []

func cleanup() -> void:
	for node in nodes:
		if is_instance_valid(node): node.free()
	for path in files:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	nodes.clear()
	files.clear()

func _enabled() -> bool:
	check(DATA.layout.motion_version==1 and DATA.dispatch.action_version==1,"formal third shop enables authoritative movement and actions")
	return DATA.layout.motion_version==1 and DATA.dispatch.action_version==1

func _state(wrapper: Dictionary) -> Dictionary:
	return bytes_to_var(Marshalls.base64_to_raw(wrapper.state))

func test_formal_shop_uses_shared_baselines_and_keeps_business_structure_after_calibration() -> void:
	_enabled()
	for kind in DATA.staff.kinds:
		var path := "res://content/characters/staff/%s.tres"%kind.id
		check(ResourceLoader.exists(path),"registered global employee: "+kind.id)
		if ResourceLoader.exists(path): check(is_same(kind,load(path)),"shop references the one global employee definition: "+kind.id)
	check_eq(DATA.fulfillment.dine_rule,"self_pickup","original delivery policy preserved")
	check_eq(DATA.fulfillment.flow_version,1,"front production explicitly enables the shared flow protocol")
	check_eq(DATA.save_file,LEGACY.save_file,"existing progress path retained")
	check_eq(DATA.staff.starting,LEGACY.staff.starting,"starting identities preserved")
	check_eq(DATA.staff.hire_pool,LEGACY.staff.hire_pool,"hire order preserved")
	check_eq(DATA.layout.motion_units,887.0/720.0,"native art density")
	for dish in DATA.dishes:
		var old := LEGACY.dish(dish.id)
		if dish.id=="plum_juice":
			check(dish.front,"the added recipe belongs to front production")
			continue
		check_eq(dish.price_parts,old.price_parts,"dish price unchanged: "+dish.id)
		check_eq(dish.steps.size(),old.steps.size(),"recipe indices preserved: "+dish.id)
	var comparable := DATA.copy_for_editing()
	comparable.staff.kinds = LEGACY.staff.duplicate(true).kinds
	comparable.layout = LEGACY.layout.duplicate(true)
	comparable.dispatch.action_version = 0
	comparable.dispatch.transport_helpers.clear()
	comparable.dispatch.preposition_work = false
	comparable.dispatch.prefetch_inputs = false
	comparable.dispatch.base_scores.erase("continuation")
	comparable.fulfillment.flow_version = 0
	comparable.fulfillment.arrival = LEGACY.fulfillment.arrival
	comparable.items.assign(comparable.items.filter(func(item: SpecItem) -> bool: return item.id!="plum_juice"))
	comparable.dishes.assign(comparable.dishes.filter(func(dish: SpecDish) -> bool: return dish.id!="plum_juice"))
	comparable.stations.assign(comparable.stations.filter(func(station: SpecStation) -> bool: return station.id!="plum_dispenser"))
	for stage in comparable.stages: stage.order_weights.erase("plum_juice")
	var content := preload("res://game/rules/shop_content_contract.gd")
	check_eq(content.describe(comparable).structure,content.describe(LEGACY).structure,"recipe and policy structure remains compatible after numeric calibration")

func test_legacy_samples_cover_real_jobs_and_validate_without_modern_protocols() -> void:
	var captured: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STATES))
	for key in ["closed","job_go_from","job_pick","job_go_to","job_drop","job_work","job_home","guest_to_pickup","guest_await","guest_to_seat","guest_eating","active"]:
		check(captured.states.has(key),"captured real legacy phase: "+key)
	for key in captured.states:
		var rules := ShopRules.new(LEGACY,11)
		check_eq(rules.load_dict(_state(captured.states[key])),"","frozen original state is valid: "+key)

func test_multistation_module_can_bind_shared_counter_and_waiting_ports() -> void:
	var art: Node2D = load("res://presentation/shop/modules/ShopTemplate.tscn").instantiate()
	nodes.append(art)
	var counter: Node = art.get_node("Sortables/Counter")
	check(counter.get("station_slots")!=null,"one shared fixture supports several functional station ports")
	if counter.get("station_slots")==null: return
	var slots: Dictionary[String,String] = {"pickup":"window"}
	counter.set("station_slots",slots)
	var part: Node = load("res://presentation/shop/modules/station.tscn").instantiate()
	nodes.append(part)
	var group := Node2D.new()
	group.name = "Slots"
	counter.get_node("Anchors").add_child(group)
	var anchors: Node = part.get_node("Anchors/Station").duplicate()
	anchors.name = "pickup"
	group.add_child(anchors)
	group = Node2D.new()
	group.name = "Slots"
	counter.get_node("Nav").add_child(group)
	var nav := Node2D.new()
	nav.name = "pickup"
	group.add_child(nav)
	var work := Node2D.new()
	work.name = "Work"
	work.position = Vector2(120,40)
	nav.add_child(work)
	var waiting := Node2D.new()
	waiting.name = "Pickup"
	counter.get_node("Nav").add_child(waiting)
	for i in 2:
		var point := Node2D.new()
		point.name = str(i)
		point.position = Vector2(120+i*40,100)
		waiting.add_child(point)
	var reader := ShopAnchors.new(art.get_node("Anchors"))
	check(reader.has("Stations/window/Tap"),"secondary tap belongs to shared counter")
	var result := reader.export_layout(SpecLayout.new())
	check_eq(result.errors,[],"multi-port module exports")
	if result.layout!=null:
		check_eq(result.layout.points.window,Vector2(220,260),"secondary work port uses shared module origin")
		check_eq(result.layout.customer_points["pickup:1"],Vector2(260,320),"authored waiting port replaces synthetic scatter")

func test_legacy_active_progress_adopts_new_ports_without_losing_goods_jobs_or_timers() -> void:
	if not _enabled(): return
	var captured: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STATES))
	for key in captured.states:
		var old: Dictionary = _state(captured.states[key])
		var rules := ShopRules.new(DATA,11)
		check_eq(rules.load_dict(old,true),"","adopt original active phase: "+key)
		if rules.clock!=old.clock: continue
		check_eq(rules.gold,old.gold,"gold retained: "+key)
		check_eq(rules.sold,old.sold,"sales retained: "+key)
		check_eq(rules.serve.goods,old.serve.goods,"goods identities/locations/reservations retained: "+key)
		var expected_units: Array = old.serve.units.duplicate(true)
		for unit: Dictionary in expected_units:
			unit.flow_version = 1
			unit.recipe_signature = preload("res://game/rules/production_plan.gd").compile(DATA,unit.dish).signature
		check_eq(rules.serve.units,expected_units,"production progress retained with explicit flow identity: "+key)
		check_eq(rules.serve.jobs,old.serve.jobs,"assignments retained: "+key)
		for worker: Dictionary in rules.workers:
			var role := Flow.role(rules,worker)
			var profile := role if DATA.layout.actor_areas.has(role) else "staff"
			check(rules.nav.can_stand(worker.pos,profile),"adopted employee has a legal footprint: "+key)
			var original: Dictionary = old.roster.filter(func(row: Dictionary) -> bool: return row.id==worker.id)[0]
			check_eq(worker.action_left,original.action_left,"remaining work time retained: "+key)
			if worker.walking:
				var job: Dictionary = Flow.job_of(rules,worker)
				if not job.is_empty():
					var target: Vector2 = rules.nav.post(worker.post) if job.stage=="home" else Flow._point(rules,job.to if job.stage=="go_to" else job.from)
					check_eq(worker.motion.goal,target,"movement rebuilt for current business port: "+key)
		var resumed := ShopRules.new(DATA,11)
		check_eq(resumed.load_dict(rules.to_dict()),"","adoption output independently validates: "+key)
		for tick in 50:
			rules.step(0.1)
			resumed.step(0.1)
		check_eq(resumed.to_dict(),rules.to_dict(),"adopted state resumes exactly: "+key)

func test_formal_geometry_and_customer_pickup_positions_cannot_enter_furniture_or_kitchen() -> void:
	if not _enabled(): return
	var prepared := Contract.prepare(DATA)
	check_eq(prepared.errors,[],"formal scene and exported space agree")
	if prepared.art!=null: nodes.append(prepared.art)
	var rules := ShopRules.new(DATA,11)
	for station in DATA.stations: rules.unlocked[station.id] = true
	rules.nav.set_open(rules.unlocked)
	check(not rules.nav.can_stand(Vector2(400,850),"staff"),"service counter is solid")
	check(not rules.nav.can_stand(Vector2(400,340),"customer"),"customer cannot enter kitchen")
	check(rules.nav.path(Vector2(215,755),Vector2(121,1010),"staff").size()>2,"staff reach dining through the passage")
	for i in 16:
		var key := "pickup:%d"%i
		check(DATA.layout.customer_points.has(key),"explicit pickup waiting slot: "+key)
		if DATA.layout.customer_points.has(key): check(rules.nav.can_stand(DATA.layout.customer_points[key],"customer"),"pickup queue does not fall inside a table")

func _write(path: String, wrapper: Dictionary) -> PackedByteArray:
	var bytes := JSON.stringify(wrapper,"  ").to_utf8_buffer()
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	if path not in files: files.append(path)
	return bytes

func _backups(path: String) -> Array[String]:
	var out: Array[String] = []
	for name in DirAccess.get_files_at(path.get_base_dir()):
		if name.begins_with(path.get_file()+".pre-content-"): out.append(path.get_base_dir().path_join(name))
	return out

func test_real_legacy_file_preserves_original_bytes_and_progress_before_first_replacement() -> void:
	if not _enabled(): return
	var captured: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STATES))
	var path := "user://stirfry-adopt-%d-%d.json"%[OS.get_process_id(),Time.get_ticks_usec()]
	var original := _write(path,captured.states.mid_walk_collision)
	var store := ShopSave.new(DATA,path)
	var rules := store.load_game()
	check_eq(store.load_error,OK,"valid old progress is adopted rather than quarantined")
	check_eq(rules.clock,_state(captured.states.mid_walk_collision).clock,"actual old simulation progress retained")
	check_eq(FileAccess.get_file_as_bytes(path),original,"loading does not replace original bytes")
	check_eq(store.save_game(rules),OK,"first new save succeeds")
	var backups := _backups(path)
	files.append_array(backups)
	check_eq(backups.size(),1,"one verified pre-content backup")
	if not backups.is_empty(): check_eq(FileAccess.get_file_as_bytes(backups[0]),original,"backup is original old file, byte for byte")
	var reopened := ShopSave.new(DATA,path)
	check_eq(reopened.load_game().to_dict(),rules.to_dict(),"new protocol round trip is exact")
	check_eq(reopened.load_error,OK,"reopen succeeds")

func test_impossible_adoption_keeps_old_bytes_without_permanently_locking_entry() -> void:
	if not _enabled(): return
	var captured: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STATES))
	var shop := DATA.copy_for_editing()
	# Only the old active pantry task is incompatible; the fresh spawn is legal.
	shop.layout.obstacles.append(Rect2(180,640,40,40))
	shop.layout.obstacle_stations.append("")
	var path := "user://stirfry-no-route-%d-%d.json"%[OS.get_process_id(),Time.get_ticks_usec()]
	var original := _write(path,captured.states.mid_walk_collision)
	var store := ShopSave.new(shop,path)
	var recovered := store.load_game()
	check_eq(store.load_error,OK,"unmigratable old positions cannot permanently lock entry")
	check_eq(recovered.clock,0.0,"fresh business returned after durable old-file backup")
	var backups: Array[String] = []
	for name in DirAccess.get_files_at("user://"):
		if name.begins_with(path.get_file()+".corrupt-"): backups.append("user://"+name)
	files.append_array(backups)
	check_eq(backups.size(),1,"old business retained for recovery")
	if not backups.is_empty(): check_eq(FileAccess.get_file_as_bytes(backups[0]),original,"failed adoption preserves original bytes")
	check_eq(store.save_game(recovered),OK,"safe recovered business can save")
	var reopened := ShopSave.new(shop,path)
	check_eq(reopened.load_game().to_dict(),recovered.to_dict(),"subsequent entry uses recovered business")
	check_eq(reopened.load_error,OK,"recovered shop does not return to retry")

func test_legacy_routes_are_retargeted_to_current_ports_and_future_protocols_are_not_overwritten() -> void:
	if not _enabled(): return
	var captured: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STATES))
	var shop := DATA.copy_for_editing()
	shop.layout.points.pantry += Vector2(40,0)
	var rules := ShopRules.new(shop,11)
	check_eq(rules.load_dict(_state(captured.states.mid_walk_collision),true),"","port changes adopt old walking task")
	var saw_port := false
	for worker: Dictionary in rules.workers:
		var job := Flow.job_of(rules,worker)
		if job.get("from","")=="pantry":
			saw_port = true
			check_eq(worker.motion.goal,Vector2(240,660),"old route endpoint is replaced by current pantry port")
	check(saw_port,"actual captured task goes to pantry")
	var state := rules.to_dict()
	state.movement.version = 2
	var wrapper: Dictionary = captured.states.mid_walk_collision.duplicate(true)
	var bytes := var_to_bytes(state)
	wrapper.state = Marshalls.raw_to_base64(bytes)
	wrapper.state_sha256 = bytes.hex_encode().sha256_text()
	var path := "user://stirfry-future-%d-%d.json"%[OS.get_process_id(),Time.get_ticks_usec()]
	var original := _write(path,wrapper)
	var store := ShopSave.new(shop,path)
	store.load_game()
	check_eq(store.load_error,ERR_UNAVAILABLE,"future movement protocol is protected")
	check(store.save_game(ShopRules.new(shop))!=OK,"future state cannot be replaced")
	check_eq(FileAccess.get_file_as_bytes(path),original,"future file remains byte-identical")

func test_formal_movement_respects_speed_footprints_arrivals_and_pause_through_real_sales() -> void:
	if not _enabled(): return
	var rules := ShopRules.new(DATA,11)
	rules.unlock("wok_a")
	var seen := {"take":0,"made":0,"pickup":0}
	var on_take := func(event: Dictionary) -> void:
		seen.take += 1
		var row: Dictionary = rules.movement.customers["guest:%d"%int(event.guest)]
		check(row.pos.is_equal_approx(DATA.layout.customer_queue[0]),"order is taken only at actual front queue port")
	var on_made := func(event: Dictionary) -> void:
		seen.made += 1
		check(rules.workers.any(func(worker: Dictionary) -> bool: return Vector2(worker.pos).is_equal_approx(rules.nav.point(event.station))),"work commits only at the real station port")
	var on_pickup := func(event: Dictionary) -> void:
		seen.pickup += 1
		var at: Vector2 = rules.movement.customers["guest:%d"%int(event.guest)].pos
		var arrived := false
		for key in DATA.layout.customer_points:
			if String(key).begins_with("pickup:") and at.is_equal_approx(DATA.layout.customer_points[key]): arrived = true
		check(arrived,"physical pickup occurs at an authored waiting port")
	rules.events.on("order_taken",on_take)
	rules.events.on("made",on_made)
	rules.events.on("picked_up",on_pickup)
	for tick in 2400:
		var before := {}
		for worker: Dictionary in rules.workers: before[worker.id] = {"pos":worker.pos,"speed":rules.walk_speed(worker)}
		var old_customers: Dictionary = rules.movement.customers.duplicate(true)
		rules.step(0.1)
		for worker: Dictionary in rules.workers:
			check(rules.nav.can_stand(worker.pos,"staff"),"employee footprint stays outside furniture")
			if before.has(worker.id): check(Vector2(before[worker.id].pos).distance_to(worker.pos)<=maxf(before[worker.id].speed,rules.walk_speed(worker))*0.1+0.01,"employee travel cannot exceed shared speed")
			if worker.has("action") and worker.action.started:
				var step: Dictionary = worker.action.steps[worker.action.index]
				if step.kind in ["pickup","operate","drop"]: check(Vector2(worker.pos).is_equal_approx(Flow._point(rules,step.target)) and not worker.walking,"hand actions require actual arrival")
		for key in rules.movement.customers:
			var row: Dictionary = rules.movement.customers[key]
			check(rules.nav.can_stand(row.pos,"customer"),"customer stays in permitted furniture-free space")
			if old_customers.has(key): check(Vector2(old_customers[key].pos).distance_to(row.pos)<=170.0*DATA.layout.motion_units*0.1+0.01,"customer uses shared logical speed")
		if tick==800:
			rules.execute_command("set_paused",{"paused":true})
			var paused := rules.to_dict()
			rules.step(5.0)
			check_eq(rules.to_dict(),paused,"pause holds every rule, route and action")
			rules.execute_command("set_paused",{"paused":false})
	rules.events.off("order_taken",on_take)
	rules.events.off("made",on_made)
	rules.events.off("picked_up",on_pickup)
	check(seen.take>0 and seen.made>0 and seen.pickup>0 and rules.sold>0,"real third-shop business reaches every physical lifecycle boundary")

func test_formal_full_menu_can_complete_every_recipe_with_shared_employees() -> void:
	if not _enabled(): return
	var rules := ShopRules.new(DATA,11)
	rules.gold = 1000000.0
	for i in DATA.stages.size()+1:
		var next := rules.next_unlock()
		if next.is_empty(): break
		check_eq(rules.unlock(next),"","formal menu unlocks through normal rules")
	for i in 10:
		if not rules.hire().is_empty(): break
		rules.deploy_worker(rules.roster[-1].id)
	var sold := {}
	var delivered := func(event: Dictionary) -> void: sold[event.dish] = int(sold.get(event.dish,0))+1
	rules.events.on("delivered",delivered)
	for tick in 12000:
		rules.step(0.1)
		if sold.size()==DATA.dishes.size(): break
	rules.events.off("delivered",delivered)
	for dish in DATA.dishes: check(int(sold.get(dish.id,0))>0,"formal shared system sells "+dish.id)
	check_eq(ShopRules.new(DATA,11).load_dict(rules.to_dict()),"","full production menu state restores independently")
