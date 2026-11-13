extends SceneTree
## U05 full display acceptance on the actual three scenes and templates.
const TestSession := preload("res://tests/shop_test_session.gd")
const Runtime := preload("res://game/rules/template/runtime.gd")
var errors := preload("res://tests/error_counter.gd").new()
var failures := 0
var checks := 0
var paths: Array = []
var results: Array = []
var _captures := {}

func _initialize() -> void:
	OS.add_logger(errors)
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; print("FAIL: "+message)

func _setup(id: String) -> Dictionary:
	var shop: SpecShop = load("res://content/shops/"+id+"/shop.tres").copy_for_editing()
	var owner := ShopRules.new(shop,42)
	owner.gold = 1000000.0
	if id=="tea":
		for machine in ["lemonade","boil","seal","mix","press","topping"]: _check(owner.unlock(machine).is_empty(),"actual tea purchases")
		for box in ["tea_leaf","milk"]: _check(owner.unlock_box(box).is_empty(),"actual tea box")
		for upgrade in 3: _check(owner.upgrade("topping").is_empty(),"actual tea flavors")
	else:
		for stage in shop.stages.size(): _check(owner.unlock(shop.sold_at(stage)).is_empty(),"actual stage purchase")
		if id=="pancake":
			_check(owner.unlock_box("flour").is_empty(),"actual flour purchase")
			for upgrade in 6: _check(owner.upgrade("topping").is_empty(),"actual pancake flavors")
	while owner.roster.size()<2: _check(owner.hire().is_empty(),"hire actual second employee")
	for worker in owner.roster:
		if not worker.deployed: _check(owner.deploy_worker(worker.id).is_empty(),"deploy actual employee")
	while owner.seat_cost()>=0: _check(owner.buy_seat().is_empty(),"buy actual complete seat pool")
	var scene: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	scene.session = TestSession.make(shop,"user://u05-display-%s-%d"%[id,Time.get_ticks_usec()],owner)
	for path in [scene.session.profile.path,scene.session.store.path,scene.session.tuning_path,scene.session.recording_path]: paths.append(path)
	root.add_child(scene); scene.set_process(false)
	_check(not scene._startup_blocked,"actual "+id+" scene")
	var template: Resource = load("res://content/shops/"+id+"/shared_production.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	if id=="stirfry":
		for stage in template.service.selection.stages: stage.weights = {"tomato_rice":1.0}
		template.service.selection.addon.share = 1.0
	var runtime := Runtime.new(owner,template)
	_check(runtime.last_error.is_empty(),id+": "+runtime.last_error)
	var error: String = scene.bind_runtime(runtime)
	_check(error.is_empty(),id+": actual geometry binding "+error)
	return {"scene":scene,"runtime":runtime,"owner":owner}

func _refresh(fixture: Dictionary) -> Dictionary:
	var before: Dictionary = fixture.runtime.snapshot()
	fixture.scene._refresh(0.0)
	_check(fixture.runtime.snapshot()==before,"render does not mutate simulation")
	var frame: Dictionary = fixture.scene.view.render_snapshot()
	_check(fixture.scene._customers.size()==frame.movement.customers.size(),"no duplicated customer ownership")
	for key in frame.movement.customers:
		var row: Dictionary = frame.movement.customers[key]
		_check(fixture.scene._customer_positions[key]==row.pos,"display does not integrate customer movement")
	for id in frame.machines:
		var status: Dictionary = fixture.scene.view.machine_status(id)
		_check(status.input==frame.machines[id].input and status.output==frame.machines[id].output,"machine UI and draws share inventory")
	for row in frame.draws:
		_check(row.pos.is_finite(),"all display positions are finite")
		if row.get("capability")=="dining_item":
			_check(frame.movement.customers["guest:"+str(row.guest)].seated,"food appears only for truly seated customer")
	return frame

func _capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or _captures.has(name): return
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(not image.is_empty(),"actual window image "+name)
	if not image.is_empty(): _check(image.save_png("res://_work/unified_shop_template_20261112/u05-captures/"+name+".png")==OK,"save "+name)
	_captures[name] = true

func _freeze(fixture: Dictionary) -> void:
	var before: Dictionary = fixture.runtime.snapshot()
	fixture.owner.paused = true
	_check(fixture.runtime.step(5.0,true).is_empty(),"paused complete display fixture")
	fixture.scene._refresh(25.0)
	_check(fixture.runtime.snapshot()==before,"pause freezes transport, machine and customer clocks")
	fixture.owner.paused = false

func _tea_stock() -> void:
	var fixture := _setup("tea")
	_check(fixture.owner.buy_connection("seal_to_shelf").is_empty(),"buy authored tea conveyor")
	var ids: Array = []
	for recipe in ["black_tea","plain_milk_tea","pearl_milk_tea","black_tea:sealed","plain_milk_tea:sealed","pearl_milk_tea:sealed"]:
		ids.append(fixture.runtime.request_production(recipe).id)
	var saw_transport := false
	var saved := false
	var complete := false
	for tick in 1600:
		_check(fixture.runtime.step(0.25).is_empty(),"actual tea stock and conveyor")
		var frame := _refresh(fixture)
		if not frame.transports.is_empty():
			saw_transport = true
			_check(frame.draws.any(func(row: Dictionary) -> bool: return row.get("capability")=="transport_item"),"real flight has authored conveyor display")
			if not saved:
				var before: Dictionary = fixture.runtime.snapshot()
				_check(fixture.runtime.restore(before).is_empty(),"restore actual sealer-to-rack flight")
				_check(fixture.runtime.snapshot()==before,"no second pickup on actual conveyor restore")
				_freeze(fixture); saved = true
			await _capture("tea-conveyor")
		complete = ids.all(func(id: int) -> bool: return fixture.runtime.ready(id))
		if complete:
			_check(frame.counters.shelf.count==3,"shelf UI counts all three real unpacked drinks")
			_check(frame.draws.size()==6,"two explicit shelf groups use distinct six authored ports")
			_check(fixture.scene._shelf.visible and fixture.scene._shelf.text.contains("3"),"actual shelf label consumes public counter")
			await _capture("tea-shelves")
			break
	_check(complete and saw_transport and saved,"full real tea showcase/transport lifecycle")
	results.append({"case":"tea_stock","complete":complete,"transport":saw_transport,"restored":saved,"seconds":fixture.runtime.snapshot().clock})
	fixture.scene.free()

func _meals(id: String) -> void:
	var fixture := _setup(id)
	if id=="tea":
		for dish in ["lemonade","black_tea"]: _check(fixture.runtime.arrive([{"dish":dish,"qty":1}]).error.is_empty(),"actual tea diners")
	else:
		for index in 2: _check(fixture.runtime.arrive([]).error.is_empty(),"actual admission-sampled rice and soup")
	var saw_meal := false
	var saw_bundle := false
	var saved := false
	for tick in 1800:
		var factor := 1.0 if tick<80 else 2.0 if tick<160 else 4.0
		_check(fixture.runtime.step(0.1*factor).is_empty(),"actual meal at selected speed")
		var frame := _refresh(fixture)
		for row in frame.movement.customers.values():
			if row.carry_count==2: saw_bundle = true
		if frame.draws.any(func(row: Dictionary) -> bool: return row.get("capability")=="dining_item"):
			saw_meal = true
			if not saved:
				var before: Dictionary = fixture.runtime.snapshot()
				_check(fixture.runtime.restore(before).is_empty(),"restore real seated meal")
				_check(fixture.runtime.snapshot()==before,"meal restore does not duplicate food")
				_freeze(fixture); saved = true
			await _capture(id+"-dining")
		if fixture.runtime.service.orders.snapshot().guests.all(func(guest: Dictionary) -> bool: return guest.state=="gone"): break
	var gone: bool = fixture.runtime.service.orders.snapshot().guests.all(func(guest: Dictionary) -> bool: return guest.state=="gone")
	_check(saw_meal and gone and saved,id+": seated meal rendered and completed")
	_check(not fixture.scene.view.render_snapshot().draws.any(func(row: Dictionary) -> bool: return row.get("capability")=="dining_item"),"eating consumes displayed food exactly once")
	if id=="stirfry": _check(saw_bundle,"actual main and soup carried together")
	results.append({"case":id+"_dining","complete":gone,"meal":saw_meal,"restored":saved,"bundle":saw_bundle,"sold":fixture.owner.sold})
	fixture.scene.free()

func _pancake() -> void:
	var fixture := _setup("pancake")
	_check(fixture.runtime.arrive([{"dish":"ham","qty":1},{"dish":"soy","qty":1}],["bag"]).error.is_empty(),"real bagged pancake plus drink")
	var saw_processing := false
	var saw_waiting := false
	var restored := false
	var wave_added := false
	for tick in 1600:
		_check(fixture.runtime.step(0.25).is_empty(),"actual pancake pipeline")
		var frame := _refresh(fixture)
		if frame.draws.any(func(row: Dictionary) -> bool: return row.get("capability")=="processing_item"):
			saw_processing = true
			await _capture("pancake-processing")
			if not wave_added:
				for index in 10: _check(fixture.runtime.arrive([{"dish":"soy","qty":1}],[]).error.is_empty(),"actual waiting cushion wave")
				wave_added = true
			if not restored:
				var before: Dictionary = fixture.runtime.snapshot()
				_check(fixture.runtime.restore(before).is_empty(),"restore actual roll/bag processing")
				_check(fixture.runtime.snapshot()==before,"no extra processing item after restore")
				_freeze(fixture); restored = true
		for row in frame.movement.customers.values():
			if row.seated and String(row.seat_key).begins_with("wait:"):
				saw_waiting = true
				_check(row.has("render_pos"),"waiting pose uses explicit pad binding")
				if wave_added: await _capture("pancake-waiting")
		if fixture.runtime.service.orders.snapshot().guests.all(func(guest: Dictionary) -> bool: return guest.state=="gone"): break
	var complete: bool = fixture.runtime.service.orders.snapshot().guests.all(func(guest: Dictionary) -> bool: return guest.state=="gone")
	_check(saw_processing and saw_waiting and restored and complete,"complete pancake processing/waiting/customer lifecycle")
	_check(fixture.scene.view.render_snapshot().draws.is_empty(),"finished work and meal leave no processing ghosts")
	results.append({"case":"pancake","complete":complete,"processing":saw_processing,"waiting":saw_waiting,"restored":restored,"sold":fixture.owner.sold})
	fixture.scene.free()

func _run() -> void:
	root.size = Vector2i(720,1280)
	root.get_node("ShopAudio")._can_play = false
	await _tea_stock()
	await _meals("tea")
	await _pancake()
	await _meals("stirfry")
	for path in paths:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	for error in errors.take(): failures += 1; print("RUNTIME: "+error)
	OS.remove_logger(errors)
	var destination := OS.get_environment("U05_DISPLAY_REPORT")
	if not destination.is_empty():
		var file := FileAccess.open(destination,FileAccess.WRITE)
		file.store_string(JSON.stringify({"failed":failures,"checks":checks,"results":results,"captures":_captures.keys()},"  ")); file.close()
	print("TEMPLATE DISPLAYS: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
