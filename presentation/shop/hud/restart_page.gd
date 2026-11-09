extends VBoxContainer
## 重开确认页（HUD 组件）。

var _view: Node2D
var cancel_button: Button
var confirm_button: Button


func setup(view: Node2D, hud: Control) -> void:
	_view = view
	add_theme_constant_override("separation", 22)
	hud._text(self, "重新开始这家店？", 36).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(HSeparator.new())
	hud._text(self, "金币、设备、店内招募员工与培养等级将重置\n只保留初始员工，跨店记录不受影响", 25).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var actions: HBoxContainer = hud._row(self, 22)
	cancel_button = hud._action(actions, "继续经营", hud.open_page.bind("menu"))
	confirm_button = hud._action(actions, "确认重新开始", func() -> void: view.restart(); hud.open_page("shop"))
	for button in [cancel_button, confirm_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 74
		button.add_theme_font_size_override("font_size", 28)
	hud._button_style(confirm_button, "danger_strong", 22)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		confirm_button.add_theme_color_override(state, Color("fff6e7"))
