extends SceneTree
## Native game scene and embedded preview, using an isolated in-memory shop.
const Library := preload("res://presentation/characters/character_library.gd")
var failures := 0
var errors := preload("res://tests/error_counter.gd").new()

func _initialize() -> void:
	OS.add_logger(errors)
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.godot/work_actions_capture")
	root.size = Vector2i(720, 1280)
	var view = load("res://presentation/tea_playtest/tea_playtest.tscn").instantiate()
	var sim = load("res://game/tea_playtest/tea_shop_sim.gd").new()
	sim.gold = 1000000
	for station in ["lemonade", "boil", "seal", "mix", "press", "topping"]:
		sim.unlock_station(station)
	sim.unlock_box("tea_leaf")
	sim.unlock_box("milk")
	for id in ["raccoon", "fox", "rabbit", "gray_cat", "bear"]: sim.acquire_staff(id, "test")
	for id in [4, 5, 6]: sim.deploy_worker(id)
	sim.worker_by_id(4).pos = Vector2(270, 430)
	sim.worker_by_id(5).pos = Vector2(430, 510)
	sim.worker_by_id(6).pos = Vector2(340, 620)
	sim.orders.clear()
	sim.seats = 8
	for seat in 8: sim.diners.append({"seat": seat, "dish": "lemonade", "left": 20.0})
	sim.paused = true
	view.sim = sim
	root.add_child(view)
	await process_frame
	view.set_process(false)
	view.guide.enabled = false
	view._refresh(0)
	for actor in view._actors.values():
		if actor.frame_actor != null:
			actor.frame_actor.seek_phase(0.45)
	var dining = view.art.get_node("Sortables/DiningArea")
	for seat in dining._diners:
		var actor = dining._diners[seat]
		if actor.frame_actor != null:
			_check(actor.frame_actor.action == "sit", "actual dining scene uses seated clips")
	await _capture("shop.png")
	# Follow the real entry path until a queued customer reaches the reserved chair.
	sim.diners.clear()
	sim.orders = [{"id": 101, "dish": "lemonade", "seat": 0, "wait": 0.0, "reserved": false, "takeaway": false}]
	for i in 100: view._update_customers(0.1)
	_check(view._customers[101].frame_actor.action == "sit", "waiting customer sits after entering")
	_check(view._customers[101].z_index == 1 and is_equal_approx(view._customers[101].position.y, view.Layout.seat_point(0).y - 14.0), "waiting customer sits above the chair at the same height as a diner")
	sim.orders[0].reserved = true
	view._update_customers(0.1)
	_check(view._customers[101].frame_actor.action == "walk", "customer stands to collect the drink")
	_check(view._customers[101].z_index == 0, "walking customer returns to normal floor sorting")
	view.ui.open_character_preview("rabbit")
	var preview = view.ui.character_preview
	for id in ["rabbit", "gray_cat", "bear", "squirrel", "dog", "sheep"]:
		preview.select_character(id)
		_check(preview.frame_actor.sprite.sprite_frames == Library.FRAME_ASSETS[id], "preview uses selected character")
		for i in preview.available_actions.size():
			preview._select_action(i)
			preview.frame_actor.pause()
			for direction in 8:
				preview.set_direction(direction)
				_check(not String(preview.frame_actor.sprite.animation).is_empty(), "every facing resolves to an authored view")
			preview.set_direction(2)
			preview.frame_actor.seek_phase(0.45)
			await _capture(id + "-" + str(preview.available_actions[i].id) + ".png")
	view.free()
	var runtime_errors: Array = Array(errors.take())
	OS.remove_logger(errors)
	for message in runtime_errors: print(message)
	failures += runtime_errors.size()
	print("WORK ACTIONS GUI: %d failures" % failures)
	quit(1 if failures else 0)

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://.godot/work_actions_capture/" + name) == OK, "native screenshot")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
