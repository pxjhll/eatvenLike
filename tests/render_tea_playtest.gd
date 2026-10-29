extends SceneTree
## Real renderer and real GUI input against the playable artwork scene.

var failures := 0
var view: Node2D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(720, 1280)
	view = load("res://presentation/tea_playtest/tea_playtest.tscn").instantiate()
	view.sim = preload("res://game/tea_playtest/tea_playtest_sim.gd").new()
	root.add_child(view)
	current_scene = view
	await process_frame
	view.set_process(false)
	var profile_before := JSON.stringify(root.get_node("App").profile.to_dict())
	_check(view.art.get_node("Sortables/PrepBench").position == Vector2(84, 594.37), "existing furniture placement retained")
	_check(not view.art.get_node("Sortables/Cat").visible, "static employee is replaced")
	_check(not view.art.get_node("Sortables/Rack/RackCupA").visible, "example cups are not real stock")
	_advance_until(func() -> bool: return view.sim.workers[0].phase == "work" and view.sim.workers[0].job.get("kind", "") == "topping")
	_check(view.sim.workers[0].phase == "work" and view.sim.workers[0].job.get("kind", "") == "topping", "worker reaches the actual manual topping step")
	await _capture("single")
	var starting_gold: int = view.sim.gold
	var hire_price: int = view.sim.hire_cost()
	await _click(view._hire_button)
	_check(view.sim.workers.size() == 2 and view.sim.gold == starting_gold - hire_price, "hire button buys a real second employee")
	var old_capacity: int = view.sim.workers[1].capacity
	if view.sim.gold >= view.sim.train_cost(2):
		await _click(view._train_button)
		_check(view.sim.workers[1].capacity > old_capacity, "training button improves selected strength employee")
	_advance_until(func() -> bool: return view.sim.gold >= view.sim.hire_cost())
	await _click(view._hire_button)
	_check(view.sim.workers.size() == 3, "three employees can be hired using earned money")
	for i in 170:
		view.sim.advance(0.1)
		view._refresh(0.1)
	_advance_until(_team_is_spread_out)
	await _capture("team")
	_check(view.sim.audit().valid, "stock and reservations conserved in actual scene")
	await _click(view._pause_button)
	var clock: float = view.sim.elapsed
	view.sim.advance(2.0)
	_check(view.sim.paused and view.sim.elapsed == clock, "pause button freezes the business clock")
	await _click(view._pause_button)
	_check(not view.sim.paused, "resume button restores simulation")
	await _click(view._speed_button)
	_check(view._speed_factor == 2.0, "speed button switches to real double-speed simulation")
	await _click(view._belt_button)
	_check(not view.sim.use_belts, "transport button selects manual delivery")
	for i in 300:
		view.sim.advance(0.1)
		view._refresh(0.1)
	await _capture("manual")
	root.size = Vector2i(360, 640)
	view._fit()
	await _capture("small")
	root.size = Vector2i(1280, 720)
	view._fit()
	await _capture("landscape")
	root.size = Vector2i(720, 1280)
	view._fit()
	await _click(view._restart_button)
	_check(view.sim.workers.size() == 1 and view.sim.sold == 0, "restart creates a fresh real session")
	_check(JSON.stringify(root.get_node("App").profile.to_dict()) == profile_before, "playtest never changes old profile")
	view.free()
	await _verify_old_game_round_trip()
	print("TEA ART PLAYTEST: real GUI, portrait/small/landscape, %d failures" % failures)
	quit(1 if failures else 0)


func _verify_old_game_round_trip() -> void:
	var app: Node = root.get_node("App")
	var previous_profile: Profile = app.profile
	var previous_pending: Dictionary = app._pending_shop_state
	var previous_path: String = app.save_service.path
	var previous_art_store: RefCounted = app.art_shop_save
	app.art_shop_save = preload("res://game/tea_playtest/tea_shop_save.gd").new("user://tea-entry-art-test.json")
	app.save_service.path = "user://tea-playtest-entry-test.json"
	for from_preview in [false, true]:
		app.profile = Profile.create(app.catalog)
		app._pending_shop_state = {}
		change_scene_to_file("res://presentation/shop.tscn")
		await process_frame
		await process_frame
		var shop: Node = current_scene
		shop.sim.paused = true
		shop.sim.economy.gold = 321
		var entry: Button
		if from_preview:
			shop.open_art_preview()
			await process_frame
			entry = _find_button(shop._art_preview, "试玩")
		else:
			entry = _find_button(shop.controls, "试玩")
		_check(entry != null, "playable entry is discoverable from old game and art preview")
		if entry == null:
			continue
		await _click(entry)
		await process_frame
		var play: Node = current_scene
		_check(play.has_method("restart"), "entry opens the real playable art scene")
		if not play.has_method("restart"):
			continue
		play.set_process(false)
		_check(app.sim == null, "old autosave is detached during session-only playtest")
		var saved: Dictionary = app.save_service.load_data()
		_check(saved.has("shop") and int(saved.shop.economy.gold) == 321, "old progress is persisted before leaving, including normal quit in playtest")
		_check(int(app._pending_shop_state.economy.gold) == 321, "old session is also retained in memory")
		await _click(play.ui.menu_button)
		await _click(play._old_button)
		await process_frame
		shop = current_scene
		shop.sim.paused = true
		_check(shop.sim.economy.gold == 321, "return restores previous old-game progress")
		app.sim = null
		shop.free()
	app.profile = previous_profile
	app._pending_shop_state = previous_pending
	app.save_service.path = previous_path
	app.art_shop_save = previous_art_store
	if FileAccess.file_exists("user://tea-entry-art-test.json"):
		DirAccess.remove_absolute("user://tea-entry-art-test.json")
	if FileAccess.file_exists("user://tea-playtest-entry-test.json"):
		DirAccess.remove_absolute("user://tea-playtest-entry-test.json")


func _team_is_spread_out() -> bool:
	if view.sim.belt_items.is_empty():
		return false
	for a in view.sim.workers.size():
		for b in range(a + 1, view.sim.workers.size()):
			if view.sim.workers[a].pos.distance_to(view.sim.workers[b].pos) < 115:
				return false
	return true


func _find_button(parent: Node, text: String) -> Button:
	for node in parent.find_children("*", "Button", true, false):
		if node.text == text:
			return node
	return null


func _advance_until(condition: Callable) -> void:
	for i in 6000:
		if condition.call():
			return
		view.sim.advance(0.1)
		view._refresh(0.1)
	_check(false, "expected playable state reached within ten simulated minutes")


func _click(button: Button) -> void:
	await process_frame
	await process_frame
	var scroll: ScrollContainer = button.find_parent("HUD").get_node("Sheet/Margin/Column/Scroll") if button.find_parent("HUD") != null else null
	if scroll != null and scroll.is_ancestor_of(button):
		scroll.ensure_control_visible(button)
		await process_frame
	var close_after := false
	var confirm_restart := false
	if is_instance_valid(view):
		if button == view._hire_button:
			await _click(view.ui.recruit_button)
			close_after = true
		elif button == view._train_button:
			await _click(view.ui.staff_button)
			close_after = true
		elif button in [view._pause_button, view._belt_button, view._restart_button, view._old_button]:
			await _click(view.ui.menu_button)
			close_after = button != view._old_button
			confirm_restart = button == view._restart_button
	_check(button.is_visible_in_tree() and not button.disabled, "tested control is visible and enabled")
	await process_frame
	var point := button.get_global_rect().get_center() * Vector2(root.size) / root.get_visible_rect().size
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = point
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var release := press.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame
	if confirm_restart:
		await _click(view.ui.confirm_restart_button)
	if close_after:
		await _click(view.ui.home_button)


func _capture(suffix: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png("res://docs/qa/tea-playtest-" + suffix + ".png")
	_check(result == OK, "screenshot saved: " + suffix)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("TEA ART PLAYTEST: " + message)
