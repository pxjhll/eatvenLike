extends VBoxContainer
## 目标页（HUD 组件）：当前目标、经营任务列表、销量营业额货架。

const Icons := preload("res://presentation/ui/reference_icons.gd")
const ReferenceTheme := preload("res://presentation/ui/reference_theme.gd")

var _view: Node2D
var _hud: Control
var _goal_icon: TextureRect
var _goal_title: Label
var _goal_bar: ProgressBar
var _goal_value: Label
var _task_column: VBoxContainer
var _task_rows: Array[Dictionary] = []
var _task_signature := ""
var _stat_values := {}
var _stat_cells := {}
## 完店后才出现：结店去下一家
var leave_button: Button


func setup(view: Node2D, hud: Control) -> void:
	_view = view
	_hud = hud
	add_theme_constant_override("separation", 12)
	var current: VBoxContainer = hud._card(self)
	var current_row: HBoxContainer = hud._row(current, 18)
	_goal_icon = hud._portrait(current_row, "cat", 100)
	_goal_icon.texture = Icons.texture("goals")
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 5)
	current_row.add_child(body)
	var current_pill: Label = hud._nowrap(hud._text(body, "当前目标", 20, true))
	hud.pill(current_pill, "当前目标", "f9e1b8", "714425")
	_goal_title = hud._text(body, "", 26)
	var progress: HBoxContainer = hud._row(body)
	_goal_bar = hud._bar(progress, 20)
	_goal_value = hud._nowrap(hud._text(progress, "", 22))
	_goal_value.size_flags_horizontal = Control.SIZE_SHRINK_END
	var task_panel := PanelContainer.new()
	task_panel.add_theme_stylebox_override("panel", ReferenceTheme.style("card", 18))
	add_child(task_panel)
	var task_scroll := ScrollContainer.new()
	task_scroll.custom_minimum_size.y = 168
	task_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	task_panel.add_child(task_scroll)
	_task_column = VBoxContainer.new()
	_task_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_task_column.add_theme_constant_override("separation", 4)
	task_scroll.add_child(_task_column)
	var stats: HBoxContainer = hud._row(self, 10)
	for stat in [["sold", "已售出", "drink_lemonade"], ["revenue", "营业额", "coin"], ["shelf", "货架", "shelf"]]:
		var cell: VBoxContainer = hud._card(stats)
		cell.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_stat_cells[stat[0]] = cell.get_parent()
		var line: HBoxContainer = hud._row(cell, 6)
		var icon: TextureRect = hud._portrait(line, "cat", 29)
		icon.texture = Icons.texture(view.view.text("icon_stat_" + stat[0], {}, stat[2]))
		hud._nowrap(hud._text(line, stat[1], 21, true))
		_stat_values[stat[0]] = hud._nowrap(hud._text(line, "", 23))
		_stat_values[stat[0]].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_stat_values[stat[0]].horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	leave_button = Button.new()
	leave_button.text = view.view.text("leave_button", {}, "结店")
	leave_button.custom_minimum_size.y = 72
	leave_button.focus_mode = Control.FOCUS_NONE
	leave_button.add_theme_font_size_override("font_size", 26)
	for state in ["normal", "hover", "pressed"]:
		leave_button.add_theme_stylebox_override(state, ReferenceTheme.style("gold", 18, state))
	leave_button.pressed.connect(func() -> void: view.open_summary())
	leave_button.visible = false
	add_child(leave_button)


func refresh() -> void:
	var rules: ShopRules = _view.rules
	var view: ShopView = _view.view
	var goal := view.goal()
	_goal_title.text = goal.text
	# 目标图标：texts["icon_<机器>"]（没写就用机器 / 原料箱的图标），完成后用“目标”
	var key := String(goal.id) if goal.kind in ["open", "box", "stage"] else ""
	_goal_icon.texture = Icons.texture(view.text("icon_" + key, {}, view.icon_of(key)) if not key.is_empty() else "goals")
	_goal_bar.get_parent().visible = int(goal.target) > 0
	_goal_bar.value = clampf(float(goal.current) / maxf(1.0, float(goal.target)), 0, 1)
	_goal_value.text = "%d / %d" % [goal.current, goal.target]
	var rows: Array = view.tasks()
	var signature := str(rows.map(func(row: Dictionary) -> String: return row.name))
	if signature != _task_signature:
		for child in _task_column.get_children(): child.free()
		_task_rows.clear()
		for row in rows:
			if _task_rows.size() > 0: _task_column.add_child(HSeparator.new())
			var line: HBoxContainer = _hud._row(_task_column, 10)
			line.custom_minimum_size.y = 42
			var check := Label.new()
			check.custom_minimum_size = Vector2(30, 30)
			check.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			check.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			check.add_theme_font_size_override("font_size", 20)
			check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_child(check)
			var name_label: Label = _hud._text(line, row.name, 22)
			name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
			name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			name_label.custom_minimum_size.x = 255
			name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var bar: ProgressBar = _hud._bar(line, 15)
			bar.custom_minimum_size.x = 110
			var count: Label = _hud._nowrap(_hud._text(line, "", 21))
			count.custom_minimum_size.x = 75
			count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			count.size_flags_horizontal = Control.SIZE_SHRINK_END
			count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_task_rows.append({"check": check, "name": name_label, "bar": bar, "count": count})
		_task_signature = signature
		_hud.relayout()
	for i in rows.size():
		var row: Dictionary = rows[i]
		var nodes: Dictionary = _task_rows[i]
		var done: bool = row.complete
		nodes.check.text = "✓" if done else ""
		nodes.check.add_theme_stylebox_override("normal", ReferenceTheme.style("check_done" if done else "check_todo", 8))
		nodes.check.add_theme_color_override("font_color", Color("fff8e9"))
		nodes.name.add_theme_color_override("font_color", Color("6f5a49" if done else "583e2d"))
		nodes.bar.visible = not done
		nodes.bar.value = clampf(float(row.current) / maxf(1.0, float(row.target)), 0, 1)
		nodes.count.text = "已完成" if done else "%d/%d" % [row.current, row.target]
	_stat_values.sold.text = "%d %s" % [rules.sold, view.text("unit", {}, "份")]
	_stat_values.revenue.text = str(int(rules.revenue))
	_stat_values.shelf.text = "%d / %d" % [rules.shelf_count, rules.shelf_capacity()]
	# 没有货架的店不显示货架
	_stat_cells.shelf.visible = rules.shelf_capacity() > 0
	if leave_button.visible != _view.can_leave():
		leave_button.visible = _view.can_leave()
		_hud.relayout()
