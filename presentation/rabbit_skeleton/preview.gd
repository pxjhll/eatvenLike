extends Node2D
## Interactive eight-direction viewer, separate from gameplay and the side study.

const ACTOR := preload("res://presentation/rabbit_skeleton/directional_rabbit.gd")
const FONT := preload("res://art/rabbit_skeleton/preview_font.ttf")
const SOURCE_FRAMES := preload("res://art/rabbit_walk_frames/rabbit_walk_frames.tres")
const INK := Color("293c37")
const MUTED := Color("7e8981")
var cycle_seconds := 0.96
var actor: Node2D
var small_actor: Node2D
var overlay: Node2D
var phase_time := 0.0
var playback_speed := 1.0
var paused := false
var looping := true
var show_grid := true
var _updating := false
var _direction_buttons: Dictionary = {}
var _prop_buttons: Dictionary = {}
var _walk: Button
var _idle: Button
var _play: Button
var _previous: Button
var _next: Button
var _reset: Button
var _loop: Button
var _bones: Button
var _soft: Button
var _grid: Button
var _speed: HSlider
var _timeline: HSlider
var _zoom: HSlider
var _time_label: Label
var _speed_label: Label
var _zoom_label: Label
var _direction_label: Label
var _compass_label: Label
var _state_label: Label
var _reference: AtlasTexture
var reference_sprite: Sprite2D
var _card_style: StyleBoxFlat


func _ready() -> void:
	get_window().title = "小兔子 · 骨骼动画预览"
	get_window().content_scale_size = Vector2i(1280, 860)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_window().size = Vector2i(1280, 860)
	get_window().min_size = Vector2i(960, 645)
	_card_style = StyleBoxFlat.new()
	_card_style.bg_color = Color.WHITE
	_card_style.set_corner_radius_all(18)
	_label("RABBIT  /  ANIMATION VIEWER", Vector2(34, 20), 13, Color("498374"))
	_label("角色骨骼动画预览", Vector2(32, 45), 32, INK)
	_label("原图动作对照 · 大图与游戏尺寸", Vector2(35, 96), 14, MUTED)
	_label("5 套基础视角  /  8 个方向", Vector2(1031, 63), 14, MUTED)
	_label("动作列表", Vector2(52, 156), 17, INK)
	_walk = _button("走路", Vector2(52, 197), Vector2(194, 43), _select_action.bind("walk"), true)
	_idle = _button("站立", Vector2(52, 251), Vector2(194, 43), _select_action.bind("idle"), true)
	_state_label = _label("", Vector2(53, 307), 13, Color("498374"))
	_label("物品", Vector2(52, 348), 17, INK)
	var prop_ids := ["none", "cup", "spoon"]
	var prop_names := ["无", "杯子", "工具"]
	for index in 3:
		var id: String = prop_ids[index]
		_prop_buttons[id] = _button(prop_names[index], Vector2(52 + index * 67, 389), Vector2(60, 36), set_prop.bind(id), true)
	_label("原图对照", Vector2(52, 455), 17, INK)
	_reference = AtlasTexture.new()
	_reference.atlas = load("res://art/rabbit_walk_frames/rabbit_walk_atlas.png")
	reference_sprite = Sprite2D.new()
	reference_sprite.texture = _reference
	reference_sprite.position = Vector2(149, 642)
	reference_sprite.centered = false
	reference_sprite.offset = Vector2(-128, -244)
	reference_sprite.scale = Vector2(0.62, 0.62)
	add_child(reference_sprite)
	_label("原图动作", Vector2(117, 646), 12, MUTED)
	_label("动作预览", Vector2(314, 156), 17, INK)
	_direction_label = _label("", Vector2(796, 158), 15, Color("498374"))
	_label("正面与背面独立 · 左右镜像", Vector2(314, 642), 12, MUTED)
	actor = ACTOR.new()
	actor.position = Vector2(636, 612)
	actor.scale = Vector2(1.60, 1.60)
	add_child(actor)
	small_actor = ACTOR.new()
	small_actor.position = Vector2(880, 612)
	small_actor.scale = Vector2.ONE * 128.0 / 228.0
	add_child(small_actor)
	_label("游戏尺寸", Vector2(850, 642), 12, MUTED)
	overlay = preload("res://presentation/rabbit_skeleton/rig_overlay.gd").new()
	overlay.z_index = 20
	overlay.visible = false
	add_child(overlay)
	_label("观察方向", Vector2(1025, 156), 17, INK)
	_label("点击切换 · 保持动作进度", Vector2(1025, 187), 12, MUTED)
	var cells := {5: Vector2i(0, 0), 4: Vector2i(1, 0), 3: Vector2i(2, 0), 6: Vector2i(0, 1), 2: Vector2i(2, 1), 7: Vector2i(0, 2), 0: Vector2i(1, 2), 1: Vector2i(2, 2)}
	for index: int in cells:
		var cell: Vector2i = cells[index]
		var button := _button("%s\n%d°" % [ACTOR.VIEW_NAMES[index], index * 45], Vector2(1024 + cell.x * 72, 222 + cell.y * 65), Vector2(64, 56), set_direction.bind(index), true)
		_direction_buttons[index] = button
	_compass_label = _label("朝向", Vector2(1110, 302), 13, MUTED)
	_bones = _check("显示骨骼", Vector2(1020, 443), false, func(value: bool) -> void: overlay.visible = value)
	_soft = _check("耳朵动作", Vector2(1020, 480), true, func(value: bool) -> void:
		actor.set_flexible(value)
		small_actor.set_flexible(value)
	)
	_grid = _check("显示网格", Vector2(1020, 517), true, func(value: bool) -> void:
		show_grid = value
		queue_redraw()
	)
	_label("显示大小", Vector2(1025, 577), 13, MUTED)
	_zoom_label = _label("160%", Vector2(1186, 577), 13, INK)
	_zoom = _slider(Vector2(1026, 615), Vector2(200, 20), 1.0, 2.0, 0.01, 1.60)
	_zoom.value_changed.connect(func(value: float) -> void:
		actor.scale = Vector2.ONE * value
		_zoom_label.text = "%d%%" % roundi(value * 100)
	)
	_play = _button("暂停", Vector2(52, 710), Vector2(94, 39), _toggle_pause)
	_reset = _button("回到开头", Vector2(158, 710), Vector2(93, 39), func() -> void: sample_pose(0.0))
	_previous = _button("上一帧", Vector2(263, 710), Vector2(85, 39), _step.bind(-1))
	_next = _button("下一帧", Vector2(360, 710), Vector2(85, 39), _step.bind(1))
	_label("速度", Vector2(480, 721), 13, MUTED)
	_speed = _slider(Vector2(527, 721), Vector2(190, 20), 0.25, 2.0, 0.25, 1.0)
	_speed_label = _label("1.00×", Vector2(737, 719), 14, INK)
	_speed.value_changed.connect(func(value: float) -> void:
		playback_speed = value
		_speed_label.text = "%.2f×" % value
	)
	_loop = _button("循环：开", Vector2(834, 710), Vector2(103, 39), func() -> void:
		looping = not looping
		_loop.text = "循环：开" if looping else "循环：关"
	)
	_time_label = _label("", Vector2(1041, 720), 14, MUTED)
	_label("动作进度", Vector2(53, 777), 13, MUTED)
	_timeline = _slider(Vector2(150, 775), Vector2(1076, 20), 0.0, cycle_seconds, 0.001, 0.0)
	_timeline.value_changed.connect(func(value: float) -> void:
		if not _updating:
			paused = true
			sample_pose(value)
	)
	_label("Space 播放 / 暂停    左右方向键 切换角度", Vector2(35, 838), 11, MUTED)
	_label("杯子固定位置 · 工具跟随手部", Vector2(1040, 838), 11, MUTED)
	_select_action("walk")
	set_direction(1)
	set_prop("none")


func set_direction(index: int) -> void:
	var phase := phase_time / cycle_seconds
	actor.set_direction(index)
	small_actor.set_direction(index)
	cycle_seconds = actor.get_cycle_seconds()
	phase_time = phase * cycle_seconds
	_updating = true
	_timeline.max_value = cycle_seconds
	_updating = false
	reference_sprite.flip_h = actor.direction > 4
	overlay.skeleton = actor.rig.get_node("Skeleton2D")
	_direction_label.text = "%s · %d°" % [ACTOR.VIEW_NAMES[actor.direction], actor.direction * 45]
	_compass_label.text = ACTOR.VIEW_NAMES[actor.direction]
	for direction: int in _direction_buttons:
		(_direction_buttons[direction] as Button).set_pressed_no_signal(direction == actor.direction)
	sample_pose(phase_time)


func _select_action(value: String) -> void:
	actor.set_action(value)
	small_actor.set_action(value)
	_walk.set_pressed_no_signal(value == "walk")
	_idle.set_pressed_no_signal(value == "idle")
	sample_pose(phase_time)


func _process(delta: float) -> void:
	if not paused and actor.action == "walk":
		phase_time += delta * playback_speed
		if phase_time >= cycle_seconds:
			if looping:
				phase_time = fposmod(phase_time, cycle_seconds)
			else:
				phase_time = cycle_seconds
				paused = true
	sample_pose(phase_time)


func sample_pose(time: float) -> void:
	phase_time = clampf(time, 0, cycle_seconds)
	actor.sample_pose(phase_time)
	small_actor.sample_pose(phase_time)
	_updating = true
	_timeline.value = phase_time
	_updating = false
	_time_label.text = "%.2f / %.2f s" % [phase_time, cycle_seconds]
	var clip: String = "walk_" + actor.view_key
	var elapsed := 0.0
	var source_index := 6
	for index in 7:
		elapsed += SOURCE_FRAMES.get_frame_duration(clip, index) / SOURCE_FRAMES.get_animation_speed(clip)
		if phase_time < elapsed:
			source_index = index
			break
	_reference.region = (SOURCE_FRAMES.get_frame_texture(clip, source_index) as AtlasTexture).region
	_play.text = "播放" if paused else "暂停"
	_state_label.text = "站立姿态" if actor.action == "idle" else ("已暂停 · 可逐帧查看" if paused else "正在播放 · 走路")


func set_prop(id: String) -> void:
	actor.set_prop(id)
	small_actor.set_prop(id)
	for key: String in _prop_buttons:
		(_prop_buttons[key] as Button).set_pressed_no_signal(key == id)


func _toggle_pause() -> void:
	paused = not paused
	if not paused and phase_time >= cycle_seconds:
		phase_time = 0.0
	sample_pose(phase_time)


func _step(direction: int) -> void:
	paused = true
	sample_pose(phase_time + direction / 30.0)


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


func _button(text: String, at: Vector2, size: Vector2, action: Callable, selectable: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = size
	button.toggle_mode = selectable
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("498374") if state == "pressed" else Color("e9efe6")
		style.set_corner_radius_all(9)
		if state == "focus":
			style.bg_color = Color(0, 0, 0, 0)
			style.border_color = Color("a4c3ad")
			style.set_border_width_all(1)
		button.add_theme_stylebox_override(state, style)
	if action.is_valid():
		button.pressed.connect(action)
	add_child(button)
	return button


func _check(text: String, at: Vector2, initial: bool, action: Callable) -> Button:
	var control := _button(text, at, Vector2(208, 31), Callable(), true)
	control.set_pressed_no_signal(initial)
	control.toggled.connect(action)
	return control


func _slider(at: Vector2, size: Vector2, minimum: float, maximum: float, increment: float, initial: float) -> HSlider:
	var slider := HSlider.new()
	slider.position = at
	slider.size = size
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = increment
	slider.value = initial
	add_child(slider)
	return slider


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 860), Color("eeefe8"))
	if _card_style == null:
		return
	for card: Rect2 in [Rect2(32, 135, 235, 535), Rect2(290, 135, 690, 535), Rect2(1004, 135, 244, 535), Rect2(32, 691, 1216, 128)]:
		draw_style_box(_card_style, card)
	if show_grid:
		for x in range(314, 963, 32):
			draw_line(Vector2(x, 218), Vector2(x, 626), Color("f1f3ed"), 1)
		for y in range(218, 627, 32):
			draw_line(Vector2(314, y), Vector2(961, y), Color("f1f3ed"), 1)
	draw_line(Vector2(396, 614), Vector2(876, 614), Color("dce4d8"), 1, true)
	var points := PackedVector2Array()
	for i in 48:
		var angle := i * TAU / 48
		points.append(Vector2(636 + cos(angle) * 92, 615 + sin(angle) * 12))
	draw_colored_polygon(points, Color(0.35, 0.4, 0.3, 0.09))
