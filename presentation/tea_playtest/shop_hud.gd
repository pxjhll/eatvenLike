extends Control
## UI composition and session binding; prices and staff always come from the sim.

const Actor := preload("res://presentation/tea_playtest/staff_actor.gd")
const StationPanel := preload("res://presentation/tea_playtest/station_panel.gd")
const Characters := preload("res://presentation/characters/character_library.gd")
const CharacterPreview := preload("res://presentation/characters/character_preview.gd")
const NAMES := Characters.NAMES
const ROLES := {"speed": "速度型", "carry": "力量型", "skill": "操作型"}
const PAGE_NAMES := {"staff": "员工", "recruit": "招募伙伴", "menu": "菜单", "restart": "重开店铺", "station": "设备", "goals": "目标", "characters": "角色预览"}
const POST_NAMES := {"boil": "煮茶", "topping": "加料", "counter": "前台"}
## Stat bars are scaled against the best value a fully trained partner can reach.
const STAT_MAX := {"speed": 220.0, "capacity": 6.0, "skill": 3.0}
var page := "shop"
var show_selection := false
var _view: Node2D
var _portraits := {}
var _staff_titles: Array[Label] = []
var _staff_tags: Array[Label] = []
var _staff_portraits: Array[TextureRect] = []
var _recruit_label: Label
var _recruit_portrait: TextureRect
var _styled_selection := -1
var _card_content: HBoxContainer
var _page_nodes := {}
var _roster_signature := ""
var _save_caption: Label
var _task_rows: Array[Dictionary] = []
var _task_signature := ""
var _task_column: VBoxContainer
var _goal_title: Label
var _goal_bar: ProgressBar
var _goal_value: Label
var _stat_values := {}
var _selected_name: Label
var _selected_role: Label
var _selected_doing: Label
var _stat_bars := {}
var _stat_numbers := {}
var _sheet_space := Vector2.ZERO
var _sheet_height := -1.0

@onready var home_button: Button = %Home
@onready var goals_button: Button = %Goals
@onready var staff_button: Button = %Staff
@onready var recruit_button: Button = %Recruit
@onready var menu_button: Button = %Menu
@onready var close_button: Button = %Close
@onready var speed_button: Button = %Speed
@onready var goal_button: Button = %Goal
@onready var toast: Label = %Toast
var hire_button: Button
var train_button: Button
var pause_button: Button
var belt_button: Button
var restart_button: Button
var old_button: Button
var cancel_restart_button: Button
var confirm_restart_button: Button
var deploy_button: Button
var save_button: Button
var station_panel: VBoxContainer
var character_preview: VBoxContainer
var character_preview_button: Button
var staff_preview_button: Button

func setup(view: Node2D) -> void:
	_view = view
	_apply_theme()
	for key in NAMES:
		_portraits[key] = Characters.portrait(key)
	for entry in [[home_button, "shop"], [goals_button, "goals"], [staff_button, "staff"], [recruit_button, "recruit"]]:
		entry[0].pressed.connect(open_page.bind(entry[1]))
		entry[0].icon = load("res://art/ui/shop/" + entry[1] + ".svg")
		entry[0].expand_icon = true
		entry[0].add_theme_constant_override("icon_max_width", 30)
		entry[0].add_theme_constant_override("h_separation", 9)
	menu_button.pressed.connect(func() -> void: open_page("shop" if page == "menu" else "menu"))
	goal_button.pressed.connect(open_page.bind("goals"))
	close_button.pressed.connect(open_page.bind("shop"))
	speed_button.pressed.connect(func() -> void:
		_view._speed_factor = 1.0 if _view._speed_factor >= 4.0 else _view._speed_factor * 2.0
		refresh())
	%Shade.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			open_page("shop")
		elif event is InputEventScreenTouch and event.pressed:
			open_page("shop"))
	$Selection/Row/Details.pressed.connect(open_page.bind("staff"))
	$Selection/Row/Dismiss.pressed.connect(func() -> void: show_selection = false; refresh())
	_build_pages()
	move_child($ToastRow, get_child_count() - 1)
	open_page("shop")

func _apply_theme() -> void:
	var ui_theme := Theme.new()
	ui_theme.default_font = load("res://art/ui/graybox_font.ttf")
	ui_theme.default_font_size = 23
	for type in ["Label", "Button"]:
		ui_theme.set_color("font_color", type, Color("583e2d"))
	ui_theme.set_color("font_hover_color", "Button", Color("583e2d"))
	ui_theme.set_color("font_pressed_color", "Button", Color("fff8e9"))
	ui_theme.set_color("font_disabled_color", "Button", Color("978b7c"))
	ui_theme.set_color("icon_normal_color", "Button", Color("79573d"))
	ui_theme.set_color("icon_hover_color", "Button", Color("79573d"))
	ui_theme.set_color("icon_pressed_color", "Button", Color("fff8e9"))
	ui_theme.set_stylebox("panel", "PanelContainer", _style("fff5e2", "b38c62", 22))
	ui_theme.set_stylebox("normal", "Button", _style("f3e5cb", "dec6a3", 15))
	ui_theme.set_stylebox("hover", "Button", _style("fff6df", "b58b5d", 15))
	ui_theme.set_stylebox("pressed", "Button", _style("8b6446", "8b6446", 15))
	ui_theme.set_stylebox("disabled", "Button", _style("e5dfd2", "d9cdbb", 15))
	ui_theme.set_stylebox("focus", "Button", _style("fff4de00", "bc8951", 15))
	ui_theme.set_stylebox("background", "ProgressBar", _style("efe3cc", "c9a97f", 7, 1))
	ui_theme.set_stylebox("fill", "ProgressBar", _style("8b6446", "8b6446", 7, 0))
	theme = ui_theme
	var header_style := _style("fff5e2f2", "b38c62", 22)
	header_style.set_content_margin_all(0)
	$Header.add_theme_stylebox_override("panel", header_style)
	%Coin.add_theme_stylebox_override("panel", _style("e6b94f", "a77d2a", 15))
	var flat := StyleBoxEmpty.new()
	for state in ["normal", "hover", "focus", "disabled"]:
		goal_button.add_theme_stylebox_override(state, flat)
	goal_button.add_theme_stylebox_override("pressed", _style("ead4b2", "ead4b2", 12, 0))
	%Sheet.add_theme_stylebox_override("panel", _style("fff5e2", "a98159", 26))
	var toast_style := _style("624831e6", "624831", 22, 0)
	toast_style.content_margin_left = 22
	toast_style.content_margin_right = 22
	toast.add_theme_stylebox_override("normal", toast_style)
	toast.add_theme_color_override("font_color", Color("fff6e5"))

func _style(background: String, border: String, radius: int, border_width := 2) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(background)
	box.border_color = Color(border)
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box

func _column(id: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = id.capitalize()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 16)
	%Content.add_child(column)
	_page_nodes[id] = column
	return column

func _text(parent: Node, text: String, font_size := 23, muted := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	if muted:
		label.add_theme_color_override("font_color", Color("6f5a49"))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

## Short labels in a row (counts, names, pills) must not wrap into one glyph per line.
func _nowrap(label: Label) -> Label:
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return label

func _action(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 78
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _card(parent: Node, background := "fffaf0", border := "e6d8bf") -> VBoxContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _style(background, border, 18))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)
	return column

func _bar(parent: Node, height := 14.0) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = height
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	return bar

func _row(parent: Node, separation := 12) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", separation)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	return row

func pill(label: Label, text: String, background: String, foreground: String) -> void:
	label.text = text
	var box := _style(background, background, 14, 0)
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	label.add_theme_stylebox_override("normal", box)
	label.add_theme_color_override("font_color", Color(foreground))

func _portrait(parent: Node, art: String, height: float) -> TextureRect:
	var portrait := TextureRect.new()
	portrait.texture = _portraits.get(art)
	portrait.custom_minimum_size = Vector2(height, height)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(portrait)
	return portrait

func _build_pages() -> void:
	var staff := _column("staff")
	_card_content = _row(staff)
	var details := _card(staff)
	var heading := _row(details, 10)
	_selected_name = _nowrap(_text(heading, "", 26))
	_selected_role = _nowrap(_text(heading, "", 19))
	_selected_role.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_selected_doing = _text(heading, "", 19, true)
	_selected_doing.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for stat in [["speed", "移速"], ["capacity", "搬量"], ["skill", "操作"]]:
		var line := _row(details, 12)
		var caption := _nowrap(_text(line, stat[1], 20))
		caption.custom_minimum_size.x = 52
		_stat_bars[stat[0]] = _bar(line, 16)
		_stat_numbers[stat[0]] = _nowrap(_text(line, "", 20))
		_stat_numbers[stat[0]].size_flags_horizontal = Control.SIZE_SHRINK_END
		_stat_numbers[stat[0]].custom_minimum_size.x = 56
		_stat_numbers[stat[0]].horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var actions := _row(staff)
	deploy_button = _action(actions, "派到店内", _view.toggle_deployment)
	train_button = _action(actions, "培养", _view.train_selected)
	for button in [deploy_button, train_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	train_button.add_theme_stylebox_override("normal", _style("8b6446", "8b6446", 15))
	train_button.add_theme_color_override("font_color", Color("fff8e9"))
	train_button.add_theme_color_override("font_hover_color", Color("583e2d"))
	staff_preview_button = _action(staff, "查看角色动作", func() -> void:
		for worker in _view.all_staff():
			if int(worker.id) == _view.selected_worker:
				open_character_preview(worker.art)
				break)
	_text(staff, "拖到工位 = 坐班，拖到柜台 = 前台接单，拖到空地 = 流动", 19, true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var recruit := _column("recruit")
	_text(recruit, "普通招募", 27)
	_recruit_portrait = _portrait(recruit, "raccoon", 154)
	_recruit_label = _text(recruit, "", 25)
	_recruit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hire_button = _action(recruit, "邀请伙伴", _view.hire_worker)
	var advanced := _card(recruit)
	_text(advanced, "高级招募", 25)
	_text(advanced, "尚未开放，更多伙伴敬请期待。", 21, true)
	var menu := _column("menu")
	character_preview_button = _action(menu, "角色预览", open_character_preview)
	pause_button = _action(menu, "暂停营业", func() -> void: _view.sim.paused = not _view.sim.paused; refresh())
	belt_button = _action(menu, "运输", _view.toggle_transport)
	save_button = _action(menu, "保存进度", func() -> void: _view.save_now())
	restart_button = _action(menu, "重新开始", open_page.bind("restart"))
	old_button = _action(menu, "进入旧版", _view.go_to_old_game)
	_save_caption = _text(menu, "", 20, true)
	var characters := _column("characters")
	character_preview = CharacterPreview.new()
	characters.add_child(character_preview)
	var restart_page := _column("restart")
	_text(restart_page, "重新开始这家店？", 28)
	_text(restart_page, "金币、设备与营业进度将重置。已拥有伙伴和培养等级会保留。", 24)
	confirm_restart_button = _action(restart_page, "确认重新开始", func() -> void: _view.restart(); open_page("shop"))
	cancel_restart_button = _action(restart_page, "继续经营", open_page.bind("menu"))
	var station_column := _column("station")
	station_panel = StationPanel.new()
	station_column.add_child(station_panel)
	station_panel.setup(_view, self)
	var goals := _column("goals")
	var current := _card(goals, "f6ead3", "d7bd97")
	_text(current, "当前目标", 19, true)
	_goal_title = _text(current, "", 27)
	var progress := _row(current)
	_goal_bar = _bar(progress, 20)
	_goal_value = _nowrap(_text(progress, "", 23))
	_goal_value.size_flags_horizontal = Control.SIZE_SHRINK_END
	_task_column = VBoxContainer.new()
	_task_column.add_theme_constant_override("separation", 10)
	goals.add_child(_task_column)
	var stats := _row(goals, 10)
	for stat in [["sold", "已售出"], ["revenue", "营业额"], ["shelf", "货架"]]:
		var cell := _card(stats)
		cell.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 2)
		_text(cell, stat[1], 18, true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_stat_values[stat[0]] = _text(cell, "", 25)
		_stat_values[stat[0]].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _rebuild_roster() -> void:
	for child in _card_content.get_children():
		child.free()
	_view._staff_cards.clear()
	_staff_titles.clear()
	_staff_tags.clear()
	_staff_portraits.clear()
	for worker in _view.all_staff():
		var card := Button.new()
		card.custom_minimum_size = Vector2(0, 214)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.focus_mode = Control.FOCUS_NONE
		card.set_meta("worker_id", int(worker.id))
		card.pressed.connect(_select_worker.bind(int(worker.id)))
		_card_content.add_child(card)
		var content := VBoxContainer.new()
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 8
		content.offset_right = -8
		content.offset_top = 10
		content.offset_bottom = -10
		content.add_theme_constant_override("separation", 6)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(content)
		_staff_portraits.append(_portrait(content, worker.art, 104))
		var label := _text(content, "", 21)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_staff_titles.append(label)
		var tag_row := CenterContainer.new()
		tag_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(tag_row)
		var tag := Label.new()
		tag.add_theme_font_size_override("font_size", 17)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag_row.add_child(tag)
		_staff_tags.append(tag)
		_view._staff_cards.append(card)
	_roster_signature = str(_view.all_staff().map(func(worker: Dictionary) -> int: return int(worker.id)))
	_styled_selection = -1
	_sheet_height = -1.0

func _select_worker(id: int) -> void:
	_view.selected_worker = id
	refresh()

func _status(worker: Dictionary) -> Array:
	if not _view.staff_is_deployed(int(worker.id)):
		return ["待派遣", "e5dfd2", "5d5548"]
	if worker.post.is_empty():
		return ["流动", "dcebcf", "3d5a2a"]
	if worker.post == "counter":
		return ["前台", "dfe8f6", "2f4a6b"]
	return ["坐班·" + POST_NAMES.get(worker.post, worker.post), "f3dfb8", "6b4a1c"]

func refresh() -> void:
	if _view == null or _view.sim == null:
		return
	var sim = _view.sim
	%Gold.text = str(sim.gold)
	speed_button.text = "×%d" % int(_view._speed_factor)
	_refresh_goal_bar(sim)
	var roster: Array = _view.all_staff()
	var signature := str(roster.map(func(worker: Dictionary) -> int: return int(worker.id)))
	if _roster_signature != signature:
		_rebuild_roster()
	if roster.is_empty():
		return
	var selected: Dictionary = roster[0]
	for i in roster.size():
		var worker: Dictionary = roster[i]
		var is_selected: bool = int(worker.id) == _view.selected_worker
		var status := _status(worker)
		_staff_titles[i].text = "%s Lv%d" % [NAMES[worker.art], worker.level]
		pill(_staff_tags[i], status[0], status[1], status[2])
		_staff_portraits[i].modulate = Color.WHITE if _view.staff_is_deployed(int(worker.id)) else Color(1, 1, 1, 0.55)
		if _styled_selection != _view.selected_worker:
			_view._staff_cards[i].add_theme_stylebox_override("normal", _style("f6e6c8" if is_selected else "fffaf0", "a47b50" if is_selected else "e6d8bf", 18))
		if is_selected:
			selected = worker
	_styled_selection = _view.selected_worker
	var task_text: String = Actor.TASKS.get(selected.task_label, selected.task_label)
	_selected_name.text = NAMES[selected.art]
	pill(_selected_role, ROLES[selected.role], "ead4b2", "583e2d")
	_selected_doing.text = "正在：" + task_text if _view.staff_is_deployed(int(selected.id)) else "在名册中待派遣"
	for stat in _stat_bars:
		_stat_bars[stat].value = clampf(float(selected[stat]) / STAT_MAX[stat], 0.04, 1.0)
	_stat_numbers.speed.text = str(int(selected.speed))
	_stat_numbers.capacity.text = str(int(selected.capacity))
	_stat_numbers.skill.text = "%.1f" % selected.skill
	deploy_button.visible = sim.has_method("deploy_worker")
	deploy_button.text = "收回到名册" if _view.staff_is_deployed(int(selected.id)) else "派到店内"
	deploy_button.disabled = false
	train_button.text = "培养 · %d 金币" % sim.train_cost(_view.selected_worker)
	train_button.disabled = sim.gold < sim.train_cost(_view.selected_worker)
	hire_button.disabled = sim.hire_cost() < 0 or sim.gold < sim.hire_cost()
	hire_button.text = "当前伙伴已集齐" if sim.hire_cost() < 0 else "邀请伙伴  ·  %d 金币" % sim.hire_cost()
	var next_art := "fox"
	for art in NAMES:
		if not roster.any(func(worker: Dictionary) -> bool: return worker.art == art):
			next_art = art
			break
	_recruit_portrait.texture = _portraits[next_art]
	var descriptions := {"raccoon": "浣熊 · 力量型\n擅长批量搬运", "fox": "狐狸 · 操作型\n擅长手工制作", "rabbit": "小兔子 · 速度型\n擅长快速搬运"}
	_recruit_label.text = "伙伴已全部加入" if sim.hire_cost() < 0 else descriptions.get(next_art, NAMES[next_art])
	pause_button.text = "继续营业" if sim.paused else "暂停营业"
	belt_button.text = "运输方式  ·  传送带" if sim.use_belts else "运输方式  ·  人工搬运"
	belt_button.visible = not sim.has_method("buy_belt")
	%Selection.visible = show_selection and page == "shop"
	$Selection/Row/Avatar.texture = _portraits[selected.art]
	$Selection/Row/Summary.text = "%s · Lv%d\n%s" % [NAMES[selected.art], selected.level, task_text]
	save_button.disabled = _view.store == null
	_save_caption.text = _view.save_status if _view.store != null else "独立练习不会覆盖经营存档"
	match page:
		"station": station_panel.refresh()
		"goals": _refresh_goals(sim)
		"staff": %Subtitle.text = "店内 %d / 3 · 拥有 %d 位" % [sim.workers.size(), roster.size()]
	_fit_sheet()

func _goal(sim) -> Dictionary:
	if sim.has_method("goal_progress"):
		return sim.goal_progress()
	return {"text": "已售出 %d 杯" % sim.sold, "current": 0, "target": 0}

func _refresh_goal_bar(sim) -> void:
	var goal := _goal(sim)
	%GoalText.text = goal.text if int(goal.target) <= 0 else "%s · %d / %d" % [goal.text, goal.current, goal.target]
	%GoalBar.visible = int(goal.target) > 0
	%GoalBar.value = clampf(float(goal.current) / maxf(1.0, float(goal.target)), 0, 1)

func _refresh_goals(sim) -> void:
	var goal := _goal(sim)
	_goal_title.text = goal.text
	_goal_bar.get_parent().visible = int(goal.target) > 0
	_goal_bar.value = clampf(float(goal.current) / maxf(1.0, float(goal.target)), 0, 1)
	_goal_value.text = "%d / %d" % [goal.current, goal.target]
	var rows: Array = sim.task_rows() if sim.has_method("task_rows") else []
	var signature := str(rows.map(func(row: Dictionary) -> String: return row.name))
	if signature != _task_signature:
		for child in _task_column.get_children():
			child.free()
		_task_rows.clear()
		if not rows.is_empty():
			_text(_task_column, "全部任务", 21)
		for row in rows:
			var card := _card(_task_column)
			var line := _row(card, 14)
			var check := Label.new()
			check.custom_minimum_size = Vector2(34, 34)
			check.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			check.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			check.add_theme_font_size_override("font_size", 20)
			check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_child(check)
			var body := VBoxContainer.new()
			body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			body.add_theme_constant_override("separation", 6)
			line.add_child(body)
			var name_label := _text(body, row.name, 22)
			var bar := _bar(body, 12)
			var count := _nowrap(_text(line, "", 21))
			count.size_flags_horizontal = Control.SIZE_SHRINK_END
			count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_task_rows.append({"check": check, "name": name_label, "bar": bar, "count": count})
		_task_signature = signature
		_sheet_height = -1.0
	for i in rows.size():
		var row: Dictionary = rows[i]
		var nodes: Dictionary = _task_rows[i]
		var done: bool = row.complete
		nodes.check.text = "✓" if done else ""
		nodes.check.add_theme_stylebox_override("normal", _style("4f8a3a" if done else "fffaf000", "4f8a3a" if done else "b38c62", 17, 2))
		nodes.check.add_theme_color_override("font_color", Color("fff8e9"))
		nodes.name.add_theme_color_override("font_color", Color("6f5a49" if done else "583e2d"))
		nodes.bar.visible = not done
		nodes.bar.value = clampf(float(row.current) / maxf(1.0, float(row.target)), 0, 1)
		nodes.count.text = "已完成" if done else "%d/%d" % [row.current, row.target]
	var limit: int = sim.shelf_limit() if sim.has_method("shelf_limit") else 3
	_stat_values.sold.text = "%d 杯" % sim.sold
	_stat_values.revenue.text = str(sim.revenue) if "revenue" in sim else "—"
	_stat_values.shelf.text = "%d / %d" % [sim.shelf_count, limit]

func open_station(id: String) -> void:
	if not _view.sim.has_method("station_info"):
		return
	station_panel.show_station(id)
	open_page("station")

func open_character_preview(art_id: String = "rabbit") -> void:
	open_page("characters")
	character_preview.select_character(art_id)

func open_page(next_page: String) -> void:
	if next_page != "shop" and not _page_nodes.has(next_page):
		return
	if is_instance_valid(_view._drag):
		_view._drag.cancel()
	page = next_page
	%Shade.visible = page != "shop"
	%Sheet.visible = page != "shop"
	%Title.text = PAGE_NAMES.get(page, "")
	%Pill.visible = false
	%Subtitle.text = ""
	%Scroll.scroll_vertical = 0
	for id in _page_nodes:
		_page_nodes[id].visible = id == page
	for pair in [[home_button, "shop"], [goals_button, "goals"], [staff_button, "staff"], [recruit_button, "recruit"]]:
		pair[0].add_theme_stylebox_override("normal", _style("ead4b2" if pair[1] == page else "fff5e2", "b38c62" if pair[1] == page else "fff5e2", 16))
	_sheet_height = -1.0
	refresh()
	# Wrapped labels report their final height only after the next layout pass.
	_fit_sheet.call_deferred()

## Called by the station panel so its title, level pill and summary sit in the sheet heading.
func set_heading(title: String, pill_text: String, pill_locked: bool, subtitle: String) -> void:
	%Title.text = title
	%Pill.visible = not pill_text.is_empty()
	pill(%Pill, pill_text, "e5dfd2" if pill_locked else "ead4b2", "6f6556" if pill_locked else "583e2d")
	%Subtitle.text = subtitle

## The sheet is as tall as its page, up to most of the screen, so the shop stays visible above short pages.
func _fit_sheet() -> void:
	if page == "shop" or _sheet_space == Vector2.ZERO:
		return
	var margin: MarginContainer = %Sheet.get_node("Margin")
	var chrome: float = 16.0 + %Heading.get_combined_minimum_size().y + margin.get_theme_constant("margin_top") + margin.get_theme_constant("margin_bottom") + 16.0
	var fraction := 0.85 if page == "characters" else 0.64
	var limit := maxf(300.0, minf(_sheet_space.y * fraction, _sheet_space.y - 122.0 - 130.0))
	var wanted := clampf(%Content.get_combined_minimum_size().y + chrome, 200.0, limit)
	if absf(wanted - _sheet_height) < 1.0:
		return
	_sheet_height = wanted
	%Sheet.offset_top = -122.0 - wanted

func begin_staff_drag() -> void:
	# Keep card nodes and the live gesture; only dismiss their visual panel.
	page = "shop"
	%Shade.hide()
	%Sheet.hide()
	show_selection = false
	refresh()

func blocks_world(screen: Vector2) -> bool:
	for control in [$Header, %Navigation, %Selection]:
		if control.is_visible_in_tree() and control.get_global_rect().has_point(screen):
			return true
	return page != "shop"

func card_hit_test(card: Button, screen: Vector2) -> bool:
	# A scrolled card remains visible in the tree even where the viewport clips it.
	return page == "staff" and card.is_visible_in_tree() and not card.disabled \
		and %Scroll.get_global_rect().has_point(screen) and card.get_global_rect().has_point(screen)

func fit_to_size(available: Vector2) -> void:
	size = available
	if available != _sheet_space:
		_sheet_space = available
		_sheet_height = -1.0
		_fit_sheet()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if page != "shop":
			open_page("shop")
		else:
			show_selection = false
			refresh()
		get_viewport().set_input_as_handled()
