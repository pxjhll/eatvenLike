extends HBoxContainer
## Uses the parent shop's theme, and reads the same preferences in either shop.

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_add_switch("音乐", ShopAudio.music_enabled, ShopAudio.set_music_enabled)
	_add_switch("音效", ShopAudio.effects_enabled, ShopAudio.set_effects_enabled)


func _add_switch(label: String, enabled: bool, apply: Callable) -> void:
	var button := Button.new()
	button.toggle_mode = true
	button.button_pressed = enabled
	button.text = _caption(label, enabled)
	button.custom_minimum_size = Vector2(94, 48)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 21)
	button.toggled.connect(func(on: bool) -> void:
		apply.call(on)
		button.text = _caption(label, on)
		if on:
			ShopAudio.play_cue(&"tap")
	)
	add_child(button)


func _caption(label: String, enabled: bool) -> String:
	return "%s %s" % [label, "开" if enabled else "关"]
