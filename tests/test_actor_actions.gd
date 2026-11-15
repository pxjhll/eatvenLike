extends "res://tests/test_case.gd"
const LegacyRules := preload("res://tests/fixtures/legacy_shops/reference_rules.gd")
const LegacySave := preload("res://tests/fixtures/legacy_shops/reference_save.gd")
const MODULE := "res://game/rules/rule_actions.gd"
const Context := preload("res://tests/fixtures/action_context.gd")
const Worker := preload("res://game/rules/worker_state.gd")
const ShopFixture := preload("res://tests/fixtures/movement_shop.gd")
const Serve := preload("res://game/rules/serve_flow.gd")
var paths: Array[String] = []

func cleanup() -> void:
	for path in paths:
		for file in DirAccess.get_files_at("user://"):
			if file.begins_with(path.get_file()): DirAccess.remove_absolute("user://"+file)

func _write_file(path: String, state: Dictionary, shop: SpecShop) -> String:
	var bytes := var_to_bytes(state)
	var wrapper := {"format":ShopSave.FORMAT,"version":ShopSave.VERSION,"shop":shop.id,"speed":2.0,
		"content":preload("res://game/rules/shop_content_contract.gd").describe(shop),
		"state":Marshalls.raw_to_base64(bytes),"state_sha256":bytes.hex_encode().sha256_text()}
	var text := JSON.stringify(wrapper)
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return text

func _shop() -> SpecShop:
	var shop := ShopFixture.definition()
	if not shop.dispatch.get_property_list().any(func(p: Dictionary) -> bool: return p.name=="action_version"):
		check(false,"dispatch must explicitly declare the action protocol")
		return null
	shop.dispatch.set("action_version",1)
	return shop

func _opened() -> ShopRules:
	var shop := _shop()
	if shop==null: return null
	var rules := LegacyRules.new(shop,42)
	rules.gold = 100000.0
	rules.unlock(shop.goals.opening_station)
	return rules

func _actions() -> Variant:
	if not ResourceLoader.exists(MODULE):
		check(false,"shared action lifecycle must exist")
		return null
	return load(MODULE)

func _step(kind: String, target := "", seconds := 0.2) -> Dictionary:
	return {"kind":kind,"target":target,"seconds":seconds,"label":kind,"data":{}}

func _worker(id := 1) -> Dictionary:
	return Worker.create(id,"cat","cat",{},Vector2(30,50))

func _plan() -> Array:
	return [_step("move","from"),_step("pickup"),_step("operate"),_step("transport","to"),_step("wait","",0.3),_step("drop")]

func test_real_inventory_executes_all_six_atoms_once_and_releases_lease() -> void:
	var actions = _actions()
	if actions==null: return
	var context := Context.new()
	var worker := _worker()
	check_eq(actions.start(worker,_plan(),context),"","program starts")
	for tick in 100: actions.tick(worker,0.1,context)
	check_eq([context.stock,context.output,context.processed,worker.carry_count],[0,1,1,0],"one real input becomes one finished delivery")
	check_eq(context.committed,["move","pickup","operate","transport","wait","drop"],"each actual effect commits once")
	check(context.locks.is_empty(),"final commit releases workbench")
	check_eq(worker.pos,Vector2(150,50),"transport reaches actual destination")
	check_eq(worker.action.status,"completed","program has an explicit terminal state")
	check(not actions.cancel(worker,context),"completed program cannot compensate delivered stock")
	check_eq(context.output,1,"completed result is stable")

func test_precondition_waits_without_consuming_time_or_inventory() -> void:
	var actions = _actions()
	if actions==null: return
	var context := Context.new()
	context.available = false
	var worker := _worker()
	check_eq(actions.start(worker,[_step("pickup","",0.4)],context),"","blocked plan retains its reservation")
	for tick in 10: actions.tick(worker,0.1,context)
	check_eq([context.stock,worker.carry_count],[1,0],"blocked pickup cannot consume stock")
	check_eq(worker.action.status,"blocked","waiting reason is saved")
	context.available = true
	actions.tick(worker,0.1,context)
	check_eq(worker.action_left,0.4,"starting after a guard leaves the full timer")
	actions.tick(worker,0.1,context)
	var remaining: float = worker.action_left
	context.available = false
	actions.tick(worker,2.0,context)
	check_eq(worker.action_left,remaining,"a lost precondition pauses active work")
	context.available = true
	for tick in 4: actions.tick(worker,0.1,context)
	check_eq([context.stock,worker.carry_count],[0,1],"work resumes the same item")

func test_invalid_plan_and_occupied_resource_never_partially_start() -> void:
	var actions = _actions()
	if actions==null: return
	for plan in [[],[_step("unknown")],[_step("wait","",-1.0)],[_step("wait","",NAN)]]:
		var context := Context.new()
		var worker := _worker()
		var before := worker.duplicate(true)
		check(not actions.start(worker,plan,context).is_empty(),"invalid plan rejected")
		check_eq(worker,before,"invalid plan leaves employee untouched")
		check(context.locks.is_empty(),"invalid plan does not reserve inventory")
	var context := Context.new()
	var first := _worker()
	check_eq(actions.start(first,[_step("wait","",1.0)],context),"","first lease accepted")
	var second := _worker(2)
	var before := second.duplicate(true)
	check(not actions.start(second,[_step("pickup")],context).is_empty(),"occupied workbench waits outside assignment")
	check_eq(second,before,"failed lease has no partial actor state")

func test_cancel_before_and_after_pickup_compensates_once() -> void:
	var actions = _actions()
	if actions==null: return
	for after_pickup in [false,true]:
		var context := Context.new()
		var worker := _worker()
		check_eq(actions.start(worker,[_step("pickup","",0.0),_step("transport","to"),_step("drop")],context),"","reserve transfer")
		if after_pickup:
			actions.tick(worker,0.1,context)
			check_eq([context.stock,worker.carry_count],[0,1],"material moved to hand before cancellation")
		check(actions.cancel(worker,context),"active cancellation succeeds")
		check(not actions.cancel(worker,context),"repeated cancellation is inert")
		check_eq([context.stock,context.output,worker.carry_count],[1,0,0],"cancel restores exactly one input")
		check(context.locks.is_empty(),"cancel frees lease")
		check(not worker.has("action") and not worker.has("motion"),"cancel clears execution requests")

func test_saved_partial_action_and_inventory_continue_independently() -> void:
	var actions = _actions()
	if actions==null: return
	var context := Context.new()
	var worker := _worker()
	actions.start(worker,_plan(),context)
	for tick in 15: actions.tick(worker,0.1,context)
	var encoded := var_to_bytes({"worker":worker,"world":context.snapshot()})
	var saved: Dictionary = bytes_to_var(encoded)
	var clone := Context.new()
	clone.restore(saved.world)
	check_eq(actions.validate(saved.worker.action),"","saved action is data-only and valid")
	for tick in 60:
		actions.tick(worker,0.1,context)
		actions.tick(saved.worker,0.1,clone)
	check_eq(saved.worker,worker,"same exact actor after independent continuation")
	check_eq(clone.snapshot(),context.snapshot(),"same inventory and leases after continuation")

func test_one_commit_per_tick_and_reentrant_replacement_does_not_enter_old_successor() -> void:
	var actions = _actions()
	if actions==null: return
	var context := Context.new()
	var worker := _worker()
	actions.start(worker,[_step("pickup","",0.0),_step("drop","",0.0)],context)
	actions.tick(worker,100.0,context)
	check_eq([context.stock,context.output,worker.carry_count],[0,0,1],"large dt cannot skip through multiple effects")
	var state := worker.duplicate(true)
	for dt in [0.0,-1.0,NAN,INF]: actions.tick(worker,dt,context)
	check_eq(worker,state,"invalid or paused time is inert")
	actions.cancel(worker,context)
	context.on_commit = func(actor: Dictionary,_step_data: Dictionary) -> void:
		actions.cancel(actor,context)
		actor.action = {"replacement":true}
	actions.start(worker,[_step("pickup","",0.0),_step("transport","to")],context)
	actions.tick(worker,0.1,context)
	check_eq(worker.action,{"replacement":true},"callback owns the replacement")
	check(not worker.walking,"old successor was not entered after replacement")
	check_eq(context.stock,1,"reassignment explicitly compensates the old scope")
	check(context.locks.is_empty(),"reassignment has no leaked workbench lease")
	context.on_commit = Callable()

func test_real_serve_jobs_use_atoms_and_keep_the_existing_inventory_ledger() -> void:
	var rules := _opened()
	if rules==null: return
	var kinds := {}
	for tick in 1600:
		rules.step(0.1)
		for worker: Dictionary in rules.workers:
			var job := Serve.job_of(rules,worker)
			if job.is_empty(): continue
			check(worker.has("action"),"real assignment owns a serializable action")
			if not worker.has("action"): return
			var action: Dictionary = worker.action
			check_eq(load(MODULE).validate(action),"","real active action validates")
			kinds[action.steps[action.index].kind] = true
	check(rules.sold>=3,"real recipe and deliveries complete")
	for kind in ["move","pickup","transport","drop","operate"]: check(kinds.has(kind),"real job uses "+kind)
	check_eq(LegacyRules.new(rules.shop).load_dict(rules.to_dict()),"","goods, orders and reservations remain consistent")

func test_action_configuration_requires_supported_business_and_shared_motion() -> void:
	var shop := _shop()
	if shop==null: return
	var validator := preload("res://game/rules/shop_spec_validator.gd")
	shop.layout.motion_version = 0
	check(validator.validate(shop).any(func(e: Dictionary) -> bool: return e.path=="dispatch.action_version"),"actions cannot bypass shared movement")
	for mode in ["single","handoff"]:
		var unsupported := ShopFixture.definition(mode)
		unsupported.dispatch.action_version = 1
		check_eq(validator.validate(unsupported),[],"business adapter supports shared movement: "+mode)
		unsupported.layout.motion_version = 0
		check(validator.validate(unsupported).any(func(e: Dictionary) -> bool: return e.path=="dispatch.action_version"),"business adapter requires shared movement: "+mode)
	shop.layout.motion_version = 1
	shop.dispatch.action_version = 2
	check(validator.validate(shop).any(func(e: Dictionary) -> bool: return e.path=="dispatch.action_version"),"future action configuration is rejected")

func test_active_atoms_roundtrip_and_legacy_stage_rebuild_without_replaying_effects() -> void:
	var rules := _opened()
	if rules==null: return
	var seen := {}
	for tick in 1800:
		rules.step(0.1)
		for worker: Dictionary in rules.workers:
			if not worker.has("action"): continue
			var kind := String(worker.action.steps[worker.action.index].kind)
			if seen.has(kind): continue
			seen[kind] = true
			var data := rules.to_dict()
			var clone := LegacyRules.new(rules.shop)
			check_eq(clone.load_dict(data),"","active atom loads: "+kind)
			check_eq(clone.to_dict(),data,"active atom preserves exact state")
			var old := data.duplicate(true)
			for row: Dictionary in old.roster: row.erase("action")
			var migrated := LegacyRules.new(rules.shop)
			check_eq(migrated.load_dict(old),"","legacy phase can be adopted")
			for row: Dictionary in migrated.workers:
				if Serve.job_of(migrated,row).is_empty(): continue
				check(row.has("action"),"adoption reconstructs action before publishing loaded rules")
				check_eq(row.action_left,old.roster.filter(func(w: Dictionary) -> bool: return w.id==row.id)[0].action_left,"remaining duration is retained")
			for advance in 12:
				rules.step(0.1)
				clone.step(0.1)
				migrated.step(0.1)
			check_eq(clone.to_dict(),rules.to_dict(),"normal continuation is exact: "+kind)
			check_eq(migrated.to_dict(),rules.to_dict(),"legacy continuation does not retake materials: "+kind)
		if seen.size()>=5: break
	for kind in ["move","pickup","operate","transport","drop"]: check(seen.has(kind),"actual partial atom captured: "+kind)

func test_malformed_action_versions_cursors_bindings_and_effects_are_rejected_atomically() -> void:
	var rules := _opened()
	if rules==null: return
	for tick in 400:
		rules.step(0.1)
		if rules.workers.any(func(w: Dictionary) -> bool: return w.has("action")): break
	var data := rules.to_dict()
	var index := -1
	for i in data.roster.size():
		if data.roster[i].has("action"): index = i; break
	check(index>=0,"real action for corruption checks")
	if index<0: return
	for change in ["version","cursor","binding","effect","started"]:
		var bad := data.duplicate(true)
		var action: Dictionary = bad.roster[index].action
		match change:
			"version": action.version = 2
			"cursor": action.index = action.steps.size()
			"binding": action.lease.owner = -1
			"effect": action.steps[action.index].kind = "drop"
			"started": action.started = false
		check(not rules.load_dict(bad).is_empty(),"invalid atom rejected: "+change)
		check_eq(rules.to_dict(),data,"invalid action cannot replace live rules")

func test_real_operation_pauses_on_missing_inputs_then_continues_same_reservation() -> void:
	var rules := _opened()
	if rules==null: return
	for tick in 1200:
		rules.step(0.1)
		for worker: Dictionary in rules.workers:
			var job := Serve.job_of(rules,worker)
			if not worker.has("action") or job.get("kind","")!="work" or worker.action.steps[worker.action.index].kind!="operate": continue
			var goods: Array = rules.serve.goods.filter(func(g: Dictionary) -> bool: return g.owner==job.unit and g.at==job.from)
			if goods.is_empty(): continue
			var good: Dictionary = goods[0]
			var location: String = good.at
			good.at = rules.counter_id
			var seconds: float = worker.action_left
			var user: int = rules.stations[location].user
			rules.run(0.5)
			check_eq(worker.action_left,seconds,"missing inputs never burn operation time")
			check_eq(worker.action.status,"blocked","operation waits explicitly")
			check_eq(rules.stations[location].user,user,"same worker keeps station lease")
			good.at = location
			rules.run(40.0)
			check(rules.sold>0,"same physical inputs resume into a sale")
			check_eq(LegacyRules.new(rules.shop).load_dict(rules.to_dict()),"","resumed inventory remains consistent")
			return
	check(false,"actual operation captured with inputs")

func test_real_cancel_before_and_after_pickup_preserves_goods_and_frees_job() -> void:
	for carried in [false,true]:
		var rules := _opened()
		if rules==null: return
		var found := false
		for tick in 1500:
			rules.step(0.1)
			for worker: Dictionary in rules.workers:
				var job := Serve.job_of(rules,worker)
				if not worker.has("action") or job.get("kind","")!="carry" or (worker.carry_count>0)!=carried: continue
				var ids: Array = rules.serve.goods.map(func(g: Dictionary) -> int: return g.id)
				var source: String = job.from
				var good_id := int(job.good)
				check_eq(rules.execute_command("recall_worker",{"id":worker.id}).code,"ok","real recall cancels atomic program")
				check(not worker.has("action") and not worker.has("motion"),"all execution requests cleared")
				check_eq(rules.serve.goods.map(func(g: Dictionary) -> int: return g.id),ids,"cancel does not create or delete an item")
				if good_id>=0:
					var good := Serve._good(rules,good_id)
					check_eq([good.at,good.res],[source,-1],"reserved or carried good is released at source")
				check_eq(LegacyRules.new(rules.shop).load_dict(rules.to_dict()),"","cancelled state immediately saves")
				found = true
				break
			if found: break
		check(found,"captured actual transfer cancellation, carried="+str(carried))

func test_old_action_file_is_backed_up_and_future_action_file_is_protected() -> void:
	var rules := _opened()
	if rules==null: return
	for tick in 400:
		rules.step(0.1)
		if rules.workers.any(func(w: Dictionary) -> bool: return w.has("action")): break
	var data := rules.to_dict()
	var old := data.duplicate(true)
	for row: Dictionary in old.roster: row.erase("action")
	var path := "user://actor-actions-%d-%d.json"%[OS.get_process_id(),Time.get_ticks_usec()]
	paths.append(path)
	var original := _write_file(path,old,rules.shop)
	var store := LegacySave.new(rules.shop,path)
	var adopted := store.load_game()
	check_eq(store.load_error,OK,"old action-less file is adopted")
	check_eq(store.save_game(adopted),OK,"adopted file can be saved")
	var backups := Array(DirAccess.get_files_at("user://")).filter(func(file: String) -> bool: return file.begins_with(path.get_file()+".pre-content-"))
	check_eq(backups.size(),1,"adoption has a durable original backup")
	if backups.size()==1: check_eq(FileAccess.get_file_as_string("user://"+backups[0]),original,"original bytes retained")
	var future := data.duplicate(true)
	for row: Dictionary in future.roster:
		if row.has("action"): row.action.version = 2
	var future_text := _write_file(path,future,rules.shop)
	var reader := LegacySave.new(rules.shop,path)
	reader.load_game()
	check_eq(reader.load_error,ERR_UNAVAILABLE,"future action version is protected")
	check_eq(reader.save_game(rules),ERR_UNAVAILABLE,"future action file cannot be overwritten")
	check(FileAccess.file_exists(path),"future file remains in place")
	if FileAccess.file_exists(path): check_eq(FileAccess.get_file_as_string(path),future_text,"future file is byte-identical")

func test_real_transfer_can_insert_a_wait_atom_and_resume_saved_carried_item() -> void:
	var rules := _opened()
	if rules==null: return
	var adapter := preload("res://game/rules/serve_action_context.gd")
	for tick in 1000:
		rules.step(0.1)
		for worker: Dictionary in rules.workers:
			if not worker.has("action") or worker.action.steps[worker.action.index].kind!="pickup": continue
			worker.action.steps.insert(worker.action.index+1,adapter.step("wait","","等待",0.5))
			var guard := 0
			while worker.action.steps[worker.action.index].kind!="wait" and guard<100:
				rules.step(0.1)
				guard += 1
			check_eq(worker.carry_count,1,"wait follows one actual pickup")
			var saved := rules.to_dict()
			var clone := LegacyRules.new(rules.shop)
			check_eq(clone.load_dict(saved),"","custom wait between atoms saves")
			check_eq(clone.to_dict(),saved,"carried object and wait timer retained")
			for advance in 150:
				rules.step(0.1)
				clone.step(0.1)
			check_eq(clone.to_dict(),rules.to_dict(),"wait composition resumes without another pickup")
			return
	check(false,"real pickup available for wait composition")

func test_detached_action_summary_and_simulation_speeds_keep_one_authority() -> void:
	var baseline := _opened()
	if baseline==null: return
	baseline.run(10.0)
	var expected := baseline.to_dict()
	expected.erase("_accumulator")
	for dt in [0.1,0.2,0.4]:
		var rules := LegacyRules.new(baseline.shop,42)
		rules.gold = 100000.0
		rules.unlock(rules.shop.goals.opening_station)
		for tick in roundi(10.0/dt): rules.step(dt)
		var actual := rules.to_dict()
		actual.erase("_accumulator")
		check_eq(actual,expected,"same rule duration at speed input "+str(dt))
	baseline.paused = true
	var before := baseline.to_dict()
	baseline.step(100.0)
	check_eq(baseline.to_dict(),before,"pause freezes actions and reservations")
	var frame := ShopView.new(baseline).render_snapshot()
	check(frame.has("actions"),"read model exposes an explicit action summary")
	if not frame.has("actions"): return
	check(not frame.actions.is_empty(),"actual active action summary")
	frame.actions.clear()
	for row: Dictionary in frame.workers:
		if row.has("action"): row.action.steps.clear()
	check_eq(baseline.to_dict(),before,"read-model mutation cannot erase live actions")

func test_business_event_snapshots_preserve_valid_committed_actions() -> void:
	var rules := _opened()
	if rules==null: return
	var seen := {}
	var listener := func(event: Dictionary) -> void:
		if event.name not in ["order_taken","made","picked_up","sale","eat_start"] or seen.has(event.name): return
		seen[event.name] = true
		var state := rules.to_dict()
		var clone := LegacyRules.new(rules.shop)
		check_eq(clone.load_dict(state),"","event snapshot is a complete rule transaction: "+event.name)
		check_eq(clone.to_dict(),state,"event snapshot retains current action without normalization")
	rules.events.on("*",listener)
	rules.run(120.0)
	rules.events.off("*",listener)
	for name in ["order_taken","made","picked_up","sale","eat_start"]: check(seen.has(name),"real atomic business event covered: "+name)

func test_blocked_real_transport_retains_carried_identity_and_resumes_after_path_opens() -> void:
	var rules := _opened()
	if rules==null: return
	rules.shop.layout.obstacles = [Rect2(380,0,40,1280)]
	rules.nav.set_open(rules.unlocked)
	var found := false
	for tick in 900:
		rules.step(0.1)
		for worker: Dictionary in rules.workers:
			if not worker.has("action") or worker.action.status!="blocked" or worker.action.steps[worker.action.index].kind!="transport": continue
			var job := Serve.job_of(rules,worker)
			var id := int(job.good)
			var position: Vector2 = worker.pos
			var remaining: float = worker.action_left
			rules.run(1.0)
			check_eq(worker.pos,position,"blocked carrier stays on its side of the wall")
			check_eq(worker.action_left,remaining,"blocked travel does not consume hand-action time")
			check_eq(Serve._good(rules,id).at,"hand:"+str(worker.id),"same physical object remains in hand")
			check_eq(LegacyRules.new(rules.shop).load_dict(rules.to_dict()),"","blocked program and route save together")
			rules.shop.layout.obstacles.clear()
			rules.nav.set_open(rules.unlocked)
			rules.run(60.0)
			check(rules.sold>0,"original carrier continues into a sale")
			check_eq(LegacyRules.new(rules.shop).load_dict(rules.to_dict()),"","unblocked program is consistent")
			found = true
			break
		if found: break
	check(found,"real blocked transport captured")

func test_forged_transport_cursor_cannot_skip_the_physical_pickup() -> void:
	var rules := _opened()
	if rules==null: return
	for tick in 1000:
		rules.step(0.1)
		for worker: Dictionary in rules.workers:
			if not worker.has("action") or worker.action.steps[worker.action.index].kind!="pickup": continue
			var data := rules.to_dict()
			var row: Dictionary = data.roster.filter(func(w: Dictionary) -> bool: return w.id==worker.id)[0]
			var job: Dictionary = data.serve.jobs[str(worker.id)]
			row.action.index = 2
			row.phase = "walk"
			row.target = String(job.to)
			job.stage = "go_to"
			preload("res://game/rules/rule_movement.gd").request(row,rules.nav,Serve._point(rules,String(job.to)),"staff")
			check(not LegacyRules.new(rules.shop).load_dict(data).is_empty(),"transport cursor needs the already picked physical object")
			return
	check(false,"real pickup captured for cursor invariant")
