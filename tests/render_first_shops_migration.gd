extends SceneTree
## Real sessions: legacy adoption, shared actors, pause/speed, save and reopen.
const Session := preload("res://tests/shop_test_session.gd")
var scene: Node2D
var checks := 0
var failures := 0
var prefixes: Array[String] = []
var logger := preload("res://tests/error_counter.gd").new()

func _initialize() -> void:
	OS.add_logger(logger)
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL ",label)

func _open(shop: SpecShop, prefix: String) -> void:
	scene = load("res://presentation/shop/shop_play.tscn").instantiate()
	scene.session = Session.make(shop,prefix)
	root.add_child(scene)
	scene.set_process(false)

func _poses() -> void:
	var frame: Dictionary = scene.view.render_snapshot()
	var before := var_to_bytes(scene.rules.to_dict())
	scene._refresh(0)
	for worker: Dictionary in frame.workers:
		_check(scene._actors.has(worker.id),"employee actor exists")
		if not scene._actors.has(worker.id): continue
		_check(scene._actors[worker.id].position.is_equal_approx(worker.pos),"employee follows authoritative native position")
		_check(scene.rules.nav.can_stand(worker.pos,"staff"),"employee feet outside furniture")
	for key in frame.movement.customers:
		var row: Dictionary = frame.movement.customers[key]
		_check(scene._customers.has(key),"customer actor exists")
		if not scene._customers.has(key): continue
		var expected: Vector2 = scene.anchors.point("Seats/"+String(row.target).get_slice(":",1)) if row.seated else row.pos
		if row.seated and scene._dining!=null:
			expected = scene._dining.seat_point(int(row.seat))-Vector2(0,14.0*scene._actor_unit_scale)
			_check(scene._customers[key].z_index==1,"dining actor stays above the original chair")
		_check(scene._customers[key].position.is_equal_approx(expected),"customer follows approach and original seated pose")
		_check(scene.rules.nav.can_stand(row.pos,"customer"),"customer stays within dining access")
	_check(var_to_bytes(scene.rules.to_dict())==before,"refresh cannot advance rules")

func _speed() -> void:
	await process_frame
	var button: Control = scene.ui.speed_button
	var point: Vector2 = button.get_global_transform_with_canvas()*(button.size/2)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame

func _run() -> void:
	root.size = Vector2i(720,1280)
	root.get_node("ShopAudio")._can_play = false
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/legacy_shops/states.json"))
	for id in ["tea","pancake"]:
		var shop: SpecShop = load("res://content/shops/%s/shop.tres"%id)
		var prefix := "user://first-migration-ui-%s-%d"%[id,Time.get_ticks_usec()]
		prefixes.append(prefix)
		var path := prefix+"-shop.json"
		var original := JSON.stringify(fixtures[id].active,"  ").to_utf8_buffer()
		var file := FileAccess.open(path,FileAccess.WRITE)
		file.store_buffer(original)
		file.close()
		_open(shop,prefix)
		await process_frame
		_check(scene.rules!=null,"actual session opens old "+id)
		if scene.rules==null: scene.free(); continue
		_check(scene._staff_height==128 and scene._customer_height==110,"shared actor sizes")
		_check(is_equal_approx(scene._actor_unit_scale,shop.layout.motion_units),"native density applied once")
		for worker: Dictionary in scene.rules.workers:
			_check(worker.stats==shop.staff.kinds.filter(func(kind: SpecStaffKind) -> bool: return kind.id==worker.kind)[0].stats,"old staff adopts global base stats")
		_poses()
		scene.execute_command("set_paused",{"paused":true})
		var paused: Dictionary = scene.rules.to_dict()
		scene._process(0.25)
		_check(scene.rules.to_dict()==paused,"pause holds all movement and work")
		scene.execute_command("set_paused",{"paused":false})
		for speed in [1,2,4]:
			_check(scene._speed_factor==speed,"speed UI selects %d in %s (actual %d)"%[speed,id,scene._speed_factor])
			var oracle := ShopRules.new(shop,42)
			_check(oracle.load_dict(scene.rules.to_dict()).is_empty(),"speed oracle loads")
			scene._process(0.1)
			oracle.step(0.1*speed)
			_check(scene.rules.to_dict()==oracle.to_dict(),"UI speed matches authoritative steps")
			await _speed()
		var sold: int = scene.rules.sold
		for tick in 600:
			scene._process(0.1)
			if tick%200==0: _poses()
		_check(scene.rules.sold>sold,"adopted real business continues selling: "+id)
		_check(scene.save_now(false)==OK,"actual session saves")
		var found := false
		for name in DirAccess.get_files_at("user://"):
			if name.begins_with(path.get_file()+".pre-content-"):
				found = true
				_check(FileAccess.get_file_as_bytes("user://"+name)==original,"byte exact old-file backup")
		_check(found,"first replacement makes backup")
		var saved: Dictionary = scene.rules.to_dict()
		scene.free()
		_open(shop,prefix)
		await process_frame
		_check(scene.rules!=null and scene.rules.to_dict()==saved,"real session reopens exactly")
		if scene.rules!=null: _poses()
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--screenshots=") and DisplayServer.get_name()!="headless":
				scene._scroll = 0
				scene._fit()
				await process_frame
				await RenderingServer.frame_post_draw
				_check(root.get_texture().get_image().save_png(arg.substr(14)+"/"+id+"-shared.png")==OK,"screenshot saved")
		scene.free()
	await process_frame
	for prefix in prefixes:
		for name in DirAccess.get_files_at("user://"):
			if name.begins_with(prefix.get_file()): DirAccess.remove_absolute("user://"+name)
	for error in logger.take(): _check(false,error)
	OS.remove_logger(logger)
	print("FIRST SHOPS MIGRATION GUI: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
