extends SceneTree
## Real art-scene inputs exercise business, owned employees and persistent resume.

var view: Node2D
var hud: Control
var failures := 0
var errors := preload("res://tests/error_counter.gd").new()
var save_path := "user://tea-business-gui-%d.json" % OS.get_process_id()

func _initialize() -> void:
	Input.use_accumulated_input = false
	OS.add_logger(errors)
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(720, 1280)
	view = load("res://presentation/tea_playtest/tea_playtest.tscn").instantiate()
	if ResourceLoader.exists("res://game/tea_playtest/tea_shop_sim.gd"):
		view.sim = load("res://game/tea_playtest/tea_shop_sim.gd").new()
	root.add_child(view)
	await process_frame
	view.set_process(false)
	hud = view.ui
	_check(view.sim.has_method("station_info"), "art scene exposes real business actions")
	if not view.sim.has_method("station_info"):
		view.free()
		quit(1)
		return
	_check(view.sim.gold == 50 and view.sim.stage_index == 0, "fresh shop begins at configured opening stage")
	await _capture("opening")
	await _click(view._station_buttons.lemonade)
	_check(hud.page == "station", "clicking the in-world spot opens real unlock panel")
	await _click(hud.station_panel.unlock_button)
	_check(view.sim.station_unlocked("lemonade") and view.sim.gold == 40, "lemonade unlock spends configured ten coins")
	_advance(500)
	_check(view.sim.revenue >= 300 and view.sim.sold > 0, "opening business earns actual revenue")
	await _click(hud.home_button)
	await _click(view._station_buttons.boil)
	var gold: int = view.sim.gold
	await _click(hud.station_panel.unlock_button)
	_check(view.sim.stage_index == 1 and view.sim.gold == gold - 100 and not view.sim.station_unlocked("mix"), "black tea line opens cabinet, brewer and sealer for its stage price")
	_advance(300)
	_check(int(view.sim.sold_by_dish.get("black_tea", 0)) > 0, "brewed tea is sealed and sold as black tea before the milk machine")
	await _capture("black-tea")
	_check(view._belt_toggle == null and view._belt_slots.is_empty(), "the game offers no conveyor belts")
	view.sim.gold = maxi(view.sim.gold, 220) # the milk machine price is what the next step checks, not black tea income
	await _click(hud.home_button)
	await _click(view._station_buttons.mix)
	gold = view.sim.gold
	await _click(hud.station_panel.unlock_button)
	_check(view.sim.stage_index == 2 and view.sim.gold == gold - 200, "milk machine has its own sign, price and revenue gate")
	_advance(600)
	_check(int(view.sim.sold_by_dish.get("plain_milk_tea", 0)) > 0, "unlocked art production sells real plain milk tea")
	await _click(hud.home_button)
	await _world_click(Vector2(328, 200))
	_check(hud.station_panel.station_id == "boil", "brewer artwork opens its own panel")
	gold = view.sim.gold
	await _click(hud.station_panel.upgrade_button)
	_check(view.sim.station_info("boil").level == 2 and view.sim.gold == gold - 60, "device panel upgrades actual machine")
	await _capture("machine")
	await _click(hud.home_button)
	await _world_click(Vector2(120, 210))
	_check(hud.station_panel.station_id == "supply", "unlocked device artwork opens its own material panel")
	gold = view.sim.gold
	await _click(hud.station_panel.material_buttons.tea_leaf)
	_check(view.sim.material_levels.supply.tea_leaf == 2 and view.sim.gold == gold - 50, "raw material panel upgrades the price of tea drinks")
	await _capture("materials")
	await _click(hud.home_button)
	await _click(view._station_buttons.topping)
	await _click(hud.station_panel.unlock_button)
	_check(view.sim.stage_index == 3, "topping unlock advances real operating stage")
	await _click(hud.station_panel.upgrade_button)
	await _click(hud.station_panel.material_buttons.coconut)
	_check(view.sim.station_info("topping").level == 2 and view.sim.material_levels.topping.coconut == 2, "machine level opens actual coconut flavor upgrade")
	await _capture("flavors")
	await _click(hud.recruit_button)
	await _click(hud.hire_button)
	_check(view.sim.roster.size() == 2 and view.sim.workers.size() == 1, "recruit owns employee without automatically deploying")
	await _click(hud.staff_button)
	await _click(view._staff_cards[1])
	await _click(hud.deploy_button)
	_check(view.sim.workers.size() == 2, "staff panel deploys selected owned employee")
	_advance(15)
	await _click(hud.deploy_button)
	_check(view.sim.workers.size() == 1 and view.sim.audit().valid, "recall refunds busy cargo and preserves owned employee")
	var id: int = view.selected_worker
	var level: int = view.sim.worker_by_id(id).level
	await _click(hud.train_button)
	_check(view.sim.worker_by_id(id).level == level + 1, "reserved employee can be trained")
	await _capture("roster")
	var before_invalid_drop: Dictionary = view.sim.to_dict()
	await _gesture(view._staff_cards[1].get_global_rect().get_center(), _world(Vector2(460, 180)))
	_check(view.sim.to_dict() == before_invalid_drop, "invalid drag never deploys a reserved employee")
	await _click(hud.staff_button)
	await _gesture(view._staff_cards[1].get_global_rect().get_center(), _world(Vector2(325, 210)))
	_check(view.sim.workers.size() == 2 and view.sim.worker_by_id(id).post == "boil", "reserved card drag atomically deploys and seats employee")
	_check(view.sim.audit().valid, "deployment preserves goods and reservations")
	var Store = load("res://game/tea_playtest/tea_shop_save.gd")
	view.store = Store.new(save_path)
	await _click(hud.home_button)
	await _click(hud.speed_button)
	await _click(hud.menu_button)
	await _click(hud.save_button)
	var resumed = view.store.load_game()
	_check(resumed.to_dict() == view.sim.to_dict(), "manual save restores complete business and employee state")
	var saved_state: Dictionary = view.sim.to_dict()
	view.store = null
	view.free()
	view = load("res://presentation/tea_playtest/tea_playtest.tscn").instantiate()
	view.store = Store.new(save_path)
	root.add_child(view)
	view.set_process(false)
	hud = view.ui
	await process_frame
	_check(view.sim.to_dict() == saved_state and view._speed_factor == 2.0, "fresh art scene automatically restores store and playback speed")
	view._process(10.1)
	_check(view.store.load_game().to_dict() == view.sim.to_dict(), "autosave writes running production state")
	await _click(hud.goal_button)
	_check(hud.page == "goals", "tapping the header goal opens the goals page")
	await _capture("tasks")
	root.size = Vector2i(360, 640)
	await _layout()
	await _click(hud.staff_button)
	await _capture("small")
	root.size = Vector2i(1280, 720)
	await _layout()
	await _capture("landscape")
	view.sim.advance(1.0)
	var exit_state: Dictionary = view.sim.to_dict()
	view.free()
	_check(Store.new(save_path).load_game().to_dict() == exit_state, "leaving the view saves the most recent state")
	var queue_view = load("res://presentation/tea_playtest/tea_playtest.tscn").instantiate()
	var queue_sim = load("res://game/tea_playtest/tea_shop_sim.gd").new()
	queue_sim.unlock_station("lemonade")
	for worker in queue_sim.workers.duplicate(): queue_sim.recall_worker(worker.id)
	queue_view.sim = queue_sim
	root.add_child(queue_view)
	await process_frame
	queue_view.set_process(false)
	for i in 200:
		queue_sim.advance(0.1)
		queue_view._refresh(0.1)
	_check(queue_sim.orders.size() > 3 and queue_view._customers.size() == queue_sim.orders.size(), "every queued customer is drawn, not just the first three")
	queue_view.free()
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	for error in errors.take():
		failures += 1
		print(error)
	OS.remove_logger(errors)
	print("TEA BUSINESS GUI: %d failures" % failures)
	quit(1 if failures else 0)

func _advance(seconds: float) -> void:
	view.sim.advance(seconds)
	view._refresh(seconds)
	_check(view.sim.audit().valid, "real business remains conserved while operating")

func _layout() -> void:
	await process_frame
	view._fit()
	await process_frame
	await process_frame

func _click(button: Button) -> void:
	await process_frame
	await process_frame
	var scroll: ScrollContainer = button.find_parent("HUD").get_node("Sheet/Margin/Column/Scroll") if button.find_parent("HUD") != null else null
	if scroll != null and scroll.is_ancestor_of(button):
		scroll.ensure_control_visible(button)
		await process_frame
	await process_frame
	await process_frame
	_check(button.is_visible_in_tree() and not button.disabled, "control is visible and enabled")
	var point := button.get_global_rect().get_center() * Vector2(root.size) / view.get_viewport_rect().size
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	view._refresh(0)
	await process_frame

func _capture(suffix: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://docs/qa/tea-business-" + suffix + ".png") == OK, "capture saved")

func _world(point: Vector2) -> Vector2:
	return view.get_node("Canvas").get_global_transform_with_canvas() * point

func _world_click(point: Vector2) -> void:
	await _gesture(_world(point), _world(point))

func _gesture(from: Vector2, to: Vector2) -> void:
	var factor := Vector2(root.size) / view.get_viewport_rect().size
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = from * factor
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	if from.distance_to(to) > 1:
		for i in range(1, 6):
			var motion := InputEventMouseMotion.new()
			motion.position = from.lerp(to, i / 5.0) * factor
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT
			Input.parse_input_event(motion)
			Input.flush_buffered_events()
	var release := press.duplicate()
	release.position = to * factor
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await process_frame
	view._refresh(0)
	await process_frame

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("TEA BUSINESS GUI: " + message)
