extends SceneTree

var failures := 0
var view: Node2D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	view = load("res://presentation/rabbit_skeleton/preview.tscn").instantiate()
	root.add_child(view)
	current_scene = view
	await process_frame
	view.set_process(false)
	await _click(view._play)
	_check(view.paused, "pause input stops the independent preview")
	view.set_direction(2)
	view.sample_pose(0.90)
	view.paused = false
	await _click(view._direction_buttons[0])
	_check(not view.paused and absf(view.phase_time-0.711) < 0.001, "turning from a long source clip near its end preserves phase and playing state")
	view.paused = true
	var cycles := [0.79, 0.96, 1.0, 0.88, 0.75, 0.88, 1.0, 0.96]
	var source_sprite: Sprite2D
	for child in view.get_children():
		if child is Sprite2D and child.texture == view._reference:
			source_sprite = child
	for direction in 8:
		await _click(view._direction_buttons[direction])
		_check(is_equal_approx(view.cycle_seconds, cycles[direction]), "direction uses the current source clip duration")
		view.sample_pose(view.cycle_seconds * 0.32)
		_check(is_equal_approx(view.actor.phase_time, view.small_actor.phase_time), "large and small source rigs stay synchronized")
		_check(is_same(view.actor.player.get_animation("walk"), view.small_actor.player.get_animation("walk")), "same-view native animations are actually shared")
		_check(source_sprite.flip_h == (direction > 4), "source comparison mirrors together with left-facing native rig")
	await _click(view._bones)
	_check(view.overlay.visible, "overlay displays actual source-fitted skeleton")
	await _click(view._bones)
	view.set_direction(1)
	view.sample_pose(0.25)
	await _capture("res://docs/qa/source-skeletal-preview.png")
	await _click(view._prop_buttons["cup"])
	var cup_pose: Transform2D = view.actor.attachment.sprite.transform
	view.sample_pose(0.55)
	_check(cup_pose.is_equal_approx(view.actor.attachment.sprite.transform), "fixed cup does not follow fitted arm motion")
	await _capture("res://docs/qa/source-skeletal-cup.png")
	await _click(view._prop_buttons["spoon"])
	_check(view.actor.attachment.sprite.global_position.distance_to(view.actor.get_hand_socket().global_position) < 0.01, "tool follows source-rabbit hand")
	await _capture("res://docs/qa/source-skeletal-tool.png")
	if "--capture-gif" in OS.get_cmdline_user_args():
		var directory := "res://.godot/source_skeletal_frames/"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		var frame := 0
		for prop: String in ["none", "cup", "spoon"]:
			view.set_prop(prop)
			for index in 32:
				view.sample_pose(fposmod(float(index)*0.06,view.cycle_seconds))
				await _capture(directory + "%03d.png" % frame)
				frame += 1
	view.free()
	await _gallery()
	print("SOURCE SKELETAL RENDER: %d failures" % failures)
	quit(1 if failures else 0)

func _gallery() -> void:
	root.content_scale_size = Vector2i(1792, 800)
	root.size = Vector2i(1792, 800)
	var gallery := Node2D.new()
	root.add_child(gallery)
	var background := ColorRect.new()
	background.color = Color("eeefe8")
	background.size = Vector2(1792, 800)
	gallery.add_child(background)
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art_src/rabbit_walk_frames/source_manifest.json"))
	var source_frames: SpriteFrames = load("res://art/rabbit_walk_frames/rabbit_walk_frames.tres")
	for row in 5:
		var data: Dictionary = meta.directions[row]
		var time := 0.0
		for index in 7:
			var position := Vector2(index * 256 + 64, row * 155 + 146)
			var original := Sprite2D.new()
			original.texture = source_frames.get_frame_texture(data.animation, index)
			original.centered = false
			original.offset = Vector2(-128, -244)
			original.scale = Vector2(0.53, 0.53)
			original.position = position
			gallery.add_child(original)
			var rig: Node2D = load("res://presentation/rabbit_skeleton/rabbit_" + data.key + ".tscn").instantiate()
			rig.position = position + Vector2(128, 0)
			rig.scale = Vector2(0.53, 0.53)
			gallery.add_child(rig)
			var player: AnimationPlayer = rig.get_node("AnimationPlayer")
			player.play("walk")
			player.pause()
			player.seek(time, true)
			time += float(data.durations_ms[index]) / 1000.0
	await _capture("res://docs/qa/source-skeletal-35-pose-comparison.png")
	gallery.free()

func _capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(path) == OK, "actual GPU capture saved")

func _click(control: Control) -> void:
	await process_frame
	var at := control.get_global_rect().get_center()
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
