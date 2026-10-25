extends CanvasLayer
## Shop controls submit existing commands; labels read snapshots, not local economy.

const Assets := preload("res://presentation/graybox/assets.gd")
const Names := {"rabbit": "兔子", "bear": "小熊", "cat": "小猫"}
const ZoneNames := {"kitchen": "后厨", "front": "前厅"}
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
var _unlock: Button
var _menu: Label
var _hint: Label
var _selected := ""
var _selected_kind := ""
var _snapshot := {}
var _font: Font
var _toast_left := 0.0


func bind(sim: GameSim, view: Node2D, debug: CanvasLayer) -> void:
	unbind()
	for child in get_children():
		child.free()
	_card_buttons.clear()
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
	view.belt_selected.connect(_select.bind("belt"))
	view.selection_cleared.connect(_close)
	view.staff_dropped.connect(_assign)
	_on_snapshot(sim.last_snapshot)


func unbind() -> void:
	if is_instance_valid(_sim):
		if _sim.tick_finished.is_connected(_on_snapshot):
			_sim.tick_finished.disconnect(_on_snapshot)
		if _sim.command_rejected.is_connected(_on_rejected):
			_sim.command_rejected.disconnect(_on_rejected)
	if is_instance_valid(_view):
		for connection in _view.station_selected.get_connections() + _view.belt_selected.get_connections() + _view.selection_cleared.get_connections() + _view.staff_dropped.get_connections():
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
	_hint = _label("按住员工拖到后厨或前厅来调岗，点机器或传送带查看操作", Vector2(40, 1214), 13, Color("8a978d"), _root)
	_toast = _label("", Vector2(0, 1236), 16, Color("a16e47"), _root)
	_toast.size = Vector2(720, 24)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu = _label("", Vector2(56, 750), 16, Color("526b65"), _root)
	_unlock = _button("", Rect2(74, 852, 572, 46), "lock", _root)
	_unlock.pressed.connect(_unlock_next)
	_build_card()


func _unlock_next() -> void:
	var stage := _next_stage(_snapshot)
	if stage == null:
		return
	for slot_id in stage.unlock_slots:
		if not slot_id in _snapshot.progress.unlocked_slots:
			_sim.submit(UnlockStationCommand.new(slot_id))
			return


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
	for i in int(snapshot.progress.stage) + 1:
		menu.append(_dish_name(_sim.config.progression.stages[i].dish_id))
	_menu.text = "菜单：" + " / ".join(menu)
	_unlock.visible = next != null
	if next != null:
		var next_slot: SlotDef
		for slot in _sim.config.slots:
			if slot.id in next.unlock_slots and not slot.id in snapshot.progress.unlocked_slots:
				next_slot = slot
		if next_slot != null:
			var cost := next_slot.station.unlock_cost
			_unlock.text = "解锁%s · 金币 %d · 营业额 %d/%d" % [_dish_name(next.dish_id), cost, snapshot.revenue, next.revenue_threshold]
			_unlock.disabled = snapshot.gold < cost or snapshot.revenue < next.revenue_threshold
	_hint.text = "按住员工拖到后厨或前厅来调岗，点机器或传送带查看操作" if snapshot.kitchen_open else "先卖柠檬水，再在前厅解锁珍珠奶茶，开放后厨"
	if snapshot.progress.completed:
		_goal.text = "本店目标已达成"
	elif current != "":
		_goal.text = "目标：" + current
	elif next != null:
		_goal.text = "目标：营业额 %d/%d，解锁%s" % [snapshot.revenue, next.revenue_threshold, _dish_name(next.dish_id)]
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
	var anchor: Rect2
	if _selected_kind == "station":
		anchor = _view.station_anchor(_selected)
	else:
		anchor = Rect2(_view.belt_anchor(_selected), Vector2.ZERO)
	anchor.position.x -= _root.position.x
	var at := Vector2(anchor.get_center().x - CARD_SIZE.x / 2.0, anchor.end.y + 34)
	if at.y + CARD_SIZE.y > 1200:
		at.y = anchor.position.y - CARD_SIZE.y - 40
	at.x = clampf(at.x, screen.position.x + 12, screen.end.x - CARD_SIZE.x - 12)
	_card.position = at


func _refresh_card() -> void:
	if _selected == "" or _card == null or not _card.visible:
		return
	if _selected_kind == "belt":
		_refresh_belt_card()
		return
	var slot := _slot()
	var row := _row()
	if slot == null or row.is_empty():
		return
	var def: StationDef = slot.station
	_card_buttons[1].visible = false
	_card_buttons[0].size.x = 236
	_card_buttons[0].icon = Assets.icon("upgrade")
	if row.status != StationState.Status.ACTIVE:
		var price := def.parallel_cost if slot.parallel_of != "" else def.unlock_cost
		_card_title.text = def.display_name
		_card_detail.text = "加一台同样的机器，本段设备数量翻倍" if slot.parallel_of != "" else "启用这个机位"
		_card_buttons[0].text = "启用  %d" % price
		_card_buttons[0].disabled = _snapshot.gold < price
		var stage := _stage_unlocking(slot.id)
		if stage != null:
			_card_detail.text = "解锁新菜：%s" % _dish_name(stage.dish_id)
			_card_buttons[0].text = "购买  %d" % price
			if _snapshot.revenue < stage.revenue_threshold:
				_card_detail.text = "营业额 %d/%d 后可买，解锁%s" % [_snapshot.revenue, stage.revenue_threshold, _dish_name(stage.dish_id)]
				_card_buttons[0].disabled = true
		return
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


func _refresh_belt_card() -> void:
	var segment := {}
	for data in _snapshot.production.segments:
		if data.id == _selected:
			segment = data
	var connection := _connection()
	if segment.is_empty() or connection == null:
		return
	_card_title.text = "传送带"
	_card_detail.text = "%s → %s · 线上 %d 件" % [_slot_name(connection.from_slot), _slot_name(connection.to_slot), segment.items.size()]
	_card_buttons[0].size.x = 114
	_card_buttons[0].icon = Assets.icon("belt")
	_card_buttons[0].text = "断开" if segment.connected else "接上"
	_card_buttons[0].disabled = false
	_card_buttons[1].visible = true
	_card_buttons[1].icon = Assets.icon("delete")
	_card_buttons[1].text = "清空"
	_card_buttons[1].disabled = segment.items.is_empty()


func _assign(id: String, zone: String) -> void:
	for staff in _snapshot.workforce.staff:
		if staff.staff != id:
			continue
		# Already heading there, or already there with nothing pending: nothing to do.
		if staff.target == zone or (staff.zone == zone and staff.target == ""):
			return
		# Dropping back on the current zone cancels a pending transfer.
		_sim.submit(AssignStaffCommand.new(id, zone))
		_show_toast("%s 留在%s" % [Names.get(id, id), ZoneNames.get(zone, zone)] if staff.zone == zone else "%s 调往%s" % [Names.get(id, id), ZoneNames.get(zone, zone)])


func _act(button: int) -> void:
	if _selected_kind == "belt":
		var connection := _connection()
		if connection == null:
			return
		if button == 1:
			_sim.submit(ClearItemsCommand.new(_selected))
			return
		for data in _snapshot.production.segments:
			if data.id == _selected:
				_sim.submit(SetConnectionCommand.new(connection.from_slot, connection.to_slot, not data.connected))
		return
	var slot := _slot()
	var row := _row()
	if slot == null or row.is_empty():
		return
	if row.status == StationState.Status.EMPTY_PARALLEL:
		_sim.submit(ActivateParallelCommand.new(_selected))
	elif row.status == StationState.Status.LOCKED:
		_sim.submit(UnlockStationCommand.new(_selected))
	else:
		_sim.submit(UpgradeStationCommand.new(_selected))


func _slot() -> SlotDef:
	for slot in _sim.config.slots:
		if slot.id == _selected:
			return slot
	return null


## The stage whose purchase list holds this slot, if any.
func _stage_unlocking(slot_id: String) -> ShopStageDef:
	for stage in _sim.config.progression.stages:
		if slot_id in stage.unlock_slots:
			return stage
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


func _slot_name(id: String) -> String:
	if id == "shelf":
		return "备料架"
	for slot in _sim.config.slots:
		if slot.id == id:
			return slot.station.display_name
	return id


func _connection() -> ConnectionDef:
	for connection in _sim.config.connections:
		if connection.id == _selected:
			return connection
	return null


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

