extends CanvasLayer
## Shop controls submit existing commands; labels read snapshots, not local economy.

const Assets := preload("res://presentation/graybox/assets.gd")
const Names := {"rabbit": "兔子", "bear": "小熊", "cat": "小猫"}
const CARD_SIZE := Vector2(268, 120)
var _sim: GameSim
var _view: Node2D
var _debug: CanvasLayer
var _root: Control
var _gold: Label
var _goal: Label
var _progress: ProgressBar
var _card: Panel
var _card_title: Label
var _card_detail: Label
var _card_buttons: Array[Button] = []
var _toast: Label
## 经营模式：「布局模式」；布局模式：一键部署 / 取消 / 确认
var _layout_button: Button
var _deploy: Button
var _cancel: Button
var _confirm: Button
var _device_cards: Array[Button] = []
var _device_drag := ""
var _device_defs := []
var _menu: Label
var _hint: Label
var _selected := ""
var _selected_kind := ""
var _snapshot := {}
var _font: Font
var _toast_left := 0.0
var _bar: Panel
var _hire: Button
var _bar_hint: Label
var _staff_cards: Array[Button] = []
var _bar_drag := ""
var _idle_staff := []
var _was_layout := false


func bind(sim: GameSim, view: Node2D, debug: CanvasLayer) -> void:
	unbind()
	for child in get_children():
		child.free()
	_card_buttons.clear()
	_staff_cards.clear()
	_device_cards.clear()
	_device_defs = []
	_device_drag = ""
	_idle_staff = []
	_bar_drag = ""
	_selected = ""
	_selected_kind = ""
	_sim = sim
	_view = view
	_debug = debug
	_font = load("res://art/ui/graybox_font.ttf")
	_build()
	sim.tick_finished.connect(_on_snapshot)
	sim.command_rejected.connect(_on_rejected)
	view.station_selected.connect(_select.bind("station"))
	view.selection_cleared.connect(_close)
	view.staff_dropped.connect(_assign)
	view.device_dropped.connect(_device_dropped)
	_on_snapshot(sim.last_snapshot)


func unbind() -> void:
	if is_instance_valid(_sim):
		if _sim.tick_finished.is_connected(_on_snapshot):
			_sim.tick_finished.disconnect(_on_snapshot)
		if _sim.command_rejected.is_connected(_on_rejected):
			_sim.command_rejected.disconnect(_on_rejected)
	if is_instance_valid(_view):
		for connection in _view.station_selected.get_connections() + _view.selection_cleared.get_connections() + _view.staff_dropped.get_connections() + _view.device_dropped.get_connections():
			if connection.callable.get_object() == self:
				connection.signal.disconnect(connection.callable)
	_sim = null
	_view = null


func _exit_tree() -> void:
	unbind()


func _process(delta: float) -> void:
	if _root != null:
		_root.position.x = (get_viewport().get_visible_rect().size.x - 720) / 2.0
	if _card != null and _card.visible:
		_place_card()
	if _toast_left > 0:
		_toast_left -= delta
		_toast.modulate.a = clampf(_toast_left * 3.0, 0.0, 1.0)


func _build() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.size = Vector2(720, 1280)
	var theme := Theme.new()
	theme.default_font = _font
	theme.default_font_size = 16
	_root.theme = theme
	add_child(_root)
	_panel(Rect2(32, 26, 168, 58), Color("fff8e4"), _root)
	var coin := TextureRect.new()
	coin.texture = Assets.icon("coin")
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.position = Vector2(44, 37)
	coin.size = Vector2(36, 36)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(coin)
	_gold = _label("", Vector2(88, 36), 26, Color("90773b"), _root)
	_panel(Rect2(212, 26, 370, 58), Color("eef3e9"), _root)
	_goal = _label("", Vector2(228, 32), 14, Color("526b65"), _root)
	_progress = ProgressBar.new()
	_progress.position = Vector2(228, 60)
	_progress.size = Vector2(338, 10)
	_progress.max_value = 1.0
	_progress.show_percentage = false
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("dbe3d2")
	bg.set_corner_radius_all(5)
	_progress.add_theme_stylebox_override("background", bg)
	var fill := bg.duplicate()
	fill.bg_color = Color("92b29b")
	_progress.add_theme_stylebox_override("fill", fill)
	_root.add_child(_progress)
	var save := _button("", Rect2(594, 30, 42, 50), "save", _root)
	save.tooltip_text = "保存进度"
	save.pressed.connect(func() -> void:
		var err := App.save_now()
		_show_toast("已保存" if err == OK else "保存失败：" + error_string(err)))
	var debug := _button("", Rect2(642, 30, 42, 50), "debug", _root)
	debug.tooltip_text = "显示 / 收起调试面板"
	debug.pressed.connect(func() -> void: _debug.visible = not _debug.visible)
	_hint = _label("", Vector2(40, 1104), 13, Color("8a978d"), _root)
	_toast = _label("", Vector2(0, 1264), 14, Color("a16e47"), _root)
	_toast.size = Vector2(720, 24)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu = _label("", Vector2(56, 750), 16, Color("526b65"), _root)
	_layout_button = _button("布局模式", Rect2(74, 1124, 572, 42), "rotate", _root)
	_layout_button.pressed.connect(func() -> void: _sim.submit(EnterLayoutCommand.new()))
	_deploy = _button("一键部署", Rect2(44, 1124, 200, 42), "assign", _root)
	_deploy.pressed.connect(func() -> void: _sim.submit(AutoDeployCommand.new()))
	_cancel = _button("取消", Rect2(256, 1124, 150, 42), "close", _root)
	_cancel.pressed.connect(func() -> void: _sim.submit(CancelLayoutCommand.new()))
	_confirm = _button("确认", Rect2(418, 1124, 258, 42), "coin", _root)
	_confirm.pressed.connect(func() -> void: _sim.submit(ConfirmLayoutCommand.new()))
	_build_staff_bar()
	_build_card()


## 员工栏（只在经营模式）：已雇未上岗的员工卡片 + 招人按钮。
## 拖卡片到工位上岗；把在岗的人拖回这里就是下岗（决定⑩）。
func _build_staff_bar() -> void:
	_bar = _panel(Rect2(32, 1194, 656, 68), Color("f2f0e4"), _root)
	_hire = _button("", Rect2(44, 1202, 136, 52), "hire", _root)
	_hire.pressed.connect(func() -> void: _sim.submit(HireStaffCommand.new()))
	_bar_hint = _label("", Vector2(196, 1218), 13, Color("8a978d"), _root)


## 一张未上岗员工的卡片，按下就跟着手指走，松手落在工位上就上岗
func _staff_card(staff_id: String, index: int) -> Button:
	var card := _button(_sim.workforce.display_name(staff_id), Rect2(196 + index * 116, 1202, 108, 52), "assign", _root)
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseMotion and _bar_drag == staff_id:
			card.position += event.relative
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_bar_drag = staff_id
				card.z_index = 10
			elif _bar_drag == staff_id:
				_finish_bar_drag(card.get_global_transform_with_canvas() * event.position))
	return card


## 松手：落在前厅工位或后厨要人的设备上就上岗，落在别处什么也不做
func _finish_bar_drag(at: Vector2) -> void:
	var staff_id := _bar_drag
	_bar_drag = ""
	for card in _staff_cards:
		card.queue_free()
	_staff_cards.clear()
	_idle_staff = ["?"]
	if _view == null or staff_id == "":
		return
	var target: String = _view.spot_at(_world_point(at))
	if target != "":
		_assign(staff_id, target)


func _refresh_staff_bar() -> void:
	var idle := []
	for staff in _snapshot.workforce.staff:
		if String(staff.post) == "":
			idle.append(String(staff.staff))
	# 拖动中不要重建卡片，否则手里的那张会被换掉
	if _bar_drag == "" and idle != _idle_staff:
		_idle_staff = idle
		for card in _staff_cards:
			card.queue_free()
		_staff_cards.clear()
		for i in idle.size():
			_staff_cards.append(_staff_card(idle[i], i))
	var cost := _sim.workforce.hire_cost()
	_hire.text = "招人 %d" % cost
	_hire.disabled = int(_snapshot.gold) < cost
	_bar_hint.text = ""
	if idle.is_empty():
		_bar_hint.text = "店里还没人，先招一个" if _sim.workforce.staff_count() == 0 else "所有人都在岗上"


## 设备栏（只在布局模式）：已开放的后厨设备，按住拖到后厨格子上放下（草稿，不扣钱）
func _device_card(def: StationDef, index: int) -> Button:
	var card := _button("%s %d" % [def.display_name, def.price], Rect2(44 + index * 160, 1202, 152, 52), "coin", _root)
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseMotion and _device_drag == def.id:
			card.position += event.relative
			_view.preview_device(def, _world_point(card.get_global_transform_with_canvas() * event.position))
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_device_drag = def.id
				card.z_index = 10
			elif _device_drag == def.id:
				_finish_device_drag(def, card.get_global_transform_with_canvas() * event.position))
	return card


func _finish_device_drag(def: StationDef, at: Vector2) -> void:
	_device_drag = ""
	var cell: Vector2i = _view.preview_device(def, _world_point(at))
	_view.clear_preview()
	_device_defs = ["?"]
	if at.y < (_root.get_global_transform_with_canvas() * Vector2(0, 1190)).y:
		_sim.submit(PlaceDeviceCommand.new(def.id, cell))


func _world_point(at: Vector2) -> Vector2:
	return _view.get_global_transform_with_canvas().affine_inverse() * at


func _refresh_device_bar(layout_mode: bool) -> void:
	var defs := []
	if layout_mode:
		defs = _snapshot.open_devices.duplicate()
	if _device_drag == "" and defs != _device_defs:
		_device_defs = defs
		for card in _device_cards:
			card.queue_free()
		_device_cards.clear()
		for i in defs.size():
			_device_cards.append(_device_card(_sim.config.device_def(defs[i]), i))


## 布局模式里设备拖回了设备栏（拿回）或拖到了新格子（挪动）
func _device_dropped(device_id: String, cell: Vector2i, to_bar: bool) -> void:
	if to_bar:
		_sim.submit(RemoveDraftDeviceCommand.new(device_id))
	else:
		_sim.submit(MoveDeviceCommand.new(device_id, cell))


func _build_card() -> void:
	_card = _panel(Rect2(Vector2.ZERO, CARD_SIZE), Color("fffaf0"), _root)
	var style: StyleBoxFlat = _card.get_theme_stylebox("panel")
	style.border_color = Color("d9cfb4")
	style.set_border_width_all(2)
	style.shadow_color = Color(0.2, 0.25, 0.25, 0.18)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 3)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card_title = _label("", Vector2(16, 12), 18, Color("3f5557"), _card)
	_card_detail = _label("", Vector2(16, 40), 13, Color("7f8d86"), _card)
	for i in 2:
		var button := _button("", Rect2(16 + i * 122, 68, 114, 40), "upgrade", _card)
		button.pressed.connect(_act.bind(i))
		_card_buttons.append(button)
	_card.visible = false


func _on_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	_gold.text = str(snapshot.gold)
	var completed := 0.0
	var current := ""
	for task in snapshot.tasks:
		completed += task.progress
		if current == "" and task.progress < 1.0:
			current = task.name
	# Tasks of dishes not yet unlocked still count, so the bar reads as progress toward the next shop.
	var total := 0
	for stage in _sim.config.progression.stages:
		total += stage.tasks.size()
	_progress.value = completed / maxf(total, 1)
	var next := _next_stage(snapshot)
	var menu: Array[String] = []
	for i in int(snapshot.front_hall.menu_stage) + 1:
		menu.append(_dish_name(_sim.config.progression.stages[i].dish_id))
	_menu.text = "菜单：" + " / ".join(menu)
	var layout_mode := int(snapshot.mode) == GameSim.Mode.LAYOUT
	_layout_button.visible = bool(snapshot.kitchen_open) and not layout_mode
	for button in [_deploy, _cancel, _confirm]:
		button.visible = layout_mode
	_bar_hint.visible = not layout_mode
	_hire.visible = not layout_mode
	if layout_mode:
		var draft: Dictionary = snapshot.layout.draft
		_confirm.text = "确认  %d" % int(draft.cost)
		_confirm.disabled = int(snapshot.gold) < int(draft.cost) or not draft.failed.is_empty() or String(draft.problem) != ""
		if layout_mode != _was_layout:
			_close()
	_was_layout = layout_mode
	_refresh_device_bar(layout_mode)
	_refresh_staff_bar()
	for card in _staff_cards:
		card.visible = not layout_mode
	if layout_mode:
		var draft: Dictionary = snapshot.layout.draft
		_hint.text = "从下面的设备栏拖设备到后厨，或点「一键部署」；拖回设备栏就拿回"
		if not draft.failed.is_empty():
			_hint.text = "有传送带铺不通，挪一挪设备"
	elif snapshot.kitchen_open:
		_hint.text = "点「布局模式」摆后厨设备；按住员工拖到工位上岗，拖回员工栏是下岗"
	else:
		_hint.text = "点价格牌解锁柠檬水台和柜台，招一个人拖到柜台"
	if snapshot.progress.completed:
		_goal.text = "本店目标已达成"
	elif current != "":
		_goal.text = "目标：" + current
	elif next != null:
		_goal.text = "目标：营业额 %d/%d，开放%s" % [snapshot.revenue, next.revenue_threshold, _dish_name(next.dish_id)]
	else:
		_goal.text = "目标：菜单与任务"
	_refresh_card()


func _select(id: String, kind: String) -> void:
	_selected = id
	_selected_kind = kind
	_view.select(kind, id)
	_card.visible = true
	_card.scale = Vector2(0.9, 0.9)
	_card.pivot_offset = CARD_SIZE / 2.0
	create_tween().tween_property(_card, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_refresh_card()
	_place_card()


func _close() -> void:
	_selected = ""
	_selected_kind = ""
	if _view != null:
		_view.select("", "")
	if _card != null:
		_card.visible = false


func _place_card() -> void:
	if _selected == "" or _view == null:
		return
	var screen := Rect2(Vector2.ZERO, Vector2(720, 1280))
	var anchor: Rect2 = _view.station_anchor(_selected)
	anchor.position.x -= _root.position.x
	var at := Vector2(anchor.get_center().x - CARD_SIZE.x / 2.0, anchor.end.y + 34)
	if at.y + CARD_SIZE.y > 1200:
		at.y = anchor.position.y - CARD_SIZE.y - 40
	at.x = clampf(at.x, screen.position.x + 12, screen.end.x - CARD_SIZE.x - 12)
	_card.position = at


func _refresh_card() -> void:
	if _selected == "" or _card == null or not _card.visible:
		return
	var row := _row()
	if row.is_empty():
		return
	var spot := _spot()
	if spot != null:
		_refresh_spot_card(spot, row)
		return
	if not _sim.production.has_slot(_selected):
		return
	var def := _sim.production.station_def(_selected)
	_card_buttons[1].visible = false
	_card_buttons[0].size.x = 236
	_card_buttons[0].icon = Assets.icon("upgrade")
	var level := int(row.level)
	var maximum := mini(def.level_speed.size(), def.upgrade_costs.size() + 1)
	var full := level >= maximum
	_card_title.text = "%s  Lv%d" % [def.display_name, level]
	if full:
		_card_detail.text = "已经是最高等级"
		_card_buttons[0].text = "已满级"
		_card_buttons[0].disabled = true
		return
	var price: int = def.upgrade_costs[level - 1]
	_card_detail.text = "速度 ×%.1f → ×%.1f" % [def.level_speed[level - 1], def.level_speed[level]]
	_card_buttons[0].text = "升级  %d" % price
	_card_buttons[0].disabled = _snapshot.gold < price


## 前厅位点：没解锁时是价格牌，解锁后和别的工位一样能升级。
func _refresh_spot_card(spot: FrontSpotDef, row: Dictionary) -> void:
	var def: StationDef = spot.station
	_card_buttons[1].visible = false
	_card_buttons[0].size.x = 236
	_card_buttons[0].icon = Assets.icon("upgrade")
	if row.status != StationState.Status.ACTIVE:
		_card_title.text = def.display_name
		_card_detail.text = "点一下在前厅摆上它" if spot.posts == 0 else "点一下摆上它，再派一名员工"
		_card_buttons[0].text = "购买  %d" % spot.unlock_cost
		_card_buttons[0].disabled = int(_snapshot.gold) < spot.unlock_cost
		return
	var level := int(row.level)
	var maximum := mini(def.level_speed.size(), def.upgrade_costs.size() + 1)
	_card_title.text = "%s  Lv%d" % [def.display_name, level]
	if level >= maximum:
		_card_detail.text = "已经是最高等级" if maximum > 1 else "这个工位不升级"
		_card_buttons[0].text = "已满级" if maximum > 1 else "不用升级"
		_card_buttons[0].disabled = true
		return
	var price: int = def.upgrade_costs[level - 1]
	_card_detail.text = "速度 ×%.2f → ×%.2f" % [def.level_speed[level - 1], def.level_speed[level]]
	_card_buttons[0].text = "升级  %d" % price
	_card_buttons[0].disabled = int(_snapshot.gold) < price


## 拖拽落点：前厅位点或后厨设备 = 上岗（满了就和台上的人换岗），空 = 下岗。
func _assign(id: String, target: String) -> void:
	var me := {}
	for staff in _snapshot.workforce.staff:
		if staff.staff == id:
			me = staff
	if me.is_empty():
		return
	var name: String = _sim.workforce.display_name(id)
	if target == "":
		if String(me.post) == "":
			return
		_sim.submit(AssignStaffCommand.new(id, ""))
		_show_toast("%s 下岗了" % name)
		return
	if String(me.post) == target:
		return
	var capacity := _sim.front_hall.post_capacity(target) if _sim.front_hall.has_spot(target) else 1
	if _sim.workforce.post_occupancy(target) >= capacity:
		# 工位满了：和台上的人换岗，而不是挤下去
		for staff in _snapshot.workforce.staff:
			if staff.post == target:
				_sim.submit(SwapStaffCommand.new(id, String(staff.staff)))
				_show_toast("%s 和 %s 换了岗" % [name, _sim.workforce.display_name(String(staff.staff))])
				return
		return
	_sim.submit(AssignStaffCommand.new(id, target))
	_show_toast("%s 去了%s" % [name, _sim.station_owner(target).station_def(target).display_name])


func _act(_button_index: int) -> void:
	var row := _row()
	if row.is_empty():
		return
	if _spot() != null and row.status != StationState.Status.ACTIVE:
		_sim.submit(UnlockFrontSpotCommand.new(_selected))
	else:
		_sim.submit(UpgradeStationCommand.new(_selected))


func _spot() -> FrontSpotDef:
	for spot in _sim.config.front_spots:
		if spot.id == _selected:
			return spot
	return null


func _next_stage(snapshot: Dictionary) -> ShopStageDef:
	var stages := _sim.config.progression.stages
	var index := int(snapshot.progress.stage) + 1
	return stages[index] if index < stages.size() else null


func _dish_name(dish_id: String) -> String:
	for dish in _sim.config.dishes:
		if dish.id == dish_id:
			return dish.display_name
	return dish_id


func _row() -> Dictionary:
	for row in _snapshot.production.stations + _snapshot.front_hall.counters:
		if row.slot == _selected:
			return row
	return {}


func _on_rejected(_command: SimCommand, reason: String) -> void:
	_show_toast(reason)


func _show_toast(message: String) -> void:
	_toast.text = message
	_toast.modulate.a = 1.0
	_toast_left = 2.0


func _label(text: String, at: Vector2, size: int, color: Color, parent: Control) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _panel(rect: Rect2, color: Color, parent: Control) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


func _button(text: String, rect: Rect2, icon: String, parent: Control) -> Button:
	var button := Button.new()
	button.text = text
	button.icon = Assets.icon(icon)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 22)
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color("42695d"))
	button.add_theme_color_override("font_disabled_color", Color("a8b3a9"))
	for type in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("e2eddf") if type != "pressed" else Color("c5dbc9")
		if type == "disabled":
			style.bg_color = Color("eef0e6")
		style.set_corner_radius_all(10)
		button.add_theme_stylebox_override(type, style)
	# Press feedback: a quick squash so taps feel physical.
	button.button_down.connect(func() -> void:
		button.pivot_offset = button.size / 2.0
		create_tween().tween_property(button, "scale", Vector2(0.93, 0.93), 0.05))
	button.button_up.connect(func() -> void:
		create_tween().tween_property(button, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_BACK))
	parent.add_child(button)
	return button
