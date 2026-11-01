extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(ResourceLoader.exists("res://presentation/rabbit_walk/directional_rabbit.gd"), "independent native skeletal actor is available without replacing frame actor")
	var script: Script = load("res://presentation/rabbit_walk/directional_rabbit.gd")
	var actor: Node2D = script.new()
	var other: Node2D = script.new()
	root.add_child(actor)
	root.add_child(other)
	await process_frame
	_check(actor.has_method("set_prop"), "skeletal actor supports independent prop policies")
	if not actor.has_method("set_prop"):
		actor.free()
		other.free()
		_finish()
		return
	actor.set_direction(1)
	other.set_direction(1)
	_check(is_same(actor.player.get_animation("walk"), other.player.get_animation("walk")), "actors share authored motion resources")
	_check(not actor.player.get_animation("walk").resource_path.contains("::"), "walk motion is an external resource suitable for reuse")
	actor.sample_pose(0.10)
	other.sample_pose(0.32)
	_check(absf(actor.player.current_animation_position - other.player.current_animation_position) > 0.1, "shared motions retain independent playback state")
	actor.set_prop("cup")
	for direction in 8:
		actor.set_direction(direction)
		actor.sample_pose(0.10)
		var cup_start: Transform2D = actor.attachment.sprite.transform
		actor.sample_pose(0.31)
		_check(cup_start.is_equal_approx(actor.attachment.sprite.transform), "fixed cup does not inherit gait or arm movement in direction %d" % direction)
		_check(is_zero_approx(actor.attachment.sprite.rotation), "fixed cup remains upright")
		_check((actor.attachment.sprite.z_index < 0) == (direction in [3, 4, 5]), "cup depth matches facing")
		var cached: Node2D = actor.rig
		actor.set_direction((direction + 1) % 8)
		actor.set_direction(direction)
		_check(is_same(cached, actor.rig), "turning reuses the authored rig")
		_check(actor.attachment.prop_id == "cup" and is_equal_approx(actor.phase_time, 0.31), "turning retains prop and gait phase")
	actor.set_prop("spoon")
	for direction in 8:
		actor.set_direction(direction)
		actor.sample_pose(0.10)
		var first: Transform2D = actor.attachment.sprite.transform
		_check(actor.attachment.sprite.global_position.distance_to(actor.get_hand_socket().global_position) < 0.01, "tool grip follows actual hand socket after turning")
		actor.sample_pose(0.31)
		_check(not first.is_equal_approx(actor.attachment.sprite.transform), "tool follows animated hand rather than fixed cup anchor")
		_check(actor.attachment.sprite.global_position.distance_to(actor.get_hand_socket().global_position) < 0.01, "tool stays attached throughout gait")
		var tool_axis: Vector2 = actor.attachment.sprite.global_transform.x.normalized()
		var hand_axis: Vector2 = actor.get_hand_socket().global_transform.x.normalized()
		_check(tool_axis.dot(hand_axis) > 0.999, "tool follows the hand rotation including mirroring")
	other.set_prop("none")
	_check(actor.attachment.sprite.visible and not other.attachment.sprite.visible, "attachment selection is instance-local")
	actor.set_prop("none")
	_check(not actor.attachment.sprite.visible, "no-prop mode hides the example attachment")
	actor.free()
	other.free()
	_finish()


func _finish() -> void:
	print("SKELETAL PREVIEW: %d failures" % failures)
	quit(1 if failures else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
