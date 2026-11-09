extends SceneTree

const TestSession := preload("res://tests/shop_test_session.gd")
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
	var tea: SpecShop = load("res://content/shops/tea/shop.tres")
	var view = load("res://presentation/shop/shop_play.tscn").instantiate()
	var sim := ShopRules.new(tea)
	sim.gold = 1000000
	for station in ["lemonade", "boil", "seal", "mix", "press", "topping"]:
		sim.unlock(station)
	sim.unlock_box("tea_leaf")
	sim.unlock_box("milk")
	for unused in 5: sim.hire()
	for id in [4, 5, 6]: sim.deploy_worker(id)
	sim.worker_by_id(4).pos = Vector2(270, 430)
	sim.worker_by_id(5).pos = Vector2(430, 510)
	sim.worker_by_id(6).pos = Vector2(340, 620)
	sim.orders.clear()
	sim.seats[sim.dine_group().id] = 8
	for seat in 8: sim.diners.append({"seat": seat, "dish": "lemonade", "left": 20.0})
	sim.paused = true
	view.session = TestSession.make(tea, "work-actions-%d" % OS.get_process_id(), sim)
	root.add_child(view)
	await process_frame
	view.set_process(false)
	view.guide.enabled = false
	view._refresh(0)
	for actor in view._actors.values():
		if actor.frame_actor != null:
			actor.frame_actor.seek_phase(0.45)
	var dining = view._dining
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
	_check(view._customers[101].z_index == 1 and is_equal_approx(view._customers[101].position.y, dining.seat_point(0).y - 14.0), "waiting customer sits above the chair at the same height as a diner")
	sim.orders[0].reserved = true
	view._update_customers(0.1)
	_check(view._customers[101].frame_actor.action == "walk", "customer stands to collect the drink")
	_check(view._customers[101].z_index == 0, "walking customer returns to normal floor sorting")
	view.ui.page_node("characters").select("rabbit")
	view.ui.open_page("characters")
	var preview = view.ui.page_node("characters").preview
	for id in ["rabbit", "gray_cat", "bear", "squirrel", "dog", "sheep", "hamster"]:
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
			if id == "gray_cat" and preview.available_actions[i].id == "work":
				preview.set_direction(3)
				_check(preview.frame_actor.sprite.animation == "work_back_right", "back operation resolves to its separate source clip")
				await _capture("gray_cat-work-back.png")
			if id == "rabbit" and preview.available_actions[i].id == "work":
				for direction in [0, 3, 6]:
					preview.set_direction(direction)
					preview.frame_actor.seek_phase(0.45)
					await _capture("rabbit-work-%d.png" % direction)
				preview.set_direction(0)
				preview.frame_actor.seek_phase(0.999)
				_check(preview.frame_actor.sprite.frame == 16, "preview can seek the seventeenth front pose")
				preview._step(1)
				_check(preview.frame_actor.sprite.frame == 0 and not preview.frame_actor.sprite.is_playing(), "assembly frame stepping wraps while paused")
				preview._step(-1)
				_check(preview.frame_actor.sprite.frame == 16, "assembly can step back to the final front pose")
	# The fourth customer is a hamster: walk in, wait seated, stand to collect, then leave.
	view.ui.open_page("shop")
	sim.orders = [{"id": 104, "dish": "lemonade", "seat": 0, "wait": 0.0, "reserved": false, "takeaway": false}]
	view._update_customers(0.1)
	_check(view._customers[104].frame_actor.action == "walk", "hamster enters using its walk clip")
	for unused in 100: view._update_customers(0.1)
	_check(view._customers[104].frame_actor.action == "sit", "hamster sits to wait for its real order")
	await _capture("hamster-seated-shop.png")
	sim.orders[0].reserved = true
	view._update_customers(0.1)
	_check(view._customers[104].frame_actor.action == "walk", "hamster stands to collect its drink")
	sim.orders.clear()
	view._update_customers(0.1)
	view._refresh(0)
	_check(dining._walkers.any(func(w): return w.actor._art == "hamster" and w.actor.frame_actor.action == "walk"), "served hamster leaves with animated walking")
	# Capture naturally assigned operations in the actual shop for both employees.
	sim.paused = false
	for worker_id in [5, 4]:
		var art_id: String = sim.worker_by_id(worker_id).kind
		_check(sim.place_worker(worker_id, "boil") == "", art_id + " can be assigned to the manual brewer post")
		var operated := false
		for unused in 3000:
			sim.step(0.1)
			if sim.worker_by_id(worker_id).phase == "work":
				view._refresh(0)
				operated = view._actors[worker_id].frame_actor.action == "work"
				break
		_check(operated, "actual shop shows " + art_id + " operation during production")
		await _capture(art_id + "-operation-shop.png")
		_check(sim.recall_worker(worker_id).is_empty(), "recall operator so the next employee is visible at the brewer")
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
