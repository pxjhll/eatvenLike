extends Node2D
## One AnimatedSprite2D at source size and one at game size, sharing the atlas.

const ACTOR := preload("res://presentation/rabbit_walk_frames/rabbit_walk.tscn")
const FONT := preload("res://art/ui/graybox_font.ttf")
const INK := Color("293c37")
const MUTED := Color("7e8981")
var actor: Node2D
var small: Node2D
var paused := false
var speed := 1.0
var _directions: Dictionary = {}
var _play: Button
var _previous: Button
var _next: Button
var _speed: HSlider
var _timeline: HSlider
var _phase_label: Label
var _direction_label: Label
var _speed_label: Label
var _updating := false
var _cards: StyleBoxFlat


func _ready() -> void:
	get_window().title = "Rabbit walking frames"
	get_window().content_scale_size = Vector2i(1100, 740)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_window().size = Vector2i(1100, 740)
	_cards = StyleBoxFlat.new()
	_cards.bg_color = Color.WHITE
	_cards.set_corner_radius_all(18)
	_label("RABBIT / FRAME ANIMATION", Vector2(34, 18), 12, Color("498374"))
	_label("兔子走路", Vector2(32, 44), 29, INK)
	_label("Five views / seven poses each / shared atlas / original timing", Vector2(34, 89), 13, MUTED)
	_label("256 x 256 / 100%", Vector2(60, 147), 14, INK)
	_label("128 x 128 / 50%", Vector2(525, 147), 14, INK)
	_label("方向", Vector2(860, 147), 18, INK)
	actor = ACTOR.instantiate()
	actor.position = Vector2(270, 475)
	add_child(actor)
	small = ACTOR.instantiate()
	small.position = Vector2(650, 475)
	small.scale = Vector2(0.5, 0.5)
	add_child(small)
	_label("01 > 02 > 03 > 04 > 05 > 06 > 07 > 01", Vector2(75, 515), 14, MUTED)
	_direction_label = _label("", Vector2(525, 515), 14, Color("498374"))
	var cells := {5: Vector2i(0, 0), 4: Vector2i(1, 0), 3: Vector2i(2, 0), 6: Vector2i(0, 1), 2: Vector2i(2, 1), 7: Vector2i(0, 2), 0: Vector2i(1, 2), 1: Vector2i(2, 2)}
	for index: int in cells:
		var at: Vector2i = cells[index]
		var button := _button("%s\n%d" % [actor.LABELS[index], index * 45], Vector2(848 + at.x * 72, 225 + at.y * 66), Vector2(66, 56), set_direction.bind(index))
		button.toggle_mode = true
		_directions[index] = button
	_label("5 source clips\n3 mirrored clips\n35 unique frames", Vector2(860, 472), 13, MUTED)
	_play = _button("暂停", Vector2(53, 591), Vector2(96, 38), _toggle_pause)
	_previous = _button("上一帧", Vector2(165, 591), Vector2(96, 38), _step.bind(-1))
	_next = _button("下一帧", Vector2(277, 591), Vector2(96, 38), _step.bind(1))
	_label("速度", Vector2(407, 602), 13, MUTED)
	_speed = HSlider.new()
	_speed.position = Vector2(459, 601)
	_speed.size = Vector2(196, 20)
	_speed.min_value = 0.25
	_speed.max_value = 2.0
	_speed.step = 0.25
	_speed.value = 1.0
	_speed.value_changed.connect(func(value: float) -> void:
		speed = value
		actor.set_speed(value)
		_speed_label.text = "%.2fx" % value
	)
	add_child(_speed)
	_speed_label = _label("1.00x", Vector2(671, 601), 13, INK)
	_phase_label = _label("", Vector2(812, 601), 13, MUTED)
	_timeline = HSlider.new()
	_timeline.position = Vector2(56, 654)
	_timeline.size = Vector2(990, 20)
	_timeline.max_value = 1.0
	_timeline.step = 0.001
	_timeline.value_changed.connect(func(value: float) -> void:
		if not _updating:
			_set_paused(true)
			actor.seek_phase(value)
			small.seek_phase(value)
	)
	add_child(_timeline)
	_label("Space: play / pause     Left / Right: direction     7 distinct frames retained", Vector2(36, 712), 12, MUTED)
	set_direction(2)
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	var phase: float = actor.get_phase()
	small.pause()
	small.seek_phase(phase)
	_updating = true
	_timeline.value = phase
	_updating = false
	_phase_label.text = "FRAME %02d / 07    %.2f s" % [actor.sprite.frame + 1, actor.get_cycle_seconds()]


func set_direction(value: int) -> void:
	actor.set_direction(value)
	small.set_direction(value)
	_direction_label.text = "%s / %.2f s" % [actor.LABELS[actor.direction], actor.get_cycle_seconds()]
	for index: int in _directions:
		(_directions[index] as Button).set_pressed_no_signal(index == actor.direction)
	_refresh()


func _set_paused(value: bool) -> void:
	paused = value
	if paused:
		actor.pause()
	else:
		actor.play()
	_play.text = "播放" if paused else "暂停"


func _toggle_pause() -> void:
	_set_paused(not paused)


func _step(offset: int) -> void:
	_set_paused(true)
	actor.sprite.set_frame_and_progress(posmod(actor.sprite.frame + offset, 7), 0.0)
	_refresh()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE: _toggle_pause()
		KEY_LEFT: set_direction(actor.direction - 1)
		KEY_RIGHT: set_direction(actor.direction + 1)
		_: return
	get_viewport().set_input_as_handled()


func _label(text: String, at: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label


func _button(text: String, at: Vector2, size: Vector2, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = size
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("498374") if state == "pressed" else Color("e9efe6")
		style.set_corner_radius_all(9)
		if state == "focus":
			style.bg_color = Color(0, 0, 0, 0)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(action)
	add_child(button)
	return button


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1100, 740), Color("eeefe8"))
	if _cards == null:
		return
	for card: Rect2 in [Rect2(32, 126, 768, 429), Rect2(823, 126, 245, 429), Rect2(32, 574, 1036, 119)]:
		draw_style_box(_cards, card)
	for x in range(60, 781, 24):
		draw_line(Vector2(x, 194), Vector2(x, 490), Color("f2f4ee"), 1)
	for y in range(194, 491, 24):
		draw_line(Vector2(60, y), Vector2(780, y), Color("f2f4ee"), 1)
	draw_line(Vector2(105, 475), Vector2(419, 475), Color("d6dfd0"), 1)
	draw_line(Vector2(550, 475), Vector2(744, 475), Color("d6dfd0"), 1)
