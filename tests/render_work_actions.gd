extends SceneTree
const LegacyRules := preload("res://tests/fixtures/legacy_shops/reference_rules.gd")

const TestSession := preload("res://tests/shop_test_session.gd")
## Native game scene and embedded preview, using an isolated in-memory shop.
const Library := preload("res://presentation/characters/character_library.gd")
const Customers := preload("res://game/rules/customer_movement.gd")
var failures := 0
var errors := preload("res://tests/error_counter.gd").new()

func _initialize() -> void:
	OS.add_logger(errors)
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.godot/work_actions_capture")
	root.size = Vector2i(720, 1280)
	var tea: SpecShop = load("res://tests/fixtures/legacy_shops/current/tea/shop.tres").duplicate(true)
	# The movement probe owns legacy order records; use the current employee roster.
	var active_tea: SpecShop = load("res://content/shops/tea/shop.tres")
	tea.staff = active_tea.staff
	var view = load("res://presentation/shop/shop_play.tscn").instantiate()
	var sim := LegacyRules.new(tea)
	sim.gold = 1000000
	for station in ["lemonade", "boil", "seal", "mix", "press", "topping"]:
		sim.unlock(station)
	sim.unlock_box("tea_leaf")
	sim.unlock_box("milk")
	for unused in 4: sim.hire()
	for id in [2, 3, 4, 5]: sim.deploy_worker(id)
	sim.worker_by_id(4).pos = Vector2(270, 430)
	sim.worker_by_id(5).pos = Vector2(430, 510)
	sim.orders.clear()
	sim.seats[sim.dine_group().id] = 8
	for seat in 8: sim.diners.append({"seat": seat, "dish": "lemonade", "left": 20.0})
	sim.paused = true
	sim.movement.customers.clear()
	Customers.sync(sim,true)
	view.session = TestSession.make(tea, "work-actions-%d" % OS.get_process_id(), sim)
	root.add_child(view)
	await process_frame
	view.set_process(false)
	view.guide.enabled = false
	view._refresh(0)
	_advance_customers(sim,view)
	for actor in view._actors.values():
		if actor.frame_actor != null:
			actor.frame_actor.seek_phase(0.45)
	var dining = view._dining
	for key in view._customers:
		var actor = view._customers[key]
		if sim.movement.customers[key].state!="diner": continue
		if actor.frame_actor != null:
			_check(actor.frame_actor.action == "sit", "actual dining scene uses seated clips")
	await _capture("shop.png")
	view.ui.open_page("staff")
	var staff_page = view.ui.page_node("staff")
	_check(staff_page._titles.size() == 5, "staff page shows all five employee species")
	for title: Label in staff_page._titles:
		_check(title.text.begins_with("小灰猫") or title.text.begins_with("小熊") or title.text.begins_with("小兔子") or title.text.begins_with("狐狸") or title.text.begins_with("小鹦鹉"), "staff page only lists active employees")
	await _capture("staff-roster.png")
	view.ui.open_page("shop")
	# Add a second gray cat for the brewer probe while the starter keeps serving.
	_check(sim.hire().is_empty() and sim.deploy_worker(6).is_empty(), "duplicate staff keep distinct roster identities")
	sim.worker_by_id(6).pos = Vector2(340, 620)
	view._refresh(0)
	# Follow the real entry path until a queued customer reaches the reserved chair.
	sim.diners.clear()
	sim.orders = [{"id": 101, "dish": "lemonade", "seat": 0, "wait": 0.0, "reserved": false, "takeaway": false}]
	for i in 100: _advance_customers(sim,view)
	_check(view._customers["order:101"].frame_actor.action == "sit", "waiting customer sits after entering")
	_check(view._customers["order:101"].z_index == 1 and is_equal_approx(view._customers["order:101"].position.y, dining.seat_point(0).y - 14.0), "waiting customer sits above the chair at the same height as a diner")
	sim.orders[0].reserved = true
	_advance_customers(sim,view)
	_check(view._customers["order:101"].frame_actor.action == "walk", "customer stands to collect the drink")
	_check(view._customers["order:101"].z_index == 0, "walking customer returns to normal floor sorting")
	view.ui.page_node("characters").select("rabbit")
	view.ui.open_page("characters")
	var preview = view.ui.page_node("characters").preview
	for id in ["rabbit", "gray_cat", "bear", "fox", "parrot", "squirrel", "dog", "sheep", "hamster"]:
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
			if id in Library.CUSTOMER_IDS and preview.available_actions[i].id == "walk":
				for direction in [0, 2, 3]:
					preview.set_direction(direction)
					preview.frame_actor.seek_phase(0.45)
					var expected: String = "walk_front" if direction == 0 else "walk_right" if direction == 2 or id == "hamster" else "walk_back_right"
					_check(preview.frame_actor.sprite.animation == expected, id + " preview resolves the supplied customer walk views")
					await _capture_stage(id + "-walk-view-%d.png" % direction, preview._stage)
			if id in Library.STAFF_IDS and preview.available_actions[i].id == "work":
				for direction in [0, 2, 3]:
					preview.set_direction(direction)
					preview.frame_actor.seek_phase(0.45)
					var clip: String = {0: "work_front", 2: "work_right", 3: "work_back_right"}[direction]
					_check(preview.frame_actor.sprite.animation == clip, id + " previews all three authored operation views")
					await _capture_stage(id + "-work-view-%d.png" % direction, preview._stage)
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
	_advance_customers(sim,view)
	_check(view._customers["order:104"].frame_actor.action == "walk", "hamster enters using its walk clip")
	for unused in 100: _advance_customers(sim,view)
	_check(view._customers["order:104"].frame_actor.action == "sit", "hamster sits to wait for its real order")
	await _capture("hamster-seated-shop.png")
	sim.orders[0].reserved = true
	_advance_customers(sim,view)
	_check(view._customers["order:104"].frame_actor.action == "walk", "hamster stands to collect its drink")
	sim.orders.clear()
	_advance_customers(sim,view)
	view._refresh(0)
	_check(sim.movement.customers["order:104"].exiting and view._customers["order:104"].frame_actor.action=="walk", "served hamster leaves with authoritative animated walking")
	# Capture naturally assigned operations in the actual shop for all five species.
	sim.paused = false
	for worker_id in [6, 2, 3, 4, 5]:
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

func _advance_customers(sim: ShopRules, view: Node2D) -> void:
	Customers.sync(sim)
	Customers.tick(sim,0.1)
	Customers.sync(sim)
	view._update_customers(0.1)


func _capture_stage(name: String, stage: Control) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	var bounds := Rect2i(stage.get_global_rect())
	_check(screenshot.get_region(bounds).save_png("res://.godot/work_actions_capture/" + name) == OK, "native three-view operation screenshot")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
