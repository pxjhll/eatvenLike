extends SceneTree
## Rebuilds editable native Godot resources, not pre-rendered animation frames.

const ART := "res://art/rabbit_walk/"
const OUTPUT := "res://presentation/rabbit_walk/rabbit_side.tscn"
const DURATION := 0.8
const BASE := "Root/Body/Chest/Head/"
const CUTS := {
	"head": Rect2i(75, 163, 364, 329),
	"ear_far": Rect2i(556, 92, 184, 350),
	"ear_near": Rect2i(946, 105, 189, 355),
	"body": Rect2i(97, 586, 303, 291),
	"arm_far": Rect2i(565, 605, 165, 231),
	"arm_near": Rect2i(979, 614, 154, 235),
	"foot_far": Rect2i(160, 1023, 189, 127),
	"foot_near": Rect2i(543, 1009, 202, 147),
	"tail": Rect2i(977, 1009, 125, 120),
}
var rig: Node2D
var skeleton: Skeleton2D
var skin: Node2D
var joints: Dictionary = {}
var art_dir := ART
var walk_axis := Vector2.RIGHT


func _initialize() -> void:
	call_deferred("_build")


func _build() -> void:
	if "--parts" in OS.get_cmdline_user_args():
		var atlas := Image.load_from_file("res://art_src/rabbit_walk/parts_atlas.png")
		for part: String in CUTS:
			var error := atlas.get_region(CUTS[part]).save_png(ART + part + ".png")
			assert(error == OK, "Could not save cutout " + part)
		print("RABBIT: extracted nine transparent cutouts")
		quit()
		return
	rig = Node2D.new()
	rig.name = "RabbitSide"
	rig.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rig.set_meta("cycle_seconds", DURATION)
	rig.set_meta("travel_units_per_second", 70.0)
	rig.set_meta("source", "User reference; occluded parts reconstructed with built-in imagegen")
	root.add_child(rig)
	skeleton = Skeleton2D.new()
	skeleton.name = "Skeleton2D"
	_owned(rig, skeleton)
	skin = Node2D.new()
	skin.name = "Skin"
	_owned(rig, skin)
	_bone("Root", skeleton, Vector2.ZERO, 25)
	_bone("Body", joints.Root, Vector2(0, -62), 34)
	_bone("Chest", joints.Body, Vector2(0, -34), 18)
	_bone("Head", joints.Chest, Vector2(0, -13), 48)
	_bone("FootFar", joints.Root, Vector2(-12, -16), 22, 0)
	_bone("FootNear", joints.Root, Vector2(10, -16), 24, 0)
	_bone("Tail", joints.Body, Vector2(-51, 15), 16, PI)
	_bone("ArmFar", joints.Chest, Vector2(27, -3), 27, PI / 2)
	_bone("ArmFarTip", joints.ArmFar, Vector2(0, 26), 24, PI / 2)
	_bone("ArmNear", joints.Chest, Vector2(-7, -5), 28, PI / 2)
	_bone("ArmNearTip", joints.ArmNear, Vector2(0, 28), 23, PI / 2)
	_bone("EarFar", joints.Head, Vector2(-23, -115), 35)
	_bone("EarFarMiddle", joints.EarFar, Vector2(0, -35), 35, -PI / 2, "Middle")
	_bone("EarFarTip", joints.EarFarMiddle, Vector2(0, -35), 26, -PI / 2, "Tip")
	_bone("EarNear", joints.Head, Vector2(16, -106), 37)
	_bone("EarNearMiddle", joints.EarNear, Vector2(0, -37), 37, -PI / 2, "Middle")
	_bone("EarNearTip", joints.EarNearMiddle, Vector2(0, -37), 27, -PI / 2, "Tip")
	# Parts are all in skeleton rest coordinates; only bones animate.
	_mesh("FootFar", "foot_far", Rect2(-35, -31, 48, 32), ["FootFar"], [], -6, 4, 3)
	_mesh("FootNear", "foot_near", Rect2(-14, -34, 54, 36), ["FootNear"], [], -4, 4, 3)
	_mesh("ArmFar", "arm_far", Rect2(11, -103, 38, 57), ["ArmFar", "ArmFarTip"], [0.15, 0.82], -3, 4, 8, false)
	_mesh("Tail", "tail", Rect2(-70, -64, 35, 34), ["Tail"], [], -2, 4, 4)
	_mesh("Body", "body", Rect2(-55, -118, 111, 107), ["Body", "Chest"], [0.12, 0.82], 0, 6, 10)
	_mesh("ArmNear", "arm_near", Rect2(-26, -106, 41, 63), ["ArmNear", "ArmNearTip"], [0.15, 0.85], 3, 4, 8, false)
	_mesh("EarFar", "ear_far", Rect2(-52, -330, 57, 118), ["EarFar", "EarFarMiddle", "EarFarTip"], [0.08, 0.42, 0.78], 4, 5, 14)
	_mesh("EarNear", "ear_near", Rect2(-12, -326, 63, 125), ["EarNear", "EarNearMiddle", "EarNearTip"], [0.08, 0.42, 0.78], 5, 5, 14)
	_mesh("Head", "head", Rect2(-81, -240, 164, 148), ["Head"], [], 8, 6, 6)
	_make_animations()
	var packed := PackedScene.new()
	var error := packed.pack(rig)
	assert(error == OK)
	error = ResourceSaver.save(packed, OUTPUT)
	assert(error == OK)
	print("RABBIT: saved native rig, %d bones, 9 weighted meshes, walk + RESET" % joints.size())
	rig.free()
	quit()


func _owned(parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = rig


func _bone(key: String, parent: Node, origin: Vector2, length: float, angle: float = -PI / 2, node_name: String = "") -> void:
	var bone := Bone2D.new()
	bone.name = node_name if not node_name.is_empty() else key
	bone.position = origin
	bone.rest = bone.transform
	bone.set_autocalculate_length_and_angle(false)
	bone.set_length(length)
	bone.set_bone_angle(angle)
	_owned(parent, bone)
	joints[key] = bone


func _mesh(node_name: String, part: String, rect: Rect2, joint_keys: Array, anchors: Array, depth: int, columns: int, rows: int, bottom_to_top: bool = true) -> void:
	var mesh := Polygon2D.new()
	mesh.name = node_name
	# Keep the entire skin above its parent's background drawing.
	mesh.z_index = depth + 6
	mesh.texture = load(art_dir + part + ".png")
	assert(mesh.texture != null, "Import cutout PNGs before building the rig")
	var grid: Array[Vector2i] = []
	# Boundary first so the native UV editor can distinguish internal vertices.
	for x in range(columns + 1):
		grid.append(Vector2i(x, 0))
	for y in range(1, rows + 1):
		grid.append(Vector2i(columns, y))
	for x in range(columns - 1, -1, -1):
		grid.append(Vector2i(x, rows))
	for y in range(rows - 1, 0, -1):
		grid.append(Vector2i(0, y))
	var boundary := grid.size()
	for y in range(1, rows):
		for x in range(1, columns):
			grid.append(Vector2i(x, y))
	var vertices := PackedVector2Array()
	var uv := PackedVector2Array()
	var lookup: Dictionary = {}
	for point in grid:
		lookup[point] = vertices.size()
		var ratio := Vector2(point) / Vector2(columns, rows)
		vertices.append(rect.position + ratio * rect.size)
		uv.append(ratio * mesh.texture.get_size())
	mesh.polygon = vertices
	mesh.uv = uv
	mesh.internal_vertex_count = vertices.size() - boundary
	var triangles: Array[PackedInt32Array] = []
	for y in rows:
		for x in columns:
			var a: int = lookup[Vector2i(x, y)]
			var b: int = lookup[Vector2i(x + 1, y)]
			var c: int = lookup[Vector2i(x + 1, y + 1)]
			var d: int = lookup[Vector2i(x, y + 1)]
			triangles.append(PackedInt32Array([a, b, c]))
			triangles.append(PackedInt32Array([a, c, d]))
	mesh.polygons = triangles
	_owned(skin, mesh)
	mesh.skeleton = mesh.get_path_to(skeleton)
	for index in joint_keys.size():
		var weights := PackedFloat32Array()
		for point in vertices:
			var ratio := (point.y - rect.position.y) / rect.size.y
			if bottom_to_top:
				ratio = 1.0 - ratio
			weights.append(_weight(ratio, index, joint_keys.size(), anchors))
		mesh.add_bone(skeleton.get_path_to(joints[joint_keys[index]]), weights)


func _weight(t: float, index: int, count: int, anchors: Array) -> float:
	if count == 1:
		return 1.0
	if t <= float(anchors[0]):
		return 1.0 if index == 0 else 0.0
	if t >= float(anchors[count - 1]):
		return 1.0 if index == count - 1 else 0.0
	for segment in range(count - 1):
		if t <= float(anchors[segment + 1]):
			var blend := inverse_lerp(float(anchors[segment]), float(anchors[segment + 1]), t)
			if index == segment:
				return 1.0 - blend
			if index == segment + 1:
				return blend
			return 0.0
	return 0.0


func _make_animations() -> void:
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	var library := AnimationLibrary.new()
	var reset := Animation.new()
	reset.length = 0.01
	for key: String in joints:
		_track(reset, joints[key], "position", [joints[key].position], [0.0])
		_track(reset, joints[key], "rotation", [0.0], [0.0])
		_track(reset, joints[key], "scale", [Vector2.ONE], [0.0])
	library.add_animation("RESET", reset)
	var walk := Animation.new()
	walk.length = DURATION
	walk.loop_mode = Animation.LOOP_LINEAR
	var times: Array = []
	var channels: Dictionary = {}
	for sample in range(65):
		var phase := float(sample) / 64.0
		var t := phase * TAU
		times.append(phase * DURATION)
		_append(channels, "Body:position", Vector2(0, -62 + 1.5 * cos(t * 2)))
		_append(channels, "Body:scale", Vector2(1.0 + 0.006 * cos(t * 2), 1.0 - 0.008 * cos(t * 2)))
		_append(channels, "Chest:rotation", 0.012 * sin(t))
		_append(channels, "Head:rotation", 0.012 * sin(t - 0.6) + 0.008 * sin(t * 2 - 0.5))
		_append(channels, "Head:position", Vector2(0, -13 + 0.7 * cos(t * 2 - 0.8)))
		_append(channels, "ArmNear:rotation", 0.27 * sin(t))
		_append(channels, "ArmNearTip:rotation", 0.06 * sin(t - 0.7))
		_append(channels, "ArmFar:rotation", -0.25 * sin(t))
		_append(channels, "ArmFarTip:rotation", -0.05 * sin(t - 0.7))
		_append(channels, "Tail:rotation", 0.07 * sin(t * 2 - 1.0))
		for side in ["Near", "Far"]:
			var p := fposmod(phase + (0.5 if side == "Far" else 0.0), 1.0)
			var x: float
			var lift := 0.0
			var angle := 0.0
			if p < 0.5:
				x = lerpf(14, -14, p * 2)
			else:
				var progress := (p - 0.5) * 2
				x = lerpf(-14, 14, smoothstep(0, 1, progress))
				lift = 12.0 * sin(progress * PI)
				angle = -0.13 * sin(progress * TAU)
			var foot_rest: Vector2 = (joints["Foot" + side] as Bone2D).rest.origin
			_append(channels, "Foot" + side + ":position", foot_rest + walk_axis * x + Vector2(0, -lift))
			_append(channels, "Foot" + side + ":rotation", angle)
			var lag := 0.45 if side == "Near" else 0.9
			_append(channels, "Ear" + side + ":rotation", 0.035 * sin(t * 2 - lag))
			_append(channels, "Ear" + side + "Middle:rotation", 0.085 * sin(t * 2 - lag - 0.65))
			_append(channels, "Ear" + side + "Tip:rotation", 0.12 * sin(t * 2 - lag - 1.35))
	for channel: String in channels:
		var split := channel.split(":")
		_track(walk, joints[split[0]], split[1], channels[channel], times)
	library.add_animation("walk", walk)
	# Shared immutable resources; player time remains local to each actor instance.
	var motion_dir := "res://art/rabbit_walk/motions/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(motion_dir))
	var view: String = rig.get_meta("view", "side")
	walk.take_over_path(motion_dir + view + "_walk.tres")
	assert(ResourceSaver.save(walk) == OK)
	library.take_over_path(motion_dir + view + ".tres")
	assert(ResourceSaver.save(library) == OK)
	player.add_animation_library("", library)
	player.autoplay = "walk"
	_owned(rig, player)


func _append(channels: Dictionary, name: String, value: Variant) -> void:
	if not channels.has(name):
		channels[name] = []
	channels[name].append(value)


func _track(animation: Animation, joint: Bone2D, property: String, values: Array, times: Array) -> void:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, NodePath(str(rig.get_path_to(joint)) + ":" + property))
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
	for i in values.size():
		animation.track_insert_key(track, times[i], values[i])
