extends Control
## 通用 HUD 核心（规格 §6.2.1）：只管顶栏、底部页签、弹出面板、提示和弹卡；具体内容都是注册进来的组件。
## - 底部页签是一张表：register_tab(id, 名字, 图标, 打开哪一页)
## - 面板页：register_page(id, 节点, 选项)；页面节点有 refresh() 就每帧调
## - 顶栏下面的槽位：add_widget(节点)（瓶颈提示、进行中加成……）；有 refresh() 就每帧调
## - 弹卡队列 popups：引导卡、奇遇卡、店长回访、结店总结都排在这里
## 界面只读 ShopView 快照、只调游戏场景的命令；不认识任何一家店。

const ReferenceTheme := preload("res://presentation/ui/reference_theme.gd")
const Icons := preload("res://presentation/ui/reference_icons.gd")
const Characters := preload("res://presentation/characters/character_library.gd")
const PopupQueue := preload("res://presentation/shop/hud/popup_queue.gd")
const COIN := preload("res://art/ui/coin.png")

var page := "shop"
var show_selection := false
var _view: Node2D
var _portraits := {}
## id → {node, title, icon, options}
var _pages := {}
var _page_nodes := {}
## [{id, page, button}]
var _tabs: Array = []
var _widgets: Array = []
var _heading_icon: TextureRect
var _sheet_space := Vector2.ZERO
var _sheet_height := -1.0
var popups: Control

@onready var menu_button: Button = %Menu
@onready var close_button: Button = %Close
@onready var speed_button: Button = %Speed
@onready var goal_button: Button = %Goal
@onready var toast: Label = %Toast


func setup(view: Node2D) -> void:
	_view = view
	_apply_theme()
	for key in Characters.NAMES:
		_portraits[key] = Characters.portrait(key)
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
	popups = PopupQueue.new()
	popups.name = "Popups"
	add_child(popups)
	popups.setup(self)
	move_child($ToastRow, get_child_count() - 1)


## 装好组件以后调一次：回到店铺页
func start() -> void:
	open_page("shop")


# ---------- 注册 ----------

## 底部页签。page = 点它打开哪一页（"shop" = 收起面板回店铺）
func register_tab(id: String, label: String, icon: String, page_id := "") -> Button:
	var button := Button.new()
	button.name = id.capitalize()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.icon = Icons.texture(icon)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 68)
	button.add_theme_constant_override("h_separation", 14)
	button.add_theme_font_size_override("font_size", 32)
	var target := page_id if not page_id.is_empty() else id
	button.pressed.connect(open_page.bind(target))
	%Tabs.add_child(button)
	_tabs.append({"id": id, "page": target, "button": button})
	_style_tabs()
	return button


func tab(id: String) -> Button:
	for row in _tabs:
		if row.id == id: return row.button
	return null


## 面板页。options：title 标题、icon 标题图标（空 = 不显示）、big 大标题、centered 居中标题、
## bare 没有副标题和关闭键、fraction 最多占屏幕多高、bottom 离底多远
func register_page(id: String, node: Control, options := {}) -> Control:
	var column := VBoxContainer.new()
	column.name = id.capitalize()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	%Content.add_child(column)
	if node != null:
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_child(node)
	column.visible = false
	_page_nodes[id] = column
	_pages[id] = {"node": node, "options": options}
	return column


func page_node(id: String) -> Control:
	return _pages[id].node if _pages.has(id) else null


## 顶栏下面的一个小部件（按加入顺序往下排）
func add_widget(node: Control) -> void:
	%UnderHeader.add_child(node)
	_widgets.append(node)


# ---------- 外观 ----------

func _apply_theme() -> void:
	theme = ReferenceTheme.make_theme()
	var header_style := ReferenceTheme.style("header", 22)
	header_style.set_content_margin_all(0)
	$Header.add_theme_stylebox_override("panel", header_style)
	var navigation_style := ReferenceTheme.style("wood", 20)
	navigation_style.set_content_margin_all(0)
	%Navigation.add_theme_stylebox_override("panel", navigation_style)
	%Coin.texture = COIN
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
	goal_button.add_theme_stylebox_override("pressed", ReferenceTheme.style("pill", 12, "pressed"))
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
	toast.add_theme_stylebox_override("normal", ReferenceTheme.style("toast", 22))
	toast.add_theme_color_override("font_color", Color("fff6e5"))


func _style_tabs() -> void:
	var selected := "shop"
	for row in _tabs:
		if row.page == page: selected = row.page
	for row in _tabs:
		_button_style(row.button, "gold" if row.page == selected else "cream", 18)


# ---------- 小零件（各页面共用） ----------

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


## 一行里的短字（数字、名字、标签）不能折成一字一行
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


func _card(parent: Node, _background := "fffaf0", _border := "e6d8bf") -> VBoxContainer:
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


func portrait_texture(art: String) -> Texture2D:
	return _portraits.get(art)


# ---------- 每帧 ----------

func refresh() -> void:
	if _view == null or _view.rules == null:
		return
	var view: ShopView = _view.view
	%Gold.text = str(int(_view.rules.gold))
	speed_button.text = "×%d" % int(_view._speed_factor)
	var goal := view.goal()
	%GoalText.text = goal.text if int(goal.target) <= 0 else "%s · %d / %d" % [goal.text, goal.current, goal.target]
	%GoalBar.visible = int(goal.target) > 0
	%GoalBar.value = clampf(float(goal.current) / maxf(1.0, float(goal.target)), 0, 1)
	for widget in _widgets:
		if widget.has_method("refresh"): widget.refresh()
	for id in _pages:
		var node: Control = _pages[id].node
		# 有些页面（员工页）在关着的时候也要更新（选中条、红 ↑）
		if node != null and node.has_method("refresh") and (id == page or node.get("always_refresh") == true): node.refresh()
	popups.refresh()
	_fit_sheet()


func open_station(id: String) -> void:
	var station := page_node("station")
	if station == null: return
	station.show_station(id)
	open_page("station")


func open_page(next_page: String) -> void:
	if next_page != "shop" and not _pages.has(next_page):
		return
	if _view != null and is_instance_valid(_view._drag):
		_view._drag.cancel()
	page = next_page
	var options: Dictionary = _pages[page].options if _pages.has(page) else {}
	%Shade.visible = page != "shop"
	%Shade.color.a = 0.34
	%Sheet.visible = page != "shop"
	%Title.text = String(options.get("title", ""))
	var big: bool = options.get("big", false)
	%Title.add_theme_font_size_override("font_size", 44 if big else 34)
	_heading_icon.custom_minimum_size = Vector2(60, 60) if big else Vector2(42, 42)
	%Subtitle.add_theme_font_size_override("font_size", 24 if big else 19)
	var icon := String(options.get("icon", ""))
	_heading_icon.texture = Icons.texture(icon) if not icon.is_empty() else null
	_heading_icon.visible = not icon.is_empty()
	var centered: bool = options.get("centered", false)
	%Title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if centered else HORIZONTAL_ALIGNMENT_LEFT
	%Title.size_flags_horizontal = Control.SIZE_EXPAND_FILL if centered else Control.SIZE_SHRINK_BEGIN
	%Heading.alignment = BoxContainer.ALIGNMENT_CENTER if options.get("plaque", false) else BoxContainer.ALIGNMENT_BEGIN
	%Title.remove_theme_stylebox_override("normal")
	if options.get("plaque", false):
		%Title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var plaque := ReferenceTheme.style("cream", 28)
		plaque.content_margin_left = 34
		plaque.content_margin_right = 34
		%Title.add_theme_stylebox_override("normal", plaque)
	%Subtitle.visible = not options.get("bare", false)
	close_button.visible = not options.get("no_close", false)
	%Pill.visible = false
	%Subtitle.text = ""
	%Scroll.scroll_vertical = 0
	for id in _page_nodes:
		_page_nodes[id].visible = id == page
	_style_tabs()
	var node := page_node(page)
	if node != null and node.has_method("on_open"): node.on_open()
	_sheet_height = -1.0
	refresh()
	# 折行的字下一帧才知道真高度
	_fit_sheet.call_deferred()


## 面板页把标题、等级标签、副标题放进面板头
func set_heading(title: String, pill_text: String, pill_locked: bool, subtitle: String) -> void:
	%Title.text = title
	%Pill.visible = not pill_text.is_empty()
	pill(%Pill, pill_text, "e5dfd2" if pill_locked else "ead4b2", "6f6556" if pill_locked else "583e2d")
	%Subtitle.text = subtitle


func set_subtitle(text: String) -> void:
	%Subtitle.text = text


func heading_icon() -> TextureRect:
	return _heading_icon


## 面板跟内容一样高，最多占大半屏，短页面上方还看得见店
func _fit_sheet() -> void:
	if page == "shop" or _sheet_space == Vector2.ZERO:
		return
	var options: Dictionary = _pages[page].options if _pages.has(page) else {}
	var margin: MarginContainer = %Sheet.get_node("Margin")
	var chrome: float = %Heading.get_combined_minimum_size().y + margin.get_theme_constant("margin_top") + margin.get_theme_constant("margin_bottom") + 16.0
	var fraction: float = options.get("fraction", 0.64)
	var bottom: float = options.get("bottom", 112.0)
	%Sheet.offset_bottom = -bottom
	var limit := maxf(300.0, minf(_sheet_space.y * fraction, _sheet_space.y - bottom - 130.0))
	var wanted := clampf(%Content.get_combined_minimum_size().y + chrome, 200.0, limit)
	if absf(wanted - _sheet_height) < 1.0:
		return
	_sheet_height = wanted
	%Sheet.offset_top = -bottom - wanted


func relayout() -> void:
	_sheet_height = -1.0


func begin_staff_drag() -> void:
	page = "shop"
	%Shade.hide()
	%Sheet.hide()
	show_selection = false
	refresh()


func blocks_world(screen: Vector2) -> bool:
	for control in [$Header, %Navigation, %Selection]:
		if control.is_visible_in_tree() and control.get_global_rect().has_point(screen):
			return true
	for widget in _widgets:
		if widget.is_visible_in_tree() and widget.mouse_filter == Control.MOUSE_FILTER_STOP and widget.get_global_rect().has_point(screen):
			return true
	if popups.blocks(screen): return true
	return page != "shop"


func card_hit_test(card: Button, screen: Vector2) -> bool:
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
