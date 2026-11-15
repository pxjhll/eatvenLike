extends SceneTree
const LegacyRules := preload("res://tests/fixtures/legacy_shops/reference_rules.gd")
const SHOP: SpecShop = preload("res://tests/fixtures/onboarding/shop.tres")
const CAMPAIGN: SpecCampaign = preload("res://tests/fixtures/onboarding/campaign.tres")
const Session := preload("res://tests/shop_test_session.gd")
const Characters := preload("res://presentation/characters/character_library.gd")
var scene: Node2D
var prefix := "user://onboarding-ui-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
var checks := 0
var failed := 0
var logger := preload("res://tests/error_counter.gd").new()

func _initialize() -> void:
	OS.add_logger(logger)
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed += 1
		print("FAIL ",label)

func _open() -> void:
	scene = load("res://presentation/shop/shop_play.tscn").instantiate()
	scene.session = Session.make(SHOP,prefix,null,null,null,CAMPAIGN)
	root.add_child(scene)
	scene.set_process(false)

func _run() -> void:
	root.size = Vector2i(720,1280)
	root.get_node("ShopAudio")._can_play = false
	_open()
	await process_frame
	_check(scene.rules!=null,"persisted demo starts without generation or custom controller")
	if scene.rules==null: await _finish(); return
	_check(scene._staff_height==128 and scene._customer_height==110,"demo uses global tea sizes")
	var hamster: Dictionary = scene.rules.workers.filter(func(worker: Dictionary) -> bool: return worker.kind=="hamster")[0]
	_check(scene._actors[hamster.id].frame_actor.sprite.sprite_frames==Characters.FRAME_ASSETS.hamster,"new employee resolves existing animation mapping")
	scene.ui.open_page("staff")
	_check(scene.ui.portrait_texture("hamster")==Characters.portrait("hamster"),"staff UI resolves the new employee portrait")
	scene.ui.open_page("shop")
	var id := SHOP.goals.opening_station
	scene.reveal_world(scene.anchors.rect("Stations/%s/Frame"%id))
	await process_frame
	var button: Control = scene._station_buttons[id]
	var point: Vector2 = button.get_global_transform_with_canvas()*(button.size/2)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	_check(scene.ui.page=="station" and scene.ui.page_node("station").station_id==id,"module world input reaches generic station panel")
	scene.ui.open_page("shop")
	scene.rules.gold = 1000000.0
	for unused in SHOP.stages.size()+1:
		var next: String = scene.rules.next_unlock()
		if next.is_empty(): break
		_check(scene.execute_command("unlock",{"id":next}).code=="ok","existing stage unlock")
	scene._refresh(0)
	scene.execute_command("set_paused",{"paused":true})
	var paused: Dictionary = scene.rules.to_dict()
	scene._process(0.25)
	_check(scene.rules.to_dict()==paused,"pause holds new shop and employee")
	scene.execute_command("set_paused",{"paused":false})
	for speed in [1,2,4]:
		_check(scene._speed_factor==speed,"existing speed cycle")
		var oracle := LegacyRules.new(SHOP,42)
		_check(oracle.load_dict(scene.rules.to_dict()).is_empty(),"speed oracle loads")
		scene._process(0.1)
		oracle.step(0.1*speed)
		_check(scene.rules.to_dict()==oracle.to_dict(),"demo follows authoritative speed")
		scene.ui.speed_button.pressed.emit()
	var seen := {"walk":false,"work":false,"bundle":false}
	for tick in 2400:
		scene.rules.step(0.1)
		if tick%5!=0: continue
		scene._refresh(0)
		var worker: Dictionary = scene.rules.worker_by_id(hamster.id)
		var actor: Node2D = scene._actors[hamster.id]
		if worker.walking and not worker.path.is_empty(): seen.walk = actor.frame_actor.action=="walk"
		if worker.phase=="work": seen.work = actor.frame_actor.action=="idle"
		seen.bundle = seen.bundle or scene.rules.workers.any(func(row: Dictionary) -> bool: return row.carry_count==2)
		if seen.walk and seen.work and seen.bundle and scene.rules.serve.orders_done>0: break
	_check(seen.walk and seen.work,"employee walks and uses its documented idle fallback during work")
	_check(seen.bundle and scene.rules.serve.orders_done>0,"persisted demo completes real multi-port delivery: "+str(seen)+" orders="+str(scene.rules.serve.orders_done))
	_check(scene.save_now(false)==OK,"demo saves through generic session")
	var saved: Dictionary = scene.rules.to_dict()
	scene.free()
	_open()
	await process_frame
	_check(scene.rules!=null and scene.rules.to_dict()==saved,"saved demo reopens exactly")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot=") and DisplayServer.get_name()!="headless":
			await process_frame
			await RenderingServer.frame_post_draw
			_check(root.get_texture().get_image().save_png(arg.substr(13))==OK,"demo screenshot saved")
	await _finish()

func _finish() -> void:
	if is_instance_valid(scene): scene.free()
	await process_frame
	for name in DirAccess.get_files_at("user://"):
		if name.begins_with(prefix.get_file()): DirAccess.remove_absolute("user://"+name)
	for error in logger.take(): _check(false,error)
	OS.remove_logger(logger)
	print("SHOP ONBOARDING GUI: %d checks, %d failures"%[checks,failed])
	quit(1 if failed else 0)
