extends SceneTree
const LegacyRules := preload("res://tests/fixtures/legacy_shops/reference_rules.gd")
## Formal third shop: real legacy file, generic session, world poses and speed UI.
const DATA: SpecShop = preload("res://tests/fixtures/legacy_shops/current/stirfry/shop.tres")
const TestSession := preload("res://tests/shop_test_session.gd")
const Campaign := preload("res://tests/fixtures/stirfry/campaign.tres")
var scene: Node2D
var prefix := ""
var logger := preload("res://tests/error_counter.gd").new()
var checks := 0
var failed := 0

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
	scene.session = TestSession.make(DATA,prefix,null,null,null,Campaign)
	root.add_child(scene)
	scene.set_process(false)

func _press_speed() -> void:
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

func _poses() -> void:
	var frame: Dictionary = scene.view.render_snapshot()
	var before := var_to_bytes(scene.rules.to_dict())
	scene._refresh(0)
	for worker: Dictionary in frame.workers:
		_check(scene._actors.has(worker.id),"every employee has a real scene actor")
		if not scene._actors.has(worker.id): continue
		_check(scene._actors[worker.id].position.is_equal_approx(worker.pos),"employee actor reads authoritative native position")
		_check(scene.rules.nav.can_stand(worker.pos,"staff"),"displayed employee feet clear physical furniture")
	for key in frame.movement.customers:
		var row: Dictionary = frame.movement.customers[key]
		_check(scene._customers.has(key),"every logical customer has an actor")
		if not scene._customers.has(key): continue
		var expected: Vector2 = scene.anchors.point("Seats/"+String(row.target).get_slice(":",1)) if row.seated else row.pos
		_check(scene._customers[key].position.is_equal_approx(expected),"customer actor follows approach or seated display point")
		_check(scene.rules.nav.can_stand(row.pos,"customer"),"customer approach stays outside kitchen and furniture")
	_check(var_to_bytes(scene.rules.to_dict())==before,"real scene refresh cannot advance business")

func _run() -> void:
	root.size = Vector2i(720,1280)
	root.get_node("ShopAudio")._can_play = false
	prefix = "user://stirfry-migration-gui-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/stirfry_modularity/legacy_states.json"))
	var original: PackedByteArray = JSON.stringify(fixture.states.mid_walk_collision,"  ").to_utf8_buffer()
	var path := prefix+"-shop.json"
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(original)
	file.close()
	_open()
	await process_frame
	_check(scene.rules!=null,"real session opens valid legacy progress on formal shared geometry")
	if scene.rules==null:
		await _finish()
		return
	_check(FileAccess.get_file_as_bytes(path)==original,"startup preserves original old save bytes")
	_check(is_equal_approx(scene.rules.clock,5.7),"old clock is retained through actual session startup")
	_check(scene._staff_height==128 and scene._customer_height==110,"formal shop reads shared tea actor sizes")
	_check(is_equal_approx(scene._actor_unit_scale,887.0/720.0),"native density is applied once")
	for worker: Dictionary in scene.rules.workers:
		_check(worker.stats==DATA.staff.kinds.filter(func(kind: SpecStaffKind) -> bool: return kind.id==worker.kind)[0].stats,"old employee caches adopt shared global base stats")
	_poses()
	scene.execute_command("set_paused",{"paused":true})
	var paused: Dictionary = scene.rules.to_dict()
	var positions := {}
	for key in scene._actors: positions[key] = scene._actors[key].position
	scene._process(0.25)
	_check(scene.rules.to_dict()==paused,"pause holds rules, route cursor and work timers")
	for key in positions: _check(scene._actors[key].position==positions[key],"paused actor does not integrate GUI delta")
	scene.execute_command("set_paused",{"paused":false})
	for speed in [1,2,4]:
		_check(scene._speed_factor==speed,"speed UI selects "+str(speed))
		var oracle := LegacyRules.new(DATA,11)
		_check(oracle.load_dict(scene.rules.to_dict()).is_empty(),"speed oracle loads exact state")
		scene._process(0.1)
		oracle.step(0.1*speed)
		_check(scene.rules.to_dict()==oracle.to_dict(),"GUI speed remains identical to authoritative simulation")
		await _press_speed()
	_check(scene._speed_factor==1,"existing speed cycle returns to one")
	await _press_speed()
	for tick in 1200:
		scene._process(0.1)
		if tick%300==0: _poses()
	_check(scene.rules.sold>0,"legacy business continues to sell through actual UI")
	_check(scene.save_now(false)==OK,"real store writes migrated protocol")
	var found_backup := false
	for name in DirAccess.get_files_at("user://"):
		if name.begins_with(path.get_file()+".pre-content-"):
			found_backup = true
			_check(FileAccess.get_file_as_bytes("user://"+name)==original,"actual session preserves byte-exact original backup")
	_check(found_backup,"first save creates verified old-file backup")
	var state: Dictionary = scene.rules.to_dict()
	scene.free()
	_open()
	await process_frame
	_check(scene.rules!=null and scene.rules.to_dict()==state,"close and reopen is exact")
	if scene.rules!=null:
		_check(scene._speed_factor==2,"session playback speed is preserved")
		var oracle := LegacyRules.new(DATA,11)
		_check(oracle.load_dict(state).is_empty(),"saved formal state independently loads")
		for tick in 80:
			scene._process(0.1)
			oracle.step(0.2)
		_check(scene.rules.to_dict()==oracle.to_dict(),"reopened session continues exactly")
		_poses()
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--screenshot=") and DisplayServer.get_name()!="headless":
				scene._scroll = 0
				scene._fit()
				await process_frame
				await RenderingServer.frame_post_draw
				_check(root.get_texture().get_image().save_png(arg.substr(13))==OK,"formal third-shop screenshot saved")
	await _finish()

func _finish() -> void:
	if is_instance_valid(scene): scene.free()
	await process_frame
	for name in DirAccess.get_files_at("user://"):
		if name.begins_with(prefix.get_file()): DirAccess.remove_absolute("user://"+name)
	for error in logger.take(): _check(false,error)
	OS.remove_logger(logger)
	print("STIRFRY MIGRATION GUI: %d checks, %d failures"%[checks,failed])
	quit(1 if failed else 0)
