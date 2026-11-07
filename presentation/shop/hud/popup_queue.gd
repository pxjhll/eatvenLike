extends Control
## 弹卡队列（规格 §6.2.1）：引导卡（欢迎、上手、完店）、奇遇卡、店长回访、结店总结都排在这里，一次只弹一张。
## 一张卡 = 字典：
##   id        唯一 id（同 id 不重复排队）
##   title     标题；title_size 字号（默认 40）
##   art       标题旁的插画（角色 id 或图标键），medal = 顶上的奖牌图标键
##   rows      [[图标键, 一句话], …]   图标 + 说明的小卡片
##   stats     [[图标键, 小标题, 数值], …]
##   note      底下一段说明
##   buttons   [{label, primary(金色), action: Callable}, …]（按钮按了就关卡；action 可以为空）
##   dim       卡片后面压暗（默认 true），pause 弹着时店里停（默认 true）
##   any_tap   点卡片外面也算按了主按钮（默认 true：有的手机浏览器点不中按钮）

const ReferenceTheme := preload("res://presentation/ui/reference_theme.gd")
const Icons := preload("res://presentation/ui/reference_icons.gd")
const DIM := Color(0.16, 0.1, 0.06, 0.62)

var _hud: Control
var queue: Array = []
var _card: PanelContainer
var _title: Label
var _body: VBoxContainer
var _buttons: HBoxContainer
var _art: TextureRect
var _medal: TextureRect
var _shown := ""


func setup(hud: Control) -> void:
	_hud = hud
	theme = hud.theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = PanelContainer.new()
	var card_style := ReferenceTheme.style("paper", 40)
	card_style.set_content_margin_all(28)
	_card.add_theme_stylebox_override("panel", card_style)
	_card.custom_minimum_size.x = 560
	add_child(_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 22)
	_card.add_child(column)
	_medal = _picture(column, null, Vector2(210, 176))
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 8)
	column.add_child(heading)
	_art = _picture(heading, null, Vector2(190, 190))
	_title = hud._text(heading, "", 40)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_title.custom_minimum_size.x = 300
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_outline_color", ReferenceTheme.INK)
	_title.add_theme_constant_override("outline_size", 1)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 12)
	column.add_child(_body)
	_buttons = hud._row(column, 14)
	visible = false


## 排一张卡（同 id 已在队里就不再排）
func push(card: Dictionary) -> void:
	for queued in queue:
		if queued.get("id", "") == card.get("id", "") and not String(card.get("id", "")).is_empty(): return
	queue.append(card)
	refresh()


func remove(id: String) -> void:
	queue = queue.filter(func(card: Dictionary) -> bool: return card.get("id", "") != id)
	refresh()


func has_card(id := "") -> bool:
	if id.is_empty(): return not queue.is_empty()
	return queue.any(func(card: Dictionary) -> bool: return card.get("id", "") == id)


func current() -> Dictionary:
	return queue[0] if not queue.is_empty() else {}


## 弹着的卡要不要让店停下
func freezes() -> bool:
	return not queue.is_empty() and queue[0].get("pause", true)


func blocks(_screen: Vector2) -> bool:
	return not queue.is_empty()


func refresh() -> void:
	visible = not queue.is_empty()
	mouse_filter = Control.MOUSE_FILTER_STOP if visible else Control.MOUSE_FILTER_IGNORE
	if not visible:
		_shown = ""
		return
	var card: Dictionary = queue[0]
	var key := "%s|%s" % [card.get("id", ""), str(card.get("title", ""))]
	if key != _shown:
		_shown = key
		_build(card)
	_place()
	queue_redraw()


func _build(card: Dictionary) -> void:
	for child in _body.get_children(): child.free()
	for child in _buttons.get_children(): child.free()
	var art := String(card.get("art", ""))
	_art.visible = not art.is_empty()
	if not art.is_empty(): _art.texture = Icons.portrait(art) if art in _hud.Characters.IDS else Icons.texture(art)
	var medal := String(card.get("medal", ""))
	_medal.visible = not medal.is_empty()
	if not medal.is_empty(): _medal.texture = Icons.texture(medal)
	_title.text = String(card.get("title", ""))
	_title.add_theme_font_size_override("font_size", int(card.get("title_size", 40)))
	for row in card.get("rows", []):
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", ReferenceTheme.style("card", 22))
		_body.add_child(panel)
		var line: HBoxContainer = _hud._row(panel, 12)
		_picture(line, Icons.texture(String(row[0])), Vector2(80, 72))
		var label: Label = _hud._text(line, String(row[1]), 23)
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		label.custom_minimum_size.x = 370
	if not card.get("stats", []).is_empty():
		var metrics: HBoxContainer = _hud._row(_body, 14)
		for stat in card.stats: _stat(metrics, String(stat[0]), String(stat[1]), String(stat[2]))
	if not String(card.get("note", "")).is_empty():
		var note: Label = _hud._text(_body, String(card.note), 22)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.custom_minimum_size.x = 500
	var buttons: Array = card.get("buttons", [{"label": "知道了", "primary": true}])
	for index in buttons.size():
		var spec: Dictionary = buttons[index]
		var button := Button.new()
		button.name = "Button%d" % index
		button.text = String(spec.get("label", ""))
		button.custom_minimum_size.y = 72
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 27)
		for state in ["normal", "hover", "pressed"]:
			button.add_theme_stylebox_override(state, ReferenceTheme.style("gold" if spec.get("primary", false) else "cream", 18, state))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(press.bind(index))
		_buttons.add_child(button)


## 按下当前卡的第 index 个按钮：先把卡从队里拿掉，再做按钮的事（事可能再排新卡）
func press(index: int) -> void:
	if queue.is_empty(): return
	var card: Dictionary = queue.pop_front()
	_shown = ""
	var buttons: Array = card.get("buttons", [{"label": "知道了", "primary": true}])
	if index >= 0 and index < buttons.size():
		var action: Variant = buttons[index].get("action")
		if action is Callable and (action as Callable).is_valid(): (action as Callable).call()
	refresh()


func primary_index() -> int:
	if queue.is_empty(): return -1
	var buttons: Array = queue[0].get("buttons", [{"label": "知道了", "primary": true}])
	for index in buttons.size():
		if buttons[index].get("primary", false): return index
	return buttons.size() - 1


func button(index: int) -> Button:
	return _buttons.get_node_or_null("Button%d" % index)


func _picture(parent: Node, texture: Texture2D, minimum: Vector2) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = texture
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = minimum
	picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(picture)
	return picture


func _stat(parent: Node, icon: String, heading: String, value: String) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", ReferenceTheme.style("card", 22))
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	_picture(row, Icons.texture(icon), Vector2(52, 72))
	var column := VBoxContainer.new()
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(column)
	var heading_label: Label = _hud._text(column, heading, 24)
	heading_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	var value_label: Label = _hud._text(column, value, 28)
	value_label.autowrap_mode = TextServer.AUTOWRAP_OFF


func _place() -> void:
	_card.reset_size()
	var inverse := get_global_transform_with_canvas().affine_inverse()
	var view := get_viewport_rect()
	var a: Vector2 = inverse * view.position
	var b: Vector2 = inverse * view.end
	var visible_rect := Rect2(a, b - a).abs().intersection(Rect2(Vector2.ZERO, size))
	if not visible_rect.has_area(): visible_rect = Rect2(Vector2.ZERO, size)
	var factor := minf(1.0, minf((visible_rect.size.x - 40.0) / _card.size.x, (visible_rect.size.y - 220.0) / _card.size.y))
	_card.scale = Vector2.ONE * maxf(0.1, factor)
	_card.position = visible_rect.position + (visible_rect.size - _card.size * _card.scale) / 2.0


## 抬起的那一下（触屏或鼠标）在按钮之前处理：点在副按钮上 = 副按钮，其他地方 = 主按钮
func _input(event: InputEvent) -> void:
	if queue.is_empty() or not queue[0].get("any_tap", true):
		return
	var released: bool = event is InputEventScreenTouch and not event.pressed and not event.canceled
	released = released or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
		and not event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION)
	if not released:
		return
	get_viewport().set_input_as_handled()
	var primary := primary_index()
	for index in _buttons.get_child_count():
		if index == primary: continue
		var other := button(index)
		if other != null and other.is_visible_in_tree() and other.get_global_rect().has_point(event.position):
			press(index)
			return
	press(primary)


func _draw() -> void:
	if queue.is_empty() or not queue[0].get("dim", true): return
	var top: float = _hud.get_node("Header").get_rect().end.y
	var bottom: float = _hud.get_node("Navigation").position.y
	draw_rect(Rect2(0, top, size.x, maxf(0, bottom - top)), DIM)
