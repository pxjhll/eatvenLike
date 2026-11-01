extends Node2D
## Simultaneous native playback; group sliders only affect this preview's instances.

const SCENE := preload("res://presentation/gray_cat_walk_frames/gray_cat_walk.tscn")
const FONT := preload("res://art/ui/graybox_font.ttf")
const ORDER := [0, 1, 7, 2, 4, 3, 5, 6]
var actors: Array[Node2D] = []
var sliders: Array[HSlider] = []
var captions: Array[Label] = []
var cycle_labels: Array[Label] = []
var play_button: Button
var reset_button: Button
var paused := false

func _ready() -> void:
	get_window().title = "小灰猫走路 · 八方向"
	get_window().content_scale_size = Vector2i(1100, 790)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_window().size = Vector2i(1100, 790)
	_label("小灰猫走路 · 八方向", Vector2(32, 25), 27)
	var summary := _label("", Vector2(32, 70), 17)
	play_button = _button("暂停", Vector2(862, 35), _toggle_pause)
	reset_button = _button("重置", Vector2(970, 35), _reset)
	for index in ORDER.size():
		var column := index % 4
		var row := index / 4
		var actor: Node2D = SCENE.instantiate()
		actor.position = Vector2(154 + column * 260, 350 + row * 270)
		actor.scale = Vector2.ONE * 0.65
		add_child(actor)
		actor.set_direction(ORDER[index])
		actor.seek_phase(0.0)
		actors.append(actor)
		_label(actor.LABELS[actor.direction], Vector2(52 + column * 260, 148 + row * 270), 21)
		cycle_labels.append(_label("%.2f 秒 / 轮" % actor.get_cycle_seconds(), Vector2(52 + column * 260, 179 + row * 270), 15))
	summary.text = "默认：正面 / 右前 / 左前 %.2f 秒 / 轮；侧面与背面 %.2f 秒 / 轮" % [actors[0].get_cycle_seconds(), actors[3].get_cycle_seconds()]
	for group in 2:
		captions.append(_label("", Vector2(48 + group * 520, 695), 18))
		var slider := HSlider.new()
		slider.position = Vector2(260 + group * 520, 710)
		slider.size = Vector2(260, 24)
		slider.min_value = 0.5
		slider.max_value = 1.75
		slider.step = 0.05
		slider.value = 1.0
		slider.value_changed.connect(_speed.bind(group))
		add_child(slider)
		sliders.append(slider)
		_speed(1.0, group)
	_label("预览调速：仅影响本窗口", Vector2(32, 761), 14)

func _speed(value: float, group: int) -> void:
	for index in actors.size():
		var actor := actors[index]
		if _group(actor.direction) == group:
			actor.set_speed(value)
			cycle_labels[index].text = "%.2f 秒 / 轮" % (actor.get_cycle_seconds() / value)
	var cycle: float = actors[0 if group == 0 else 3].get_cycle_seconds()
	captions[group].text = ("正面三向" if group == 0 else "侧面 / 背面") + "\n%.2f 秒 / 轮 · ×%.2f" % [cycle / value, value]

func _group(direction: int) -> int:
	return 0 if direction in [0, 1, 7] else 1

func _toggle_pause() -> void:
	paused = not paused
	for actor in actors:
		if paused: actor.pause()
		else: actor.play()
	play_button.text = "播放" if paused else "暂停"

func _reset() -> void:
	for slider in sliders: slider.value = 1.0
	for actor in actors: actor.seek_phase(0.0)

func _label(text: String, at: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("493e38"))
	add_child(label)
	return label

func _button(text: String, at: Vector2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = at
	button.size = Vector2(96, 46)
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(callback)
	add_child(button)
	return button

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1100, 790), Color("eee9de"))
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("fffcf4")
	panel.set_corner_radius_all(16)
	for index in ORDER.size():
		draw_style_box(panel, Rect2(32 + index % 4 * 260, 130 + index / 4 * 270, 244, 240))
	draw_style_box(panel, Rect2(32, 680, 1036, 74))
