extends HBoxContainer
## The same preferences are shown in every shop's menu.

func setup(hud: Control) -> void:
	add_theme_constant_override("separation", 8)
	_add_switch(hud, "音乐", ShopAudio.music_enabled, ShopAudio.set_music_enabled)
	_add_switch(hud, "音效", ShopAudio.effects_enabled, ShopAudio.set_effects_enabled)


func _add_switch(hud: Control, label: String, enabled: bool, apply: Callable) -> void:
	var button := Button.new()
	button.toggle_mode = true
	button.set_pressed_no_signal(enabled)
	button.text = _caption(label, enabled)
	button.custom_minimum_size = Vector2(94, 60)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 23)
	hud._button_style(button, "card", 14)
	hud.bind_action(button, func() -> void:
		apply.call(button.button_pressed)
		button.text = _caption(label, button.button_pressed))
	add_child(button)


func _caption(label: String, enabled: bool) -> String:
	return "%s %s" % [label, "开" if enabled else "关"]
