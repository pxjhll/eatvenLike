extends SceneTree

var failures := 0
var view: Node2D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	view = load("res://presentation/rabbit_walk/animation_viewer.tscn").instantiate()
	root.add_child(view)
	current_scene = view
	await process_frame
	view.set_process(false)
	view.sample_pose(0.18)
	await _click(view._play)
	_check(view.paused, "playback can be paused by mouse")
	await _click(view._speed, 0.70)
	var speed: float = view.playback_speed
	_check(speed > 1.0, "speed control changes playback rate")
	await _click(view._bones)
	_check(view.overlay.visible, "bone overlay can be shown")
	await _click(view._soft)
	_check(not view.actor.flexible, "flexible ear control reaches actual actor")
	for direction in 8:
		await _click(view._direction_buttons[direction])
		_check(view.actor.direction == direction, "direction button selects %d" % direction)
		_check(is_equal_approx(view.phase_time, 0.18) and view.paused, "angle switch preserves phase and pause")
		_check(is_equal_approx(view.playback_speed, speed), "angle switch preserves speed")
		_check(view.overlay.skeleton == view.actor.rig.get_node("Skeleton2D"), "overlay follows replacement skeleton")
		_check(view._reference.region == view.REFERENCE_RECTS[direction], "reference follows selected direction")
		_check(not view.actor.flexible, "angle switch preserves rigid ear setting")
	await _click(view._soft)
	await _click(view._bones)
	await _click(view._idle)
	_check(view.actor.action == "idle", "standing action selectable")
	var foot: Bone2D = view.actor.rig.get_node("Skeleton2D/Root/FootNear")
	var foot_before := foot.position
	view.sample_pose(0.35)
	_check(foot_before.is_equal_approx(foot.position), "standing action displays a still pose")
	await _click(view._walk)
	_check(view.actor.action == "walk", "walk action selectable")
	view.sample_pose(0.18)
	await _click(view._next)
	_check(view.paused and absf(view.phase_time - 0.2133333) < 0.002, "next frame advances by 1/30 second and pauses")
	await _click(view._previous)
	_check(absf(view.phase_time - 0.18) < 0.002, "previous frame reverses the step")
	await _click(view._timeline, 0.35)
	_check(view.paused and absf(view.phase_time - 0.28) < 0.02, "timeline seeks actual clip")
	await _click(view._loop)
	view.paused = false
	view.sample_pose(0.79)
	view._process(0.1)
	_check(view.paused and is_equal_approx(view.phase_time, 0.8), "non-loop playback stops at the end")
	await _click(view._play)
	_check(not view.paused and is_zero_approx(view.phase_time), "play at end restarts the clip")
	await _click(view._loop)
	await _click(view._reset)
	_check(is_zero_approx(view.phase_time), "rewind reaches start")
	await _click(view._zoom, 0.9)
	_check(view.actor.scale.x > 1.2, "zoom changes actual character size")
	await _key(KEY_RIGHT)
	_check(view.actor.direction == 0, "right key wraps to front after front-left")
	await _key(KEY_LEFT)
	_check(view.actor.direction == 7, "left key wraps to front-left")
	await _key(KEY_SPACE)
	_check(view.paused, "global space works after controls have focus")
	view._zoom.value = 1.12
	view._speed.value = 1.0
	view.paused = false
	view.set_direction(1)
	view.sample_pose(0.18)
	await _capture("res://docs/qa/rabbit-animation-viewer.png")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/rabbit_viewer_frames"))
	for direction in 8:
		view.set_direction(direction)
		for frame in 16:
			view.sample_pose(frame * 0.05)
			await _capture("res://.godot/rabbit_viewer_frames/%03d.png" % (direction * 16 + frame))
	view.free()
	await _gallery()
	print("RABBIT VIEWER: %d failures, all 8 angles, 128 actual Godot frames" % failures)
	quit(1 if failures else 0)


func _gallery() -> void:
	var gallery := Node2D.new()
	root.add_child(gallery)
	var background := ColorRect.new()
	background.size = Vector2(1280, 860)
	background.color = Color("eeefe8")
	gallery.add_child(background)
	var title := Label.new()
	title.text = "八个方向 · 同一走路时刻"
	title.position = Vector2(35, 24)
	title.add_theme_font_override("font", load("res://art/ui/graybox_font.ttf"))
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color("293c37"))
	gallery.add_child(title)
	var script: Script = load("res://presentation/rabbit_walk/directional_rabbit.gd")
	for direction in 8:
		var actor: Node2D = script.new()
		actor.position = Vector2(160 + direction % 4 * 320, 405 + direction / 4 * 388)
		actor.scale = Vector2(0.88, 0.88)
		gallery.add_child(actor)
		actor.set_direction(direction)
		actor.sample_pose(0.18)
		var label := Label.new()
		label.text = "%s · %d°" % [script.VIEW_NAMES[direction], direction * 45]
		label.position = actor.position + Vector2(-37, 12)
		label.add_theme_font_override("font", load("res://art/ui/graybox_font.ttf"))
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", Color("293c37"))
		gallery.add_child(label)
	await _capture("res://docs/qa/rabbit-eight-directions.png")
	gallery.free()


func _capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(path) == OK, "frame saved")


func _click(control: Control, fraction: float = 0.5) -> void:
	await process_frame
	var at := control.get_global_rect().position + control.size * Vector2(fraction, 0.5)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
		await process_frame


func _key(keycode: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.pressed = down
		root.push_input(event, true)
		await process_frame


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
