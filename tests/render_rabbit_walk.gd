extends SceneTree
## Actual renderer capture and real GUI input against the standalone preview.

var failures := 0
var view: Node2D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	view = load("res://presentation/rabbit_walk/walk_preview.tscn").instantiate()
	root.add_child(view)
	current_scene = view
	await process_frame
	view.set_process(false)
	view.sample_pose(0.18)
	await _capture("res://docs/qa/rabbit-walk.png")
	await _click(view._pause)
	_check(view.paused, "pause receives actual mouse input")
	var before: float = view.phase_time
	view._process(0.1)
	_check(is_equal_approx(view.phase_time, before), "paused preview does not advance")
	await _click(view._mirror)
	_check(view.rabbit.transform.x.x < 0 and view.diagram.transform.x.x > 0, "mirror flips both real rigs")
	await _key(KEY_SPACE)
	_check(not view.paused and view.rabbit.transform.x.x < 0, "Space pauses playback even when the mirror button has focus")
	await _key(KEY_SPACE)
	_check(view.paused, "Space toggles back to paused")
	await _capture("res://.godot/rabbit-ear-flexible.png")
	var flexible_frame := root.get_texture().get_image()
	await _click(view._soft)
	_check(not view.flexible, "flexible toggle disables secondary ear bends")
	view.sample_pose(0.18)
	var ear: Bone2D = view.rabbit.get_node("Skeleton2D/Root/Body/Chest/Head/EarNear/Middle/Tip")
	_check(is_zero_approx(ear.rotation), "rigid mode straightens the actual ear tip bone")
	await _capture("res://.godot/rabbit-ear-rigid.png")
	var rigid_frame := root.get_texture().get_image()
	var changed := 0
	# Count actual GPU-rendered differences only in the main rabbit's ears.
	for y in range(246, 342):
		for x in range(535, 660):
			var difference := flexible_frame.get_pixel(x, y) - rigid_frame.get_pixel(x, y)
			if absf(difference.r) + absf(difference.g) + absf(difference.b) > 0.08:
				changed += 1
	_check(changed > 100, "weighted ear bones visibly deform the rendered texture")
	await _click(view._soft)
	_check(view.flexible and absf(ear.rotation) > 0.02, "flexible mode restores the actual ear deformation (enabled=%s, bend=%f)" % [view.flexible, ear.rotation])
	await _click(view._mirror)
	# Slider uses a real GUI pointer event, not a direct signal emit.
	await _click(view._speed, 0.81)
	_check(view.playback_speed > 1.0, "speed slider changes real playback rate")
	await _click(view._scrub, 0.40)
	_check(view.paused and absf(view.phase_time - 0.32) < 0.025, "timeline seeks and pauses the real clip (paused=%s, time=%f)" % [view.paused, view.phase_time])
	view.playback_speed = 1.0
	view._speed.value = 1.0
	view.paused = false
	view._pause.text = "暂停"
	view.sample_pose(0.0)
	await _capture("res://.godot/rabbit-loop-start.png")
	var floor_start := root.get_texture().get_image()
	view.sample_pose(0.8)
	await _capture("res://.godot/rabbit-loop-end.png")
	var floor_end := root.get_texture().get_image()
	var floor_difference := 0
	for y in range(570, 577):
		for x in range(390, 810):
			if not floor_start.get_pixel(x, y).is_equal_approx(floor_end.get_pixel(x, y)):
				floor_difference += 1
	_check(floor_difference < 10, "floor pattern closes with the walk cycle (different pixels=%d)" % floor_difference)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/rabbit_walk_frames"))
	for frame in 32:
		view.sample_pose(frame * 0.8 / 32)
		await _capture("res://.godot/rabbit_walk_frames/%03d.png" % frame)
	print("RABBIT RENDER: %d failures, 32 real Godot frames" % failures)
	view.free()
	quit(1 if failures else 0)


func _capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image.save_png(path) == OK, "rendered frame saved")


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


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)


func _key(keycode: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.pressed = down
		root.push_input(event, true)
		await process_frame
