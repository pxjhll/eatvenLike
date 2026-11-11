extends SceneTree
## Full generic scene and real sessions over the independent module assembly.
const Fixture := preload("res://tests/fixtures/module_shop.gd")
const TestSession := preload("res://tests/shop_test_session.gd")
const Campaign := preload("res://tests/fixtures/stirfry/campaign.tres")
var checks := 0
var failed := 0
var logger := preload("res://tests/error_counter.gd").new()
var paths: Array[String] = []
var scene: Node2D
var prefix := ""
var spec: SpecShop

func _initialize() -> void:
	OS.add_logger(logger)
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed += 1
		print("FAIL "+label)

func _open() -> void:
	scene = load("res://presentation/shop/shop_play.tscn").instantiate()
	scene.session = TestSession.make(spec,prefix,null,null,null,Campaign)
	for path in [scene.session.profile.path,scene.session.store.path,scene.session.tuning_path,scene.session.recording_path]:
		if path not in paths: paths.append(path)
	root.add_child(scene)
	scene.set_process(false)

func _run() -> void:
	root.size = Vector2i(720,1280)
	root.get_node("ShopAudio")._can_play = false
	prefix = "user://module-gui-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	var assembled := Fixture.assemble()
	assembled.art.get_node("Sortables/wok_a").position += Vector2(-40,0)
	assembled.art.get_node("Sortables/Table0").position += Vector2(40,0)
	assembled.art.get_node("Sortables/Entrance").position += Vector2(40,0)
	var exported := ShopAnchors.new(assembled.art.get_node("Anchors")).export_layout(assembled.shop.layout)
	_check(exported.errors.is_empty(),"moved module geometry compiles")
	if exported.layout==null:
		assembled.art.free()
		await _finish()
		return
	assembled.shop.layout = exported.layout
	var files := Fixture.persist(assembled.shop,assembled.art,prefix)
	assembled.art.free()
	_check(files.error==OK,"module scene persists as editable PackedScene")
	paths.append_array([files.shop_path,files.scene_path])
	spec = load(files.shop_path)
	_open()
	await process_frame
	_check(scene.rules!=null,"generic shop startup accepts modules: "+str(scene.save_status))
	if scene.rules==null:
		await _finish()
		return
	_check(scene._sortables.y_sort_enabled,"module and actor roots share y sorting")
	_check(scene.anchors.rect("Stations/wok_a/Frame")==Rect2(500,140,80,80),"moved interaction uses module coordinates")
	_check(scene._station_buttons.wok_a.get_rect().get_center()==Vector2(540,180),"actual world button follows moved frame")
	scene.reveal_world(scene.anchors.rect("Stations/wok_a/Frame"))
	await process_frame
	var button: Control = scene._station_buttons.wok_a
	var click: Vector2 = button.get_global_transform_with_canvas()*(button.size/2)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = click
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	_check(scene.ui.page=="station" and scene.ui.page_node("station").station_id=="wok_a","real click opens the moved station")
	scene.ui.open_page("shop")
	_check(not scene.art.get_node("Sortables/wok_a/Visual").visible,"unopened module visual is hidden")
	scene.rules.gold = 1000000.0
	for guard in spec.stages.size()+1:
		var next: String = scene.rules.next_unlock()
		if next.is_empty(): break
		scene.rules.unlock(next)
	scene._refresh(0)
	_check(scene.art.get_node("Sortables/wok_a/Visual").visible,"station unlock reveals module visual")
	var seated := false
	var held_two := false
	var routed := false
	for tick in 1800:
		scene.rules.step(0.1)
		if tick%5!=0: continue
		var before := var_to_bytes(scene.rules.to_dict())
		scene._refresh(0)
		if tick%200==0: _check(var_to_bytes(scene.rules.to_dict())==before,"real scene refresh is read-only")
		for worker: Dictionary in scene.rules.workers:
			if worker.walking and worker.path.size()>2: routed = true
			if worker.carry_count==2 and not held_two:
				held_two = true
				_check(scene._actors[worker.id].amount.text=="×2","real actor displays both collected goods")
		var customers: Dictionary = scene.view.render_snapshot().movement.customers
		for customer_key in customers:
			var row: Dictionary = customers[customer_key]
			if not row.seated or seated: continue
			seated = true
			var key: String = row.target.get_slice(":",1)
			_check(scene._customers[customer_key].position==scene.anchors.point("Seats/"+key),"seated customer uses moved authored seat")
	_check(seated and held_two and routed and scene.rules.sold>=2,"full module scene routes, seats and serves real bundles")
	_check(scene.save_now(false)==OK,"module shop saves through actual store")
	var saved: Dictionary = scene.rules.to_dict()
	var oracle := ShopRules.new(spec,42)
	_check(oracle.load_dict(saved).is_empty(),"module save independently validates")
	scene.free()
	_open()
	await process_frame
	_check(scene.rules!=null and scene.rules.to_dict()==saved,"real close and reopen restores every rule field")
	if scene.rules!=null:
		for tick in 100:
			scene.rules.step(0.1)
			oracle.step(0.1)
		scene._refresh(0)
		_check(scene.rules.to_dict()==oracle.to_dict(),"session continues exactly on module geometry")
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--screenshot=") and DisplayServer.get_name()!="headless":
				scene._scroll = 0
				scene._fit()
				await process_frame
				await RenderingServer.frame_post_draw
				_check(root.get_texture().get_image().save_png(arg.substr(13))==OK,"module screenshot saved")
	await _finish()

func _finish() -> void:
	if is_instance_valid(scene): scene.free()
	await process_frame
	await process_frame
	for path in paths:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	for error in logger.take(): _check(false,error)
	OS.remove_logger(logger)
	print("SCENE MODULE GUI: %d checks, %d failures"%[checks,failed])
	quit(1 if failed else 0)
