extends Control
## First-shop tutorial (PXJ-36). Every step is read from the live sim and UI each frame, so
## closing a panel or reloading a save resumes at the right place instead of a stored step.
##
## Opening: welcome card → tap the lemonade sign → unlock → watch the first sale → hire a
## second partner → deploy them → done card. Later, once each: a hint when the next line can
## be bought, and a hint the first time a customer leaves. Dimmed steps freeze the shop.

const STAGE_SIGNS := ["", "boil", "seal", "mix", "topping"]
const COUNTER_AREA := Rect2(410, 850, 120, 110)
const DIM := Color(0.16, 0.1, 0.06, 0.62)
const GLOW := Color("ffd98a")
const HAND := Color("8b6446")

var enabled := false
var seen := {}
## The guide currently on screen: "", "welcome", "opening", "done", "line_N", "box_*", "shop_done" or "lost".
var active := ""
var _view: Node2D
var _hud: Control
var _blocking := false
var _hole := Rect2()
var _point := Vector2.INF
var _time := 0.0
var _seen_event: Variant = null
## A walk-out waits here until its hint can show (shop page, no other guide up).
var _lost_pending := false
var _bubble: PanelContainer
var _bubble_text: Label
var _bubble_skip: Button
var _card: PanelContainer
var _card_title: Label
var _card_body: VBoxContainer
var _card_primary: Button
var _card_secondary: Button


func setup(view: Node2D, seen_ids: Array) -> void:
	_view = view
	_hud = view.ui
	theme = _hud.theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for id in seen_ids:
		seen[String(id)] = true
	_bubble = PanelContainer.new()
	_bubble.add_theme_stylebox_override("panel", _hud._style("fff5e2", "8b6446", 20, 3))
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
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", _hud._style("fff5e2", "8b6446", 26, 3))
	_card.custom_minimum_size.x = 560
	add_child(_card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	_card.add_child(body)
	_card_title = _hud._text(body, "", 32)
	_card_title.custom_minimum_size.x = 500
	_card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_body = VBoxContainer.new()
	_card_body.add_theme_constant_override("separation", 12)
	body.add_child(_card_body)
	var buttons: HBoxContainer = _hud._row(body, 14)
	_card_secondary = _button(buttons, "跳过引导", _skip)
	_card_primary = _button(buttons, "开始营业", _confirm)
	_card_primary.add_theme_stylebox_override("normal", _hud._style("8b6446", "8b6446", 15))
	_card_primary.add_theme_color_override("font_color", Color("fff8e9"))
	_seen_event = _last_event()
	refresh(0.0)


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 72
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


## Dimmed guides stop the shop clock so nothing is missed while reading.
func freezes() -> bool:
	return enabled and _blocking


func seen_list() -> Array:
	return seen.keys()


func refresh(delta: float) -> void:
	_time += delta
	_blocking = false
	_hole = Rect2()
	_point = Vector2.INF
	_bubble.visible = false
	_card.visible = false
	if enabled and _view.sim.has_method("station_info"):
		_pick_guide()
		match active:
			"welcome", "done", "shop_done": _show_card()
			"opening": _opening_step()
			"lost": _lost_step()
			"box_tea_leaf", "box_milk": _box_step(active.trim_prefix("box_"))
			"": pass
			_: _line_step(int(active.trim_prefix("line_")))
	visible = enabled and not active.is_empty()
	_place_bubble()
	queue_redraw()


func _pick_guide() -> void:
	var sim = _view.sim
	# Walk-outs during the opening are part of learning the ropes, not the later hint.
	_lost_pending = (_customer_left() or _lost_pending) and seen.has("opening")
	if not active.is_empty():
		return
	if not seen.has("opening"):
		# Saves already past the lemonade opening (or from before this guide) skip it.
		if sim.stage_index > 0 or (sim.station_unlocked("lemonade") and sim.workers.size() >= _opening_staff()):
			seen.opening = true
		else:
			active = "welcome" if not sim.station_unlocked("lemonade") and not seen.has("welcome") else "opening"
			return
	if _hud.page != "shop":
		return
	var next: int = sim.stage_index + 1
	if next < STAGE_SIGNS.size() and not seen.has("line_%d" % next):
		var info: Dictionary = sim.station_info(STAGE_SIGNS[next])
		if String(info.unlock_error).is_empty():
			active = "line_%d" % next
			return
	if sim.has_method("shop_complete") and sim.shop_complete() and not seen.has("shop_done"):
		active = "shop_done"
		return
	var box: String = sim.pending_box()
	if not box.is_empty() and not seen.has("box_" + box) and sim.box_error(box).is_empty():
		active = "box_" + box
		return
	if _lost_pending and not seen.has("lost"):
		active = "lost"
		_lost_pending = false


## True once a customer in line is angry (customers never leave in the tea shop),
## or, in the older shop, when one gave up since the last check.
func _customer_left() -> bool:
	if _view.sim.has_method("order_mood"):
		for order in _view.sim.orders:
			if _view.sim.order_mood(order) >= 2: return true
		return false
	var events: Array = _view.sim.events
	var left := false
	for index in range(events.size() - 1, -1, -1):
		if is_same(events[index], _seen_event):
			break
		left = left or events[index].kind == "customer_left"
	_seen_event = _last_event()
	return left


func _last_event() -> Variant:
	return null if _view.sim.events.is_empty() else _view.sim.events.back()


func _opening_staff() -> int:
	return mini(2, _view.sim.staff_slots())


func _opening_step() -> void:
	var sim = _view.sim
	var page: String = _hud.page
	_bubble_skip.text = "跳过引导"
	if not sim.station_unlocked("lemonade"):
		if page == "station" and _hud.station_panel.station_id == "lemonade":
			_focus(_hud.station_panel.unlock_button, "点「解锁」，花 10 金币摆上柠檬茶台")
		elif page != "shop":
			_hud.open_page("shop")
		else:
			_focus(_view._station_buttons.lemonade, "先开张！点这里摆上柠檬茶台")
		return
	if sim.sold == 0:
		_point = _world_rect(COUNTER_AREA).get_center()
		_say("小猫会自己做柠檬茶、招呼客人。\n看看第一杯卖出去！")
		return
	if sim.workers.size() < _opening_staff():
		var waiting: Array = sim.all_workers().filter(func(worker: Dictionary) -> bool: return not _view.staff_is_deployed(int(worker.id)))
		if not waiting.is_empty():
			if page != "staff":
				_focus(_hud.staff_button, "新伙伴在名册里，点「员工」")
			else:
				if _view.staff_is_deployed(_view.selected_worker):
					_view.select_worker(int(waiting[0].id), true)
				_focus(_hud.deploy_button, "点「派到店内」，让伙伴一起干活")
		elif sim.gold < sim.hire_cost():
			_point = _hud.get_node("%Gold").get_global_rect().get_center()
			_say("攒够 %d 金币就能招第二位伙伴" % sim.hire_cost())
		elif page != "recruit":
			_focus(_hud.recruit_button, "收到金币了！人手多出杯更快，点「招募」")
		else:
			_focus(_hud.hire_button, "邀请一位新伙伴")
		return
	active = "done"
	_hud.open_page("shop")
	_show_card()


func _line_step(stage: int) -> void:
	var sim = _view.sim
	var definition = sim.PROGRESSION.stages[stage]
	var sign: String = STAGE_SIGNS[stage]
	if sim.stage_index >= stage or not String(sim.station_info(sign).unlock_error).is_empty():
		_finish()
		return
	_bubble_skip.text = "以后再说"
	if _hud.page == "station" and _hud.station_panel.station_id == sign:
		_focus(_hud.station_panel.unlock_button, "点「解锁」开通%s" % definition.line_name)
	elif _hud.page != "shop":
		_hud.open_page("shop")
	else:
		_focus(_view._station_buttons[sign], "金币够了！开通%s，能卖新饮品" % definition.line_name)


func _box_step(material: String) -> void:
	var sim = _view.sim
	if sim.pending_box() != material or not sim.box_error(material).is_empty():
		_finish()
		return
	_bubble_skip.text = "以后再说"
	var definition = sim._box_def(material)
	var machine: String = sim.station_info_name(definition.box_machine)
	if _hud.page == "station" and _hud.station_panel.station_id == "supply":
		_focus(_hud.station_panel.material_buttons[material], "解锁%s箱，%s才有原料" % [definition.display_name, machine])
	elif _hud.page != "shop":
		_hud.open_page("shop")
	else:
		_focus(_view._station_buttons["supply"], "%s要用%s：去原料柜解锁%s箱" % [machine, definition.display_name, definition.display_name])


func _lost_step() -> void:
	var sim = _view.sim
	if _hud.page != "shop":
		_finish()
		return
	_bubble_skip.text = "知道了"
	if sim.workers.size() < sim.staff_slots():
		_focus(_hud.recruit_button, "有客人等急了！\n多招伙伴上岗，出杯更快")
	else:
		_focus_world(_view.STATION_REGIONS.lemonade, "有客人等急了！\n点设备升级，出杯更快")


func _show_card() -> void:
	_blocking = true
	_card.visible = true
	if _card_body.get_child_count() > 0 and _card.get_meta("kind", "") == active:
		return
	_card.set_meta("kind", active)
	for child in _card_body.get_children():
		child.free()
	if active == "welcome":
		_card_title.text = "欢迎，店长！"
		_card_secondary.visible = true
		_card_primary.text = "开始营业"
		for row in [["drink_lemonade", "招待顾客，卖饮品收金币"], ["drink_black_tea", "开通后厨生产线，做新饮品"], ["drink_pearl_milk_tea", "完成经营任务，把小店做大"]]:
			var line: HBoxContainer = _hud._row(_card_body, 16)
			var icon := TextureRect.new()
			icon.texture = load("res://art/ui/%s.png" % row[0])
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(64, 64)
			line.add_child(icon)
			var label: Label = _hud._text(line, row[1], 24)
			label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			# Wrapped labels need a width up front, or the card measures one glyph per line.
			label.custom_minimum_size.x = 420
	elif active == "shop_done":
		var sim = _view.sim
		_card_title.text = "首店完成！"
		_card_secondary.visible = false
		_card_primary.text = "继续营业"
		var minutes := int(sim.elapsed) / 60
		var label: Label = _hud._text(_card_body, "用时 %d 分 %02d 秒 · 总营业额 %d 金\n第二家店还在准备中，可以继续把这家店做大。" % [minutes, int(sim.elapsed) % 60, sim.revenue], 23)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size.x = 500
	else:
		_card_title.text = "开店上手了！"
		_card_secondary.visible = false
		_card_primary.text = "继续营业"
		var goal = _view.sim.PROGRESSION.stages[1]
		var label: Label = _hud._text(_card_body, "接下来自己经营：营业额到 %d，就能开%s。\n点机器可以升级，点「员工」可以调整岗位。" % [goal.revenue_threshold, goal.line_name], 23)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.custom_minimum_size.x = 500


func _confirm() -> void:
	if active == "welcome":
		seen.welcome = true
		active = "opening"
	else:
		_finish()
	refresh(0.0)


func _skip() -> void:
	if active in ["welcome", "opening", "done"]:
		seen.welcome = true
		seen.opening = true
		active = ""
	else:
		_finish()
	refresh(0.0)


func _finish() -> void:
	if active == "done":
		seen.opening = true
	elif not active.is_empty():
		seen[active] = true
	active = ""
	_view.save_now(false)


func _focus(target: Control, text: String) -> void:
	_hole = _to_local(target.get_global_transform_with_canvas(), Rect2(Vector2.ZERO, target.size)).grow(8)
	_blocking = true
	_point = _hole.get_center()
	_say(text)


func _focus_world(rect: Rect2, text: String) -> void:
	_hole = _world_rect(rect)
	_blocking = true
	_point = _hole.get_center()
	_say(text)


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
	if _card.visible:
		_card.reset_size()
		_card.position = (size - _card.size) / 2.0
	if not _bubble.visible:
		return
	_bubble.reset_size()
	var anchor := _point if _point != Vector2.INF else size / 2.0
	var target := _hole if _hole.has_area() else Rect2(anchor, Vector2.ZERO)
	# The bubble sits on the far side of the hand so neither covers the target.
	var below := anchor.y < size.y * 0.5
	var y := target.end.y + 120.0 if below else target.position.y - 120.0 - _bubble.size.y
	_bubble.position = Vector2(clampf(anchor.x - _bubble.size.x / 2.0, 16, size.x - _bubble.size.x - 16), clampf(y, 120, size.y - _bubble.size.y - 16))


## A welcome or done card answers any finished tap, touch or mouse, before the buttons see it:
## some phone browsers never turn touches into button presses, and a tap beside the card
## (or slightly off it) must not leave the player stuck behind the dim.
func _input(event: InputEvent) -> void:
	if not enabled or not _card.visible:
		return
	var released: bool = event is InputEventScreenTouch and not event.pressed and not event.canceled
	released = released or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
		and not event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION)
	if not released:
		return
	get_viewport().set_input_as_handled()
	if _card_secondary.is_visible_in_tree() and _card_secondary.get_global_rect().has_point(event.position):
		_skip()
	else:
		_confirm()


## Only the cut-out lets clicks through while a dimmed step is up.
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
	# A pointer bobs toward the target from the side the bubble is on.
	var below := _point.y < size.y * 0.5
	var direction := -1.0 if below else 1.0
	var reach := (_hole.size.y / 2.0 if _hole.has_area() else 0.0) + 12.0 + absf(sin(_time * 5.0)) * 14.0
	var tip := _point - Vector2(0, direction * reach)
	var back := tip - Vector2(0, direction * 44)
	draw_colored_polygon(PackedVector2Array([tip, back + Vector2(-24, 0), back + Vector2(24, 0)]), HAND)
	draw_rect(Rect2(back.x - 10, minf(back.y, back.y - direction * 40), 20, 40), HAND)
	draw_polyline(PackedVector2Array([tip, back + Vector2(-24, 0), back + Vector2(24, 0), tip]), Color("fff5e2"), 3.0)
