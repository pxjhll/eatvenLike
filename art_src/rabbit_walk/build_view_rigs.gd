extends "res://art_src/rabbit_walk/build_rig.gd"
## Adds four authored views while reusing the side rig's native mesh/animation builder.

const VIEWS := ["front", "front_right", "back_right", "back"]
const PARTS := ["head", "ear_far", "ear_near", "body", "arm_far", "arm_near", "foot_far", "foot_near", "tail"]


func _build() -> void:
	if "--parts" in OS.get_cmdline_user_args():
		_extract()
	else:
		for view: String in VIEWS:
			_assemble(view)
	quit()


func _extract() -> void:
	var manifest := {}
	for view: String in VIEWS:
		var atlas := Image.load_from_file("res://art_src/rabbit_walk/views/" + view + ".png")
		var mask := BitMap.new()
		mask.create_from_image_alpha(atlas, 0.1)
		var boxes := {}
		for outline in mask.opaque_to_polygons(Rect2i(Vector2i.ZERO, atlas.get_size()), 2.0):
			var bounds := Rect2(outline[0], Vector2.ZERO)
			for point in outline:
				bounds = bounds.expand(point)
			if bounds.get_area() < 1000:
				continue
			var center := bounds.get_center() / Vector2(atlas.get_size())
			var cell := clampi(int(center.y * 3), 0, 2) * 3 + clampi(int(center.x * 3), 0, 2)
			if not boxes.has(cell) or bounds.get_area() > (boxes[cell] as Rect2).get_area():
				boxes[cell] = bounds
		assert(boxes.size() == 9, "Atlas must have nine isolated parts: " + view)
		var folder := ART + view + "/"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		manifest[view] = {}
		for index in 9:
			var bounds: Rect2 = boxes[index]
			var crop := Rect2i(bounds.position.floor(), bounds.size.ceil()).grow(6).intersection(Rect2i(Vector2i.ZERO, atlas.get_size()))
			assert(atlas.get_region(crop).save_png(folder + PARTS[index] + ".png") == OK)
			manifest[view][PARTS[index]] = [crop.position.x, crop.position.y, crop.size.x, crop.size.y]
		print("RABBIT VIEWS: extracted " + view)
	var file := FileAccess.open("res://art_src/rabbit_walk/views/crops.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))


func _assemble(view: String) -> void:
	art_dir = ART + view + "/"
	var frontal := view in ["front", "back"]
	var rear := view in ["back", "back_right"]
	walk_axis = Vector2(0, -0.42 if rear else 0.42) if frontal else Vector2(0.8, -0.32 if rear else 0.32)
	joints = {}
	rig = Node2D.new()
	rig.name = "Rabbit" + view.to_pascal_case()
	rig.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rig.set_meta("view", view)
	rig.set_meta("cycle_seconds", DURATION)
	rig.set_meta("walk_axis", walk_axis)
	rig.set_meta("source", "User turnaround; parts reconstructed with built-in imagegen")
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
	var near_foot := Vector2(-22, -16) if frontal else Vector2(11, -16)
	var far_foot := Vector2(22, -16) if frontal else Vector2(-16, -20)
	_bone("FootFar", joints.Root, far_foot, 22, 0)
	_bone("FootNear", joints.Root, near_foot, 24, 0)
	var tail_at := Vector2(0, -46) if frontal else Vector2(-35, -46)
	_bone("Tail", joints.Body, tail_at - Vector2(0, -62), 16, PI)
	var near_arm := Vector2(-48, -101) if frontal else Vector2(31 if rear else -29, -101)
	var far_arm := Vector2(48, -99) if frontal else Vector2(-36 if rear else 36, -99)
	_bone("ArmFar", joints.Chest, far_arm - Vector2(0, -96), 27, PI / 2)
	_bone("ArmFarTip", joints.ArmFar, Vector2(0, 26), 24, PI / 2)
	_bone("ArmNear", joints.Chest, near_arm - Vector2(0, -96), 28, PI / 2)
	_bone("ArmNearTip", joints.ArmNear, Vector2(0, 28), 23, PI / 2)
	var head_texture: Texture2D = load(art_dir + "head.png")
	var head_width := 174.0 if frontal else 168.0
	var head_height := head_width * head_texture.get_height() / head_texture.get_width()
	var head_rect := Rect2(-head_width / 2, -94 - head_height, head_width, head_height)
	var far_ear := Vector2(-30 if frontal else -24, head_rect.position.y + 23)
	var near_ear := Vector2(30 if frontal else 20, head_rect.position.y + 23)
	for data: Array in [["EarFar", far_ear], ["EarNear", near_ear]]:
		var key: String = data[0]
		_bone(key, joints.Head, (data[1] as Vector2) - Vector2(0, -109), 39)
		_bone(key + "Middle", joints[key], Vector2(0, -39), 39, -PI / 2, "Middle")
		_bone(key + "Tip", joints[key + "Middle"], Vector2(0, -39), 30, -PI / 2, "Tip")
	_mesh("FootFar", "foot_far", Rect2(far_foot - Vector2(24, 15), Vector2(48, 32)), ["FootFar"], [], -6, 4, 3)
	_mesh("FootNear", "foot_near", Rect2(near_foot - Vector2(25, 16), Vector2(50, 34)), ["FootNear"], [], -4, 4, 3)
	_mesh("ArmFar", "arm_far", Rect2(far_arm - Vector2(19, 4), Vector2(38, 60)), ["ArmFar", "ArmFarTip"], [0.15, 0.82], 2 if frontal else -3, 4, 8, false)
	_mesh("Body", "body", Rect2(-61, -118, 122, 107), ["Body", "Chest"], [0.12, 0.82], 0, 6, 10)
	_mesh("Tail", "tail", Rect2(tail_at - Vector2(16, 16), Vector2(32, 32)), ["Tail"], [], 1 if rear else -2, 4, 4)
	(skin.get_node("Tail") as Polygon2D).visible = rear
	_mesh("ArmNear", "arm_near", Rect2(near_arm - Vector2(20, 4), Vector2(40, 62)), ["ArmNear", "ArmNearTip"], [0.15, 0.85], 3, 4, 8, false)
	for data: Array in [["EarFar", "ear_far", far_ear], ["EarNear", "ear_near", near_ear]]:
		var height := 139.0 if frontal else 133.0
		var texture: Texture2D = load(art_dir + str(data[1]) + ".png")
		var width := height * texture.get_width() / texture.get_height()
		var key: String = data[0]
		var at: Vector2 = data[2]
		_mesh(key, data[1], Rect2(at.x - width / 2, at.y + 16 - height, width, height), [key, key + "Middle", key + "Tip"], [0.08, 0.42, 0.78], 4, 5, 14)
	_mesh("Head", "head", head_rect, ["Head"], [], 8, 6, 6)
	_make_animations()
	var packed := PackedScene.new()
	assert(packed.pack(rig) == OK)
	assert(ResourceSaver.save(packed, "res://presentation/rabbit_walk/rabbit_" + view + ".tscn") == OK)
	rig.free()
	print("RABBIT VIEWS: built native " + view + " walking rig")
