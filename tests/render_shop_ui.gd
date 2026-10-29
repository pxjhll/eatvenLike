extends SceneTree
## Exercise visible UI routes against the actual playable scene and session.

var view: Node2D
var hud: Control
var failures := 0
var captures := false
var script_errors := preload("res://tests/error_counter.gd").new()

func _initialize() -> void:
	OS.add_logger(script_errors)
	Input.use_accumulated_input = false
	captures = DisplayServer.get_name() != "headless"
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(720, 1280)
	view = load("res://presentation/tea_playtest/tea_playtest.tscn").instantiate()
	root.add_child(view)
	await process_frame
	view.set_process(false)
	hud = view.get_node_or_null("Overlay/UI/HUD")
	_check(hud != null, "shop has a separate navigable HUD")
	if hud == null:
		view.free()
		quit(1)
		return
	await _capture("home")
	var gold_before: int = view.sim.gold
	await _click(hud.build_button)
	_check(hud.page == "build", "build entry opens its panel")
	_check(view.sim.gold == gold_before and view.sim.workers.size() == 1, "unreleased construction has no economic side effects")
	await _capture("build")
	await _click(hud.recruit_button)
	_check(hud.page == "recruit", "recruit entry opens real normal recruitment")
	await _capture("recruit")
	await _click(hud.hire_button)
	_check(view.sim.workers.size() == 2 and view.sim.gold == gold_before - 35, "recruit spends actual price and adds actual worker")
	await _click(hud.staff_button)
	_check(hud.page == "staff", "staff entry opens owned roster")
	await _click(view._staff_cards[0])
	gold_before = view.sim.gold
	await _click(hud.train_button)
	_check(view.sim.workers[0].level == 2 and view.sim.gold == gold_before - 25, "training targets selected real employee")
	await _capture("staff")
	root.size = Vector2i(1280, 720)
	await _layout()
	var scroll: ScrollContainer = hud.get_node("Sheet/Margin/Column/Scroll")
	scroll.scroll_vertical = 10000
	await process_frame
	await process_frame
	var clipped_point: Vector2 = view._staff_cards[0].get_global_rect().position + Vector2(20, 4)
	_check(clipped_point.y < scroll.get_global_rect().position.y, "scroll fixture clips card under the panel heading")
	await _gesture(clipped_point, _world(Vector2(325, 210)))
	_check(view.sim.workers[0].post == "" and hud.page == "staff", "clipped roster card cannot be dragged through panel heading")
	scroll.scroll_vertical = 0
	await process_frame
	await process_frame
	var before_header_drop: Dictionary = view.sim.workers[0].duplicate(true)
	var header_target := _world(Vector2(325, 130))
	_check(hud.blocks_world(header_target), "landscape header overlaps the upper workstation art")
	await _gesture(view._staff_cards[0].get_global_rect().get_center(), header_target)
	_check(view.sim.workers[0] == before_header_drop and not view._drag.dragging, "dropping over header preserves employee assignment and work")
	await _click(hud.staff_button)
	root.size = Vector2i(720, 1280)
	await _layout()
	await process_frame
	# An open sheet must not let a gesture pick the actor behind it.
	await _gesture(_world(view.sim.workers[0].pos + Vector2(0, -65)), _world(Vector2(325, 210)))
	_check(view.sim.workers[0].post == "" and not view._drag.dragging, "overlay blocks actor drag through its panel")
	await _click(hud.home_button)
	var hidden_card: Vector2 = view._staff_cards[0].get_global_rect().get_center()
	await _gesture(hidden_card, _world(Vector2(325, 210)))
	_check(view.sim.workers[0].post == "", "hidden staff cards cannot start a drag")
	await _click(hud.staff_button)
	await _gesture(view._staff_cards[0].get_global_rect().get_center(), _world(Vector2(325, 210)))
	_check(view.sim.workers[0].post == "boil" and hud.page == "shop", "dragging visible roster card dismisses sheet and seats real employee")
	_check(view.sim.audit().valid, "new UI drag preserves simulation stock")
	await _click(hud.menu_button)
	_check(hud.page == "menu", "menu opens secondary controls")
	await _click(hud.pause_button)
	_check(view.sim.paused, "menu pause reaches simulation")
	await _click(hud.close_button)
	await _click(hud.staff_button)
	_check(view.sim.paused, "panel navigation preserves explicit pause")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	Input.flush_buffered_events()
	await process_frame
	_check(hud.page == "shop" and view.sim.paused, "Escape dismisses panel without unpausing")
	await _click(hud.home_button)
	await _click(hud.menu_button)
	await _click(hud.restart_button)
	_check(hud.page == "restart" and view.sim.workers.size() == 2, "restart first requests in-game confirmation")
	await _click(hud.cancel_restart_button)
	_check(view.sim.workers.size() == 2 and view.sim.paused, "cancel restart preserves session")
	await _click(hud.home_button)
	root.size = Vector2i(360, 640)
	await _layout()
	await _click(hud.staff_button)
	_check(hud.page == "staff", "small screen navigation remains clickable")
	await _capture("small")
	root.size = Vector2i(1280, 720)
	await _layout()
	await _capture("landscape")
	await _click(hud.home_button)
	await _click(hud.menu_button)
	await _click(hud.restart_button)
	await _click(hud.confirm_restart_button)
	_check(view.sim.workers.size() == 1 and view.sim.gold == 60 and not view.sim.paused and hud.page == "shop", "confirmed restart resets actual session and returns to shop")
	view.free()
	for error in script_errors.take():
		failures += 1
		print("SHOP UI runtime error: " + error)
	OS.remove_logger(script_errors)
	print("SHOP UI GUI: %d failures" % failures)
	quit(1 if failures else 0)

func _layout() -> void:
	await process_frame
	view._fit()
	await process_frame
	await process_frame

func _click(button: Button) -> void:
	_check(button.is_visible_in_tree() and not button.disabled, "tested control is visible and enabled")
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

func _world(point: Vector2) -> Vector2:
	return view.get_node("Canvas").get_global_transform_with_canvas() * point

func _gesture(from: Vector2, to: Vector2) -> void:
	var factor := Vector2(root.size) / view.get_viewport_rect().size
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = from * factor
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
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

func _capture(suffix: String) -> void:
	if not captures:
		return
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://docs/qa/shop-ui-" + suffix + ".png") == OK, "screenshot saved")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("SHOP UI GUI: " + message)
