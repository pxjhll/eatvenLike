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
	_check(_art_hidden(["MachineTable", "PrepBench", "Sealer", "Rack", "DisplayCase"]), "locked machines draw no art before unlock")
	_check(not _art_hidden(["IngredientTable"]), "the ingredient cabinet is furniture from the start")
	_check(_frames_shown(["lemonade"]) and _frames_hidden(["boil", "supply", "seal", "shelf", "mix", "topping"]), "fresh shop shows only the lemonade stand's dashed frame")
	_check(view._station_buttons.lemonade.can_unlock, "red arrow marks what can be bought now")
	await _capture("opening")
	await _click(view._station_buttons.lemonade)
	_check(hud.page == "station", "clicking the in-world spot opens real unlock panel")
	await _click(hud.station_panel.unlock_button)
	_check(_frames_shown(["boil", "shelf"]) and _frames_hidden(["lemonade", "supply", "seal", "mix", "topping"]), "after opening only the brewer's frames show")
	await _click(hud.home_button)
	await _click(view._station_buttons.shelf)
	_check(hud.page == "station" and hud.station_panel.station_id == "boil", "the shelf spot opens the brewer's unlock panel")
	_check(view.sim.station_unlocked("lemonade") and view.sim.gold == 40, "lemonade unlock spends configured ten coins")
	_check(view._seats.visible and view._seats.text.begins_with("堂食"), "the seat chip shows who is sitting")
	_advance(500)
	_check(view.sim.revenue >= 300 and view.sim.sold > 0, "opening business earns actual revenue")
	_check(view.sim.diners.size() <= view.sim.seats, "never more diners than seats")
	await _click(hud.home_button)
	await _click(view._station_buttons.boil)
	var gold: int = view.sim.gold
	await _click(hud.station_panel.unlock_button)
	_check(view.sim.stage_index == 1 and view.sim.gold == gold - 100 and not view.sim.station_unlocked("seal"), "the brewer opens on its own for its stage price")
	_check(not _art_hidden(["IngredientTable", "MachineTable", "MachineTable/PearlPot", "Rack", "DisplayCase"]) and _art_hidden(["MachineTable/Brewer", "PrepBench", "Sealer"]), "the brewer and shelf appear, later machines stay hidden")
	_check(_frames_shown(["supply", "seal"]) and _frames_hidden(["boil", "mix", "topping"]), "the cabinet asks for the tea leaf box, the sealer is next")
	await _click(hud.home_button)
	await _capture("frames")
	await _click(view._station_buttons.supply)
	_check(hud.page == "station" and hud.station_panel.station_id == "supply", "the cabinet frame opens the cabinet panel")
	gold = view.sim.gold
	await _click(hud.station_panel.material_buttons.tea_leaf)
	_check(view.sim.boxes.tea_leaf and view.sim.gold == gold - 20, "the tea leaf box is bought in the cabinet panel")
	await _click(hud.home_button)
	_check(_frames_hidden(["supply"]), "the cabinet frame goes away once the box is in")
	# The front worker stays at the counter; brewing needs a kitchen hand.
	view.sim.gold = maxi(view.sim.gold, 200)
	await _click(hud.recruit_button)
	await _click(hud.hire_button)
	await _click(hud.staff_button)
	await _click(view._staff_cards[1])
	await _click(hud.deploy_button)
	_check(view.sim.kitchen_staff() == 1 and view.sim.front_staff() == 1, "the recruit deploys to the kitchen, the starter keeps the counter")
	await _click(hud.home_button)
	_advance(300)
	_check(int(view.sim.sold_by_dish.get("black_tea", 0)) > 0, "brewed tea is shelved and served to seated customers")
	await _capture("black-tea")
	_check(view._belt_toggle == null and view._belt_slots.is_empty(), "the game offers no conveyor belts")
	await _world_click(view._seats.position + view._seats.size / 2)
	_check(hud.page == "station" and hud.station_panel.station_id == "counter", "the seat chip opens the counter")
	view.sim.gold = maxi(view.sim.gold, 1000)
	gold = view.sim.gold
	var seat_cost: int = view.sim.seat_cost()
	await _click(hud.station_panel.seat_button)
	_check(view.sim.seats == 4 and view.sim.gold == gold - seat_cost and seat_cost <= 15, "the counter sells one more seat, the first one cheap")
	view.sim.revenue = maxi(view.sim.revenue, 600)
	await _click(hud.home_button)
	await _click(view._station_buttons.seal)
	gold = view.sim.gold
	await _click(hud.station_panel.unlock_button)
	_check(view.sim.stage_index == 2 and view.sim.gold == gold - 150 and not _art_hidden(["Sealer"]), "the sealer has its own frame, price and art")
	await _click(hud.home_button)
	_check(_frames_shown(["mix"]) and _frames_hidden(["seal", "supply"]), "the milk machine frame appears next")
	await _click(view._station_buttons.mix)
	gold = view.sim.gold
	await _click(hud.station_panel.unlock_button)
	_check(view.sim.stage_index == 3 and view.sim.gold == gold - 250, "milk machine has its own sign, price and revenue gate")
	await _click(hud.home_button)
	_check(_frames_shown(["supply"]), "the cabinet now asks for the milk box")
	await _click(view._station_buttons.supply)
	gold = view.sim.gold
	await _click(hud.station_panel.material_buttons.milk)
	_check(view.sim.boxes.milk and view.sim.gold == gold - 40, "the milk box is bought in the cabinet panel")
	_advance(600)
	_check(int(view.sim.sold_by_dish.get("plain_milk_tea", 0)) > 0, "unlocked art production sells real plain milk tea")
	await _click(hud.home_button)
	await _capture("takeaway")
	await _world_click(Vector2(390, 150))
	_check(hud.station_panel.station_id == "boil", "brewer artwork opens its own panel")
	gold = view.sim.gold
	var brew_cost: int = view.sim.station_info("boil").upgrade_cost
	await _click(hud.station_panel.upgrade_button)
	_check(view.sim.station_info("boil").level == 2 and view.sim.gold == gold - brew_cost, "device panel upgrades actual machine")
	await _capture("machine")
	await _click(hud.home_button)
	await _world_click(Vector2(120, 210))
	_check(hud.station_panel.station_id == "supply", "unlocked device artwork opens its own material panel")
	gold = view.sim.gold
	await _click(hud.station_panel.material_buttons.tea_leaf)
	_check(view.sim.material_levels.supply.tea_leaf == 2 and view.sim.gold == gold - 50, "raw material panel upgrades the price of tea drinks")
	await _capture("materials")
	view.sim.revenue = maxi(view.sim.revenue, 1200)
	view.sim.gold = maxi(view.sim.gold, 1000)
	await _click(hud.home_button)
	await _click(view._station_buttons.topping)
	await _click(hud.station_panel.unlock_button)
	_check(view.sim.stage_index == 4, "topping unlock advances real operating stage")
	await _click(hud.station_panel.upgrade_button)
	await _click(hud.station_panel.material_buttons.coconut)
	_check(view.sim.station_info("topping").level == 2 and view.sim.material_levels.topping.coconut == 2, "machine level opens actual coconut flavor upgrade")
	await _capture("flavors")
	await _click(hud.recruit_button)
	await _click(hud.hire_button)
	_check(view.sim.roster.size() == 3 and view.sim.workers.size() == 2, "recruit owns employee without automatically deploying")
	await _click(hud.staff_button)
	await _click(view._staff_cards[2])
	await _click(hud.deploy_button)
	_check(view.sim.workers.size() == 3, "staff panel deploys selected owned employee")
	_advance(15)
	await _click(hud.deploy_button)
	_check(view.sim.workers.size() == 2 and view.sim.audit().valid, "recall refunds busy cargo and preserves owned employee")
	var id: int = view.selected_worker
	view.sim.gold = maxi(view.sim.gold, 1000)
	await _click(hud.train_button)
	_check(view.sim.front_upgrades == 1, "the staff page buys the next front upgrade")
	await _click(hud.kitchen_upgrade_button)
	_check(view.sim.kitchen_upgrades == 1, "the staff page buys the next kitchen upgrade")
	await _capture("roster")
	var before_invalid_drop: Dictionary = view.sim.to_dict()
	await _gesture(view._staff_cards[2].get_global_rect().get_center(), _world(Vector2(460, 180)))
	_check(view.sim.to_dict() == before_invalid_drop, "invalid drag never deploys a reserved employee")
	await _click(hud.staff_button)
	await _gesture(view._staff_cards[2].get_global_rect().get_center(), _world(Vector2(325, 210)))
	_check(view.sim.workers.size() == 3 and view.sim.worker_by_id(id).post == "boil", "reserved card drag atomically deploys and seats employee")
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

func _art_hidden(paths: Array) -> bool:
	for path in paths:
		if view.art.get_node("Sortables/" + path).is_visible_in_tree():
			return false
	return true

func _frames_shown(ids: Array) -> bool:
	for id in ids:
		if not view._station_buttons[id].is_visible_in_tree():
			return false
	return true

func _frames_hidden(ids: Array) -> bool:
	for id in ids:
		if view._station_buttons[id].is_visible_in_tree():
			return false
	return true

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
