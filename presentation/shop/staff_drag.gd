extends Node2D
## 拖员工换岗位（通用）：落点规则读场景锚点 Anchors/Drops（按顺序判断的矩形：meta post = 落到哪个岗位、
## point = 站在哪、invalid = 不能放的原因、show = 拖的时候画出来）；放得下放不下由规则层 command_status 说了算。

const CommandResult := preload("res://game/rules/rule_command_result.gd")
const Actor := preload("res://presentation/shop/shop_actor.gd")
const ERROR_TEXTS := {
	"automatic_station": "自动机器无需坐班", "invalid_post": "请拖到人工工位",
	"occupied_post": "岗位已有坐班员工", "blocked_ground": "这里不能站立",
	"unreachable": "这个位置无法到达", "invalid_worker": "员工不存在",
	"ui_overlay": "请放到店内工位或空地",
}
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
	if not is_instance_valid(_view) or _view.rules == null or not _view.rules.shop.staff.can_drag:
		return
	# 压暗的引导只让指着的那个按钮通过，不能拖人
	if _view.guide != null and _view.guide.freezes():
		if worker_id != -1 or _source_card >= 0: cancel()
		return
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and worker_id != -1:
		cancel()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if _touch_index != -1: return
		if event.pressed: _press_body(event.position)
		else: _release(event.position)
	elif event is InputEventMouseMotion and worker_id != -1:
		if _touch_index == -1 and event.button_mask & MOUSE_BUTTON_MASK_LEFT: _motion(event.position)
	elif event is InputEventScreenTouch:
		if event.pressed:
			if _touch_index != -1 or worker_id != -1:
				get_viewport().set_input_as_handled()
				return
			_touch_index = event.index
			_press_body(event.position)
		else:
			if event.index != _touch_index: return
			if event.canceled:
				cancel()
				get_viewport().set_input_as_handled()
			else:
				_release(event.position)
				_touch_index = -1
	elif event is InputEventScreenDrag and worker_id != -1 and event.index == _touch_index:
		_motion(event.position)


func _press_body(screen: Vector2) -> void:
	if worker_id != -1: return
	for i in _view._staff_cards.size():
		var card: Button = _view._staff_cards[i]
		if _view.ui.card_hit_test(card, screen):
			_candidate(int(card.get_meta("worker_id", -1)), screen, true)
			return
	if _view.ui.blocks_world(screen) or _view.tuning_covers(screen): return
	var point := _world(screen)
	var band: Vector2 = _view.anchors.meta("Drops", "grab_band", Vector2(-INF, INF))
	if point.y < band.x or point.y >= band.y: return
	var found := -1
	var depth := -INF
	for worker in _view.view.deployed_snapshot():
		if Rect2(worker.pos + Vector2(-50, -130), Vector2(100, 145)).has_point(point) and worker.pos.y >= depth:
			found = int(worker.id)
			depth = worker.pos.y
	if found != -1: _candidate(found, screen, false)


func _candidate(id: int, screen: Vector2, from_card: bool) -> void:
	worker_id = id
	_press = screen
	_pointer = _world(screen)
	_view.select_worker(id, from_card)
	var worker := _worker()
	_grab_offset = Vector2(0, 60) if from_card else worker.pos - _pointer


func _motion(screen: Vector2) -> void:
	if not dragging and screen.distance_to(_press) < 8: return
	if not dragging: _start_drag()
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
	_ghost = _view._actor(String(worker.kind))
	_ghost.selected = true
	_ghost.modulate.a = 0.78
	add_child(_ghost)
	for i in _view._staff_cards.size():
		if int(_view._staff_cards[i].get_meta("worker_id", -1)) == worker_id:
			_source_card = i
			# 先清掉按钮按住的状态，松手被拖拽吃掉也不会卡住
			_view._staff_cards[i].disabled = true
	if _view._actors.has(worker_id): _view._actors[worker_id].visible = false
	_view.ui.begin_staff_drag()


func _update_ghost() -> void:
	if not dragging or not is_instance_valid(_ghost): return
	var worker := _worker().duplicate()
	if worker.is_empty():
		cancel()
		return
	worker.pos = _pointer + _grab_offset
	worker.walking = false
	worker.phase = "idle"
	worker.job = {}
	var status := _target_status()
	# 预览真正落脚的位置（包括吸到工位上）
	if CommandResult.is_ok(status): worker.pos = target.point
	worker.task_label = _status_text(status) if not CommandResult.is_ok(status) else _view.view.text("drop_" + String(target.get("post", "")), {},
		"坐班" + _view.view.station_name(String(target.post)) if not String(target.get("post", "")).is_empty() else "恢复流动")
	_ghost.task_text = func(w: Dictionary) -> String: return String(w.task_label)
	_ghost.display(worker, _view.rules.clock)
	# 松手会怎样也写在顶上，手指挡不住
	var hint: String = ("松手：" + worker.task_label) if CommandResult.is_ok(status) else worker.task_label
	if hint != _hint:
		_hint = hint
		_view._show_toast(hint)


func _process(_delta: float) -> void:
	if dragging: _update_ghost()


func _target_status() -> Dictionary:
	if target.get("kind", "invalid") == "invalid":
		return CommandResult.failure(CommandResult.UI_DROP_REJECTED, {"reason": target.get("reason", "blocked_ground")})
	var post: String = target.get("post", "")
	var rules: ShopRules = _view.rules
	if not post.is_empty():
		if not rules.station_unlocked(post): return CommandResult.failure(CommandResult.STATION_REQUIRED, {"station": post})
		if rules.post_owner(post, worker_id) != -1:
			if post == rules.counter_id: return CommandResult.failure(CommandResult.FRONT_FULL, {"count": rules.front_slots(), "ui_hint": "front_full"})
			return CommandResult.failure(CommandResult.POST_OCCUPIED)
	return rules.command_status("place_worker", {"id": worker_id, "post": post, "point": target.point})


## 按 Drops 的顺序找第一块盖住手指的；都不是就看是不是能站的空地
func _drop_target(screen: Vector2) -> Dictionary:
	if _view.ui.blocks_world(screen) or _view.tuning_covers(screen): return {"kind": "invalid", "reason": "ui_overlay"}
	var point := _world(screen)
	var anchors: ShopAnchors = _view.anchors
	var rules: ShopRules = _view.rules
	for name in _drop_names():
		var path := "Drops/" + name
		var post := String(anchors.meta(path, "post", ""))
		var stand: Vector2 = anchors.meta(path, "point", _view.view.post_point(post))
		var near: bool = anchors.meta(path, "point", null) != null and point.distance_to(stand) < 30
		if not anchors.rect(path).has_point(point) and not near: continue
		var reason := String(anchors.meta(path, "invalid", ""))
		if not reason.is_empty(): return {"kind": "invalid", "reason": reason}
		return {"kind": "post", "post": post, "point": _view.view.post_point(post)}
	var cell := rules.shop.layout.cell
	var snapped := (Vector2(floorf(point.x / cell), floorf(point.y / cell)) + Vector2(0.5, 0.5)) * cell
	if not _view.view.walkable(snapped, snapped): return {"kind": "invalid", "reason": "blocked_ground"}
	if not _view.view.walkable(snapped, _view.view.navigation_point(rules.counter_id)): return {"kind": "invalid", "reason": "unreachable"}
	return {"kind": "mobile", "post": "", "point": snapped}


func _drop_names() -> Array[String]:
	var names: Array[String] = _view.anchors.children("Drops")
	names.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	return names


func _release(screen: Vector2) -> void:
	if worker_id == -1: return
	if not dragging:
		cancel()
		return
	_pointer = _world(screen)
	target = _drop_target(screen)
	var status := _target_status()
	if CommandResult.is_ok(status): status = _view.execute_command("place_worker", {"id": worker_id, "post": target.post, "point": target.point})
	if CommandResult.is_ok(status):
		var post: String = target.post
		var message: String = _view.view.text("placed_" + post, {}, "已安排到" + _view.view.station_name(post) + "坐班" if not post.is_empty() else "已恢复流动")
		# 玩家怎么排都行；只在没人搬东西的时候提醒一句
		if _view.carrier_warning(): message = _view._t("no_carrier")
		_view._show_toast(message)
		_view.save_now(false)
	else:
		_view._show_toast(_status_text(status))
	cancel()
	_view._refresh(0.0)
	get_viewport().set_input_as_handled()


func cancel() -> void:
	if is_instance_valid(_view) and not _hint.is_empty() and _view._toast.text == _hint: _view._toast_left = 0.0
	_hint = ""
	if is_instance_valid(_view) and _source_card >= 0 and _source_card < _view._staff_cards.size():
		_view._staff_cards[_source_card].disabled = false
	_source_card = -1
	if is_instance_valid(_view) and _view._actors.has(worker_id): _view._actors[worker_id].visible = true
	if is_instance_valid(_ghost): _ghost.free()
	_ghost = null
	worker_id = -1
	_touch_index = -1
	dragging = false
	target = {}
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and (worker_id != -1 or _touch_index != -1): cancel()


func _worker() -> Dictionary:
	return _view.view.worker_snapshot(worker_id)


func _world(screen: Vector2) -> Vector2:
	return _view.get_node("Canvas").get_global_transform_with_canvas().affine_inverse() * screen


func _status_text(status: Dictionary) -> String:
	if status.code == CommandResult.UI_DROP_REJECTED:
		return ERROR_TEXTS.get(status.params.reason, "拖放位置无效")
	if status.code == CommandResult.FRONT_FULL and status.params.get("ui_hint") == "front_full":
		return _view.view.text("front_full", status.params, "前台最多 {count} 位，前台升级可以加前台位")
	if status.code == CommandResult.POST_OCCUPIED: return ERROR_TEXTS.occupied_post
	return _view.view.command_message(status)


func _draw() -> void:
	if not dragging: return
	var anchors: ShopAnchors = _view.anchors
	var rules: ShopRules = _view.rules
	for name in _drop_names():
		var path := "Drops/" + name
		if not anchors.meta(path, "show", false): continue
		var post := String(anchors.meta(path, "post", ""))
		var occupied := not rules.station_unlocked(post) or rules.post_owner(post, worker_id) != -1
		var color := Color("c96e59") if occupied else Color("92b76b")
		var rect := anchors.rect(path)
		draw_rect(rect, Color(color, 0.18))
		draw_rect(rect, color, false, 4)
		draw_circle(anchors.meta(path, "point", rect.get_center()), 25, Color(color, 0.4))
	var valid := CommandResult.is_ok(_target_status())
	draw_circle(_pointer, 18, Color(0.37, 0.7, 0.3, 0.5) if valid else Color(0.85, 0.25, 0.2, 0.5))
