extends SceneTree
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(ResourceLoader.exists("res://presentation/rabbit_skeleton/preview.tscn"), "preview is built from current frame rabbit rather than old reconstructed artwork")
	var complete_path := "res://art_src/rabbit_skeleton/complete_manifest.json"
	_check(FileAccess.file_exists(complete_path), "runtime artwork is exported from complete-parts atlases")
	if not FileAccess.file_exists(complete_path):
		_finish()
		return
	var complete: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(complete_path))
	_check(complete.views.front_right.sha256 == "7cb88cf990529f129329ced9df83b8192344159eafaaa8359c4e0ff4387437e6", "right-front artwork uses the exact user-approved complete atlas")
	var manifest_path := "res://art_src/rabbit_skeleton/source_fit.json"
	_check(FileAccess.file_exists(manifest_path), "source-derived poses and original durations are recorded")
	if not FileAccess.file_exists(manifest_path):
		_finish()
		return
	var fit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	for view: String in ["front", "front_right", "right", "back_right", "back"]:
		var data: Dictionary = fit.views[view]
		_check(data.frames.size() == 7, "all seven distinct source poses are fitted")
		var scene: PackedScene = load("res://presentation/rabbit_skeleton/rabbit_" + view + ".tscn")
		_check(scene != null, "source-derived native rig exists")
		if scene == null:
			continue
		var actor: Node2D = scene.instantiate()
		root.add_child(actor)
		var player: AnimationPlayer = actor.get_node("AnimationPlayer")
		var clip := player.get_animation("walk")
		_check(is_equal_approx(clip.length, float(data.cycle_ms) / 1000.0), "direction retains original source cycle")
		_check(actor.get_meta("source") == "rabbit_walk_frames", "native rig records the correct art source")
		_check(actor.get_meta("artwork") == "complete_parts", "rig renders complete reconstructed parts")
		_check(actor.get_node("Skeleton2D").get_bone_count() >= 11, "animation is driven by a real native skeleton")
		_check(not actor.has_node("Skin/Surface"), "whole-character deforming surface is absent")
		var visuals: Array[Sprite2D] = []
		var skeleton: Skeleton2D = actor.get_node("Skeleton2D")
		for bone_index in skeleton.get_bone_count():
			for child in skeleton.get_bone(bone_index).get_children():
				if child is Sprite2D:
					visuals.append(child)
		_check(visuals.size() >= 9, "independent source cutouts are displayed as sprites attached to actual bones")
		var baseline := {}
		for sprite in visuals:
			_check(sprite.texture.resource_path.contains("/complete/"), "every visible part comes from the complete atlas export")
			baseline[sprite] = Vector2(sprite.global_transform.x.length(),sprite.global_transform.y.length())
		player.play("walk")
		player.pause()
		for phase in [0.0, 0.13, 0.31, 0.55, 0.79, 0.99]:
			player.seek(clip.length * phase, true)
			for sprite in visuals:
				var transform := sprite.global_transform
				var size: Vector2 = baseline[sprite]
				_check(absf(transform.x.length()-size.x) < 0.0001 and absf(transform.y.length()-size.y) < 0.0001, "cutout width and height remain unchanged throughout the gait")
				_check(absf(transform.x.dot(transform.y)) < 0.0001, "cutouts never shear as their parent bones move")
		actor.free()
	if failures > 0:
		_finish()
		return
	var script: Script = load("res://presentation/rabbit_skeleton/directional_rabbit.gd")
	var actor: Node2D = script.new()
	root.add_child(actor)
	actor.set_direction(1)
	var head: Sprite2D = actor.rig.get_node("Skeleton2D/Root/Body/Chest/Head/Visual")
	var full_head := head.texture
	actor.sample_pose(0.25)
	actor.sample_pose(0.31)
	_check(head.texture == full_head and not head.has_node("Face"), "complete head is retained without cutting a rectangular facial patch")
	actor.set_prop("cup")
	for direction in 8:
		actor.set_direction(direction)
		actor.sample_pose(actor.get_cycle_seconds()*0.25)
		var fixed: Transform2D = actor.attachment.sprite.transform
		actor.sample_pose(actor.get_cycle_seconds()*0.65)
		_check(fixed.is_equal_approx(actor.attachment.sprite.transform), "fixed cup stays fixed through the source gait")
		actor.set_prop("spoon")
		_check(actor.attachment.sprite.global_position.distance_to(actor.get_hand_socket().global_position) < 0.01, "hand tool stays on the actual mirrored source-rabbit socket")
		var phase: float = actor.phase_time/actor.get_cycle_seconds()
		actor.set_direction((direction+1)%8)
		_check(absf(actor.phase_time/actor.get_cycle_seconds()-phase) < 0.001, "turning between unequal source periods preserves normalized phase")
		actor.set_prop("cup")
	actor.free()
	_finish()

func _finish() -> void:
	print("SOURCE SKELETAL RABBIT: %d failures" % failures)
	quit(1 if failures else 0)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
