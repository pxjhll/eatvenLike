extends VBoxContainer
## Embeddable HUD page. No window resizing, scene replacement or save mutation.

const Library := preload("res://presentation/characters/character_library.gd")
var art_id := "rabbit"
var available_actions: Array = []
var direction := 0
var frame_actor: Node2D
var character_select: OptionButton
var action_select: OptionButton
var play_button: Button
var previous_button: Button
var next_button: Button
var speed_slider: HSlider
var timeline: HSlider
var directions: Array[Button] = []
var _stage: Control
var _static := Sprite2D.new()
var _details: Label
var _frame_label: Label
var _updating := false


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	var selectors := HBoxContainer.new()
	selectors.add_theme_constant_override("separation", 12)
	add_child(selectors)
	character_select = OptionButton.new()
	character_select.custom_minimum_size = Vector2(210, 58)
	character_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id: String in Library.IDS:
		character_select.add_item(Library.NAMES[id])
	character_select.item_selected.connect(func(index: int) -> void: select_character(Library.IDS[index]))
	selectors.add_child(character_select)
	action_select = OptionButton.new()
	action_select.custom_minimum_size = Vector2(170, 58)
	action_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_select.item_selected.connect(_select_action)
	selectors.add_child(action_select)
	_stage = Control.new()
	_stage.custom_minimum_size.y = 278
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.resized.connect(_place_visuals)
	add_child(_stage)
	var background := Panel.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fffaf0")
	style.set_corner_radius_all(18)
	background.add_theme_stylebox_override("panel", style)
	_stage.add_child(background)
	_stage.add_child(_static)
	frame_actor = Library.RABBIT_SCENE.instantiate()
	_stage.add_child(frame_actor)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	add_child(controls)
	play_button = _button(controls, "暂停", _toggle_play)
	previous_button = _button(controls, "上一帧", _step.bind(-1))
	next_button = _button(controls, "下一帧", _step.bind(1))
	speed_slider = HSlider.new()
	speed_slider.min_value = 0.25
	speed_slider.max_value = 2.0
	speed_slider.step = 0.25
	speed_slider.value = 1.0
	speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_slider.custom_minimum_size.x = 100
	speed_slider.value_changed.connect(func(value: float) -> void: frame_actor.set_speed(value))
	controls.add_child(speed_slider)
	timeline = HSlider.new()
	timeline.max_value = 1.0
	timeline.step = 0.001
	timeline.custom_minimum_size.y = 32
	timeline.value_changed.connect(func(value: float) -> void:
		if not _updating and frame_actor.visible:
			frame_actor.pause()
			frame_actor.seek_phase(value)
	)
	add_child(timeline)
	_frame_label = Label.new()
	_frame_label.add_theme_font_size_override("font_size", 18)
	add_child(_frame_label)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	add_child(grid)
	for index in 8:
		var button := _button(grid, frame_actor.LABELS[index], set_direction.bind(index))
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		directions.append(button)
	_details = Label.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_theme_font_size_override("font_size", 18)
	add_child(_details)
	visibility_changed.connect(_visibility)
	select_character(art_id)


func _button(parent: Node, caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(0, 54)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func select_character(id: String) -> void:
	if id not in Library.IDS:
		return
	art_id = id
	if not is_node_ready():
		return
	character_select.select(Library.IDS.find(id))
	available_actions = Library.actions(id)
	action_select.clear()
	for action: Dictionary in available_actions:
		action_select.add_item(action.label)
	_static.texture = Library.portrait(id)
	_static.scale = Vector2.ONE * 224.0 / _static.texture.get_height()
	_static.centered = false
	_static.offset = Vector2(-_static.texture.get_width() / 2.0, -_static.texture.get_height())
	_select_action(0)
	_place_visuals()


func _select_action(index: int) -> void:
	if index < 0 or index >= available_actions.size():
		return
	action_select.select(index)
	var action: Dictionary = available_actions[index]
	var animated: bool = action.type == "frames"
	frame_actor.visible = animated
	_static.visible = not animated
	if animated:
		frame_actor.set_action(action.id)
		frame_actor.seek_phase(0.0)
		frame_actor.play()
	else:
		frame_actor.pause()
	for button in [play_button, previous_button, next_button, speed_slider, timeline]:
		button.visible = animated
	_frame_label.visible = animated
	for button in directions:
		button.disabled = not action.directional
	set_direction(direction)
	_details.text = "切换方向查看动作，可暂停、逐帧查看或拖动进度条。" if animated else "当前可查看站姿，其他动作待补充。"


func set_direction(value: int) -> void:
	direction = posmod(value, 8)
	frame_actor.set_direction(direction)
	for index in directions.size():
		directions[index].set_pressed_no_signal(index == direction)


func _toggle_play() -> void:
	if frame_actor.sprite.is_playing():
		frame_actor.pause()
	else:
		frame_actor.play()


func _step(offset: int) -> void:
	frame_actor.pause()
	var sprite: AnimatedSprite2D = frame_actor.sprite
	var count := sprite.sprite_frames.get_frame_count(sprite.animation)
	sprite.set_frame_and_progress(posmod(sprite.frame + offset, count), 0.0)


func _place_visuals() -> void:
	if is_instance_valid(frame_actor):
		frame_actor.position = Vector2(_stage.size.x / 2.0, 258)
		_static.position = frame_actor.position


func _visibility() -> void:
	if is_instance_valid(frame_actor) and not is_visible_in_tree():
		frame_actor.pause()


func _process(_delta: float) -> void:
	if not is_visible_in_tree() or not is_instance_valid(frame_actor) or not frame_actor.visible:
		return
	_updating = true
	timeline.value = frame_actor.get_phase()
	_updating = false
	play_button.text = "暂停" if frame_actor.sprite.is_playing() else "播放"
	_frame_label.text = "第 %d / %d 帧 · %.2f 秒 / 轮 · %.2f 倍速" % [frame_actor.sprite.frame + 1, frame_actor.sprite.sprite_frames.get_frame_count(frame_actor.sprite.animation), frame_actor.get_cycle_seconds(), speed_slider.value]
