extends SceneTree
## Generic native mesh/weight serialization helpers; contains no artwork or gait.

var rig: Node2D
var skeleton: Skeleton2D
var skin: Node2D
var joints: Dictionary = {}
var art_dir := ""

func _initialize() -> void:
	call_deferred("_build")

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
