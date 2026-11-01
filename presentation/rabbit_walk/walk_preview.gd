extends Node2D
## Independent art study. The reusable rabbit scene itself needs no script.

const RABBIT := preload("res://presentation/rabbit_walk/rabbit_side.tscn")
const FONT := preload("res://art/rabbit_walk/preview_font.ttf")
const CYCLE := 0.8
const INK := Color("293c37")
const MUTED := Color("7e8981")
var rabbit: Node2D
var diagram: Node2D
var miniature: Node2D
var phase_time := 0.0
var playback_speed := 1.0
var paused := false
var flexible := true
var mirrored := false
var _updating := false
var _pause: Button
var _mirror: Button
var _soft: Button
var _speed: HSlider
var _scrub: HSlider
var _speed_label: Label
var _phase_label: Label


func _ready() -> void:
	get_window().title = "小兔子 · Godot 原生柔性骨骼走路试作"
	get_window().content_scale_size = Vector2i(1280, 800)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_window().size = Vector2i(1280, 800)
	get_window().min_size = Vector2i(960, 600)
	_label("RABBIT  /  MOTION STUDY", Vector2(43, 25), 13, Color("498374"))
	_label("小兔子的第一步", Vector2(40, 49), 33, INK)
	_label("侧面走路试作   ·   原生骨骼 + 柔性网格   ·   0.8 秒循环", Vector2(43, 105), 15, MUTED)
	_label("01 / SIDE WALK", Vector2(1080, 54), 14, MUTED)
	_label("图像重构 → 部件拆分 → 权重绑定 → 动作", Vector2(895, 106), 13, MUTED)
	_label("原始参考", Vector2(65, 177), 19, INK)
	_label("右侧面 · 用于核对造型", Vector2(65, 210), 13, MUTED)
	_label("柔性行走", Vector2(389, 177), 19, INK)
	_label("耳根 → 中段 → 耳尖，延迟跟随", Vector2(389, 210), 13, MUTED)
	_label("LIVE", Vector2(765, 182), 12, Color("498374"))
	_label("骨骼与镜像", Vector2(888, 177), 19, INK)
	_label("同一个动画 · 水平翻转复用", Vector2(888, 210), 13, MUTED)
	var reference := Sprite2D.new()
	var crop := AtlasTexture.new()
	crop.atlas = load("res://art_src/rabbit_walk/reference.png")
	crop.region = Rect2(251, 18, 174, 320)
	reference.texture = crop
	reference.position = Vector2(192, 409)
	add_child(reference)
	rabbit = _actor(Vector2(602, 568), Vector2(0.96, 0.96))
	diagram = _actor(Vector2(1054, 568), Vector2(-0.86, 0.86))
	diagram.modulate = Color(1, 1, 1, 0.32)
	miniature = _actor(Vector2(779, 572), Vector2(0.23, 0.23))
	var overlay := preload("res://presentation/rabbit_walk/rig_overlay.gd").new()
	overlay.skeleton = diagram.get_node("Skeleton2D")
	overlay.z_index = 20
	add_child(overlay)
	_label("原图", Vector2(175, 580), 12, MUTED)
	_label("双脚交替接地 · 头部轻微起伏", Vector2(389, 580), 13, MUTED)
	_label("小尺寸", Vector2(756, 580), 11, MUTED)
	_label("17 根骨骼 / 耳朵各 3 节", Vector2(888, 580), 13, MUTED)
	_pause = _button("暂停", Vector2(62, 654), Vector2(87, 38), _toggle_pause)
	_mirror = _button("左右镜像", Vector2(162, 654), Vector2(112, 38), _toggle_mirror)
	_soft = _button("柔性耳朵：开", Vector2(287, 654), Vector2(158, 38), _toggle_soft)
	_label("速度", Vector2(476, 663), 14, MUTED)
	_speed = HSlider.new()
	_speed.position = Vector2(524, 663)
	_speed.size = Vector2(202, 22)
	_speed.min_value = 0.25
	_speed.max_value = 1.5
	_speed.step = 0.25
	_speed.value = 1.0
	_speed.value_changed.connect(func(value: float) -> void:
		playback_speed = value
		_speed_label.text = "%.2f×" % value
	)
	add_child(_speed)
	_speed_label = _label("1.00×", Vector2(743, 662), 14, INK)
	_phase_label = _label("", Vector2(998, 663), 13, MUTED)
	_label("循环进度", Vector2(65, 716), 13, MUTED)
	_scrub = HSlider.new()
	_scrub.position = Vector2(159, 714)
	_scrub.size = Vector2(1050, 22)
	_scrub.max_value = CYCLE
	_scrub.step = 0.001
	_scrub.value_changed.connect(_scrub_changed)
	add_child(_scrub)
	_label("原生可编辑：Skeleton2D · Bone2D · Polygon2D · AnimationPlayer", Vector2(44, 775), 11, MUTED)
	_label("SPACE 暂停    M 镜像    F 柔性开关", Vector2(928, 775), 11, MUTED)
	sample_pose(0.0)


func _actor(at: Vector2, size: Vector2) -> Node2D:
	var actor: Node2D = RABBIT.instantiate()
	actor.position = at
	actor.scale = size
	add_child(actor)
	var player: AnimationPlayer = actor.get_node("AnimationPlayer")
	player.play("walk")
	player.pause()
	return actor


func _process(delta: float) -> void:
	if not paused:
		phase_time = fposmod(phase_time + delta * playback_speed, CYCLE)
	sample_pose(phase_time)


func sample_pose(time: float) -> void:
	phase_time = clampf(time, 0, CYCLE)
	for actor in [rabbit, diagram, miniature]:
		var player: AnimationPlayer = actor.get_node("AnimationPlayer")
		player.seek(phase_time, true)
		if not flexible:
			for side in ["Near", "Far"]:
				var ear: Bone2D = actor.get_node("Skeleton2D/Root/Body/Chest/Head/Ear" + side)
				(ear.get_node("Middle") as Bone2D).rotation = 0.0
				(ear.get_node("Middle/Tip") as Bone2D).rotation = 0.0
	_updating = true
	_scrub.value = phase_time
	_updating = false
	_phase_label.text = "%04.2f s / 0.80 s" % phase_time
	queue_redraw()


func _toggle_pause() -> void:
	paused = not paused
	_pause.text = "播放" if paused else "暂停"


func _toggle_mirror() -> void:
	mirrored = not mirrored
	rabbit.scale.x = -0.96 if mirrored else 0.96
	diagram.scale.x = 0.86 if mirrored else -0.86
	miniature.scale.x = -0.23 if mirrored else 0.23


func _toggle_soft() -> void:
	flexible = not flexible
	_soft.text = "柔性耳朵：开" if flexible else "柔性耳朵：关"
	sample_pose(phase_time)


func _scrub_changed(value: float) -> void:
	if _updating:
		return
	paused = true
	_pause.text = "播放"
	sample_pose(value)


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE: _toggle_pause()
		KEY_M: _toggle_mirror()
		KEY_F: _toggle_soft()
		_: return
	get_viewport().set_input_as_handled()


func _label(text: String, at: Vector2, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
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
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("e9efe6") if state != "pressed" else Color("d5e4d6")
		style.set_corner_radius_all(9)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(action)
	add_child(button)
	return button


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 800), Color("eeefe8"))
	for card in [Rect2(40, 154, 304, 462), Rect2(363, 154, 477, 462), Rect2(859, 154, 381, 462), Rect2(40, 635, 1200, 126)]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("ffffff")
		style.set_corner_radius_all(18)
		style.shadow_color = Color(0.25, 0.32, 0.27, 0.035)
		style.shadow_size = 8
		draw_style_box(style, card)
	var floors := [Vector2(386, 815), Vector2(884, 1216)]
	for panel in 2:
		var bounds: Vector2 = floors[panel]
		draw_line(Vector2(bounds.x, 570), Vector2(bounds.y, 570), Color("e2e6dd"), 1.0)
		var actor: Node2D = rabbit if panel == 0 else diagram
		# Two markers per stride, so the ground closes with the authored loop.
		var spacing := CYCLE * 70.0 * absf(actor.transform.x.x) / 2.0
		var shift := fposmod(-phase_time * 70.0 * actor.transform.x.x, spacing)
		for i in range(int((bounds.y - bounds.x) / spacing)):
			var x := bounds.x + i * spacing + shift
			draw_line(Vector2(x, 570), Vector2(x - 5, 575), Color("e2e6dd"), 1.0, true)
	for data: Vector3 in [Vector3(602, 569, 51), Vector3(1054, 569, 46), Vector3(779, 573, 13)]:
		var points := PackedVector2Array()
		for i in 40:
			var angle := i * TAU / 40
			points.append(Vector2(data.x + cos(angle) * data.z, data.y + sin(angle) * data.z * 0.13))
		draw_colored_polygon(points, Color(0.35, 0.40, 0.30, 0.10))
