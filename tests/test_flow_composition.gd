extends "res://tests/test_case.gd"
const MODULE := "res://game/rules/production_plan.gd"
const Fixture := preload("res://tests/fixtures/flow_shop.gd")
const Serve := preload("res://game/rules/serve_flow.gd")
var paths: Array[String] = []

func cleanup() -> void:
	for path in paths:
		for file in DirAccess.get_files_at("user://"):
			if file.begins_with(path.get_file()): DirAccess.remove_absolute("user://"+file)

func _write_file(path: String, state: Dictionary, shop: SpecShop) -> String:
	var bytes := var_to_bytes(state)
	var wrapper := {"format":ShopSave.FORMAT,"version":ShopSave.VERSION,"shop":shop.id,"speed":2.0,
		"content":preload("res://game/rules/shop_content_contract.gd").describe(shop),"state":Marshalls.raw_to_base64(bytes),"state_sha256":bytes.hex_encode().sha256_text()}
	var text := JSON.stringify(wrapper)
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return text

func _active_bundle() -> ShopRules:
	var rules := _opened()
	if rules==null: return null
	for tick in 1600:
		rules.step(0.1)
		if rules.serve.jobs.values().any(func(job: Dictionary) -> bool: return job.kind=="bundle"): return rules
	check(false,"real active bundle found")
	return null

func _opened() -> ShopRules:
	var rules := Fixture.opened()
	check(rules!=null,"fulfillment must declare the explicit flow protocol")
	return rules

func _production() -> Variant:
	if not ResourceLoader.exists(MODULE):
		check(false,"shared production dependency plan must exist")
		return null
	return load(MODULE)

func _step(at: String, inputs: Dictionary, outputs: Dictionary) -> SpecStep:
	var step := SpecStep.new()
	step.station = at
	step.consumes.merge(inputs)
	step.produces.merge(outputs)
	return step

func _graph() -> SpecShop:
	var shop := SpecShop.new()
	for entry in [["source","supply"],["left","hand"],["right","hand"],["join","combine"]]:
		var station := SpecStation.new()
		station.id = entry[0]
		station.block = entry[1]
		shop.stations.append(station)
	var dish := SpecDish.new()
	dish.id = "test"
	dish.item = "meal"
	# Authored order is deliberately not topological: dependencies define readiness.
	dish.steps.assign([_step("join",{"left":1,"right":1},{"meal":1}),_step("left",{"a":1},{"left":1}),
		_step("source",{},{"b":1}),_step("right",{"b":1},{"right":1}),_step("source",{},{"a":1})])
	shop.dishes.append(dish)
	return shop

func test_parallel_dependencies_require_both_branches_independent_of_array_order() -> void:
	var production = _production()
	if production==null: return
	var shop := _graph()
	var plan: Dictionary = production.compile(shop,"test")
	check_eq(plan.errors,[],"acyclic two-branch join is valid")
	check_eq(plan.nodes[0].dependencies,[1,3],"join requires both material producers")
	check_eq(plan.nodes[1].dependencies,[4],"left work uses its source")
	check_eq(plan.nodes[3].dependencies,[2],"right work uses an independent source")
	check_eq(plan.order[-1],0,"final join follows both branches")
	check(production.blocked_inputs(shop,"test",0,[]),"join blocked before work")
	check(production.blocked_inputs(shop,"test",0,[1]),"one branch does not unlock the join")
	check(not production.blocked_inputs(shop,"test",0,[1,3]),"both completed branches unlock join")
	check(not production.blocked_inputs(shop,"test",1,[]),"source stock does not require a manual done flag")
	check(not production.blocked_inputs(shop,"test",3,[]),"other branch can run independently")

func test_linear_plan_remains_a_simple_dependency_chain() -> void:
	var production = _production()
	if production==null: return
	var shop := _graph()
	shop.dish("test").steps.assign([_step("source",{},{"a":1}),_step("left",{"a":1},{"left":1}),_step("join",{"left":1},{"meal":1})])
	var plan: Dictionary = production.compile(shop,"test")
	check_eq(plan.errors,[],"linear data is still supported")
	check_eq(plan.order,[0,1,2],"linear topological order")
	check_eq(plan.nodes[2].dependencies,[1],"last step uses previous output")

func test_missing_ambiguous_cyclic_and_insufficient_output_graphs_are_rejected() -> void:
	var production = _production()
	if production==null: return
	for kind in ["missing_input","ambiguous_producer","cycle","insufficient_output","missing_output","unconsumed_output"]:
		var shop := _graph()
		match kind:
			"missing_input": shop.dish("test").steps[1].consumes = {"unknown":1}
			"ambiguous_producer": shop.dish("test").steps[3].produces = {"left":1}
			"cycle": shop.dish("test").steps[1].consumes = {"meal":1}
			"insufficient_output": shop.dish("test").steps[0].consumes.left = 2
			"missing_output": shop.dish("test").item = "absent"
			"unconsumed_output": shop.dish("test").steps[1].produces.left = 2
		var plan: Dictionary = production.compile(shop,"test")
		check(plan.errors.any(func(error: Dictionary) -> bool: return error.code==kind),"graph rejects "+kind)

func test_recipe_signature_tracks_identity_not_timing_and_snapshots_are_detached() -> void:
	var production = _production()
	if production==null: return
	var shop := _graph()
	var first: Dictionary = production.compile(shop,"test")
	var signature: String = first.signature
	shop.dish("test").steps[1].seconds = 20.0
	check_eq(production.compile(shop,"test").signature,signature,"numeric operation tuning does not reinterpret done indices")
	first.nodes[0].dependencies.clear()
	check_eq(production.compile(shop,"test").nodes[0].dependencies,[1,3],"consumer cannot mutate future dependency reads")
	shop.dish("test").steps.reverse()
	check(production.compile(shop,"test").signature!=signature,"reordering indexed steps changes recipe identity")

func test_bundle_collects_distinct_goods_from_two_ports_and_pays_once() -> void:
	var rules := _opened()
	if rules==null: return
	var seen := {}
	var snapshots: Array = []
	var listener := func(_sale: Dictionary) -> void: snapshots.append(rules.to_dict())
	rules.events.on("sale",listener)
	for tick in 2000:
		rules.step(0.1)
		for worker: Dictionary in rules.workers:
			var job := Serve.job_of(rules,worker)
			if job.get("kind","")!="bundle": continue
			seen[worker.carry_count] = true
			check_eq(job.goods.size(),2,"two existing order units reserved")
			check_eq(job.goods.map(func(entry: Dictionary) -> String: return entry.from),["window","side_window"],"main and side have different authored collection ports")
		if not snapshots.is_empty(): break
	rules.events.off("sale",listener)
	check(seen.has(1) and seen.has(2),"employee physically collects the second item after the first")
	check_eq(snapshots.size(),1,"one completed order pays once")
	if snapshots.is_empty(): return
	var saved: Dictionary = snapshots[0]
	check_eq(saved.sold,2,"both menu lines count as sold together")
	check_eq(saved.serve.orders_done,1,"one fulfilled order")
	var order: Dictionary = saved.serve.orders.filter(func(o: Dictionary) -> bool: return o.paid)[0]
	check(order.lines.all(func(line: Dictionary) -> bool: return line.delivered==line.qty),"event snapshot never sees a half-committed bundle")
	check_eq(ShopRules.new(rules.shop).load_dict(saved),"","event snapshot has valid goods and claims")

func test_capacity_or_missing_dish_prevents_partial_order_reservation() -> void:
	var rules := _opened()
	if rules==null: return
	for worker in rules.workers: worker.stats.carry = 1.0
	rules.run(180.0)
	check_eq(rules.sold,0,"capacity one cannot silently fall back to separate deliveries")
	check(rules.serve.jobs.values().all(func(job: Dictionary) -> bool: return job.kind!="bundle"),"insufficient capacity never partially reserves a batch")
	for worker in rules.workers: worker.stats.carry = 2.0
	rules.run(80.0)
	check(rules.sold>=2,"same waiting orders resume with a capable employee")

func test_real_parallel_work_joins_only_after_both_manual_branches_finish() -> void:
	var shop := Fixture.parallel()
	check(shop!=null,"new production protocol available")
	if shop==null: return
	var validator := preload("res://game/rules/shop_spec_validator.gd")
	check_eq(validator.summary(validator.validate(shop)),"","out-of-array-order DAG is a valid shop definition")
	var rules := Fixture.opened(shop)
	var overlapped := false
	for tick in 1800:
		rules.step(0.1)
		var active := {}
		for job: Dictionary in rules.serve.jobs.values():
			if job.kind=="work": active[job.from] = true
		if active.has("wok_a") and active.has("branch"): overlapped = true
		for unit: Dictionary in rules.serve.units:
			if 0 in unit.done: check(1 in unit.done and 3 in unit.done,"join cannot complete without both branches")
	check(overlapped,"independent manual branches execute concurrently")
	check(rules.sold>0,"the joined product reaches a customer")

func test_active_bundle_positions_pickups_and_drop_resume_exactly_from_save() -> void:
	var rules := _opened()
	if rules==null: return
	var seen := {}
	for tick in 2000:
		rules.step(0.1)
		for worker: Dictionary in rules.workers:
			var job := Serve.job_of(rules,worker)
			if job.get("kind","")!="bundle": continue
			var key := "%s:%d"%[worker.action.steps[worker.action.index].kind,worker.carry_count]
			if seen.has(key): continue
			seen[key] = true
			var state := rules.to_dict()
			var clone := ShopRules.new(rules.shop)
			var error := clone.load_dict(state)
			check_eq(error,"","bundle phase is a valid save: "+key)
			if not error.is_empty(): return
			check_eq(clone.to_dict(),state,"active bundle roundtrip exact")
			for next in 8:
				rules.step(0.1)
				clone.step(0.1)
			check_eq(clone.to_dict(),rules.to_dict(),"independent bundle continuation: "+key)
		if seen.has("drop:2"): break
	for key in ["pickup:0","transport:1","pickup:1","transport:2","drop:2"]: check(seen.has(key),"actual saved phase covered: "+key)

func test_cancel_after_first_or_second_item_returns_each_id_to_its_own_port() -> void:
	for count in [1,2]:
		var rules := _opened()
		if rules==null: return
		var found := false
		for tick in 1600:
			rules.step(0.1)
			for worker: Dictionary in rules.workers:
				var job := Serve.job_of(rules,worker)
				if job.get("kind","")!="bundle" or worker.carry_count!=count: continue
				var entries: Array = job.goods.duplicate(true)
				var ids: Array = rules.serve.goods.map(func(g: Dictionary) -> int: return g.id)
				check_eq(rules.execute_command("recall_worker",{"id":worker.id}).code,"ok","recall active multi-item carrier")
				check_eq(rules.serve.goods.map(func(g: Dictionary) -> int: return g.id),ids,"cancel creates or deletes no physical good")
				for entry: Dictionary in entries:
					var good := Serve._good(rules,int(entry.id))
					check_eq([good.at,good.res],[entry.from,-1],"each item returns to its own original pickup")
				check_eq(worker.carry_count,0,"hands clear once")
				check_eq(ShopRules.new(rules.shop).load_dict(rules.to_dict()),"","cancelled bundle can immediately save")
				found = true
				break
			if found: break
		check(found,"captured partial bundle with "+str(count)+" item(s)")

func test_missing_side_dish_waits_without_claiming_the_ready_main_dish() -> void:
	var shop := Fixture.definition()
	check(shop!=null,"flow protocol present")
	if shop==null: return
	shop.station("soup_pot").stock[0].start = 0
	shop.station("soup_pot").params.cook_seconds = 100000.0
	var rules := Fixture.opened(shop)
	rules.run(180.0)
	check_eq(rules.sold,0,"one ready line cannot complete the order")
	var ready := false
	for good: Dictionary in rules.serve.goods:
		if good.item=="tomato_rice" and good.at=="window":
			ready = true
			check_eq(good.res,-1,"ready main is not prematurely reserved")
	check(ready,"main dish has really completed")
	rules.stations.soup_pot.remaining = 0.0
	rules.run(80.0)
	check(rules.sold>=2,"restored side supply completes waiting order")

func test_recipe_signatures_and_old_indexed_units_adopt_without_repeating_work() -> void:
	var rules := _opened()
	if rules==null: return
	rules.run(25.0)
	check(not rules.serve.units.is_empty(),"real production units exist")
	for unit: Dictionary in rules.serve.units:
		check(unit.has("recipe_signature") and unit.get("flow_version",0)==1,"new units record dependency identity")
	var state := rules.to_dict()
	var old := state.duplicate(true)
	for unit: Dictionary in old.serve.units:
		unit.erase("recipe_signature")
		unit.erase("flow_version")
	var clone := ShopRules.new(rules.shop)
	check_eq(clone.load_dict(old),"","legacy units with unchanged recipe indices are adoptable")
	check_eq(clone.to_dict(),state,"adoption only restores missing recipe identities")
	for tick in 30:
		rules.step(0.1)
		clone.step(0.1)
	check_eq(clone.to_dict(),rules.to_dict(),"adopted production neither repeats nor loses a completed step")

func test_bundle_corruption_is_rejected_without_runtime_errors_or_replacing_live_state() -> void:
	var rules := _active_bundle()
	if rules==null: return
	var state := rules.to_dict()
	var key: String = state.serve.jobs.keys().filter(func(id: String) -> bool: return state.serve.jobs[id].kind=="bundle")[0]
	for change in ["duplicate","non_record","missing_member","cursor","version","wrong_owner","target"]:
		var bad := state.duplicate(true)
		var job: Dictionary = bad.serve.jobs[key]
		var worker: Dictionary = bad.roster.filter(func(w: Dictionary) -> bool: return w.id==int(key))[0]
		match change:
			"duplicate": job.goods[1] = job.goods[0].duplicate(true)
			"non_record": job.goods[1] = 8
			"missing_member": job.goods.pop_back()
			"cursor": worker.action.index += 1
			"version": job.bundle_version = 2
			"wrong_owner": job.order = -1
			"target": worker.action.steps[0].target = rules.counter_id
		check(not rules.load_dict(bad).is_empty(),"bad bundle rejected: "+change)
		check_eq(rules.to_dict(),state,"failed bundle load is atomic")

func test_future_flow_and_changed_recipe_files_are_protected_in_place() -> void:
	var rules := _active_bundle()
	if rules==null: return
	var state := rules.to_dict()
	for changed in ["bundle_version","flow_version","recipe"]:
		var path := "user://flow-%s-%d-%d.json"%[changed,OS.get_process_id(),Time.get_ticks_usec()]
		paths.append(path)
		var data := state.duplicate(true)
		var shop: SpecShop = rules.shop.copy_for_editing()
		if changed=="bundle_version":
			for job: Dictionary in data.serve.jobs.values():
				if job.kind=="bundle": job.bundle_version = 2
		elif changed=="flow_version": data.serve.units[0].flow_version = 2
		var original := _write_file(path,data,shop)
		if changed=="recipe": shop.dish("tomato_rice").steps.reverse()
		var reader := ShopSave.new(shop,path)
		reader.load_game()
		check_eq(reader.load_error,ERR_UNAVAILABLE,"future/incompatible flow is protected: "+changed)
		check_eq(reader.save_game(ShopRules.new(shop)),ERR_UNAVAILABLE,"cannot overwrite protected flow")
		check(FileAccess.file_exists(path),"original flow file kept at original path")
		if FileAccess.file_exists(path): check_eq(FileAccess.get_file_as_string(path),original,"original bytes preserved")

func test_legacy_units_get_a_verified_backup_before_first_replacement() -> void:
	var rules := _opened()
	if rules==null: return
	rules.run(25.0)
	var old := rules.to_dict()
	for unit: Dictionary in old.serve.units:
		unit.erase("flow_version")
		unit.erase("recipe_signature")
	var path := "user://flow-adopt-%d-%d.json"%[OS.get_process_id(),Time.get_ticks_usec()]
	paths.append(path)
	var original := _write_file(path,old,rules.shop)
	var reader := ShopSave.new(rules.shop,path)
	var adopted := reader.load_game()
	check_eq(reader.load_error,OK,"unchanged legacy recipe indices can be adopted")
	check_eq(reader.save_game(adopted),OK,"adopted flow saves")
	var backups := Array(DirAccess.get_files_at("user://")).filter(func(file: String) -> bool: return file.begins_with(path.get_file()+".pre-content-"))
	check_eq(backups.size(),1,"first replacement has one durable backup")
	if backups.size()==1: check_eq(FileAccess.get_file_as_string("user://"+backups[0]),original,"legacy original byte-identical")

func test_two_employees_cannot_claim_the_same_bundle_and_expired_capacity_keeps_existing_goods() -> void:
	var rules := _opened()
	if rules==null: return
	for worker in rules.workers: worker.stats.carry = 1.0
	rules.run(100.0)
	for worker in rules.workers:
		Serve.cancel(rules,worker)
		worker.stats.carry = 2.0
	var bundle := preload("res://game/rules/bundle_delivery.gd")
	var first: Dictionary = rules.workers[0]
	var second: Dictionary = rules.workers[1]
	var candidates: Array = bundle.candidates(rules,first,Serve)
	check(not candidates.is_empty(),"full real order ready at both ports")
	if candidates.is_empty(): return
	var candidate: Dictionary = candidates[0]
	Serve._claim(rules,first,candidate)
	Serve._claim(rules,second,candidate.duplicate(true))
	check_eq(Serve.job_of(rules,first).get("kind",""),"bundle","first reservation succeeds")
	check(Serve.job_of(rules,second).is_empty(),"stale second proposal cannot reserve any member")
	for entry: Dictionary in candidate.goods: check_eq(Serve._good(rules,int(entry.id)).res,first.id,"every member has exactly one owner")
	first.stats.carry = 1.0
	check_eq(ShopRules.new(rules.shop).load_dict(rules.to_dict()),"","historical reservation capacity survives a later modifier reduction")
	rules.run(60.0)
	check(rules.sold>=2,"already reserved batch is not discarded when capacity decreases")

func test_blocked_between_pickups_keeps_one_item_and_resumes_or_cancels_cleanly() -> void:
	var rules := _opened()
	if rules==null: return
	for tick in 1500:
		rules.step(0.1)
		for worker: Dictionary in rules.workers:
			var job := Serve.job_of(rules,worker)
			if job.get("kind","")!="bundle" or worker.carry_count!=1: continue
			rules.shop.layout.obstacles = [Rect2(780,0,40,1280)]
			rules.nav.set_open(rules.unlocked)
			var position: Vector2 = worker.pos
			var id := int(job.goods[0].id)
			rules.run(2.0)
			check_eq(worker.pos,position,"blocked carrier cannot cross the wall to side pickup")
			check_eq(worker.carry_count,1,"only the item actually collected is carried")
			check_eq(Serve._good(rules,id).at,"hand:"+str(worker.id),"same first object stays in hand")
			check_eq(ShopRules.new(rules.shop).load_dict(rules.to_dict()),"","blocked partial collection saves")
			rules.shop.layout.obstacles.clear()
			rules.nav.set_open(rules.unlocked)
			rules.run(60.0)
			check(rules.sold>=2,"remaining collection resumes after route opens")
			return
	check(false,"real first pickup captured before blockage")

func test_repeated_final_commit_cannot_recount_or_rebill_delivered_units() -> void:
	var rules := _opened()
	if rules==null: return
	var bundle := preload("res://game/rules/bundle_delivery.gd")
	for tick in 1500:
		rules.step(0.1)
		for worker: Dictionary in rules.workers:
			var job := Serve.job_of(rules,worker)
			if job.get("kind","")!="bundle" or worker.action.steps[worker.action.index].kind!="drop" or not worker.action.started: continue
			bundle.complete(rules,worker,job,Serve)
			var before := rules.to_dict()
			bundle.complete(rules,worker,job,Serve)
			check_eq(rules.to_dict(),before,"retry after final transaction is inert")
			return
	check(false,"real final drop captured")

func test_flow_read_models_are_detached_and_configuration_rejects_unsupported_combinations() -> void:
	var rules := _active_bundle()
	if rules==null: return
	var view := ShopView.new(rules)
	check(view.has_method("production_snapshot"),"dependency graph has a detached read interface")
	if not view.has_method("production_snapshot"): return
	var before := rules.to_dict()
	var plan: Dictionary = view.call("production_snapshot","tomato_rice")
	plan.nodes.clear()
	var frame := view.render_snapshot()
	check(frame.has("flow"),"delivery lease has a read model")
	if frame.has("flow"): frame.flow.bundles.clear()
	check_eq(rules.to_dict(),before,"graph/delivery read edits cannot mutate the simulation")
	var validator := preload("res://game/rules/shop_spec_validator.gd")
	for change in ["version","pickup","mode","actions"]:
		var shop := Fixture.definition()
		match change:
			"version": shop.fulfillment.flow_version = 2
			"pickup": shop.fulfillment.delivery_points.soup = shop.goals.opening_station
			"mode": shop.fulfillment.dine_rule = "self_pickup"
			"actions": shop.dispatch.action_version = 0
		check(not validator.validate(shop).is_empty(),"unsupported flow configuration: "+change)

func test_fanout_does_not_steal_material_already_allocated_to_another_consumer() -> void:
	var shop := Fixture.parallel()
	check(shop!=null,"flow graph fixture available")
	if shop==null: return
	var other: SpecStation = shop.station("branch").duplicate(true)
	other.id = "branch_b"
	shop.stations.append(other)
	shop.layout.points[other.id] = Vector2(1000,300)
	shop.layout.posts[other.id] = shop.layout.points[other.id]
	shop.dish("tomato_rice").steps.assign([
		_step("pantry",{},{"tomato_egg_raw":1}),
		_step("wok_a",{"tomato_egg_raw":1},{"rice":2}),
		_step("branch",{"rice":1},{"tomato_egg":1}),
		_step("branch_b",{"rice":1},{"pepper_pork":1}),
		_step("plating",{"tomato_egg":1,"pepper_pork":1},{"tomato_rice":1})])
	var rules := Fixture.opened(shop)
	for tick in 200:
		rules.step(0.1)
		if not rules.serve.units.is_empty(): break
	for worker in rules.workers: Serve.cancel(rules,worker)
	var unit: Dictionary = rules.serve.units[0]
	unit.done.assign([1])
	var allocated := Serve._birth(rules,"rice","branch",int(unit.id))
	var free := Serve._birth(rules,"rice","wok_a",int(unit.id))
	var candidate := Serve._carry_in(rules,rules.workers[0],unit,"rice","branch_b")
	check_eq(candidate.get("good",-1),int(free.id),"fork chooses unallocated producer output, not another branch's input")
	check_eq(allocated.at,"branch","dependency planning leaves the first consumer's real item in place")

func test_unopened_collection_port_waits_before_any_finished_item_is_sent_there() -> void:
	var rules := _opened()
	if rules==null: return
	rules.unlocked.side_window = false
	rules.nav.set_open(rules.unlocked)
	rules.run(140.0)
	check(rules.serve.goods.all(func(g: Dictionary) -> bool: return g.at!="side_window"),"finished goods cannot be placed at unopened collection station")
	check(rules.serve.jobs.values().all(func(job: Dictionary) -> bool: return job.to!="side_window"),"closed collection module receives no transport job")
	check_eq(rules.sold,0,"closed side port keeps complete order pending")
	rules.unlocked.side_window = true
	rules.nav.set_open(rules.unlocked)
	rules.run(80.0)
	check(rules.sold>=2,"opening the port resumes the original pending order")
