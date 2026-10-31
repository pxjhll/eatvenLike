extends SceneTree
## First-shop tutorial driven by real taps: welcome, lemonade, first sale, hire, deploy, later hints.

var view: Node2D
var hud: Control
var guide: Control
var failures := 0
var errors := preload("res://tests/error_counter.gd").new()
var save_path := "user://tea-guide-gui-%d.json" % OS.get_process_id()
var Store = load("res://game/tea_playtest/tea_shop_save.gd")

func _initialize() -> void:
	Input.use_accumulated_input = false
	OS.add_logger(errors)
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(720, 1280)
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	view = load("res://presentation/tea_playtest/tea_playtest.tscn").instantiate()
	view.sim = load("res://game/tea_playtest/tea_shop_sim.gd").new()
	view.store = Store.new(save_path)
	root.add_child(view)
	await process_frame
	view.set_process(false)
	hud = view.ui
	guide = view.guide
	_check(not guide.enabled and not guide.visible, "injected test sims run without the tutorial")
	guide.enabled = true
	guide.refresh(0)
	_check(guide.active == "welcome" and guide.freezes(), "a fresh shop opens on the welcome card and holds the clock")
	await process_frame
	guide.refresh(0)
	await _capture("welcome")
	await _click(guide._card_primary)
	_check(guide.active == "opening" and guide._hole.intersects(_local(view._station_buttons.lemonade)), "the hand points at the lemonade sign")
	await _capture("unlock-sign")
	var elapsed: float = view.sim.elapsed
	await _press(hud.recruit_button.get_global_rect().get_center())
	_check(hud.page == "shop", "taps outside the highlight are swallowed")
	view._process(1.0)
	_check(view.sim.elapsed == elapsed, "the shop clock stops while a dimmed step is up")
	await _click(view._station_buttons.lemonade)
	_check(hud.page == "station" and guide._hole.intersects(_local(hud.station_panel.unlock_button)), "inside the panel the hand moves to the unlock button")
	await _capture("unlock-button")
	await _click(hud.station_panel.unlock_button)
	_check(view.sim.station_unlocked("lemonade"), "the guided tap unlocks the lemonade stand")
	await _click(hud.home_button)
	_check(not guide.freezes() and guide._bubble.visible, "the first sale plays out live with a hint")
	await _capture("first-sale")
	_run_until(func() -> bool: return view.sim.sold > 0 and view.sim.gold >= view.sim.hire_cost(), 120.0)
	_check(guide._hole.intersects(_local(hud.recruit_button)), "after the first sale the hand points at recruiting")
	await _capture("hire")
	await _click(hud.recruit_button)
	await _click(hud.hire_button)
	_check(view.sim.roster.size() == 2, "the guided hire adds a partner to the roster")
	_check(guide._hole.intersects(_local(hud.staff_button)), "the hand then points at the staff tab")
	await _click(hud.staff_button)
	_check(guide._hole.intersects(_local(hud.deploy_button)) and not view.staff_is_deployed(view.selected_worker), "the staff page selects the waiting partner and points at deploy")
	await _capture("deploy")
	await _click(hud.deploy_button)
	_check(view.sim.workers.size() == 2 and guide.active == "done", "deploying finishes the opening")
	_check(hud.page == "shop", "the done card shows over the shop floor")
	await _capture("done")
	await _click(guide._card_primary)
	_check(guide.active.is_empty() and guide.seen.has("opening") and not guide.freezes(), "the done card hands the shop back")
	var resumed = Store.new(save_path)
	resumed.load_game()
	_check("opening" in resumed.loaded_guides, "finished guides are saved beside the shop")
	view.sim.gold = maxi(view.sim.gold, 200)
	guide.seen.lost = true # a walk-out during the run is covered separately below
	_run_until(func() -> bool: return guide.active == "line_1", 300.0)
	_check(guide.freezes() and guide._hole.intersects(_local(view._station_buttons.boil)), "the black tea line gets one guided unlock once it is affordable")
	await _capture("line")
	await _click(view._station_buttons.boil)
	await _click(hud.station_panel.unlock_button)
	_check(view.sim.stage_index == 1 and guide.active.is_empty(), "unlocking the line closes its hint")
	await _click(hud.home_button)
	guide.seen.erase("lost")
	view.sim._event("customer_left", "顾客等待过久，已离开")
	guide.refresh(0)
	_check(guide.active == "lost" and guide.freezes(), "the first customer who walks out pauses on a short hint")
	await _capture("lost")
	await _click(guide._bubble_skip)
	view.sim._event("customer_left", "顾客等待过久，已离开")
	guide.refresh(0)
	_check(guide.active.is_empty(), "each hint shows only once")
	view.free()
	var reopened = load("res://presentation/tea_playtest/tea_playtest.tscn").instantiate()
	reopened.store = Store.new(save_path)
	root.add_child(reopened)
	await process_frame
	reopened.set_process(false)
	reopened.guide.refresh(0)
	_check(reopened.guide.enabled and reopened.guide.active.is_empty() and reopened.guide.seen.has("lost"), "a reopened game remembers which guides were seen")
	reopened.free()
	var old_save = load("res://game/tea_playtest/tea_shop_sim.gd").new()
	old_save.unlock_station("lemonade")
	old_save.hire()
	old_save.deploy_worker(old_save.roster[1].id)
	Store.new(save_path).save_game(old_save)
	var veteran = load("res://presentation/tea_playtest/tea_playtest.tscn").instantiate()
	veteran.store = Store.new(save_path)
	root.add_child(veteran)
	await process_frame
	veteran.set_process(false)
	veteran.guide.refresh(0)
	_check(veteran.guide.active.is_empty() and veteran.guide.seen.has("opening"), "a save from before the tutorial skips the opening")
	veteran.free()
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	for error in errors.take():
		failures += 1
		print(error)
	OS.remove_logger(errors)
	print("TEA GUIDE GUI: %d failures" % failures)
	quit(1 if failures else 0)

func _run_until(done: Callable, limit: float) -> void:
	var spent := 0.0
	while not done.call() and spent < limit:
		view._process(0.25)
		spent += 0.25

func _local(control: Control) -> Rect2:
	return guide._to_local(control.get_global_transform_with_canvas(), Rect2(Vector2.ZERO, control.size))

func _click(button: Button) -> void:
	for unused in 4:
		await process_frame
	view._refresh(0)
	guide.refresh(0)
	_check(button.is_visible_in_tree() and not button.disabled, "control is visible and enabled: " + button.text)
	await _press(button.get_global_transform_with_canvas() * (button.size / 2.0))

func _press(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	view._refresh(0)
	guide.refresh(0)
	await process_frame
	guide.refresh(0)

func _capture(suffix: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	guide.refresh(0.4)
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://docs/qa/guide-" + suffix + ".png") == OK, "capture saved")

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: " + label)
