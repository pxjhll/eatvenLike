extends CanvasLayer
## Shop controls submit existing commands; labels read snapshots, not local economy.

const Assets := preload("res://presentation/graybox/assets.gd")
const Names := {"rabbit": "兔子", "bear": "小熊", "cat": "小猫"}
var _sim: GameSim
var _view: Node2D
var _debug: CanvasLayer
var _root: Control
var _gold: Label
var _revenue: Label
var _selection: Label
var _detail: Label
var _goal: Label
var _progress: ProgressBar
var _action: Button
var _toast: Label
var _staff_labels := {}
var _staff_buttons := {}
var _selected := ""
var _snapshot := {}
var _font: Font
var _toast_left := 0.0


func bind(sim: GameSim, view: Node2D, debug: CanvasLayer) -> void:
	unbind()
	for child in get_children():
		child.free()
	_staff_labels.clear()
	_staff_buttons.clear()
	_sim = sim
	_view = view
	_debug = debug
	_font = load("res://art/ui/graybox_font.ttf")
	_build()
	sim.tick_finished.connect(_on_snapshot)
	sim.command_rejected.connect(_on_rejected)
	view.station_selected.connect(_select)
	_on_snapshot(sim.last_snapshot)


func unbind() -> void:
	if is_instance_valid(_sim):
		if _sim.tick_finished.is_connected(_on_snapshot):
			_sim.tick_finished.disconnect(_on_snapshot)
		if _sim.command_rejected.is_connected(_on_rejected):
			_sim.command_rejected.disconnect(_on_rejected)
	if is_instance_valid(_view) and _view.station_selected.is_connected(_select):
		_view.station_selected.disconnect(_select)
	_sim = null
	_view = null


func _exit_tree() -> void:
	unbind()


func _process(delta: float) -> void:
	if _root != null:
		_root.position.x = (get_viewport().get_visible_rect().size.x - 720) / 2.0
	if _toast_left > 0:
		_toast_left -= delta
		if _toast_left <= 0:
			_toast.text = ""


func _build() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.size = Vector2(720, 1280)
	var theme := Theme.new()
	theme.default_font = _font
	theme.default_font_size = 16
	_root.theme = theme
	add_child(_root)
	_label("面包小店", Vector2(38, 28), 32, Color("3f5557"))
	_label("让每一道工序顺起来", Vector2(41, 76), 15, Color("81938c"))
	_panel(Rect2(460, 29, 222, 76), Color("fff8e4"))
	var coin := TextureRect.new()
	coin.texture = Assets.icon("coin")
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.position = Vector2(474, 39)
	coin.size = Vector2(36, 36)
	_root.add_child(coin)
	_gold = _label("", Vector2(519, 34), 25, Color("90773b"))
	_revenue = _label("", Vector2(476, 77), 12, Color("9a966e"))
	var save := _button("", Rect2(348, 40, 43, 43), "save")
	save.tooltip_text = "保存进度"
	save.pressed.connect(App.save_now)
	var debug := _button("", Rect2(399, 40, 43, 43), "debug")
	debug.tooltip_text = "显示 / 收起调试面板"
	debug.pressed.connect(func() -> void: _debug.visible = not _debug.visible)
	for i in _sim.last_snapshot.workforce.staff.size():
		var staff: Dictionary = _sim.last_snapshot.workforce.staff[i]
		var x: float = 38.0 + i * 328
		_panel(Rect2(x, 125, 316, 54), Color("eaf0e7"))
		_staff_labels[staff.staff] = _label("", Vector2(x + 16, 143), 15, Color("526b65"))
		var button := _button("", Rect2(x + 180, 133, 125, 38), "assign")
		var id: String = staff.staff
		button.pressed.connect(_assign.bind(id))
		_staff_buttons[id] = button
	_panel(Rect2(36, 1122, 648, 142), Color("fff9ec"))
	_selection = _label("点选工位，查看升级与并联", Vector2(57, 1138), 19, Color("526763"))
	_detail = _label("观察物料和员工，找到最慢的一环", Vector2(57, 1170), 13, Color("89968b"))
	_action = _button("", Rect2(489, 1138, 174, 49), "upgrade")
	_action.visible = false
	_action.pressed.connect(_act)
	_goal = _label("", Vector2(57, 1204), 13, Color("8b947b"))
	_progress = ProgressBar.new()
	_progress.position = Vector2(57, 1228)
	_progress.size = Vector2(605, 7)
	_progress.max_value = 1.0
	_progress.show_percentage = false
	_progress.add_theme_font_size_override("font_size", 1)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("e3e8d7")
	bg.set_corner_radius_all(3)
	_progress.add_theme_stylebox_override("background", bg)
	var fill := bg.duplicate()
	fill.bg_color = Color("92b29b")
	_progress.add_theme_stylebox_override("fill", fill)
	_root.add_child(_progress)
	_toast = _label("", Vector2(56, 1080), 16, Color("a16e47"))


func _on_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	_gold.text = str(snapshot.gold)
	_revenue.text = "累计营业额  %d" % snapshot.revenue
	for staff in snapshot.workforce.staff:
		if not _staff_labels.has(staff.staff):
			continue
		var zone := "后厨" if staff.zone == "kitchen" else "前厅"
		_staff_labels[staff.staff].text = Names.get(staff.staff, staff.staff) + " · " + zone
		_staff_buttons[staff.staff].text = "调往" + ("前厅" if staff.zone == "kitchen" else "后厨")
		_staff_buttons[staff.staff].disabled = staff.target != ""
	var completed := 0.0
	for task in snapshot.tasks:
		completed += task.progress
	_progress.value = completed / maxf(snapshot.tasks.size(), 1)
	_goal.text = "本店目标已达成" if snapshot.progress.completed else ("本店目标  ·  " + (snapshot.tasks[0].name if not snapshot.tasks.is_empty() else "菜单与任务"))
	_refresh_selection()


func _select(id: String) -> void:
	_selected = id
	_refresh_selection()


func _refresh_selection() -> void:
	if _selected == "":
		return
	var slot := _slot()
	var row := _row()
	if slot == null or row.is_empty():
		return
	var def: StationDef = slot.station
	_selection.text = def.display_name + "  ·  Lv" + str(row.level)
	_action.visible = true
	if row.status != StationState.Status.ACTIVE:
		var price := def.parallel_cost if slot.parallel_of != "" else def.unlock_cost
		_detail.text = "启用固定机位，增加生产能力"
		_action.text = "启用  %d" % price
		_action.disabled = _snapshot.gold < price
	else:
		var maximum := mini(def.level_speed.size(), def.upgrade_costs.size() + 1)
		var full: bool = row.level >= maximum
		var price := 0 if full else def.upgrade_costs[int(row.level) - 1]
		_detail.text = "已达当前等级上限" if full else "提升工位效率，原有生产继续运行"
		_action.text = "已满级" if full else "升级  %d" % price
		_action.disabled = full or _snapshot.gold < price


func _assign(id: String) -> void:
	for staff in _snapshot.workforce.staff:
		if staff.staff == id:
			_sim.submit(AssignStaffCommand.new(id, "front" if staff.zone == "kitchen" else "kitchen"))


func _act() -> void:
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


func _row() -> Dictionary:
	for row in _snapshot.production.stations + _snapshot.front_hall.counters:
		if row.slot == _selected:
			return row
	return {}


func _on_rejected(_command: SimCommand, reason: String) -> void:
	_show_toast(reason)


func _show_toast(message: String) -> void:
	_toast.text = message
	_toast_left = 2.0


func _label(text: String, at: Vector2, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	_root.add_child(label)
	return label


func _panel(rect: Rect2, color: Color) -> void:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", style)
	_root.add_child(panel)


func _button(text: String, rect: Rect2, icon: String) -> Button:
	var button := Button.new()
	button.text = text
	button.icon = Assets.icon(icon)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 23)
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
	_root.add_child(button)
	return button
