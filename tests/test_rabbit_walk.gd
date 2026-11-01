extends SceneTree
## Integration checks for the native walking asset; independent from game saves.

const SCENE := "res://presentation/rabbit_walk/rabbit_side.tscn"
const FOOT_NEAR := "Skeleton2D/Root/FootNear"
const FOOT_FAR := "Skeleton2D/Root/FootFar"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(ResourceLoader.exists(SCENE), "editable rabbit side scene exists")
	if failures:
		quit(1)
		return
	var rabbit: Node2D = load(SCENE).instantiate()
	root.add_child(rabbit)
	await process_frame
	var player: AnimationPlayer = rabbit.get_node("AnimationPlayer")
	_check(player.has_animation("walk"), "rabbit has a native walk clip")
	if not player.has_animation("walk"):
		rabbit.free()
		quit(1)
		return
	player.pause()
	var clip := player.get_animation("walk")
	var duration := clip.length
	var foot: Bone2D = rabbit.get_node(FOOT_NEAR)
	var far_foot: Bone2D = rabbit.get_node(FOOT_FAR)
	# A support foot must counter the preview's 70-unit/second forward travel.
	player.play("walk")
	player.seek(0.08, true)
	var planted_start := foot.global_position + Vector2(70.0 * 0.08, 0)
	player.seek(0.28, true)
	var planted_end := foot.global_position + Vector2(70.0 * 0.28, 0)
	_check(planted_start.distance_to(planted_end) < 0.1, "support foot stays planted during forward travel")
	player.seek(0.60, true)
	_check(foot.position.y < -24.0 and is_equal_approx(far_foot.position.y, -16.0), "near foot lifts while far foot supports")
	player.seek(0.20, true)
	_check(far_foot.position.y < -24.0 and is_equal_approx(foot.position.y, -16.0), "far foot lifts while near foot supports")
	# The loop must close for every animated joint, including ear bends.
	player.seek(0.0, true)
	var skeleton: Skeleton2D = rabbit.get_node("Skeleton2D")
	var start: Array[Transform2D] = []
	for i in skeleton.get_bone_count():
		start.append(skeleton.get_bone(i).transform)
	player.seek(duration, true)
	for i in skeleton.get_bone_count():
		_check(start[i].is_equal_approx(skeleton.get_bone(i).transform), "joint %d closes without a loop pop" % i)
	var ear: Bone2D = rabbit.get_node("Skeleton2D/Root/Body/Chest/Head/EarNear/Middle/Tip")
	player.seek(0.0, true)
	var first_bend := ear.rotation
	player.seek(0.18, true)
	_check(absf(ear.rotation - first_bend) > 0.05, "ear tip bends independently through the walk")
	for node in rabbit.get_node("Skin").get_children():
		var mesh: Polygon2D = node
		_check(mesh.texture != null and mesh.get_bone_count() > 0, "%s is a textured weighted mesh" % mesh.name)
		_check(not mesh.polygons.is_empty(), "%s has explicit deformation triangles" % mesh.name)
		for vertex in mesh.polygon.size():
			var total := 0.0
			for bone in mesh.get_bone_count():
				var weights := mesh.get_bone_weights(bone)
				_check(weights.size() == mesh.polygon.size(), "%s weights cover all mesh vertices" % mesh.name)
				total += weights[vertex]
			_check(absf(total - 1.0) < 0.001, "%s vertex weights are normalized" % mesh.name)
		if mesh.name in ["EarNear", "EarFar"]:
			var blended := false
			for bone in mesh.get_bone_count():
				for weight in mesh.get_bone_weights(bone):
					if weight > 0.05 and weight < 0.95:
						blended = true
			_check(blended, "%s has blended weights for continuous bending" % mesh.name)
	rabbit.free()
	print("RABBIT WALK: %d failures" % failures)
	quit(1 if failures else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
