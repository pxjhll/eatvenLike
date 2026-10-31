extends Node2D
## Valid release directly places an employee; simulation returns interrupted cargo.

const Layout := preload("res://content/tea/art_playtest_layout.gd")
const Actor := preload("res://presentation/tea_playtest/staff_actor.gd")
const POST_NAMES := {"boil": "煮茶台", "topping": "加料台", "counter": "前台"}
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
var _hint := ""


func setup(view: Node2D) -> void:
	_view = view
	z_index = 80


func _input(event: InputEvent) -> void:
	if not is_instance_valid(_view) or _view.sim == null:
		return
	# A dimmed tutorial step only lets its highlighted control through, so no staff drags.
	if _view.guide != null and _view.guide.freezes():
		if worker_id != -1 or _source_card >= 0:
			cancel()
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
	for i in _view._staff_cards.size():
		var card: Button = _view._staff_cards[i]
		if _view.ui.card_hit_test(card, screen):
			_candidate(int(card.get_meta("worker_id", -1)), screen, true)
			return
	if _view.ui.blocks_world(screen):
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
	_view.select_worker(id, from_card)
	var worker := _worker()
	_grab_offset = Vector2(0, 60) if from_card else worker.pos - _pointer


func _motion(screen: Vector2) -> void:
	if not dragging and screen.distance_to(_press) < 8:
		return
	if not dragging:
		_start_drag()
	_pointer = _world(screen)
	target = _drop_target(screen)
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
	for i in _view._staff_cards.size():
		if int(_view._staff_cards[i].get_meta("worker_id", -1)) == worker_id:
			_source_card = i
			# Clear the button's held-down GUI state before release is consumed by drag.
			_view._staff_cards[i].disabled = true
	if _view._actors.has(worker_id):
		_view._actors[worker_id].visible = false
	_view.ui.begin_staff_drag()


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
	if error.is_empty():
		# Preview the actual landing position, including the workstation snap point.
		worker.pos = target.point
	if not error.is_empty():
		worker.task_label = _error_text(error)
	elif target.get("kind", "") == "post":
		worker.task_label = "前台接单" if target.post == "counter" else "坐班" + POST_NAMES[target.post]
	else:
		worker.task_label = "恢复流动"
	_ghost.display(worker, _view.sim.elapsed)
	# The release outcome is also spelled out at the top, where the finger does not cover it.
	var hint: String = ("松手：" + worker.task_label) if error.is_empty() else worker.task_label
	if hint != _hint:
		_hint = hint
		_view._show_toast(hint)


func _process(_delta: float) -> void:
	if dragging:
		_update_ghost()


func _target_error() -> String:
	if target.get("kind", "invalid") == "invalid":
		return target.get("reason", "blocked_ground")
	if target.kind == "post":
		if _view.sim.has_method("station_unlocked") and not _view.sim.station_unlocked(target.post):
			return "请先解锁设备"
		if _post_taken(target.post):
			if target.post == "counter" and _view.sim.has_method("front_slots"):
				return "前台最多 %d 位，前台升级可以加前台位" % _view.sim.front_slots()
			return "occupied_post"
	return ""


## The counter can hold several front staff in the tea shop; ask the sim when it can.
func _post_taken(post: String) -> bool:
	if _view.sim.has_method("front_slots"):
		return _view.sim.post_owner(post, worker_id) != -1
	for worker in _view.sim.workers:
		if int(worker.id) != worker_id and worker.get("post", "") == post:
			return true
	return false


func _drop_target(screen: Vector2) -> Dictionary:
	if _view.ui.blocks_world(screen):
		return {"kind": "invalid", "reason": "ui_overlay"}
	return Layout.drop_target(_world(screen))


func _release(screen: Vector2) -> void:
	if worker_id == -1:
		return
	if not dragging:
		cancel()
		return
	_pointer = _world(screen)
	target = _drop_target(screen)
	var error := _target_error()
	if error.is_empty():
		if _view.sim.has_method("deploy_at"):
			error = _view.sim.deploy_at(worker_id, target.post, target.point)
		else:
			error = _view.sim.assign_post(worker_id, target.post, target.point)
	if error.is_empty():
		var message: String = ("已安排到后厨" if _view.sim.has_method("front_slots") else "已恢复流动") if target.kind == "mobile" else "已安排到" + POST_NAMES[target.post] + "坐班"
		if target.get("post", "") == "counter":
			message = "已安排到前台：只负责接待客人、取杯上菜。"
		_view._show_toast(message)
		_view.save_now(false)
	else:
		_view._show_toast(_error_text(error))
	cancel()
	_view._refresh(0.0)
	get_viewport().set_input_as_handled()


func cancel() -> void:
	if is_instance_valid(_view) and not _hint.is_empty() and _view._toast.text == _hint:
		_view._toast_left = 0.0
	_hint = ""
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
	for worker in _view.all_staff():
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
		"ui_overlay": "请放到店内工位或空地",
	}.get(error, "拖放位置无效" if "_" in error else error)


func _draw() -> void:
	if not dragging:
		return
	for post in Layout.POST_RECTS:
		var occupied := false
		if _view.sim.has_method("station_unlocked") and not _view.sim.station_unlocked(post):
			occupied = true
		occupied = occupied or _post_taken(post)
		var color := Color("c96e59") if occupied else Color("92b76b")
		draw_rect(Layout.POST_RECTS[post], Color(color, 0.18))
		draw_rect(Layout.POST_RECTS[post], color, false, 4)
		draw_circle(Layout.POST_POINTS[post], 25, Color(color, 0.4))
	var valid := _target_error().is_empty()
	draw_circle(_pointer, 18, Color(0.37, 0.7, 0.3, 0.5) if valid else Color(0.85, 0.25, 0.2, 0.5))
