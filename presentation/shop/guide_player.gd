extends Control
## 通用引导播放器（规格 §6.3）：步骤全在店铺数据 shop.guide 里（SpecGuideStep），这里只会
## 判断条件、指向目标、压暗挖洞、画手指和气泡；卡片型步骤交给 HUD 的弹卡队列。
## 每帧从规则层和界面现状重新判断，关掉面板、读档都能接着在对的地方提示，不存“走到第几步”。

const ReferenceTheme := preload("res://presentation/ui/reference_theme.gd")
const DIM := Color(0.16, 0.1, 0.06, 0.62)
const GLOW := Color("ffd98a")
const HAND := Color("8b6446")

var enabled := false
var seen := {}
## 正在播的步骤 id（空 = 没有）
var active := ""
var _steps := {}
var _order: Array[SpecGuideStep] = []
var _view: Node2D
var _hud: Control
var _blocking := false
var _hole := Rect2()
var _point := Vector2.INF
var _time := 0.0
## 有客人等急了：等能提示的时候（店铺页、没有别的引导）再说一次
var _angry_pending := false
## 一人跟单的店客人等急了会走：记下看过的流失人数，多出来就算“等急了”（-1 = 还没开始记）
var _lost_seen := -1
## 步骤开始时店里有几个人（hired 条件用）
var _staff_at_start := 0
var _bubble: PanelContainer
var _bubble_text: Label
var _bubble_skip: Button


func setup(view: Node2D, seen_ids: Array) -> void:
	_view = view
	_hud = view.ui
	theme = _hud.theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for id in seen_ids: seen[String(id)] = true
	for step in view.rules.shop.guide:
		_steps[step.id] = step
		_order.append(step)
	_bubble = PanelContainer.new()
	_bubble.add_theme_stylebox_override("panel", ReferenceTheme.style("paper", 20))
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.custom_minimum_size.x = 440
	add_child(_bubble)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_bubble.add_child(column)
	_bubble_text = _hud._text(column, "", 23)
	_bubble_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble_text.custom_minimum_size.x = 400
	_bubble_skip = Button.new()
	_bubble_skip.focus_mode = Control.FOCUS_NONE
	_bubble_skip.add_theme_font_size_override("font_size", 18)
	_bubble_skip.size_flags_horizontal = Control.SIZE_SHRINK_END
	_bubble_skip.pressed.connect(_skip)
	column.add_child(_bubble_skip)
	refresh(0.0)


## 压暗的提示和卡片都让店停下，免得看字的时候错过什么
func freezes() -> bool:
	return enabled and (_blocking or (not active.is_empty() and _step().style == "card"))


func seen_list() -> Array:
	return seen.keys()


## Keep seen steps and playback preference; the next refresh selects from fresh rules.
func restart() -> void:
	active = ""
	_blocking = false
	_hole = Rect2()
	_point = Vector2.INF
	_time = 0.0
	_angry_pending = false
	_lost_seen = -1
	_staff_at_start = 0
	visible = false
	if _bubble != null: _bubble.hide()
	queue_redraw()


func _step() -> SpecGuideStep:
	return _steps.get(active)


func refresh(delta: float) -> void:
	_time += delta
	_blocking = false
	_hole = Rect2()
	_point = Vector2.INF
	_bubble.visible = false
	if enabled:
		_pick()
		if not active.is_empty(): _play(_step())
	visible = enabled and not active.is_empty() and _step() != null and _step().style != "card"
	_place_bubble()
	queue_redraw()


# ---------- 选步骤 ----------

func _pick() -> void:
	# 开场那几步看完以后，客人等急了才记下来
	_angry_pending = (_angry_pending or _any_angry()) and _opening_done()
	if not active.is_empty(): return
	for step in _order:
		if seen.has(step.id) or step.trigger == "next": continue
		if _any(step.seen_when, step):
			seen[step.id] = true
			continue
		if step.shop_page_only and _hud.page != "shop": return
		if step.trigger == "angry" and not _angry_pending: continue
		if not _all(step.when, step): continue
		if step.trigger == "angry": _angry_pending = false
		_start(step.id)
		return
	# 走到最后也没有要提示的：这次等急就算过去了
	_angry_pending = false


func _opening_done() -> bool:
	for step in _order:
		if not step.shop_page_only and step.trigger != "next" and not seen.has(step.id): return false
	return true


func _start(id: String) -> void:
	active = id
	_staff_at_start = _view.view.deployed_count()
	var step := _step()
	if step.style == "card":
		_hud.open_page("shop")
		_push_card(step)


# ---------- 播放 ----------

func _play(step: SpecGuideStep) -> void:
	if step == null:
		active = ""
		return
	if step.style == "card":
		if not _hud.popups.has_card("guide:" + step.id): _push_card(step)
		return
	if _any(step.done_when, step):
		_finish()
		return
	_bubble_skip.text = step.skip_label
	for cue in step.cues:
		if not _all(cue.get("if", []), step): continue
		if cue.get("back", false):
			active = ""
			return
		if cue.has("then"):
			active = ""
			_start(String(cue.then))
			return
		if cue.has("go"):
			_hud.open_page(String(cue.go))
			return
		if cue.get("wait", false): return
		if cue.get("select_waiting", false) and _hud.page == "staff":
			var waiting := _waiting()
			if not waiting.is_empty() and _view.staff_is_deployed(_view.selected_worker):
				_view.select_worker(int(waiting[0].id), true)
		var text := _fill(String(cue.get("text", "")), step)
		var target := String(cue.get("at", ""))
		var at := _fill(target, step)
		if target == "station:{slow_id}":
			var id := at.trim_prefix("station:")
			var rules: ShopRules = _view.rules
			if not rules.station_unlocked(id) or rules.upgrade_cost(id) < 0 or not _target_rect(at).has_area():
				_say("有客人等急了！可以看看哪些设备还能升级。")
				return
		if cue.get("pause", true): _aim(at, text)
		else:
			var rect := _target_rect(at)
			if rect.has_area(): _point = rect.get_center()
			_say(text)
		return


func _push_card(step: SpecGuideStep) -> void:
	var buttons: Array = []
	if step.confirm_action == "leave" and not _view.can_leave():
		buttons.append({"label": step.cancel_label if not step.cancel_label.is_empty() else step.confirm_label, "primary": true, "action": _skip})
	else:
		if not step.cancel_label.is_empty(): buttons.append({"label": step.cancel_label, "action": _skip})
		buttons.append({"label": step.confirm_label, "primary": true, "action": _confirm})
	var stats: Array = []
	for row in step.stats: stats.append([row[0], row[1], _stat_value(String(row[2]))])
	_hud.popups.push({"id": "guide:" + step.id, "title": _fill(step.title, step), "title_size": step.title_size,
		"art": step.art, "medal": step.medal, "rows": step.rows, "stats": stats, "note": _fill(step.text, step),
		"buttons": buttons, "speaker": step.speaker})


func _stat_value(key: String) -> String:
	var rules: ShopRules = _view.rules
	match key:
		"time": return "%d 分 %02d 秒" % [int(rules.clock) / 60, int(rules.clock) % 60]
		"revenue": return "%d 金" % int(rules.revenue)
	return key


func _confirm() -> void:
	var step := _step()
	if step == null: return
	if not step.next.is_empty():
		seen[step.id] = true
		active = ""
		_start(step.next)
	else:
		_finish()
	refresh(0.0)
	if step.confirm_action == "leave": _view.open_summary()


func _skip() -> void:
	var step := _step()
	if step == null: return
	_hud.popups.remove("guide:" + step.id)
	seen[step.id] = true
	for id in step.skip_marks: seen[id] = true
	active = ""
	_view.request_save()
	refresh(0.0)


func _finish() -> void:
	var step := _step()
	if step != null:
		seen[step.id] = true
		for id in step.finish_marks: seen[id] = true
	active = ""
	_view.request_save()


# ---------- 条件 ----------

func _all(conditions: Array, step: SpecGuideStep) -> bool:
	for c in conditions:
		if not _holds(_fill(String(c), step)): return false
	return true


func _any(conditions: Array, step: SpecGuideStep) -> bool:
	for c in conditions:
		if _holds(_fill(String(c), step)): return true
	return false


func _holds(condition: String) -> bool:
	if "&" in condition:
		for part in condition.split("&"):
			if not _holds(part.strip_edges()): return false
		return true
	if condition.begins_with("!"): return not _holds(condition.substr(1))
	var rules: ShopRules = _view.rules
	var view: ShopView = _view.view
	var arg := condition.get_slice(":", 1) if ":" in condition else ""
	var head := condition.get_slice(":", 0)
	for op in [">=", "<"]:
		if op in condition and not ":" in condition:
			var left := condition.get_slice(op, 0)
			var right := condition.get_slice(op, 1)
			var value := _number(left)
			var limit := _number(right)
			return value >= limit if op == ">=" else value < limit
	match head:
		"open": return rules.is_open()
		"seen": return seen.has(arg)
		"page":
			if arg == "station": return _hud.page == "station" and _hud.page_node("station").station_id == condition.get_slice(":", 2)
			return _hud.page == arg
		"sold": return rules.sold == int(arg)
		"waiting": return not _waiting().is_empty()
		"can_hire": return rules.hire_cost() >= 0 and rules.gold >= rules.hire_cost()
		"can_staff": return not _waiting().is_empty() or (rules.hire_cost() >= 0 and rules.gold >= rules.hire_cost())
		"affordable": return rules.command_status("unlock", {"id": arg}).code == "ok"
		"box": return rules.pending_box() == arg
		"box_affordable": return not rules.pending_box().is_empty() and rules.command_status("unlock_box", {"material": rules.pending_box()}).code == "ok"
		"no_box": return rules.pending_box().is_empty()
		"kitchen_staff": return rules.kitchen_staff() == int(arg)
		"room": return _view.view.deployed_count() < rules.staff_slots()
		"complete": return rules.shop_complete()
		"hired": return _view.view.deployed_count() > _staff_at_start
		"angry": return _angry_cause() == arg
	return false


func _number(name: String) -> float:
	var rules: ShopRules = _view.rules
	match name:
		"staff": return _view.view.deployed_count()
		"opening": return mini(2, rules.staff_slots())
		"stage": return rules.stage_index
		"kitchen_staff": return rules.kitchen_staff()
	return float(name) if name.is_valid_float() else 0.0


func _waiting() -> Array:
	return _view.all_staff().filter(func(worker: Dictionary) -> bool: return not _view.staff_is_deployed(int(worker.id)))


func _any_angry() -> bool:
	var snapshot: Dictionary = _view.view.guide_snapshot()
	if _single():
		var lost: int = snapshot.lost
		var more := _lost_seen >= 0 and lost > _lost_seen
		_lost_seen = lost
		if more: return true
	return snapshot.any_angry


func _angry_cause() -> String:
	return _view.view.guide_snapshot().angry_cause


func _single() -> bool:
	return _view.shop.fulfillment.handoff == "single"


func _slow_machine() -> String:
	return _view.view.guide_snapshot().slow_machine


func _fill(text: String, step: SpecGuideStep) -> String:
	if not "{" in text: return text
	var rules: ShopRules = _view.rules
	var values: Dictionary = step.params.duplicate()
	var next := rules.stage_index + 1
	var stage: int = int(step.params.get("stage", next))
	if stage < rules.shop.stages.size():
		values.line = rules.shop.stages[stage].display_name
		values.cost = rules.shop.stages[stage].cost
	var box := rules.pending_box()
	if not box.is_empty():
		var m := rules.shop.station(rules.supply_id).material(box)
		values.box = m.display_name
		values.machine = _view.view.station_name(m.box_station)
	if "{slow}" in text or "{slow_id}" in text:
		var slow := _slow_machine()
		values.slow = _view.view.station_name(slow)
		values.slow_id = slow
	for k in values: text = text.replace("{%s}" % k, str(values[k]))
	return text


# ---------- 指向 ----------

func _target_rect(at: String) -> Rect2:
	var kind := at.get_slice(":", 0)
	var arg := at.substr(kind.length() + 1)
	match kind:
		"frame":
			var frame: Control = _view._station_buttons.get(arg)
			return _control_rect(frame) if frame != null else Rect2()
		"station", "area":
			var rect: Rect2 = _view.anchors.rect("Stations/%s/Tap" % arg) if kind == "station" else _view.anchors.rect(arg)
			return _world_rect(rect)
		"ui":
			var control: Control = _ui(arg)
			return _control_rect(control) if control != null else Rect2()
	return Rect2()


func _ui(name: String) -> Control:
	if name.begins_with("tab:"): return _hud.tab(name.substr(4))
	if name.begins_with("material:"):
		var station: Control = _hud.page_node("station")
		return station.material_buttons.get(name.substr(9)) if station != null else null
	match name:
		"hire": return _hud.page_node("staff").hire_button
		"deploy": return _hud.page_node("staff").deploy_button
		"unlock": return _hud.page_node("station").unlock_button
		"chip:seats": return _view._seats
	return null


func _aim(at: String, text: String) -> void:
	if at.begins_with("station:") or at.begins_with("area:"):
		var rect: Rect2 = _view.anchors.rect("Stations/%s/Tap" % at.substr(8)) if at.begins_with("station:") else _view.anchors.rect(at.substr(5))
		if rect.has_area():
			if _view.has_method("reveal_world"): _view.reveal_world(rect)
			_hole = _world_rect(rect)
	else:
		var rect := _target_rect(at)
		if rect.has_area(): _hole = rect.grow(8)
	_blocking = _hole.has_area()
	if _blocking: _point = _hole.get_center()
	_say(text)


func _control_rect(target: Control) -> Rect2:
	return _to_local(target.get_global_transform_with_canvas(), Rect2(Vector2.ZERO, target.size))


func _world_rect(rect: Rect2) -> Rect2:
	var canvas: Node2D = _view.get_node("Canvas")
	return _to_local(canvas.get_global_transform_with_canvas(), rect)


func _to_local(screen: Transform2D, rect: Rect2) -> Rect2:
	var inverse := get_global_transform_with_canvas().affine_inverse()
	var a: Vector2 = inverse * (screen * rect.position)
	var b: Vector2 = inverse * (screen * rect.end)
	return Rect2(a, b - a).abs()


func _say(text: String) -> void:
	_bubble_text.text = text
	_bubble.visible = true


func _place_bubble() -> void:
	if not _bubble.visible:
		return
	_bubble.reset_size()
	var anchor := _point if _point != Vector2.INF else size / 2.0
	var target := _hole if _hole.has_area() else Rect2(anchor, Vector2.ZERO)
	var below := anchor.y < size.y * 0.5
	var y := target.end.y + 120.0 if below else target.position.y - 120.0 - _bubble.size.y
	_bubble.position = Vector2(clampf(anchor.x - _bubble.size.x / 2.0, 16, size.x - _bubble.size.x - 16), clampf(y, 120, size.y - _bubble.size.y - 16))


## 压暗的时候只有挖开的洞能点
func _has_point(point: Vector2) -> bool:
	return _blocking and not _hole.has_point(point)


func _draw() -> void:
	if not visible:
		return
	if _blocking:
		var hole := _hole if _hole.has_area() else Rect2(size / 2.0, Vector2.ZERO)
		draw_rect(Rect2(0, 0, size.x, hole.position.y), DIM)
		draw_rect(Rect2(0, hole.end.y, size.x, size.y - hole.end.y), DIM)
		draw_rect(Rect2(0, hole.position.y, hole.position.x, hole.size.y), DIM)
		draw_rect(Rect2(hole.end.x, hole.position.y, size.x - hole.end.x, hole.size.y), DIM)
		if _hole.has_area():
			draw_rect(_hole, GLOW, false, 5.0)
	if _point == Vector2.INF:
		return
	var pulse := fmod(_time, 1.2) / 1.2
	draw_arc(_point, 18.0 + pulse * 30.0, 0, TAU, 40, Color(GLOW, 1.0 - pulse), 5.0)
	var below := _point.y < size.y * 0.5
	var direction := -1.0 if below else 1.0
	var reach := (_hole.size.y / 2.0 if _hole.has_area() else 0.0) + 12.0 + absf(sin(_time * 5.0)) * 14.0
	var tip := _point - Vector2(0, direction * reach)
	var back := tip - Vector2(0, direction * 44)
	draw_colored_polygon(PackedVector2Array([tip, back + Vector2(-24, 0), back + Vector2(24, 0)]), HAND)
	draw_rect(Rect2(back.x - 10, minf(back.y, back.y - direction * 40), 20, 40), HAND)
	draw_polyline(PackedVector2Array([tip, back + Vector2(-24, 0), back + Vector2(24, 0), tip]), Color("fff5e2"), 3.0)
