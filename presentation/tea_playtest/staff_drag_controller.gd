extends Node2D
## A visual drag proposes an assignment. The simulation owns position and inventory.

const Layout := preload("res://content/tea/art_playtest_layout.gd")
const Actor := preload("res://presentation/tea_playtest/staff_actor.gd")
const POST_NAMES := {"boil": "煮茶台", "topping": "加料台"}
var dragging := false
var worker_id := -1
var target: Dictionary = {}
var _view: Node2D
var _press := Vector2.ZERO
var _pointer := Vector2.ZERO
var _grab_offset := Vector2.ZERO
var _ghost: Node2D
var _touch_index := -1
var _source_card := -1


func setup(view: Node2D) -> void:
	_view = view
	z_index = 80


func _input(event: InputEvent) -> void:
	if not is_instance_valid(_view) or _view.sim == null:
		return
	# Native touch is handled below. Its synthetic mouse events must not commit twice.
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and worker_id != -1:
		cancel()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if _touch_index != -1:
			return
		if event.pressed:
			_press_body(event.position)
		else:
			_release(event.position)
	elif event is InputEventMouseMotion and worker_id != -1:
		if _touch_index == -1 and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_motion(event.position)
	elif event is InputEventScreenTouch:
		if event.pressed:
			if _touch_index != -1 or worker_id != -1:
				get_viewport().set_input_as_handled()
				return
			_touch_index = event.index
			_press_body(event.position)
		else:
			if event.index != _touch_index:
				return
			if event.canceled:
				cancel()
				get_viewport().set_input_as_handled()
			else:
				_release(event.position)
				_touch_index = -1
	elif event is InputEventScreenDrag and worker_id != -1 and event.index == _touch_index:
		_motion(event.position)


func _press_body(screen: Vector2) -> void:
	if worker_id != -1:
		return
	for i in mini(_view._staff_cards.size(), _view.sim.workers.size()):
		if _view._staff_cards[i].get_global_rect().has_point(screen):
			_candidate(int(_view.sim.workers[i].id), screen, true)
			return
	var point := _world(screen)
	if point.y < 98 or point.y >= 1200:
		return
	var found := -1
	var depth := -INF
	for worker in _view.sim.workers:
		if Rect2(worker.pos + Vector2(-50, -130), Vector2(100, 145)).has_point(point) and worker.pos.y >= depth:
			found = int(worker.id)
			depth = worker.pos.y
	if found != -1:
		_candidate(found, screen, false)


func _candidate(id: int, screen: Vector2, from_card: bool) -> void:
	worker_id = id
	_press = screen
	_pointer = _world(screen)
	_view.selected_worker = id
	var worker := _worker()
	_grab_offset = Vector2(0, 60) if from_card else worker.pos - _pointer


func _motion(screen: Vector2) -> void:
	if not dragging and screen.distance_to(_press) < 8:
		return
	if not dragging:
		_start_drag()
	_pointer = _world(screen)
	target = Layout.drop_target(_pointer)
	_update_ghost()
	queue_redraw()
	get_viewport().set_input_as_handled()


func _start_drag() -> void:
	var worker := _worker()
	if worker.is_empty():
		cancel()
		return
	dragging = true
	_ghost = Actor.new()
	_ghost.setup(worker.art, _view._font)
	_ghost.selected = true
	_ghost.modulate.a = 0.78
	add_child(_ghost)
	for i in _view.sim.workers.size():
		if int(_view.sim.workers[i].id) == worker_id:
			_source_card = i
			# Clear the button's held-down GUI state before release is consumed by drag.
			_view._staff_cards[i].disabled = true
	if _view._actors.has(worker_id):
		_view._actors[worker_id].visible = false


func _update_ghost() -> void:
	if not dragging or not is_instance_valid(_ghost):
		return
	var worker := _worker().duplicate()
	if worker.is_empty():
		cancel()
		return
	worker.pos = _pointer + _grab_offset
	worker.walking = false
	worker.phase = "idle"
	var error := _target_error()
	if not error.is_empty():
		worker.task_label = _error_text(error)
	elif target.get("kind", "") == "post":
		worker.task_label = "坐班：" + POST_NAMES[target.post]
	else:
		worker.task_label = "流动：松手解除坐班"
	_ghost.display(worker, _view.sim.elapsed)


func _process(_delta: float) -> void:
	if dragging:
		_update_ghost()


func _target_error() -> String:
	if target.get("kind", "invalid") == "invalid":
		return target.get("reason", "blocked_ground")
	if target.kind == "post":
		for worker in _view.sim.workers:
			if int(worker.id) != worker_id and worker.get("post", "") == target.post:
				return "occupied_post"
	return ""


func _release(screen: Vector2) -> void:
	if worker_id == -1:
		return
	if not dragging:
		cancel()
		return
	_pointer = _world(screen)
	target = Layout.drop_target(_pointer)
	var error := _target_error()
	if error.is_empty():
		error = _view.sim.assign_post(worker_id, target.post, target.point)
	if error.is_empty():
		var worker := _worker()
		var pending: bool = worker.get("assignment_pending", false)
		var message: String = "已恢复流动" if target.kind == "mobile" else "已安排到" + POST_NAMES[target.post] + "坐班"
		if pending:
			message += "，完成交接后前往"
		_view._show_toast(message)
	else:
		_view._show_toast(_error_text(error))
	cancel()
	_view._refresh(0.0)
	get_viewport().set_input_as_handled()


func cancel() -> void:
	if is_instance_valid(_view) and _source_card >= 0 and _source_card < _view._staff_cards.size():
		_view._staff_cards[_source_card].disabled = false
	_source_card = -1
	if is_instance_valid(_view) and _view._actors.has(worker_id):
		_view._actors[worker_id].visible = true
	if is_instance_valid(_ghost):
		_ghost.free()
	_ghost = null
	worker_id = -1
	_touch_index = -1
	dragging = false
	target = {}
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and (worker_id != -1 or _touch_index != -1):
		cancel()


func _worker() -> Dictionary:
	for worker in _view.sim.workers:
		if int(worker.id) == worker_id:
			return worker
	return {}


func _world(screen: Vector2) -> Vector2:
	return _view.get_node("Canvas").get_global_transform_with_canvas().affine_inverse() * screen


func _error_text(error: String) -> String:
	return {
		"automatic_station": "自动机器无需坐班", "invalid_post": "请拖到人工工位",
		"occupied_post": "岗位已有坐班员工", "blocked_ground": "这里不能站立",
		"unreachable": "这个位置无法到达", "invalid_worker": "员工不存在",
	}.get(error, "拖放位置无效")


func _draw() -> void:
	if not dragging:
		return
	for post in Layout.POST_RECTS:
		var occupied := false
		for worker in _view.sim.workers:
			occupied = occupied or (int(worker.id) != worker_id and worker.get("post", "") == post)
		var color := Color("c96e59") if occupied else Color("92b76b")
		draw_rect(Layout.POST_RECTS[post], Color(color, 0.18))
		draw_rect(Layout.POST_RECTS[post], color, false, 4)
		draw_circle(Layout.POST_POINTS[post], 25, Color(color, 0.4))
	var valid := _target_error().is_empty()
	draw_circle(_pointer, 18, Color(0.37, 0.7, 0.3, 0.5) if valid else Color(0.85, 0.25, 0.2, 0.5))
