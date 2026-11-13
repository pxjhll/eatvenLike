extends "res://tests/test_case.gd"
const LegacyRules := preload("res://tests/fixtures/legacy_shops/reference_rules.gd")
const LegacySave := preload("res://tests/fixtures/legacy_shops/reference_save.gd")

const WorkerState := preload("res://game/rules/worker_state.gd")
const MODULE := "res://game/rules/rule_movement.gd"
const Fixture := preload("res://tests/fixtures/movement_shop.gd")
const Serve := preload("res://game/rules/serve_flow.gd")
var save_paths: Array[String] = []

class MeasuredNav extends RuleNav:
	var stand_checks := 0
	func can_stand(at: Vector2, profile := "staff") -> bool:
		stand_checks += 1
		return super.can_stand(at,profile)

func test_detour_validates_cell_footprints_once_and_keeps_full_route_validation() -> void:
	var layout := _layout()
	layout.obstacles = [Rect2(80,80,40,60)]
	var nav := MeasuredNav.new(layout)
	var route: PackedVector2Array = nav.path(Vector2(50,110),Vector2(170,110),"staff")
	check(route.size()>2,"real footprint-constrained detour exercises BFS")
	var maximum: int = layout.grid_size.x*layout.grid_size.y+2*route.size()+4
	check(nav.stand_checks<=maximum,"BFS reuses validated cell centers instead of rescanning footprints on every edge (%d>%d)"%[nav.stand_checks,maximum])
	for index in range(1,route.size()): check(nav.segment_clear(route[index-1],route[index]),"final segments still pass full physical clearance")
	layout.obstacles.append(Rect2(100,0,20,240))
	nav.set_open({})
	check(nav.path(Vector2(50,110),Vector2(170,110),"staff").is_empty(),"topology changes invalidate prevalidated cell centers")

func cleanup() -> void:
	for path in save_paths:
		for file in DirAccess.get_files_at("user://"):
			if file.begins_with(path.get_file()): DirAccess.remove_absolute("user://"+file)

func _write_state(path: String, state: Dictionary, shop: SpecShop) -> String:
	var bytes := var_to_bytes(state)
	var wrapper := {"format":ShopSave.FORMAT,"version":ShopSave.VERSION,"shop":shop.id,"speed":2.0,
		"content":preload("res://game/rules/shop_content_contract.gd").describe(shop),
		"state":Marshalls.raw_to_base64(bytes),"state_sha256":bytes.hex_encode().sha256_text()}
	var text := JSON.stringify(wrapper)
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return text

func _layout() -> SpecLayout:
	var data := SpecLayout.new()
	if not data.get_property_list().any(func(p: Dictionary) -> bool: return p.name == "motion_version"):
		check(false,"Layout must declare the opt-in shared movement protocol")
		return null
	data.set("motion_version",1)
	data.set("motion_units",1.0)
	data.nav = "grid"
	data.cell = 20.0
	data.grid_size = Vector2i(12,12)
	data.areas = [Rect2i(0,0,12,12)]
	data.set("actor_areas",{"staff":[Rect2i(0,0,12,12)],"customer":[Rect2i(0,0,5,12)]})
	return data

func test_empty_route_is_blocked_without_business_arrival() -> void:
	var worker := WorkerState.create(1,"cat","cat",{},Vector2(30,30))
	WorkerState.begin_walk(worker,PackedVector2Array(),"walk")
	check(not WorkerState.advance_walk(worker,100.0),"no route must never count as arrival")
	check_eq(worker.pos,Vector2(30,30),"blocked actor stays at actual position")
	check(worker.walking,"blocked request remains pending")

func test_grid_profiles_deny_backstage_and_unknown_access() -> void:
	var layout := _layout()
	if layout == null: return
	var nav := RuleNav.new(layout)
	check(not nav.call("path",Vector2(50,50),Vector2(190,50),"staff").is_empty(),"staff may enter kitchen")
	check(nav.call("path",Vector2(50,50),Vector2(190,50),"customer").is_empty(),"customer cannot enter kitchen")
	check(nav.call("path",Vector2(50,50),Vector2(70,50),"unknown").is_empty(),"unknown access cannot use all floor")
	check(nav.call("path",Vector2(89,50),Vector2(89,70),"customer").is_empty(),"footprint may not protrude across access boundary")

func test_radius_avoids_obstacles_edges_and_same_cell_endpoint_loss() -> void:
	var layout := _layout()
	if layout == null: return
	layout.obstacles = [Rect2(80,80,40,60)]
	var nav := RuleNav.new(layout)
	var route: PackedVector2Array = nav.call("path",Vector2(50,110),Vector2(170,110),"staff")
	check(route.size() > 2,"wall requires a detour")
	if route.is_empty(): return
	check_eq(route[0],Vector2(50,110),"exact starting position retained")
	check_eq(route[-1],Vector2(170,110),"exact destination retained")
	var footprint := Rect2(68,68,64,84)
	for index in range(1,route.size()):
		for step in 101:
			var point := route[index-1].lerp(route[index],float(step)/100.0)
			check(not footprint.has_point(point),"path never cuts expanded wall")
	check(nav.call("path",Vector2(5,50),Vector2(50,50),"staff").is_empty(),"footprint outside room cannot route")
	check(nav.call("path",Vector2(69,110),Vector2(50,110),"staff").is_empty(),"center outside wall is insufficient for foot radius")
	var close: PackedVector2Array = nav.call("path",Vector2(51,51),Vector2(55,55),"staff")
	check_eq(close,PackedVector2Array([Vector2(51,51),Vector2(55,55)]),"same-cell travel preserves both positions")

func test_blocked_request_replans_from_real_position_after_obstacle_change() -> void:
	var layout := _layout()
	if layout == null: return
	if not ResourceLoader.exists(MODULE):
		check(false,"shared movement kernel required")
		return
	var motion: Variant = load(MODULE)
	layout.obstacles = [Rect2(100,0,20,240)]
	layout.obstacle_stations = ["wall"]
	var nav := RuleNav.new(layout)
	nav.set_open({"wall":true})
	var actor := {"pos":Vector2(50,50),"path":PackedVector2Array(),"path_index":0,"walking":false}
	motion.request(actor,nav,Vector2(190,50),"staff")
	check(not motion.tick(actor,nav,1000.0),"unreachable goal remains pending")
	check_eq(actor.pos,Vector2(50,50),"blocked request cannot teleport")
	nav.set_open({})
	check(not motion.tick(actor,nav,40.0),"open path resumes with finite budget")
	check_eq(actor.pos,Vector2(90,50),"resume from actual origin")
	nav.set_open({"wall":true})
	check(not motion.tick(actor,nav,1000.0),"a new obstacle invalidates in-flight route")
	check_eq(actor.pos,Vector2(90,50),"blocked mid-route does not move into new wall")
	nav.set_open({})
	check(motion.tick(actor,nav,100.0),"reopened route reaches exact target")
	check_eq(actor.pos,Vector2(190,50),"exact final position")

func test_invalid_distance_never_moves_or_arrives() -> void:
	if not ResourceLoader.exists(MODULE):
		check(false,"shared movement kernel required")
		return
	var motion: Variant = load(MODULE)
	for value in [-1.0,INF,NAN]:
		var actor := {"pos":Vector2(30,30),"path":PackedVector2Array([Vector2(30,30),Vector2(70,30)]),"path_index":1,"walking":true}
		check(not motion.advance(actor,value),"invalid budget is rejected")
		check_eq(actor.pos,Vector2(30,30),"invalid budget preserves position")

func test_customer_must_reach_queue_before_any_order_is_taken() -> void:
	if _layout() == null: return
	for mode in ["serve","single"]:
		var rules := Fixture.opened(mode)
		if rules.get("movement") == null:
			check(false,"rules must own authoritative customer movement")
			return
		rules._next_customer = 0.1
		rules.run(1.0)
		check_eq(rules.get("movement").get("version",0),1,"rules owns versioned customer movement")
		if mode == "serve":
			check(not rules.serve.guests.is_empty(),"real serve guest spawned")
			check(rules.serve.orders.is_empty(),"cannot take a remote guest's order")
			check(rules.serve.jobs.values().all(func(job: Dictionary) -> bool: return job.kind != "take"),"cannot claim remote guest")
		else:
			check(not rules.customers.is_empty(),"real follower customer spawned")
			check(rules.workers.all(func(worker: Dictionary) -> bool: return worker.order < 0),"follower cannot claim remote guest")
		rules.run(20.0)
		check(rules.events.log.any(func(event: Dictionary) -> bool: return event.name == ("order_taken" if mode == "serve" else "sale")),"business resumes after physical arrival: "+mode)

func test_serve_blocked_seat_never_starts_eating_then_resumes() -> void:
	if _layout() == null: return
	var rules := Fixture.opened()
	rules.shop.fulfillment.dine_rule = "seat_wait"
	for tick in 200:
		rules.step(0.1)
		if not rules.serve.orders.is_empty(): break
	check(not rules.serve.orders.is_empty(),"order accepted after entry")
	if rules.serve.orders.is_empty(): return
	var guest: Dictionary = rules.serve.guests[0]
	rules.shop.layout.obstacles = [Rect2(0,620,1280,40)]
	rules.nav.set_open(rules.unlocked)
	rules.run(80.0)
	check_eq(guest.state,"to_seat","elapsed travel estimate cannot replace a blocked route")
	check_eq(guest.eat_left,0.0,"blocked guest has not started eating")
	check(not rules.events.log.any(func(e: Dictionary) -> bool: return e.name == "eat_start"),"no premature eating event")
	rules.shop.layout.obstacles.clear()
	rules.nav.set_open(rules.unlocked)
	rules.run(20.0)
	check(rules.events.log.any(func(e: Dictionary) -> bool: return e.name == "eat_start"),"unblocked seat continues existing order")

func test_pending_staff_path_does_not_start_work_in_any_mode() -> void:
	if _layout() == null: return
	for mode in ["serve","single","handoff"]:
		var rules := Fixture.opened(mode)
		if not rules.has_method("advance_move"):
			check(false,"every employee flow must use shared movement")
			return
		# A full-width wall isolates every employee from the production ports.
		rules.shop.layout.obstacles = [Rect2(0,240,1280,40)]
		rules.nav.set_open(rules.unlocked)
		var worker: Dictionary = rules.workers.back()
		worker.pos = Vector2(200,400)
		if mode == "single": rules._go(worker,rules.counter_id,"test")
		elif mode == "handoff": rules._walk(worker,rules.nav.point(rules.counter_id),"walk_pickup")
		else:
			rules.serve.jobs[str(worker.id)] = Serve._job("take",-1,-1,"",-1,rules.counter_id,rules.counter_id)
			Serve._go(rules,worker,rules.counter_id,"go_from")
		check(worker.path.is_empty(),"fixture has no route: "+mode)
		# Drive only the movement boundary; the fabricated request has no inventory side effects.
		check(not rules.call("advance_move",worker,10.0),"blocked employee cannot report arrival: "+mode)
		check_eq(worker.pos,Vector2(200,400),"employee stays outside wall: "+mode)

func test_blocked_customer_pickup_cannot_complete_delivery_in_any_mode() -> void:
	for mode in ["serve","single","handoff"]:
		var rules := Fixture.opened(mode)
		rules.shop.layout.obstacles = [Rect2(200,440,140,120)]
		rules.nav.set_open(rules.unlocked)
		rules.run(60.0)
		check_eq(rules.sold,0,"blocked pickup cannot sell: "+mode)
		if mode=="serve":
			check(not rules.serve.orders.is_empty(),"accepted orders remain pending")
			check(rules.serve.orders.all(func(o: Dictionary) -> bool: return not o.paid),"self pickup cannot bill before physical pickup")
		rules.shop.layout.obstacles.clear()
		rules.nav.set_open(rules.unlocked)
		rules.run(40.0)
		check(rules.sold>0,"pending delivery resumes without losing order: "+mode)

func test_pause_and_existing_speed_inputs_share_one_clock() -> void:
	for mode in ["serve","single","handoff"]:
		var baseline := Fixture.opened(mode)
		baseline.run(16.0)
		var expected := baseline.to_dict()
		expected.erase("_accumulator")
		for dt in [0.1,0.2,0.4]:
			var rules := Fixture.opened(mode)
			for tick in roundi(16.0/dt): rules.step(dt)
			var actual := rules.to_dict()
			actual.erase("_accumulator")
			check_eq(actual,expected,"same game duration, speed input "+str(dt)+" "+mode)
			check_eq(rules.movement,baseline.movement,"same authoritative positions at each speed")
			rules.paused = true
			var paused := rules.to_dict()
			var actors := rules.movement.duplicate(true)
			rules.step(10.0)
			check_eq(rules.to_dict(),paused,"pause freezes business and movement")
			check_eq(rules.movement,actors,"pause freezes position")

func test_native_units_do_not_change_logical_actor_speed() -> void:
	for mode in ["serve","single","handoff"]:
		var normal := Fixture.opened(mode)
		var dense := Fixture.opened(mode,2.0)
		normal.run(16.0)
		dense.run(16.0)
		check_eq(dense.sold,normal.sold,"pixel density cannot change delivery rhythm: "+mode)
		check_eq(dense.movement.customers.keys(),normal.movement.customers.keys(),"same identities across density")
		for key in normal.movement.customers:
			if dense.movement.customers.has(key): check(Vector2(dense.movement.customers[key].pos/2.0).is_equal_approx(normal.movement.customers[key].pos),"same logical customer position")
		for i in normal.workers.size(): check(Vector2(dense.workers[i].pos/2.0).is_equal_approx(normal.workers[i].pos),"same logical employee position")

func test_motion_roundtrip_legacy_rebuild_and_detached_view() -> void:
	for mode in ["serve","single","handoff"]:
		var rules := Fixture.opened(mode)
		rules.run(12.0)
		var data := rules.to_dict()
		check(data.has("movement"),"authoritative movement must be saved: "+mode)
		if not data.has("movement"): return
		var clone := LegacyRules.new(rules.shop)
		check_eq(clone.load_dict(data),"","active movement loads")
		check_eq(clone.to_dict(),data,"roundtrip does not normalize active positions")
		for tick in 30:
			rules.step(0.1)
			clone.step(0.1)
		check_eq(clone.to_dict(),rules.to_dict(),"exact independent continuation")
		var frame := ShopView.new(rules).render_snapshot()
		check(frame.has("movement"),"view must publish detached movement facts")
		if frame.has("movement"):
			frame.movement.customers.clear()
			check(not rules.movement.customers.is_empty(),"view caller cannot clear live positions")
		var old := data.duplicate(true)
		old.erase("movement")
		for worker: Dictionary in old.roster: worker.erase("motion")
		var migrated := LegacyRules.new(rules.shop)
		check_eq(migrated.load_dict(old),"","old state without positions can continue")
		check_eq(migrated.gold,data.gold,"migration retains money")
		check_eq(migrated.sold,data.sold,"migration retains sales")
		check_eq(migrated.workers.map(func(w: Dictionary) -> int: return w.id),old.workers,"migration retains employee identity")
		check(not migrated.movement.customers.is_empty(),"legacy migration builds movement records")
		var bad := data.duplicate(true)
		bad.movement.version = 2
		check(not LegacyRules.new(rules.shop).load_dict(bad).is_empty(),"future movement versions are rejected")

func test_invalid_new_spatial_contract_is_rejected_before_runtime() -> void:
	var validator := preload("res://game/rules/shop_spec_validator.gd")
	for key in ["motion_version","motion_units","actor_areas","customer_points","customer_queue","nav"]:
		var shop := Fixture.definition()
		match key:
			"motion_version": shop.layout.motion_version = 2
			"motion_units": shop.layout.motion_units = 0.0
			"actor_areas": shop.layout.actor_areas.erase("customer")
			"customer_points": shop.layout.customer_points.erase("pickup")
			"customer_queue": shop.layout.customer_queue.clear()
			"nav": shop.layout.nav = "straight"
		var errors: Array = validator.validate(shop)
		check(errors.any(func(error: Dictionary) -> bool: return String(error.path).begins_with("layout."+key)),"invalid shared movement configuration: "+key)

func test_scene_movement_units_must_match_native_canvas_density() -> void:
	var shop := Fixture.definition("handoff",2.0)
	var art: Node2D = load(shop.scene_path).instantiate()
	var contract := preload("res://presentation/shop/shop_scene_contract.gd")
	var errors: Array = contract.validate(shop,art)
	check(errors.any(func(error: Dictionary) -> bool: return error.code=="movement_units"),"a 720-wide art scene cannot use doubled simulation units")
	art.free()

func test_snapshot_keeps_blocked_requests_pending_without_running_animation() -> void:
	var rules := Fixture.opened("handoff",2.0)
	rules.shop.layout.obstacles = [Rect2(0,480,2560,80)]
	rules.nav.set_open(rules.unlocked)
	var worker: Dictionary = rules.workers[0]
	worker.pos = Vector2(400,800)
	rules.begin_move(worker,Vector2(400,400),"walk_pickup")
	var frame := ShopView.new(rules).render_snapshot()
	check(worker.walking,"live blocked request is still pending")
	check(not frame.workers[0].walking,"blocked worker uses a stationary pose")
	check_eq(frame.workers[0].get("speed"),112.0,"walk animation uses logical speed independent of canvas density")

func test_movement_file_migration_backs_up_old_state_and_protects_future_state() -> void:
	var rules := Fixture.opened()
	rules.run(12.0)
	var old := rules.to_dict()
	old.erase("movement")
	for worker: Dictionary in old.roster: worker.erase("motion")
	var path := "user://movement-%d-%d.json"%[OS.get_process_id(),Time.get_ticks_usec()]
	save_paths.append(path)
	var original := _write_state(path,old,rules.shop)
	var store := LegacySave.new(rules.shop,path)
	var migrated := store.load_game()
	check_eq(store.load_error,OK,"legacy movement file loads")
	check_eq(migrated.gold,rules.gold,"file migration keeps progress")
	check_eq(store.save_game(migrated,2.0),OK,"migrated movement can save")
	var backups := Array(DirAccess.get_files_at("user://")).filter(func(file: String) -> bool: return file.begins_with(path.get_file()+".pre-content-"))
	check_eq(backups.size(),1,"old file has one durable backup")
	if backups.size()==1: check_eq(FileAccess.get_file_as_string("user://"+backups[0]),original,"backup preserves original bytes")
	var reloaded := LegacySave.new(rules.shop,path).load_game()
	check_eq(reloaded.to_dict(),migrated.to_dict(),"new format file retains authoritative positions")
	var future := migrated.to_dict()
	future.movement.version = 2
	var future_text := _write_state(path,future,rules.shop)
	var reader := LegacySave.new(rules.shop,path)
	reader.load_game()
	check_eq(reader.load_error,ERR_UNAVAILABLE,"future movement file requires a compatible program")
	check_eq(reader.save_game(rules),ERR_UNAVAILABLE,"future movement file cannot be overwritten")
	check_eq(FileAccess.get_file_as_string(path),future_text,"future original bytes retained")

func test_malformed_motion_rejects_atomically_and_blocked_state_resumes() -> void:
	var rules := Fixture.opened()
	rules._next_customer = 0.1
	rules.run(1.0)
	var saved := rules.to_dict()
	var key: String = saved.movement.customers.keys()[0]
	for change in ["version","profile","path_index","arrival","goal"]:
		var bad := saved.duplicate(true)
		var row: Dictionary = bad.movement.customers[key]
		match change:
			"version": row.motion.version = 2
			"profile": row.motion.profile = "unknown"
			"path_index": row.path_index = row.path.size()+1
			"arrival": row.walking = false
			"goal": row.motion.goal += Vector2(100,0)
		var before := rules.to_dict()
		check(not rules.load_dict(bad).is_empty(),"reject malformed motion: "+change)
		check_eq(rules.to_dict(),before,"failed load is atomic")
	rules.shop.layout.obstacles = [Rect2(0,620,1280,40)]
	rules.nav.set_open(rules.unlocked)
	rules.run(2.0)
	var blocked := rules.to_dict()
	var clone := LegacyRules.new(rules.shop)
	check_eq(clone.load_dict(blocked),"","blocked pending route can save and load")
	check_eq(clone.to_dict(),blocked,"blocked path roundtrip is exact")
	rules.shop.layout.obstacles.clear()
	rules.nav.set_open(rules.unlocked)
	clone.nav.set_open(clone.unlocked)
	for tick in 100:
		rules.step(0.1)
		clone.step(0.1)
	check_eq(clone.to_dict(),rules.to_dict(),"unblocked original and restored pending routes resume identically")

func test_motion_is_valid_at_synchronous_business_events() -> void:
	for mode in ["serve","single","handoff"]:
		var rules := Fixture.opened(mode)
		var captured := {}
		var callback := func(event: Dictionary) -> void:
			if event.name not in ["order_taken","picked_up","seated","eat_start","sale","lost","left"] or captured.has(event.name): return
			captured[event.name] = true
			var state := rules.to_dict()
			var restored := LegacyRules.new(rules.shop)
			check_eq(restored.load_dict(state),"","event snapshot independently validates: "+event.name+" "+mode)
			check_eq(restored.to_dict(),state,"event snapshot preserves position and job")
		rules.events.on("*",callback)
		rules.run(100.0)
		rules.events.off("*",callback)
		check(captured.has("sale"),"real business events tested: "+mode)

func test_recalling_walking_serve_employee_cancels_pending_motion_and_keeps_save_valid() -> void:
	var rules := Fixture.opened()
	for tick in 600:
		rules.step(0.1)
		for worker: Dictionary in rules.workers:
			if not worker.walking or worker.path.is_empty() or not worker.has("motion") or Serve.job_of(rules,worker).is_empty(): continue
			var position: Vector2 = worker.pos
			check_eq(rules.execute_command("recall_worker",{"id":worker.id}).code,"ok","recall a real walking assignment")
			check_eq(worker.pos,position,"cancellation does not teleport employee")
			check(Serve.job_of(rules,worker).is_empty(),"assignment reservation is released")
			check(not worker.has("motion"),"cancellation removes pending route request")
			check_eq(LegacyRules.new(rules.shop).load_dict(rules.to_dict()),"","cancelled movement can immediately save")
			return
	check(false,"real walking assignment found for cancellation")

func test_second_employee_cannot_take_an_order_behind_the_claimed_queue_head() -> void:
	var rules := Fixture.opened()
	rules.shop.staff.zones.clear()
	rules.workers[1].post = ""
	Serve._spawn(rules)
	Serve._spawn(rules)
	var motion: Variant = load(MODULE)
	for row: Dictionary in rules.movement.customers.values(): motion.advance(row,10000.0)
	var first := Serve.candidates(rules,rules.workers[0]).filter(func(job: Dictionary) -> bool: return job.kind=="take")
	check(not first.is_empty(),"head reached the actual queue point")
	if first.is_empty(): return
	Serve._claim(rules,rules.workers[0],first[0])
	var second := Serve.candidates(rules,rules.workers[1]).filter(func(job: Dictionary) -> bool: return job.kind=="take")
	check(second.is_empty(),"another employee cannot serve someone still behind a claimed head")
