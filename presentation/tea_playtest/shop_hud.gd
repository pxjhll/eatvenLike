extends Control
## UI composition and session binding; prices and staff always come from the sim.

const Actor := preload("res://presentation/tea_playtest/staff_actor.gd")
const StationPanel := preload("res://presentation/tea_playtest/station_panel.gd")
const Characters := preload("res://presentation/characters/character_library.gd")
const CharacterPreview := preload("res://presentation/characters/character_preview.gd")
const ReferenceTheme := preload("res://presentation/ui/reference_theme.gd")
const Icons := preload("res://presentation/ui/reference_icons.gd")
const NAMES := Characters.NAMES
const ROLES := {"speed": "速度型", "carry": "力量型", "skill": "操作型"}
const PAGE_NAMES := {"staff": "员工", "menu": "菜单", "restart": "重开店铺", "station": "设备", "goals": "目标", "characters": "角色预览"}
const POST_NAMES := {"boil": "煮茶", "topping": "加料", "counter": "前台"}
## Stat bars are scaled against the best value a fully trained partner can reach.
const STAT_MAX := {"speed": 220.0, "capacity": 6.0, "skill": 3.0}
const COIN := preload("res://art/ui/coin.png")
var _bottleneck_button: Button

var page := "shop"
var show_selection := false
var _view: Node2D
var _portraits := {}
var _staff_titles: Array[Label] = []
var _staff_tags: Array[Label] = []
var _staff_portraits: Array[TextureRect] = []
## Hiring sits at the top of the staff page: one tap hires and puts the new partner straight to work.
var _recruit_label: Label
var _recruit_portrait: TextureRect
var _styled_selection := -1
var _card_content: GridContainer
var _page_nodes := {}
var _roster_signature := ""
var _save_caption: Label
var _menu_footer: HBoxContainer
var _heading_icon: TextureRect
var _selected_portrait: TextureRect
var _goal_icon: TextureRect
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
@onready var menu_button: Button = %Menu
@onready var close_button: Button = %Close
@onready var speed_button: Button = %Speed
@onready var goal_button: Button = %Goal
@onready var toast: Label = %Toast
var hire_button: Button
var train_button: Button
## Tea shop: the front and kitchen upgrade lists (train_button shows the front list there).
var kitchen_upgrade_button: Button
var pause_button: Button
var belt_button: Button
var restart_button: Button
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
	for entry in [[home_button, "shop"], [goals_button, "goals"], [staff_button, "staff"]]:
		entry[0].pressed.connect(open_page.bind(entry[1]))
		entry[0].icon = Icons.texture(entry[1])
		entry[0].expand_icon = true
		entry[0].add_theme_constant_override("icon_max_width", 68)
		entry[0].add_theme_constant_override("h_separation", 14)
		entry[0].add_theme_font_size_override("font_size", 32)
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
	theme = ReferenceTheme.make_theme()
	var header_style := ReferenceTheme.style("header", 22)
	header_style.set_content_margin_all(0)
	$Header.add_theme_stylebox_override("panel", header_style)
	var navigation_style := ReferenceTheme.style("wood", 20)
	navigation_style.set_content_margin_all(0)
	%Navigation.add_theme_stylebox_override("panel", navigation_style)
	%Coin.texture = COIN
	_bottleneck_button = Button.new()
	_bottleneck_button.name = "BottleneckHint"
	_bottleneck_button.position = Vector2(74, 112)
	_bottleneck_button.custom_minimum_size = Vector2(332, 48)
	_bottleneck_button.add_theme_font_size_override("font_size", 21)
	_bottleneck_button.add_theme_constant_override("icon_max_width", 29)
	_bottleneck_button.expand_icon = true
	_bottleneck_button.focus_mode = Control.FOCUS_NONE
	_button_style(_bottleneck_button, "cream", 18)
	_bottleneck_button.pressed.connect(func() -> void:
		var hint: Dictionary = _view.sim.bottleneck_hint() if _view.sim.has_method("bottleneck_hint") else {}
		var target: String = hint.get("target", "")
		if target.begins_with("staff_"): open_page("staff")
		elif not target.is_empty(): open_station(target))
	add_child(_bottleneck_button)
	move_child(_bottleneck_button, $Header.get_index() + 1)
	_bottleneck_button.hide()
	var divider := VSeparator.new()
	var divider_line := StyleBoxLine.new()
	divider_line.color = Color("cb9a6d")
	divider_line.thickness = 2
	divider_line.vertical = true
	divider.add_theme_stylebox_override("separator", divider_line)
	divider.custom_minimum_size.y = 52
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	$Header/Margin/Row.add_child(divider)
	$Header/Margin/Row.move_child(divider, 2)
	var flat := StyleBoxEmpty.new()
	for state in ["normal", "hover", "focus", "disabled"]:
		goal_button.add_theme_stylebox_override(state, flat)
	goal_button.add_theme_stylebox_override("pressed", _style("ead4b2", "ead4b2", 12, 0))
	var sheet_style := ReferenceTheme.style("paper", 28)
	sheet_style.set_content_margin_all(0)
	%Sheet.add_theme_stylebox_override("panel", sheet_style)
	_heading_icon = TextureRect.new()
	_heading_icon.custom_minimum_size = Vector2(42, 42)
	_heading_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_heading_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_heading_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	%Heading.add_child(_heading_icon)
	%Heading.move_child(_heading_icon, 0)
	for button in [menu_button, speed_button, close_button]:
		_button_style(button, "cream")
	var toast_style := _style("624831e6", "624831", 22, 0)
	toast_style.content_margin_left = 22
	toast_style.content_margin_right = 22
	toast.add_theme_stylebox_override("normal", toast_style)
	toast.add_theme_color_override("font_color", Color("fff6e5"))

func _button_style(button: Button, kind: String, radius := 16.0) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, ReferenceTheme.style(kind, radius, state))

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
	column.add_theme_constant_override("separation", 12)
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
	button.custom_minimum_size.y = 60
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 24)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		button.add_theme_color_override(state, Color.WHITE)
	button.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.5))
	parent.add_child(button)
	return button

func _card(parent: Node, background := "fffaf0", border := "e6d8bf") -> VBoxContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", ReferenceTheme.style("card", 18))
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
	staff.add_theme_constant_override("separation", 16)
	var recruit := _card(staff, "f6ead3", "d7bd97")
	var recruit_line := _row(recruit, 12)
	_recruit_portrait = _portrait(recruit_line, "raccoon", 96)
	_recruit_label = _text(recruit_line, "", 24)
	_recruit_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hire_button = _action(recruit_line, "招一位", _view.hire_worker)
	hire_button.custom_minimum_size = Vector2(204, 54)
	hire_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_button_style(hire_button, "gold")
	# Reference roster: three horizontal portrait-and-status cards per row.
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	staff.add_child(grid)
	_card_content = grid
	var details := _card(staff)
	var detail_row := _row(details, 18)
	_selected_portrait = _portrait(detail_row, "cat", 172)
	var detail_body := VBoxContainer.new()
	detail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_body.add_theme_constant_override("separation", 7)
	detail_row.add_child(detail_body)
	var heading := _row(detail_body, 10)
	_selected_name = _nowrap(_text(heading, "", 26))
	_selected_role = _nowrap(_text(heading, "", 17))
	_selected_role.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_selected_doing = _text(detail_body, "", 17, true)
	_selected_doing.visible = false
	for stat in [["speed", "移速"], ["capacity", "搬量"], ["skill", "操作"]]:
		var line := _row(detail_body, 10)
		var caption := _nowrap(_text(line, stat[1], 22))
		caption.custom_minimum_size.x = 52
		_stat_bars[stat[0]] = _bar(line, 18)
		_stat_numbers[stat[0]] = _nowrap(_text(line, "", 17))
		_stat_numbers[stat[0]].size_flags_horizontal = Control.SIZE_SHRINK_END
		_stat_numbers[stat[0]].custom_minimum_size.x = 34
		_stat_numbers[stat[0]].horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var actions := _row(staff, 9)
	deploy_button = _action(actions, "派到店内", _view.toggle_deployment)
	train_button = _action(actions, "培养", _view.train_selected)
	kitchen_upgrade_button = _action(actions, "后厨升级", func() -> void: _view.buy_staff_upgrade("kitchen"))
	staff_preview_button = _action(actions, "查看角色动作", func() -> void:
		for worker in _view.all_staff():
			if int(worker.id) == _view.selected_worker:
				open_character_preview(worker.art)
				break)
	for button in [deploy_button, train_button, kitchen_upgrade_button, staff_preview_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 64
		button.add_theme_font_size_override("font_size", 18 if button in [train_button, kitchen_upgrade_button] else 21)
		button.add_theme_constant_override("icon_max_width", 17)
		button.add_theme_constant_override("h_separation", 3)
		_button_style(button, "gold" if button in [train_button, kitchen_upgrade_button] else "cream", 14)
	var drag_hint := _text(staff, "───  拖动员工到工位  ───", 20, true)
	drag_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drag_hint.tooltip_text = "拖到柜台 = 前台（接待客人）；拖到工位或空地 = 后厨"
	var menu := _column("menu")
	character_preview_button = _menu_action(menu, "角色预览", "hat", open_character_preview)
	pause_button = _menu_action(menu, "暂停营业", "pause", func() -> void: _view.sim.paused = not _view.sim.paused; refresh())
	save_button = _menu_action(menu, "保存进度", "save", func() -> void: _view.save_now())
	belt_button = _menu_action(menu, "运输方式", "shop", _view.toggle_transport)
	restart_button = _menu_action(menu, "重新开始", "trash", open_page.bind("restart"))
	_button_style(restart_button, "danger", 18)
	restart_button.add_theme_color_override("font_color", Color("8e311a"))
	_menu_footer = _row(menu, 12)
	_save_caption = _text(_menu_footer, "", 19, true)
	_save_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_save_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var characters := _column("characters")
	character_preview = CharacterPreview.new()
	characters.add_child(character_preview)
	var restart_page := _column("restart")
	restart_page.add_theme_constant_override("separation", 22)
	_text(restart_page, "重新开始这家店？", 36).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var separator := HSeparator.new()
	restart_page.add_child(separator)
	_text(restart_page, "金币、设备与营业进度将重置\n已拥有伙伴和培养等级会保留", 25).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var restart_actions := _row(restart_page, 22)
	cancel_restart_button = _action(restart_actions, "继续经营", open_page.bind("menu"))
	confirm_restart_button = _action(restart_actions, "确认重新开始", func() -> void: _view.restart(); open_page("shop"))
	for button in [cancel_restart_button, confirm_restart_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 74
		button.add_theme_font_size_override("font_size", 28)
	_button_style(confirm_restart_button, "danger", 22)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var danger := ReferenceTheme.style("danger", 22, state)
		if state != "disabled":
			danger.set("bg_color", Color("df916e") if state == "hover" else Color("cf7b59") if state == "pressed" else Color("d48664"))
			danger.set("face_bottom", Color("c66d4d") if state == "hover" else Color("af5135") if state == "pressed" else Color("bb5d40"))
			danger.set("contour", Color("8f482e"))
			danger.set("depth_color", Color("8b432a"))
			danger.set("highlight", Color("f5b78e"))
		confirm_restart_button.add_theme_stylebox_override(state, danger)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		confirm_restart_button.add_theme_color_override(state, Color("fff6e7"))
	var station_column := _column("station")
	station_panel = StationPanel.new()
	station_column.add_child(station_panel)
	station_panel.setup(_view, self)
	var goals := _column("goals")
	var current := _card(goals, "f6ead3", "d7bd97")
	var current_row := _row(current, 18)
	_goal_icon = _portrait(current_row, "cat", 100)
	_goal_icon.texture = Icons.texture("seal")
	var current_body := VBoxContainer.new()
	current_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	current_body.add_theme_constant_override("separation", 5)
	current_row.add_child(current_body)
	var current_pill := _nowrap(_text(current_body, "当前目标", 20, true))
	pill(current_pill, "当前目标", "f9e1b8", "714425")
	_goal_title = _text(current_body, "", 26)
	var progress := _row(current_body)
	_goal_bar = _bar(progress, 20)
	_goal_value = _nowrap(_text(progress, "", 22))
	_goal_value.size_flags_horizontal = Control.SIZE_SHRINK_END
	var task_panel := PanelContainer.new()
	task_panel.add_theme_stylebox_override("panel", ReferenceTheme.style("card", 18))
	goals.add_child(task_panel)
	var task_scroll := ScrollContainer.new()
	task_scroll.custom_minimum_size.y = 168
	task_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	task_panel.add_child(task_scroll)
	_task_column = VBoxContainer.new()
	_task_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_task_column.add_theme_constant_override("separation", 4)
	task_scroll.add_child(_task_column)
	var stats := _row(goals, 10)
	for stat in [["sold", "已售出"], ["revenue", "营业额"], ["shelf", "货架"]]:
		var cell := _card(stats)
		cell.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var stat_line := _row(cell, 6)
		var icon := _portrait(stat_line, "cat", 29)
		icon.texture = Icons.texture("coin" if stat[0] == "revenue" else "drink_lemonade" if stat[0] == "sold" else "shelf")
		_nowrap(_text(stat_line, stat[1], 21, true))
		_stat_values[stat[0]] = _nowrap(_text(stat_line, "", 23))
		_stat_values[stat[0]].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_stat_values[stat[0]].horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func _menu_action(parent: Node, caption: String, icon: String, callback: Callable) -> Button:
	var button := _action(parent, caption, callback)
	button.set_meta("semantic_icon", icon)
	button.icon = Icons.texture(icon)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_constant_override("icon_max_width", 46)
	button.add_theme_constant_override("h_separation", 22)
	button.add_theme_font_size_override("font_size", 27)
	button.custom_minimum_size.y = 66
	_button_style(button, "card", 18)
	var arrow := TextureRect.new()
	arrow.texture = Icons.texture("arrow_right")
	arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	arrow.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	arrow.position = Vector2(-42, -15)
	arrow.size = Vector2(28, 30)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(arrow)
	return button

func _rebuild_roster() -> void:
	for child in _card_content.get_children():
		child.free()
	_view._staff_cards.clear()
	_staff_titles.clear()
	_staff_tags.clear()
	_staff_portraits.clear()
	for worker in _view.all_staff():
		var card := Button.new()
		card.custom_minimum_size = Vector2(0, 170)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.focus_mode = Control.FOCUS_NONE
		card.set_meta("worker_id", int(worker.id))
		card.pressed.connect(_select_worker.bind(int(worker.id)))
		_card_content.add_child(card)
		var content := HBoxContainer.new()
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 6
		content.offset_right = -6
		content.offset_top = 10
		content.offset_bottom = -10
		content.add_theme_constant_override("separation", 4)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(content)
		_staff_portraits.append(_portrait(content, worker.art, 112))
		var body := VBoxContainer.new()
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_theme_constant_override("separation", 8)
		content.add_child(body)
		var label := _text(body, "", 23)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_staff_titles.append(label)
		var tag_row := HBoxContainer.new()
		tag_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(tag_row)
		var tag := Label.new()
		tag.add_theme_font_size_override("font_size", 17)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag_row.add_child(tag)
		_staff_tags.append(tag)
		var badge := TextureRect.new()
		badge.name = "SelectedBadge"
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.texture = Icons.texture("selected_check")
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(badge)
		badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		badge.offset_left = -42
		badge.offset_top = -10
		badge.offset_right = 2
		badge.offset_bottom = 34
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
		return ["流动", "f9e8cc", "784a29"]
	if worker.post == "counter":
		return ["前台", "f9e8cc", "784a29"]
	return [POST_NAMES.get(worker.post, worker.post), "f3dfb8", "6b4a1c"]

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
		_staff_titles[i].text = _staff_name(worker, roster)
		_view._staff_cards[i].tooltip_text = "%s · Lv%d · %s" % [_staff_name(worker, roster), worker.level, ROLES[worker.role]]
		pill(_staff_tags[i], status[0], status[1], status[2])
		_staff_portraits[i].modulate = Color.WHITE if _view.staff_is_deployed(int(worker.id)) else Color(1, 1, 1, 0.55)
		if _styled_selection != _view.selected_worker:
			for state in ["normal", "hover", "pressed", "disabled", "focus"]:
				var skin_state: String = "selected" if is_selected and state in ["normal", "hover"] else state
				_view._staff_cards[i].add_theme_stylebox_override(state, ReferenceTheme.style("card", 18, skin_state))
		_view._staff_cards[i].get_node("SelectedBadge").visible = is_selected
		if is_selected:
			selected = worker
	_styled_selection = _view.selected_worker
	var task_text: String = Actor.TASKS.get(selected.task_label, selected.task_label)
	_selected_name.text = _staff_name(selected, roster)
	_selected_portrait.texture = _portraits[selected.art]
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
	kitchen_upgrade_button.visible = sim.has_method("buy_staff_upgrade")
	if sim.has_method("buy_staff_upgrade"):
		for side in ["front", "kitchen"]:
			var button: Button = train_button if side == "front" else kitchen_upgrade_button
			var info: Dictionary = sim.staff_upgrade_info(side)
			var title: String = "前台" if side == "front" else "后厨"
			button.text = ("%s已满级" % title) if info.cost < 0 else "%s升级 · %d 金币\n%s" % [title, int(info.cost), info.name]
			button.tooltip_text = ("%s升级已买完" % title) if info.cost < 0 else "%s %d/%d：%s · %d 金币" % [title, int(info.bought) + 1, int(info.total), info.name, int(info.cost)]
			button.disabled = info.cost < 0 or sim.gold < int(info.cost)
	else:
		var train_cost: int = sim.train_cost(_view.selected_worker)
		train_button.text = "已满级" if train_cost < 0 else "培养 Lv%d\n%d 金币" % [int(selected.level) + 1, train_cost]
		train_button.tooltip_text = "已满级" if train_cost < 0 else "培养 Lv%d · %d 金币" % [int(selected.level) + 1, train_cost]
		train_button.disabled = train_cost < 0 or sim.gold < train_cost
	var room := has_staff_room()
	hire_button.disabled = sim.hire_cost() < 0 or sim.gold < sim.hire_cost() or not room
	hire_button.text = "暂无空位" if not room else "招募 · %d 金币" % sim.hire_cost()
	var next_art := "fox"
	if sim.has_method("next_hire_art"):
		next_art = sim.next_hire_art()
	else:
		for art in NAMES:
			if not roster.any(func(worker: Dictionary) -> bool: return worker.art == art):
				next_art = art
				break
	_recruit_portrait.texture = _portraits[next_art]
	var descriptions := {"cat": "小猫 · 速度型\n跑得快的多面手", "raccoon": "浣熊 · 力量型\n擅长批量搬运", "fox": "狐狸 · 操作型\n擅长手工制作", "rabbit": "小兔子 · 速度型\n擅长快速搬运", "gray_cat": "小灰猫 · 速度型\n跑得快的多面手", "bear": "小熊 · 力量型\n擅长批量搬运"}
	_recruit_label.text = String(descriptions.get(next_art, NAMES[next_art])).get_slice("\n", 0)
	_recruit_label.tooltip_text = "招来直接上岗" if room else "解锁新设备后有更多空位"
	pause_button.text = "继续营业" if sim.paused else "暂停营业"
	belt_button.text = "运输方式  ·  传送带" if sim.use_belts else "运输方式  ·  人工搬运"
	belt_button.visible = not sim.has_method("buy_belt")
	%Selection.visible = show_selection and page == "shop"
	$Selection/Row/Avatar.texture = _portraits[selected.art]
	$Selection/Row/Summary.text = "%s · Lv%d\n%s" % [_staff_name(selected, roster), selected.level, task_text]
	save_button.disabled = _view.store == null
	_save_caption.text = _view.save_status if _view.store != null else "独立练习不会覆盖经营存档"
	match page:
		"station": station_panel.refresh()
		"goals": _refresh_goals(sim)
		"staff": %Subtitle.text = ("前台 %d/%d · 后厨 %d/%d" % [sim.front_staff(), sim.front_slots(), sim.kitchen_staff(), sim.kitchen_slots()]) if sim.has_method("front_slots") else "店内 %d / %d" % [sim.workers.size(), sim.staff_slots() if sim.has_method("staff_slots") else 3]
	_fit_sheet()

## A hire goes straight to work, so hiring only makes sense while the shop has an open spot.
func has_staff_room() -> bool:
	var sim = _view.sim
	if not sim.has_method("staff_slots"): return true
	return sim.workers.size() < sim.staff_slots()

## Something on the staff page can be bought right now (drives the red ↑ on the 员工 tab).
func staff_affordable() -> bool:
	var sim = _view.sim
	if sim.hire_cost() >= 0 and sim.gold >= sim.hire_cost() and has_staff_room(): return true
	if sim.has_method("staff_upgrade_info"):
		for side in ["front", "kitchen"]:
			var info: Dictionary = sim.staff_upgrade_info(side)
			if int(info.cost) >= 0 and sim.gold >= int(info.cost): return true
	return false

## A second fox reads 狐狸 2, so cards of the same animal can be told apart.
func _staff_name(worker: Dictionary, roster: Array) -> String:
	var same: Array = roster.filter(func(other: Dictionary) -> bool: return other.art == worker.art)
	if same.size() < 2: return NAMES[worker.art]
	return "%s %d" % [NAMES[worker.art], same.find(worker) + 1]

func _goal(sim) -> Dictionary:
	if sim.has_method("goal_progress"):
		return sim.goal_progress()
	return {"text": "已售出 %d 杯" % sim.sold, "current": 0, "target": 0}

func _refresh_goal_bar(sim) -> void:
	var goal := _goal(sim)
	var hint: Dictionary = sim.bottleneck_hint() if sim.has_method("bottleneck_hint") else {}
	_bottleneck_button.visible = not hint.is_empty()
	if not hint.is_empty():
		_bottleneck_button.text = String(hint.short).replace("排长队", "排队").replace("升级", "看") + " ›"
		_bottleneck_button.tooltip_text = hint.text
		var drink_icon := "drink_black_tea"
		if sim.has_method("dish_name"):
			for dish in sim.DISHES:
				if sim.dish_name(dish) == hint.drink:
					drink_icon = "drink_" + dish
					break
		_bottleneck_button.icon = Icons.texture(drink_icon)
	%GoalText.text = goal.text if int(goal.target) <= 0 else "%s · %d / %d" % [goal.text, goal.current, goal.target]
	%GoalBar.visible = int(goal.target) > 0
	%GoalBar.value = clampf(float(goal.current) / maxf(1.0, float(goal.target)), 0, 1)

func _refresh_goals(sim) -> void:
	var goal := _goal(sim)
	_goal_title.text = goal.text
	var icon_key := "goals"
	if sim.has_method("station_unlocked"):
		for machine in ["lemonade", "boil", "seal", "mix", "press", "topping"]:
			if not sim.station_unlocked(machine):
				icon_key = "mix" if machine in ["press", "topping"] else machine
				break
		if sim.has_method("pending_box") and not String(sim.pending_box()).is_empty():
			icon_key = sim.pending_box()
	_goal_icon.texture = Icons.texture(icon_key)
	_goal_bar.get_parent().visible = int(goal.target) > 0
	_goal_bar.value = clampf(float(goal.current) / maxf(1.0, float(goal.target)), 0, 1)
	_goal_value.text = "%d / %d" % [goal.current, goal.target]
	var rows: Array = sim.task_rows() if sim.has_method("task_rows") else []
	var signature := str(rows.map(func(row: Dictionary) -> String: return row.name))
	if signature != _task_signature:
		for child in _task_column.get_children():
			child.free()
		_task_rows.clear()
		for row in rows:
			if _task_rows.size() > 0:
				var separator := HSeparator.new()
				_task_column.add_child(separator)
			var line := _row(_task_column, 10)
			line.custom_minimum_size.y = 42
			var check := Label.new()
			check.custom_minimum_size = Vector2(30, 30)
			check.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			check.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			check.add_theme_font_size_override("font_size", 20)
			check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_child(check)
			var name_label := _text(line, row.name, 22)
			name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
			name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			name_label.custom_minimum_size.x = 255
			name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var bar := _bar(line, 15)
			bar.custom_minimum_size.x = 110
			var count := _nowrap(_text(line, "", 21))
			count.custom_minimum_size.x = 75
			count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
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
		nodes.check.add_theme_stylebox_override("normal", _style("93b94a" if done else "ffe7be", "5f7e2d" if done else "996534", 8, 2))
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
	%Shade.color.a = 0.34
	%Sheet.visible = page != "shop"
	%Title.text = PAGE_NAMES.get(page, "")
	%Title.add_theme_font_size_override("font_size", 44 if page == "staff" else 34)
	_heading_icon.custom_minimum_size = Vector2(60, 60) if page == "staff" else Vector2(42, 42)
	%Subtitle.add_theme_font_size_override("font_size", 24 if page == "staff" else 19)
	_heading_icon.texture = Icons.texture("staff" if page == "staff" else "goals" if page == "goals" else "hat")
	_heading_icon.visible = page in ["staff", "goals", "characters", "station"]
	%Title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if page in ["menu", "restart"] else HORIZONTAL_ALIGNMENT_LEFT
	%Title.size_flags_horizontal = Control.SIZE_EXPAND_FILL if page in ["menu", "restart"] else Control.SIZE_SHRINK_BEGIN
	%Heading.alignment = BoxContainer.ALIGNMENT_CENTER if page == "restart" else BoxContainer.ALIGNMENT_BEGIN
	%Title.remove_theme_stylebox_override("normal")
	if page == "restart":
		%Title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var plaque := ReferenceTheme.style("cream", 28)
		plaque.content_margin_left = 34
		plaque.content_margin_right = 34
		%Title.add_theme_stylebox_override("normal", plaque)
	%Subtitle.visible = page not in ["menu", "restart"]
	close_button.visible = page != "restart"
	%Pill.visible = false
	%Subtitle.text = ""
	%Scroll.scroll_vertical = 0
	for id in _page_nodes:
		_page_nodes[id].visible = id == page
	var selected_tab := page if page in ["staff", "goals"] else "shop"
	for pair in [[home_button, "shop"], [goals_button, "goals"], [staff_button, "staff"]]:
		_button_style(pair[0], "gold" if pair[1] == selected_tab else "cream", 18)
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
	var chrome: float = %Heading.get_combined_minimum_size().y + margin.get_theme_constant("margin_top") + margin.get_theme_constant("margin_bottom") + 16.0
	var fraction := 0.85 if page == "characters" else 0.64
	var bottom := 78.0 if page == "staff" else 112.0
	%Sheet.offset_bottom = -bottom
	var limit := maxf(300.0, minf(_sheet_space.y * fraction, _sheet_space.y - bottom - 130.0))
	var wanted := clampf(%Content.get_combined_minimum_size().y + chrome, 200.0, limit)
	if absf(wanted - _sheet_height) < 1.0:
		return
	_sheet_height = wanted
	%Sheet.offset_top = -bottom - wanted

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
