extends SceneTree
## Real UI input and GPU captures; never loads or changes a gameplay save.

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
	_check("small_actor" in view, "preview includes a synchronized gameplay-size actor")
	if not "small_actor" in view:
		view.free()
		_finish()
		return
	await _click(view._play)
	_check(view.paused, "pause button stops preview clock")
	view.sample_pose(0.18)
	await _click(view._prop_buttons["cup"])
	for direction in 8:
		await _click(view._direction_buttons[direction])
		_check(view.actor.direction == direction and view.small_actor.direction == direction, "direction buttons update both real rigs")
		_check(view.paused and is_equal_approx(view.actor.phase_time, 0.18), "turning retains paused phase")
		_check(view.small_actor.attachment.prop_id == "cup", "small preview uses the same prop policy")
		_check(is_same(view.actor.player.get_animation("walk"), view.small_actor.player.get_animation("walk")), "large and small previews actually share motion resources")
	await _click(view._prop_buttons["spoon"])
	await _click(view._bones)
	_check(view.overlay.visible, "bone toggle shows actual skeleton overlay")
	await _click(view._soft)
	_check(not view.actor.flexible and not view.small_actor.flexible, "ear toggle reaches both actual rigs")
	await _click(view._soft)
	await _click(view._idle)
	_check(view.actor.action == "idle" and view.small_actor.action == "idle", "standing control stops both rigs")
	await _click(view._walk)
	await _click(view._next)
	_check(absf(view.phase_time - 0.2133333) < 0.002, "frame step advances by 1/30 second")
	await _click(view._previous)
	await _click(view._timeline, 0.75)
	_check(view.paused and absf(view.phase_time - 0.60) < 0.02, "timeline seeks authored animation time")
	await _click(view._speed, 0.7)
	_check(view.playback_speed > 1.0, "speed control changes preview time rate")
	await _click(view._loop)
	view.paused = false
	view.sample_pose(0.79)
	view._process(0.1)
	_check(view.paused and is_equal_approx(view.phase_time, 0.8), "non-looping preview stops at authored endpoint")
	await _click(view._play)
	_check(not view.paused and is_zero_approx(view.phase_time), "play at endpoint restarts")
	view._zoom.value = 1.12
	view._speed.value = 1.0
	view.paused = true
	view.set_direction(1)
	view.sample_pose(0.18)
	await _click(view._bones)
	await _capture("res://docs/qa/skeletal-preview-tool.png")
	await _click(view._prop_buttons["cup"])
	await _capture("res://docs/qa/skeletal-preview-cup.png")
	await _click(view._prop_buttons["none"])
	await _capture("res://docs/qa/skeletal-preview.png")
	for direction in 8:
		view.set_direction(direction)
		view.set_prop("none")
		var empty := await _image()
		view.set_prop("spoon")
		var tool := await _image()
		var changed := 0
		for y in range(235, 614):
			for x in range(420, 810):
				if empty.get_pixel(x, y) != tool.get_pixel(x, y):
					changed += 1
		_check(changed > 700, "hand tool remains clearly visible in direction %d (visible pixels: %d)" % [direction, changed])
	# Sample actual native playback for one full cycle in every direction.
	for direction in 8:
		view.set_direction(direction)
		for index in 8:
			view.sample_pose(float(index) * 0.1)
			await process_frame
	if "--capture-gif" in OS.get_cmdline_user_args():
		var frame_dir := "res://.godot/skeletal_preview_frames/"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(frame_dir))
		view.set_direction(1)
		var frame := 0
		for prop: String in ["none", "cup", "spoon"]:
			view.set_prop(prop)
			for sample in 32:
				view.sample_pose(fposmod(float(sample) * 0.05, 0.8))
				await _capture(frame_dir + "%03d.png" % frame)
				frame += 1
	view.free()
	_finish()


func _capture(path: String) -> void:
	var captured := await _image()
	_check(captured.save_png(path) == OK, "GPU screenshot saved")


func _image() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


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


func _finish() -> void:
	print("SKELETAL PREVIEW RENDER: %d failures" % failures)
	quit(1 if failures else 0)
