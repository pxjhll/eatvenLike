extends SceneTree
## Native input regression: direct placement, interruption and legal/invalid drops.

const Layout := preload("res://content/tea/art_playtest_layout.gd")
var view: Node2D
var failures := 0
var _focus_losses := 0


func _initialize() -> void:
	Input.use_accumulated_input = false
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(720, 1280)
	view = load("res://presentation/tea_playtest/tea_playtest.tscn").instantiate()
	view.sim = preload("res://game/tea_playtest/tea_playtest_sim.gd").new()
	root.add_child(view)
	await process_frame
	view.set_process(false)
	root.focus_exited.connect(func() -> void:
		_focus_losses += 1
		print("STAFF POST GUI: focus lost during input verification")
	)
	root.grab_focus()
	for i in 6:
		await process_frame
	if view.sim == null:
		push_error("STAFF POST GUI: scene did not initialize")
		quit(1)
		return
	var first: Dictionary = view.sim.workers[0]
	await _drag(_screen(first.pos + Vector2(0, -65)), _screen(Vector2(86, 430)), true)
	_check(first.post == "topping", "dragging body into preparation table seats employee")
	_check(first.pos == Vector2(190, 410) and not first.assignment_pending, "release immediately places employee at seated operation point")
	_check(not view._drag.dragging and view._actors[first.id].visible, "drag ghost is removed and actor restored")
	_until(func() -> bool: return not first.assignment_pending)
	_check(first.pos == Layout.POST_POINTS.topping and first.post == "topping", "seated employee remains at operation point")
	view._toast_left = 0
	view._process(0)
	_check(view._mobile_count() == 0 and view._toast.visible, "sole seated employee warns about missing mobile staff")
	await _click(view._staff_cards[0])
	_check(first.post == "topping", "normal card click selects without changing mode")
	await _drag_card(0, _screen(Vector2(360, 610)))
	_check(first.post.is_empty(), "dragging card onto clear floor restores mobile mode")
	_check(first.pos == Vector2(370, 610) and not first.assignment_pending, "card drop immediately places employee in chosen floor cell")
	_until(func() -> bool: return not first.assignment_pending)
	_check(first.pos == Layout.drop_target(Vector2(360, 610)).point, "floor drop remains at chosen cell before new work")
	await _click(view._hire_button)
	_check(view.sim.workers.size() == 2, "normal hire interaction survives drag handlers")
	var second: Dictionary = view.sim.workers[1]
	await _drag_card(0, _screen(Vector2(325, 210)))
	_check(first.post == "boil", "boil art accepts a seated employee")
	var before := JSON.stringify(view.sim.workers)
	await _drag_card(1, _screen(Vector2(325, 210)))
	_check(second.post.is_empty() and first.post == "boil", "occupied post rejects a second employee")
	_check(JSON.stringify(view.sim.workers) == before, "occupied drop leaves current work and assignment untouched")
	await _drag_card(1, _screen(Vector2(460, 180)))
	_check(second.post.is_empty(), "automatic mixing machine does not seat employees")
	await _drag_card(1, _screen(Vector2(100, 760)))
	_check(second.post.is_empty(), "partition wall is not blank walkable floor")
	await _begin_card_drag(1, _screen(Vector2(190, 460)))
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	Input.flush_buffered_events()
	await process_frame
	_check(not view._drag.dragging and second.post.is_empty(), "Escape cancels drag without assignment")
	await _release(_screen(Vector2(190, 460)))
	_until(func() -> bool: return view.sim.sold >= 2)
	_check(view.sim.audit().valid and view.sim.sold >= 2, "seated boil with mobile courier keeps selling and conserving goods")
	await _capture("boil")
	# Dragging interrupts a real delivery and refunds its goods without losing stock.
	_until(func() -> bool: return second.carry_count > 0)
	await _drag_card(1, _screen(Vector2(85, 430)))
	_check(second.post == "topping" and not second.assignment_pending and second.carry_count == 0 and second.job.is_empty(), "busy drop cancels job and returns cargo immediately")
	_check(second.pos == Vector2(190, 410) and view.sim.audit().valid, "busy employee lands immediately with valid stock accounting")
	await _drag_card(0, _screen(Vector2(350, 610)))
	_until(func() -> bool: return not second.assignment_pending)
	var sold_before: int = view.sim.sold
	_until(func() -> bool: return view.sim.sold >= sold_before + 2)
	_check(second.post == "topping" and view.sim.audit().valid, "new seated topping employee operates while mobile worker delivers")
	await _capture("topping")
	# Scaled portrait must use canvas coordinates, not raw 720-unit coordinates.
	root.size = Vector2i(360, 640)
	await process_frame
	view._fit()
	await process_frame
	await _drag_card(1, _screen(Vector2(350, 610)))
	_check(second.post.is_empty(), "scaled viewport card-to-floor drag releases employee")
	_check(second.pos == Vector2(350, 610), "scaled viewport drop places employee immediately")
	await _capture("small")
	root.size = Vector2i(1280, 720)
	await process_frame
	view._fit()
	await process_frame
	await _drag_card(1, _screen(Vector2(85, 430)))
	_check(second.post == "topping", "landscape drag recognizes the same manual station")
	await _capture("landscape")
	root.size = Vector2i(720, 1280)
	await process_frame
	view._fit()
	await process_frame
	await _touch_drag(_screen(second.pos + Vector2(0, -65)), _screen(Vector2(350, 610)))
	_check(second.post.is_empty() and not view._drag.dragging, "touch drag uses the same mobile assignment and clears ghost")
	_check(second.pos == Vector2(350, 610) and not second.walking, "touch release immediately places employee without old route")
	await _begin_touch_card_drag(1, _screen(Vector2(85, 430)))
	_check(view._drag.dragging and view._drag.worker_id == second.id, "touch drag can start from employee card")
	var other := InputEventScreenTouch.new()
	other.index = 1
	other.position = _window_point(_screen(Vector2(400, 610)))
	other.pressed = true
	Input.parse_input_event(other)
	Input.flush_buffered_events()
	await process_frame
	var other_motion := InputEventScreenDrag.new()
	other_motion.index = 1
	other_motion.position = _window_point(_screen(Vector2(325, 210)))
	Input.parse_input_event(other_motion)
	Input.flush_buffered_events()
	await process_frame
	other.pressed = false
	Input.parse_input_event(other)
	Input.flush_buffered_events()
	await process_frame
	_check(view._drag.dragging and second.post.is_empty() and view._drag.target.get("post", "") == "topping", "second finger cannot move or release the owning pointer's drag")
	var cancellation := InputEventScreenTouch.new()
	cancellation.index = 0
	cancellation.position = _window_point(_screen(Vector2(85, 430)))
	cancellation.pressed = false
	cancellation.canceled = true
	Input.parse_input_event(cancellation)
	Input.flush_buffered_events()
	await process_frame
	_check(not view._drag.dragging and second.post.is_empty(), "system-canceled touch never commits the hovered post")
	var blank_touch := InputEventScreenTouch.new()
	blank_touch.index = 0
	blank_touch.position = _window_point(_screen(Vector2(20, 20)))
	blank_touch.pressed = true
	Input.parse_input_event(blank_touch)
	Input.flush_buffered_events()
	_check(view._drag.worker_id == -1 and view._drag._touch_index == 0, "non-worker touch still owns its pointer until release")
	view._drag._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_check(view._drag._touch_index == -1, "focus loss clears pointer even without an employee candidate")
	var blank_cancel := blank_touch.duplicate()
	blank_cancel.pressed = false
	blank_cancel.canceled = true
	Input.parse_input_event(blank_cancel)
	Input.flush_buffered_events()
	await _begin_card_drag(0, _screen(Vector2(85, 430)))
	_check(view._drag.dragging, "mouse drag works after focus-loss cleanup")
	view.restart()
	_check(not view._drag.dragging and view.sim.workers.size() == 1, "restart safely clears pending gesture")
	view.free()
	print("STAFF POST GUI: %d failures" % failures)
	quit(1 if failures else 0)


func _drag_card(index: int, to: Vector2) -> void:
	await _click(view.ui.staff_button)
	await _drag(view._staff_cards[index].get_global_rect().get_center(), to)


func _begin_card_drag(index: int, to: Vector2) -> void:
	await _click(view.ui.staff_button)
	await _begin_drag(view._staff_cards[index].get_global_rect().get_center(), to)


func _begin_touch_card_drag(index: int, to: Vector2) -> void:
	await _click(view.ui.staff_button)
	await _begin_touch_drag(view._staff_cards[index].get_global_rect().get_center(), to)


func _screen(point: Vector2) -> Vector2:
	return view.get_node("Canvas").get_global_transform_with_canvas() * point


func _drag(from: Vector2, to: Vector2, capture := false) -> void:
	await _begin_drag(from, to)
	_check(view._drag.dragging, "real pointer motion starts a drag")
	if capture:
		await _capture("drag-target")
		print("STAFF POST GUI: captured drag active=%s, focus_losses=%d" % [view._drag.dragging, _focus_losses])
	await _release(to)


func _begin_drag(from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = _window_point(from)
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	for i in range(1, 6):
		var motion := InputEventMouseMotion.new()
		motion.position = _window_point(from.lerp(to, i / 5.0))
		motion.relative = _window_point((to - from) / 5.0)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(motion)
		Input.flush_buffered_events()


func _release(point: Vector2) -> void:
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = _window_point(point)
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await process_frame
	view._refresh(0)


func _click(button: Button) -> void:
	await process_frame
	await process_frame
	var scroll: ScrollContainer = button.find_parent("HUD").get_node("Sheet/Margin/Column/Scroll") if button.find_parent("HUD") != null else null
	if scroll != null and scroll.is_ancestor_of(button):
		scroll.ensure_control_visible(button)
		await process_frame
	var close_after := false
	if button == view._hire_button:
		await _click(view.ui.recruit_button)
		close_after = true
	elif button in view._staff_cards and not button.is_visible_in_tree():
		await _click(view.ui.staff_button)
	_check(button.is_visible_in_tree() and not button.disabled, "tested control is visible and enabled")
	await process_frame
	var point := button.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = _window_point(point)
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await _release(point)
	if close_after:
		await _click(view.ui.home_button)


func _window_point(point: Vector2) -> Vector2:
	# Native input is in window pixels; canvas_items keeps a larger logical viewport.
	return point * Vector2(root.size) / view.get_viewport_rect().size


func _touch_drag(from: Vector2, to: Vector2) -> void:
	await _begin_touch_drag(from, to)
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.position = _window_point(to)
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await process_frame
	view._refresh(0)


func _begin_touch_drag(from: Vector2, to: Vector2) -> void:
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = _window_point(from)
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	for i in range(1, 6):
		var motion := InputEventScreenDrag.new()
		motion.index = 0
		motion.position = _window_point(from.lerp(to, i / 5.0))
		motion.relative = _window_point((to - from) / 5.0)
		Input.parse_input_event(motion)
		Input.flush_buffered_events()


func _until(condition: Callable) -> void:
	for i in 8000:
		if condition.call():
			return
		view.sim.advance(0.1)
		view._refresh(0.1)
		if not view.sim.audit().valid:
			_check(false, "inventory audit remains valid during role handoff")
			return
	_check(false, "role transition or sale completes within simulated time limit")


func _capture(suffix: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://docs/qa/staff-posts-" + suffix + ".png") == OK, "screenshot saved")


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("STAFF POST GUI: " + message)
