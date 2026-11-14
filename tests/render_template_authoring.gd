extends SceneTree
## Actual normal sessions prove public calls; imports and final counters are insufficient.
const Sessions := preload("res://tests/shop_test_session.gd")
const ErrorLog := preload("res://tests/error_counter.gd")
const Presentation := preload("res://content/characters/actor_presentation.tres")
var logger := ErrorLog.new()
var checks := 0
var failures := 0
var paths: Array = []
var results: Array = []
var report_path := ""
func _initialize() -> void:
	OS.add_logger(logger)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
	call_deferred("_run")
func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures += 1; print("FAIL ",label)
func _shop(row: Dictionary) -> void:
	var spec: SpecShop = load("res://"+row.path)
	var owner := ShopRules.new(spec,42)
	check(owner.runtime!=null and owner.runtime_error.is_empty(),spec.id+": ordinary constructor")
	if owner.runtime==null: return
	owner.gold = 1000000.0
	for stage in spec.stages.size(): check(owner.unlock(spec.sold_at(stage)).is_empty(),"ordinary unlock")
	for box in owner.boxes: check(owner.unlock_box(box).is_empty(),"ordinary materials")
	while owner.roster.size()<2: check(owner.hire().is_empty(),"ordinary recruit")
	for worker in owner.roster:
		if not worker.deployed: check(owner.deploy_worker(worker.id).is_empty(),"ordinary deploy")
	var campaign: SpecCampaign = load("res://content/campaign/campaign.tres" if row.kind=="campaign" else "res://content/examples/campaign.tres")
	var scene: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	scene.session = Sessions.make(spec,"user://u07-runtime-"+spec.id+"-"+str(Time.get_ticks_usec()),owner,null,null,campaign)
	for path in [scene.session.profile.path,scene.session.store.path,scene.session.tuning_path,scene.session.recording_path]: paths.append(path)
	root.add_child(scene); scene.set_process(false)
	check(not scene._startup_blocked,spec.id+": actual scene starts "+str(scene.save_status))
	if scene._startup_blocked: scene.free(); return
	owner.runtime.set_tracing(true)
	var operations := {}; var proofs := []; var merged := false; var customer_bundle := false
	var restored := false; var recalled := false; var new_work := false
	var new_staff: bool = spec.staff.starting.has("squirrel")
	for tick in 2400:
		var before := {}
		for worker in owner.workers: before[worker.id] = worker.pos
		scene._process(0.1)
		check(owner.runtime_error.is_empty(),spec.id+": normal scene advance "+owner.runtime_error)
		if not owner.runtime_error.is_empty(): break
		for worker in owner.workers:
			if before.has(worker.id): check(Vector2(before[worker.id]).distance_to(worker.pos)<=owner.walk_speed(worker)*0.1+0.01,"employee movement follows the shared speed")
		var trace: Dictionary = owner.runtime.take_trace()
		check(not trace.overflow,"complete trace without silently dropped calls")
		for event in trace.events:
			operations[event.operation] = int(operations.get(event.operation,0))+1
			if event.operation.begins_with("action."):
				check(event.facts.pos.is_equal_approx(event.facts.port),"actual common action commits at the physical port")
				if proofs.size()<48: proofs.append({"operation":event.operation,"worker":event.facts.worker,"target":event.facts.target,"pos":[event.facts.pos.x,event.facts.pos.y],"port":[event.facts.port.x,event.facts.port.y]})
			if event.operation=="inventory.reserve_operation" and event.facts.consumes.size()>1: merged = true
			if event.operation=="inventory.reserve_transfer" and String(event.facts.actor).begins_with("customer:"): customer_bundle = true
		if tick%5==0:
			var frame: Dictionary = scene.view.render_snapshot()
			for worker in owner.workers:
				check(owner.nav.can_stand(worker.pos,owner.runtime.runner.access_profile(worker)),"legal staff footprint")
				check(is_equal_approx(scene._actors[worker.id]._height,Presentation.staff_height),"global employee height")
				check(scene._actors[worker.id].scale.is_equal_approx(Vector2.ONE*scene._actor_unit_scale),"scene density applied once")
				check(worker.carry_count==int(frame.held.get(worker.id,{"count":0}).count),"hand picture and UI read actual stock")
				if worker.kind=="squirrel": new_work = new_work or worker.phase=="work"
			for actor in owner.runtime.service.customers.snapshot().customers: check(owner.nav.can_stand(actor.pos,"customer"),"legal customer footprint")
		for worker in owner.workers.duplicate():
			if new_staff and worker.kind=="squirrel" and worker.carry_count>0 and not recalled:
				check(owner.recall_worker(worker.id).is_empty(),"real shared cancellation")
				check(owner.deploy_worker(worker.id).is_empty(),"redeploy new employee")
				recalled = true
		if tick==300:
			check(scene.session.save()==OK,"actual session disk save")
			var saved := owner.to_dict()
			var reopened: ShopRules = scene.store.load_game()
			check(scene.store.load_error==OK and reopened.to_dict()==saved,"ordinary disk roundtrip including active order")
			check(owner.load_dict(saved).is_empty(),"live restore")
			owner.runtime.set_tracing(true)
			check(scene.view._runtime==owner.runtime,"existing view follows restored owner")
			restored = true
		if tick>300 and owner.sold>=4 and (not new_staff or (recalled and new_work)): break
	for op in ["runtime.step","inventory.reserve_transfer","inventory.pickup","inventory.drop","inventory.reserve_operation","inventory.complete_operation","action.pickup","action.drop","action.operate"]:
		check(operations.has(op),spec.id+": actual shared call "+op)
	check(owner.sold>=4 and restored,spec.id+": actual service and restoration completed")
	check(not new_staff or (new_work and recalled and merged),"new employee uses common production, merge and compensation")
	if new_staff and owner.runtime.service._policy.delivery=="self_pickup": check(customer_bundle,"customer uses the same actual transfer transactions")
	check(owner.inventory_diagnostics().is_empty(),"physical stock conservation")
	var clock := owner.clock
	owner.paused = true; scene._process(0.4); check(owner.clock==clock,"pause freezes the authoritative clock"); owner.paused = false
	for speed in [1.0,2.0,4.0]:
		scene._speed_factor = speed; clock = owner.clock; scene._process(0.2)
		check(is_equal_approx(owner.clock-clock,0.2*speed),"speed only changes common simulation amount")
	if "--capture" in OS.get_cmdline_user_args() and not report_path.is_empty():
		await process_frame; await RenderingServer.frame_post_draw
		var path: String = report_path.get_base_dir().path_join(spec.id+".png")
		check(root.get_texture().get_image().save_png(path)==OK,"actual viewport capture")
	results.append({"shop":spec.id,"delivery":owner.runtime.service._policy.delivery,"sold":owner.sold,"clock":owner.clock,"restored":restored,"new_staff_worked":new_work,"recalled":recalled,"merged":merged,"customer_bundle":customer_bundle,"operations":operations,"proofs":proofs})
	scene.free()
func _run() -> void:
	root.size = Vector2i(720,1280); root.get_node("ShopAudio")._can_play = false
	if not report_path.is_empty():
		check(report_path.begins_with("res://_work/") and not report_path.contains(".."),"isolated evidence path")
		DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/template_shops.json"))
	for row in catalog.shops: await _shop(row)
	for path in paths:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	for error in logger.take(): failures += 1; print("FAIL runtime: ",error)
	OS.remove_logger(logger)
	if not report_path.is_empty():
		var file := FileAccess.open(report_path,FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failures":failures,"results":results},"  ")+"\n")
	print("TEMPLATE RUNTIME PROOF: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
