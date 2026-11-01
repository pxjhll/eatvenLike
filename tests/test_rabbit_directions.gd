extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var path := "res://presentation/rabbit_walk/directional_rabbit.gd"
	_check(ResourceLoader.exists(path), "directional walking actor exists")
	if failures:
		quit(1)
		return
	var actor: Node2D = load(path).new()
	root.add_child(actor)
	await process_frame
	var expected := ["front", "front_right", "side", "back_right", "back", "back_right", "side", "front_right"]
	for direction in 8:
		actor.sample_pose(0.24)
		actor.set_direction(direction)
		_check(actor.view_key == expected[direction], "direction %d selects its actual authored view" % direction)
		_check(is_equal_approx(actor.phase_time, 0.24), "angle switch preserves animation phase")
		_check((actor.rig.transform.x.x < 0) == (direction > 4), "only left-facing views are mirrored")
		var player: AnimationPlayer = actor.rig.get_node("AnimationPlayer")
		_check(player.has_animation("walk"), "each angle has a real walk animation")
		var foot: Bone2D = actor.rig.get_node("Skeleton2D/Root/FootNear")
		actor.sample_pose(0.10)
		var before := foot.position
		actor.sample_pose(0.30)
		_check(before.distance_to(foot.position) > 2.0, "selected angle really animates its feet")
		actor.set_flexible(false)
		var tip: Bone2D = actor.rig.get_node("Skeleton2D/Root/Body/Chest/Head/EarNear/Middle/Tip")
		_check(is_zero_approx(tip.rotation), "rigid ear setting survives angle changes")
		actor.set_flexible(true)
		actor.sample_pose(0.18)
		_check(absf(tip.rotation) > 0.02, "flexible ears work in every authored view")
		actor.set_action("idle")
		actor.sample_pose(0.1)
		before = foot.position
		actor.sample_pose(0.6)
		_check(before.is_equal_approx(foot.position), "standing pose remains still")
		actor.set_action("walk")
	actor.free()
	print("RABBIT DIRECTIONS: %d failures" % failures)
	quit(1 if failures else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
