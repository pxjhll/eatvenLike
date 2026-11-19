extends Control
## 通用引导播放器（规格 §6.3）：步骤全在店铺数据 shop.guide 里（SpecGuideStep），这里只会
## 判断条件、指向目标、压暗挖洞、画手指和气泡；卡片型步骤交给 HUD 的弹卡队列。
## 每帧从规则层和界面现状重新判断，关掉面板、读档都能接着在对的地方提示，不存“走到第几步”。

const DIM := Color(0.16, 0.1, 0.06, 0.62)
const GLOW := Color("ffd98a")
const HAND := Color("8b6446")
const BUBBLE_WIDTH := 644.0
const BUBBLE_TEXT_MIN_WIDTH := 400.0
const GUIDE_PORTRAIT_SLOT_SIZE := Vector2(174, 146)
const COMPACT_PORTRAIT_SLOT_SIZE := Vector2(154, 124)

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
var _bubble_column: VBoxContainer
var _bubble_row: HBoxContainer
var _bubble_text: Label
var _dialogue_slot: Control
var _dialogue_portrait: TextureRect
var _dialogue_heading: Label
var _dialogue_title := ""
var _dialogue_visible := false
var _compact_portrait := false
var _pointer_bounds := Rect2()
var _announcement_title := ""
var _announcement := ""
var _announcement_portrait: Texture2D
var _announcement_left := 0.0
var _bubble_skip: Button
var _skip_touch := -1
var _show_bubble := false
var _show_notice := false
var _notice_elapsed := {}
var _eligible_since := {}


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
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("fff5e1bd")
	paper.border_color = Color("d7a473de")
	paper.shadow_color = Color("3d261735")
	paper.shadow_size = 5
	paper.shadow_offset = Vector2(0, 4)
	paper.set_corner_radius_all(24)
	paper.set_border_width_all(2)
	paper.content_margin_left = 16
	paper.content_margin_right = 16
	paper.content_margin_top = 9
	paper.content_margin_bottom = 9
	_bubble.add_theme_stylebox_override("panel", paper)
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.custom_minimum_size.x = BUBBLE_WIDTH
	add_child(_bubble)
	_bubble_column = VBoxContainer.new()
	_bubble_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_column.add_theme_constant_override("separation", 8)
	_bubble.add_child(_bubble_column)
	_bubble_row = HBoxContainer.new()
	_bubble_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_row.add_theme_constant_override("separation", 12)
	_bubble_column.add_child(_bubble_row)
	_dialogue_slot = Control.new()
	_dialogue_slot.custom_minimum_size = GUIDE_PORTRAIT_SLOT_SIZE
	_dialogue_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_slot.hide()
	_bubble_row.add_child(_dialogue_slot)
	_dialogue_portrait = TextureRect.new()
	_dialogue_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_dialogue_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_dialogue_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_slot.add_child(_dialogue_portrait)
	_dialogue_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_theme_constant_override("separation", 4)
	_bubble_row.add_child(copy)
	_dialogue_heading = _hud._text(copy, "", 30)
	_dialogue_heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	_dialogue_heading.hide()
	_bubble_text = _hud._text(copy, "", 23)
	_bubble_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_bubble_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bubble_text.custom_minimum_size.x = BUBBLE_TEXT_MIN_WIDTH
	_bubble_skip = Button.new()
	_bubble_skip.focus_mode = Control.FOCUS_NONE
	_bubble_skip.add_theme_font_size_override("font_size", 18)
	_bubble_skip.size_flags_horizontal = Control.SIZE_SHRINK_END
	_bubble_skip.size_flags_vertical = Control.SIZE_SHRINK_END
	_bubble_skip.pressed.connect(_skip)
	_bubble_column.add_child(_bubble_skip)
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
	_announcement_left = 0.0
	_announcement_portrait = null
	_eligible_since.clear()
	_skip_touch = -1
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
	_show_bubble = false
	_show_notice = false
	_dialogue_visible = false
	_compact_portrait = false
	_dialogue_title = ""
	_pointer_bounds = Rect2()
	if enabled:
		_pick()
		if not active.is_empty(): _play(_step(), delta)
	visible = enabled and not active.is_empty() and _step() != null and _step().style != "card"
	if _announcement_left > 0.0 and _announcement_space_available():
		_render_announcement()
		_announcement_left = maxf(0.0, _announcement_left - delta)
	else:
		_bubble.visible = _show_bubble and visible
	_sync_dialogue()
	_place_bubble()
	queue_redraw()


func can_show_announcement() -> bool:
	return _announcement_left <= 0.0 and _announcement_space_available()


func _announcement_space_available() -> bool:
	return active.is_empty() and _hud.page == "shop" and not _hud.popups.has_card()


func show_announcement(title: String, text: String, seconds: float, portrait: Texture2D = null) -> void:
	_announcement_title = title
	_announcement = text
	_announcement_portrait = portrait
	_announcement_left = seconds
	_render_announcement()
	_sync_dialogue()
	_place_bubble()


func _render_announcement() -> void:
	_dialogue_title = _announcement_title
	_dialogue_visible = _announcement_portrait != null
	_compact_portrait = false
	if _dialogue_visible: _dialogue_portrait.texture = _announcement_portrait
	_show_notice = true
	_say(_announcement)
	_bubble_skip.hide()
	visible = true
	_bubble.show()


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
		if step.shop_page_only and _hud.page != "shop":
			_eligible_since.clear()
			return
		if step.trigger == "angry" and not _angry_pending: continue
		var delayed := step.when_seconds > 0.0
		if (delayed and not can_show_announcement()) or not _all(step.when, step):
			if delayed: _eligible_since.erase(step.id)
			continue
		if delayed:
			var clock: float = _view.rules.clock
			var since: float = _eligible_since.get_or_add(step.id, clock)
			if clock - since + 0.000001 < step.when_seconds: continue
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
	_eligible_since.clear()
	_notice_elapsed.clear()
	_staff_at_start = _view.view.deployed_count()
	var step := _step()
	if step.style == "card":
		_hud.open_page("shop")
		_push_card(step)


# ---------- 播放 ----------

func _play(step: SpecGuideStep, delta: float) -> void:
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
	for index in step.cues.size():
		var cue := step.cues[index]
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
		if cue.has("notice_seconds"):
			var finish_after_notice: bool = cue.get("finish_after_notice", false)
			var dialogue := step.portrait != null and cue.has("heading")
			_bubble_skip.visible = not finish_after_notice and not dialogue
			if (finish_after_notice or dialogue) and (_hud.page != "shop" or _hud.popups.has_card()): return
			var elapsed: float = _notice_elapsed.get(index, 0.0)
			if elapsed < float(cue.notice_seconds):
				_show_notice = true
				_say(text)
				_set_dialogue(step, cue)
				if cue.has("at"):
					_pointer_bounds = _target_rect(_fill(String(cue.at), step))
					if _pointer_bounds.has_area(): _point = _pointer_bounds.get_center()
				_notice_elapsed[index] = elapsed + delta
			elif finish_after_notice:
				_finish()
			return
		_bubble_skip.show()
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
		_set_dialogue(step, cue)
		return


func _set_dialogue(step: SpecGuideStep, cue: Dictionary) -> void:
	if not cue.has("heading"): return
	_dialogue_title = _fill(String(cue.heading), step)
	_dialogue_visible = step.portrait != null
	_compact_portrait = _dialogue_visible and cue.get("compact_portrait", false)
	if _dialogue_visible: _dialogue_portrait.texture = step.portrait


func _sync_dialogue() -> void:
	if _dialogue_heading.text != _dialogue_title: _dialogue_heading.text = _dialogue_title
	_dialogue_heading.visible = not _dialogue_title.is_empty()
	var skip_parent: Container = _bubble_row if _compact_portrait else _bubble_column
	if _bubble_skip.get_parent() != skip_parent:
		_bubble_skip.reparent(skip_parent, false)
		_dialogue_slot.custom_minimum_size = COMPACT_PORTRAIT_SLOT_SIZE if _compact_portrait else GUIDE_PORTRAIT_SLOT_SIZE
		_bubble_text.custom_minimum_size.x = 0.0 if _compact_portrait else BUBBLE_TEXT_MIN_WIDTH
	if _dialogue_slot.visible == _dialogue_visible: return
	_dialogue_slot.visible = _dialogue_visible
	_bubble_text.autowrap_mode = TextServer.AUTOWRAP_OFF if _dialogue_visible else TextServer.AUTOWRAP_WORD_SMART


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
		"buttons": buttons, "speaker": step.speaker, "portrait": step.portrait,
		"portrait_right": step.portrait_right, "subtitle": _fill(step.subtitle, step)})


func _stat_value(key: String) -> String:
	var rules: ShopRules = _view.rules
	match key:
		"time":
			var seconds := int(rules.completed_at if rules.completed_at >= 0.0 else rules.clock)
			return "%d 分 %02d 秒" % [seconds / 60, seconds % 60]
		"revenue": return "%d 金币" % int(rules.revenue)
	return key


func _confirm() -> void:
	var step := _step()
	if step == null: return
	_finish()
	refresh(0.0)
	if step.confirm_action == "leave": _view.open_summary()


func _skip() -> void:
	var step := _step()
	if step == null: return
	_hud.popups.remove("guide:" + step.id)
	seen[step.id] = true
	for id in step.skip_marks: seen[id] = true
	if step.skip_tutorial:
		for tutorial_step in _order:
			if not tutorial_step.when.has("complete"): seen[tutorial_step.id] = true
	active = ""
	_view.request_save()
	refresh(0.0)


func _finish() -> void:
	var step := _step()
	if step != null:
		seen[step.id] = true
		for id in step.finish_marks: seen[id] = true
	active = ""
	if step != null and not step.next.is_empty() and not seen.has(step.next):
		_start(step.next)
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
		"can_send_flyers": return rules.shop.flyer != null and rules.command_status("send_flyers").code == "ok"
		"idle_staff":
			for worker in rules.workers:
				if rules.worker_idle(worker): return true
			return false
		"affordable": return rules.command_status("unlock", {"id": arg}).code == "ok"
		"box": return rules.pending_box() == arg
		"box_affordable": return not rules.pending_box().is_empty() and rules.command_status("unlock_box", {"material": rules.pending_box()}).code == "ok"
		"processing": return view.has_order_requiring_processing(arg)
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
		"sold": return rules.sold
		"customers": return rules.waiting_customers().size()
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
	_show_bubble = true


func _place_bubble() -> void:
	if not _bubble.visible:
		return
	_bubble.reset_size()
	if _show_notice or _dialogue_visible:
		var header := _control_rect(_hud.get_node("Header"))
		var y := header.end.y + 12.0
		if _dialogue_visible: y += 22.0 if _show_notice else 84.0
		_bubble.position = Vector2((size.x - _bubble.size.x) * 0.5, y)
		return
	var anchor := _point if _point != Vector2.INF else size / 2.0
	var target := _hole if _hole.has_area() else Rect2(anchor, Vector2.ZERO)
	var below := anchor.y < size.y * 0.5
	var y := target.end.y + 120.0 if below else target.position.y - 120.0 - _bubble.size.y
	_bubble.position = Vector2(clampf(anchor.x - _bubble.size.x / 2.0, 16, size.x - _bubble.size.x - 16), clampf(y, 120, size.y - _bubble.size.y - 16))


## 真触屏也能按气泡按钮，无需依赖系统模拟的鼠标事件。
func _input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch == null or _bubble_skip == null: return
	if not _bubble_skip.is_visible_in_tree() or _hud.popups.has_card():
		_skip_touch = -1
		return
	var local := _bubble_skip.get_global_transform_with_canvas().affine_inverse() * touch.position
	var on_button := Rect2(Vector2.ZERO, _bubble_skip.size).has_point(local)
	if touch.pressed and on_button and _skip_touch < 0:
		_skip_touch = touch.index
		get_viewport().set_input_as_handled()
	elif not touch.pressed and touch.index == _skip_touch:
		_skip_touch = -1
		get_viewport().set_input_as_handled()
		if on_button and not touch.canceled: _skip()


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
	if _dialogue_visible:
		_draw_dialogue_arrow()
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


func _draw_dialogue_arrow() -> void:
	var target := _hole if _blocking else _pointer_bounds.grow(6)
	if not _blocking: draw_rect(target, GLOW, false, 4.0)
	var from_below := target.position.y < _bubble.position.y + _bubble.size.y + 65.0
	var direction := -1.0 if from_below else 1.0
	var edge := target.end.y if from_below else target.position.y
	var tip := Vector2(target.get_center().x, edge - direction * 9.0)
	var base := tip - Vector2(0, direction * 25.0)
	var top := tip - Vector2(0, direction * 50.0)
	var points := PackedVector2Array([tip, base + Vector2(-24, 0), base + Vector2(-10, 0),
		top + Vector2(-10, 0), top + Vector2(10, 0), base + Vector2(10, 0), base + Vector2(24, 0)])
	draw_colored_polygon(points, Color("e44436"))
	points.append(tip)
	draw_polyline(points, Color("2a1714"), 5.0, true)
