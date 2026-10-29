extends Control
## UI composition and session binding; prices and staff always come from the sim.

const Actor := preload("res://presentation/tea_playtest/staff_actor.gd")
const StationPanel := preload("res://presentation/tea_playtest/station_panel.gd")
const NAMES := {"cat": "小猫", "raccoon": "浣熊", "fox": "狐狸"}
const ROLES := {"speed": "速度型", "carry": "力量型", "skill": "操作型"}
const PAGE_NAMES := {"staff": "员工伙伴", "recruit": "招募伙伴", "build": "店铺建设", "menu": "店铺菜单", "restart": "重开店铺", "station": "设备详情", "tasks": "经营目标"}
var page := "shop"
var show_selection := false
var _view: Node2D
var _roster_size := -1
var _portraits := {}
var _staff_titles: Array[Label] = []
var _details: Label
var _roster_label: Label
var _recruit_label: Label
var _recruit_portrait: TextureRect
var _styled_selection := -1
var _card_content: HBoxContainer
var _page_nodes := {}
var _roster_signature := ""
var _save_caption: Label
var _task_labels: Array[Label] = []
var _task_signature := ""
var _task_column: VBoxContainer
var _goal_label: Label

@onready var home_button: Button = %Home
@onready var build_button: Button = %Build
@onready var staff_button: Button = %Staff
@onready var recruit_button: Button = %Recruit
@onready var menu_button: Button = %Menu
@onready var close_button: Button = %Close
@onready var speed_button: Button = %Speed
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
var tasks_button: Button
var station_panel: VBoxContainer

func setup(view: Node2D) -> void:
	_view = view
	_apply_theme()
	for key in NAMES:
		_portraits[key] = load("res://art/reference/" + key + ".png")
	for entry in [[home_button, "shop"], [build_button, "build"], [staff_button, "staff"], [recruit_button, "recruit"]]:
		entry[0].pressed.connect(open_page.bind(entry[1]))
		entry[0].icon = load("res://art/ui/shop/" + entry[1] + ".svg")
		entry[0].expand_icon = true
		entry[0].add_theme_constant_override("icon_max_width", 30)
		entry[0].add_theme_constant_override("h_separation", 9)
	menu_button.pressed.connect(open_page.bind("menu"))
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
	move_child(%Toast, get_child_count() - 1)
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
	theme = ui_theme
	var header_style := _style("fff5e2f2", "b38c62", 22)
	header_style.set_content_margin_all(0)
	$Header.add_theme_stylebox_override("panel", header_style)
	%Sheet.add_theme_stylebox_override("panel", _style("fff5e2", "a98159", 26))
	%Toast.add_theme_color_override("font_color", Color("fff6e5"))
	%Toast.add_theme_color_override("font_outline_color", Color("624831"))
	%Toast.add_theme_constant_override("outline_size", 6)

func _style(background: String, border: String, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(background)
	box.border_color = Color(border)
	box.set_border_width_all(2)
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
	column.add_theme_constant_override("separation", 20)
	%Content.add_child(column)
	_page_nodes[id] = column
	return column

func _text(parent: Node, text: String, font_size := 23) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _action(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 78
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

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
	_roster_label = _text(staff, "")
	_card_content = HBoxContainer.new()
	_card_content.add_theme_constant_override("separation", 12)
	staff.add_child(_card_content)
	_details = _text(staff, "", 24)
	deploy_button = _action(staff, "派到店内", _view.toggle_deployment)
	train_button = _action(staff, "培养", _view.train_selected)
	_action(staff, "回到店铺安排岗位", func() -> void: show_selection = true; open_page("shop"))
	_text(staff, "按住伙伴卡拖到工位坐班，拖到空地恢复流动。", 20)
	var recruit := _column("recruit")
	_text(recruit, "普通招募", 27)
	_recruit_portrait = _portrait(recruit, "raccoon", 154)
	_recruit_label = _text(recruit, "", 25)
	_recruit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hire_button = _action(recruit, "邀请伙伴", _view.hire_worker)
	var advanced := PanelContainer.new()
	recruit.add_child(advanced)
	var advanced_column := VBoxContainer.new()
	advanced_column.add_theme_constant_override("separation", 10)
	advanced.add_child(advanced_column)
	_text(advanced_column, "高级招募", 25)
	_text(advanced_column, "尚未开放", 21)
	_text(advanced_column, "更多伙伴，敬请期待。", 21)
	var build := _column("build")
	_text(build, "布置你的奶茶小店", 28)
	var options := HBoxContainer.new()
	options.add_theme_constant_override("separation", 12)
	build.add_child(options)
	for caption in ["机器", "传送带", "布局"]:
		var button := _action(options, caption, func() -> void: pass)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = true
	var illustration := TextureRect.new()
	illustration.texture = load("res://art/reference/brewer.png")
	illustration.custom_minimum_size.y = 210
	illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	build.add_child(illustration)
	_text(build, "建设功能尚未开放", 27).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text(build, "机器、传送带与店铺布局将在这里管理。", 23).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var menu := _column("menu")
	_text(menu, "营业设置", 26)
	pause_button = _action(menu, "暂停营业", func() -> void: _view.sim.paused = not _view.sim.paused; refresh())
	belt_button = _action(menu, "运输", _view.toggle_transport)
	save_button = _action(menu, "保存进度", func() -> void: _view.save_now())
	tasks_button = _action(menu, "经营目标", open_page.bind("tasks"))
	restart_button = _action(menu, "重新开始", open_page.bind("restart"))
	old_button = _action(menu, "进入旧版", _view.go_to_old_game)
	_save_caption = _text(menu, "", 20)
	var restart_page := _column("restart")
	_text(restart_page, "重新开始这家店？", 28)
	_text(restart_page, "金币、设备与营业进度将重置。已拥有伙伴和培养等级会保留。", 24)
	confirm_restart_button = _action(restart_page, "确认重新开始", func() -> void: _view.restart(); open_page("shop"))
	cancel_restart_button = _action(restart_page, "继续经营", open_page.bind("menu"))
	var station_column := _column("station")
	station_panel = StationPanel.new()
	station_column.add_child(station_panel)
	station_panel.setup(_view)
	var tasks := _column("tasks")
	_goal_label = _text(tasks, "", 26)
	_task_column = VBoxContainer.new()
	_task_column.add_theme_constant_override("separation", 20)
	tasks.add_child(_task_column)

func _rebuild_roster() -> void:
	for child in _card_content.get_children():
		child.free()
	_view._staff_cards.clear()
	_staff_titles.clear()
	for worker in _view.all_staff():
		var card := Button.new()
		card.custom_minimum_size = Vector2(0, 224)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.focus_mode = Control.FOCUS_NONE
		card.set_meta("worker_id", int(worker.id))
		card.pressed.connect(_select_worker.bind(int(worker.id)))
		_card_content.add_child(card)
		var content := VBoxContainer.new()
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 10
		content.offset_right = -10
		content.offset_top = 12
		content.offset_bottom = -12
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(content)
		_portrait(content, worker.art, 118)
		var label := _text(content, "", 22)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_staff_titles.append(label)
		_view._staff_cards.append(card)
	_roster_size = _view.all_staff().size()
	_roster_signature = str(_view.all_staff().map(func(worker: Dictionary) -> int: return int(worker.id)))
	_styled_selection = -1

func _select_worker(id: int) -> void:
	_view.selected_worker = id
	refresh()

func refresh() -> void:
	if _view == null or _view.sim == null:
		return
	var sim = _view.sim
	%Gold.text = "金币 %d" % sim.gold
	%Sold.text = "%d 杯" % sim.sold
	speed_button.text = "×%d" % int(_view._speed_factor)
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
		var mode := "流动" if worker.post.is_empty() else ("煮茶坐班" if worker.post == "boil" else "加料坐班")
		if not _view.staff_is_deployed(int(worker.id)):
			mode = "待派遣"
		_staff_titles[i].text = "%s Lv%d\n%s" % [NAMES[worker.art], worker.level, mode]
		if _styled_selection != _view.selected_worker:
			_view._staff_cards[i].add_theme_stylebox_override("normal", _style("f6e6c8" if is_selected else "fff9ed", "a47b50" if is_selected else "e6d8bf", 18))
		if is_selected:
			selected = worker
	_styled_selection = _view.selected_worker
	_roster_label.text = "已拥有 %d 位伙伴 · 店内 %d 位" % [roster.size(), sim.workers.size()]
	var task_text: String = Actor.TASKS.get(selected.task_label, selected.task_label)
	_details.text = "%s · %s · Lv%d\n移速 %d    搬量 %d    操作 %.1f\n正在：%s" % [NAMES[selected.art], ROLES[selected.role], selected.level, selected.speed, selected.capacity, selected.skill, task_text]
	if sim.has_method("all_workers"):
		_details.text += "\n来源：" + String(selected.get("source", "初始"))
		if not _view.staff_is_deployed(int(selected.id)):
			_details.text = _details.text.replace("正在：" + task_text, "状态：待派遣")
	deploy_button.visible = sim.has_method("deploy_worker")
	deploy_button.text = "收回到名册" if _view.staff_is_deployed(int(selected.id)) else "派到店内"
	deploy_button.disabled = false
	train_button.text = "培养伙伴  ·  %d 金币" % sim.train_cost(_view.selected_worker)
	train_button.disabled = sim.gold < sim.train_cost(_view.selected_worker)
	hire_button.disabled = sim.hire_cost() < 0 or sim.gold < sim.hire_cost()
	hire_button.text = "当前伙伴已集齐" if sim.hire_cost() < 0 else "邀请伙伴  ·  %d 金币" % sim.hire_cost()
	var next_art := "fox"
	for art in NAMES:
		if not roster.any(func(worker: Dictionary) -> bool: return worker.art == art):
			next_art = art
			break
	_recruit_portrait.texture = _portraits[next_art]
	_recruit_label.text = "伙伴已全部加入" if sim.hire_cost() < 0 else ("浣熊 · 力量型\n擅长批量搬运" if next_art == "raccoon" else "狐狸 · 操作型\n擅长手工制作")
	pause_button.text = "继续营业" if sim.paused else "暂停营业"
	belt_button.text = "运输方式  ·  传送带" if sim.use_belts else "运输方式  ·  人工搬运"
	%Selection.visible = show_selection and page == "shop"
	$Selection/Row/Avatar.texture = _portraits[selected.art]
	$Selection/Row/Summary.text = "%s · Lv%d\n%s" % [NAMES[selected.art], selected.level, task_text]
	save_button.disabled = _view.store == null
	_save_caption.text = _view.save_status if _view.store != null else "独立练习不会覆盖经营存档"
	tasks_button.visible = sim.has_method("task_rows")
	if sim.has_method("task_rows"):
		if page == "station":
			station_panel.refresh()
		if page == "tasks":
			_refresh_tasks()

func _refresh_tasks() -> void:
	var rows: Array = _view.sim.task_rows()
	var signature := str(rows.map(func(row: Dictionary) -> String: return row.name))
	if signature != _task_signature:
		for label in _task_labels:
			label.free()
		_task_labels.clear()
		for row in rows:
			_task_labels.append(_text(_task_column, "", 23))
		_task_signature = signature
	_goal_label.text = _view.sim.current_goal()
	var stock_lines: Array[String] = []
	for dish in _view.sim.shelf_stock:
		if _view.sim.shelf_stock[dish] > 0:
			stock_lines.append("%s %d 杯" % [_view.sim.dish_name(dish), _view.sim.shelf_stock[dish]])
	if not stock_lines.is_empty():
		_goal_label.text += "\n货架库存：" + "、".join(stock_lines)
	for i in rows.size():
		_task_labels[i].text = "%s\n%d / %d%s" % [rows[i].name, rows[i].current, rows[i].target, " · 已完成" if rows[i].complete else ""]

func open_station(id: String) -> void:
	if not _view.sim.has_method("station_info"):
		return
	station_panel.show_station(id)
	open_page("station")
	%Title.text = _view.sim.station_info(id).name

func open_page(next_page: String) -> void:
	if next_page != "shop" and not _page_nodes.has(next_page):
		return
	if is_instance_valid(_view._drag):
		_view._drag.cancel()
	page = next_page
	%Shade.visible = page != "shop"
	%Sheet.visible = page != "shop"
	%Title.text = PAGE_NAMES.get(page, "")
	%Scroll.scroll_vertical = 0
	for id in _page_nodes:
		_page_nodes[id].visible = id == page
	for pair in [[home_button, "shop"], [build_button, "build"], [staff_button, "staff"], [recruit_button, "recruit"]]:
		pair[0].add_theme_stylebox_override("normal", _style("ead4b2" if pair[1] == page else "fff5e2", "b38c62" if pair[1] == page else "fff5e2", 16))
	refresh()

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
	%Sheet.offset_top = -minf(862.0, available.y - 122.0)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if page != "shop":
			open_page("shop")
		else:
			show_selection = false
			refresh()
		get_viewport().set_input_as_handled()
