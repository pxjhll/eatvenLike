extends VBoxContainer
## 菜单页（HUD 组件）：角色预览、暂停、存档、美术开关（场景里带 toggle_label 的节点，如玻璃隔板）、重新开始。

const Icons := preload("res://presentation/ui/reference_icons.gd")
const ReferenceTheme := preload("res://presentation/ui/reference_theme.gd")
const Toggle := preload("res://presentation/ui/reference_toggle.gd")

var _view: Node2D
var _hud: Control
var pause_button: Button
var save_button: Button
var restart_button: Button
var footer: HBoxContainer
var save_caption: Label
## 美术开关：节点 → 按钮
var toggles := {}


func setup(view: Node2D, hud: Control) -> void:
	_view = view
	_hud = hud
	add_theme_constant_override("separation", 12)
	_item("角色预览", "hat", func() -> void: hud.page_node("characters").select("rabbit"); hud.open_page("characters"))
	pause_button = _item("暂停营业", "pause", func() -> void: view.rules.paused = not view.rules.paused; hud.refresh())
	save_button = _item("保存进度", "save", func() -> void: view.save_now())
	for node in view.art.find_children("*", "Node2D", true, false):
		if node.has_meta("toggle_label"): _toggle(node)
	restart_button = _item("重新开始", "trash", hud.open_page.bind("restart"))
	hud._button_style(restart_button, "danger", 18)
	restart_button.add_theme_color_override("font_color", Color("8e311a"))
	footer = hud._row(self, 12)
	save_caption = hud._text(footer, "", 19, true)
	save_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	save_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _item(caption: String, icon: String, callback: Callable) -> Button:
	var button: Button = _hud._action(self, caption, callback)
	button.set_meta("semantic_icon", icon)
	button.icon = Icons.texture(icon)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_constant_override("icon_max_width", 46)
	button.add_theme_constant_override("h_separation", 22)
	button.add_theme_font_size_override("font_size", 27)
	button.custom_minimum_size.y = 66
	_hud._button_style(button, "card", 18)
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


func _toggle(node: Node2D) -> void:
	var button := Button.new()
	button.text = String(node.get_meta("toggle_label"))
	button.toggle_mode = true
	button.custom_minimum_size.y = 64
	button.icon = Icons.texture(String(node.get_meta("toggle_icon", "hat")))
	button.expand_icon = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_constant_override("icon_max_width", 38)
	button.add_theme_constant_override("h_separation", 18)
	button.add_theme_font_size_override("font_size", 25)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, ReferenceTheme.style("card", 14, state))
	button.set_pressed_no_signal(node.visible)
	button.toggled.connect(func(on: bool) -> void: node.visible = on)
	add_child(button)
	var knob := Toggle.new()
	knob.anchor_left = 1.0
	knob.anchor_right = 1.0
	knob.anchor_top = 0.5
	knob.anchor_bottom = 0.5
	knob.offset_left = -90
	knob.offset_right = -26
	knob.offset_top = -17
	knob.offset_bottom = 17
	button.add_child(knob)
	toggles[node] = button


func refresh() -> void:
	pause_button.text = "继续营业" if _view.rules.paused else "暂停营业"
	save_button.disabled = _view.store == null
	save_caption.text = _view.save_status if _view.store != null else "独立练习不会覆盖经营存档"
