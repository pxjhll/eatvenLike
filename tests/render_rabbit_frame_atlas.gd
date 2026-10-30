extends SceneTree
## Actual renderer and input checks against the frame-only walking preview.

var failures := 0
var view: Node2D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	view = load("res://presentation/rabbit_walk_frames/preview.tscn").instantiate()
	root.add_child(view)
	current_scene = view
	await process_frame
	await _click(view._play)
	_check(view.paused and not view.actor.sprite.is_playing(), "pause controls the actual AnimatedSprite2D")
	view.actor.seek_phase(0.37)
	await _click(view._speed, 0.80)
	_check(view.speed > 1 and view.actor.sprite.speed_scale == view.speed, "speed slider controls native playback")
	for direction in 8:
		await _click(view._directions[direction])
		_check(view.actor.direction == direction, "direction button selects actual clip")
		_check(view.paused and absf(view.actor.get_phase() - 0.37) < 0.001, "switch preserves paused gait phase")
		_check(view.small.sprite.flip_h == view.actor.sprite.flip_h, "small preview mirrors consistently")
		_check(absf(view.small.get_phase() - view.actor.get_phase()) < 0.001, "source-size and game-size previews stay synchronized")
	await _click(view._next)
	_check(view.actor.sprite.frame == 3, "next advances one actual keyframe")
	await _click(view._previous)
	_check(view.actor.sprite.frame == 2, "previous reverses actual keyframe step")
	await _click(view._timeline, 0.80)
	_check(view.paused and absf(view.actor.get_phase() - 0.80) < 0.02, "timeline seeks by actual frame durations")
	# Resume very near the end and check the native wrap at a throttled speed.
	view.actor.set_speed(0.1)
	view.actor.seek_phase(0.9999)
	var loops := [0]
	view.actor.sprite.animation_looped.connect(func() -> void: loops[0] += 1)
	await _click(view._play)
	for i in 10:
		await process_frame
	_check(loops[0] > 0, "native frame animation emits a real loop")
	_check(view.actor.sprite.frame == 0, "loop wraps from last distinct pose directly to first")
	await _click(view._play)
	view._speed.value = 1.0
	view.set_direction(2)
	view.actor.seek_phase(0.20)
	view._refresh()
	await _capture("res://docs/qa/rabbit-frame-preview.png")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/rabbit_frame_capture"))
	# Two full loops per direction, evenly sampled for a 2.5-second comparison GIF.
	for frame in 50:
		var time := frame * 0.05
		var image := Image.create(1280, 520, false, Image.FORMAT_RGBA8)
		image.fill(Color("edf1e8"))
		for direction in 8:
			view.set_direction(direction)
			var cycle: float = view.actor.get_cycle_seconds()
			view.actor.seek_phase(fposmod(time / cycle, 1.0))
			var texture: Texture2D = view.actor.sprite.sprite_frames.get_frame_texture(view.actor.sprite.animation, view.actor.sprite.frame)
			var cell: Image = texture.get_image()
			if view.actor.sprite.flip_h:
				cell.flip_x()
			image.blend_rect(cell, Rect2i(0, 0, 256, 256), Vector2i(direction % 4 * 320 + 32, direction / 4 * 260))
		assert(image.save_png("res://.godot/rabbit_frame_capture/%03d.png" % frame) == OK)
	view.free()
	print("RABBIT FRAME RENDER: %d failures; actual input, native loop, eight directions" % failures)
	quit(1 if failures else 0)


func _capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(path) == OK, "rendered preview saved")


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
