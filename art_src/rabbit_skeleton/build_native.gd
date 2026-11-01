extends "res://art_src/rabbit_skeleton/native_mesh_builder.gd"
## Complete reconstructed parts on rigid bones; movement is fitted from current frames.

const SOURCE_ROOT := "res://art_src/rabbit_walk_frames/frames/"
const CURRENT_ART := "res://art/rabbit_skeleton/"
const CURRENT_SCENES := "res://presentation/rabbit_skeleton/"
const PART_NAMES := ["head", "ear_far", "ear_near", "body", "arm_far", "arm_near", "foot_far", "foot_near", "tail"]
const JOINT_NAMES := {"head":"Head", "ear_far":"EarFar", "ear_near":"EarNear", "body":"Body", "arm_far":"ArmFar", "arm_near":"ArmNear", "foot_far":"FootFar", "foot_near":"FootNear", "tail":"Tail"}
var cuts: Dictionary
var parts: Dictionary
var source_fit: Dictionary
var current_view := ""
var source_anchor := Vector2(128, 244)

func _build() -> void:
	cuts = JSON.parse_string(FileAccess.get_file_as_string("res://art_src/rabbit_skeleton/cuts.json"))
	if "--parts" in OS.get_cmdline_user_args():
		_cut_parts()
	elif "--faces" in OS.get_cmdline_user_args():
		print("Complete heads are retained; no facial crops are generated.")
	else:
		parts = JSON.parse_string(FileAccess.get_file_as_string("res://art_src/rabbit_skeleton/complete_manifest.json"))
		source_fit = JSON.parse_string(FileAccess.get_file_as_string("res://art_src/rabbit_skeleton/source_fit.json"))
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CURRENT_SCENES))
		for view: String in cuts.views:
			_build_view(view)
	quit()

func _cut_parts() -> void:
	var references: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art_src/rabbit_skeleton/parts_manifest.json"))
	var output := {"artwork":"complete_parts", "views":{}}
	for view: String in cuts.views:
		var source_path := "res://art_src/rabbit_skeleton/complete_atlases/"+view+".png"
		var atlas := Image.load_from_file(ProjectSettings.globalize_path(source_path))
		assert(not atlas.is_empty(), "Complete artwork is required: "+source_path)
		var mask := BitMap.new()
		mask.create_from_image_alpha(atlas,0.1)
		var boxes := {}
		for outline in mask.opaque_to_polygons(Rect2i(Vector2i.ZERO,atlas.get_size()),1.0):
			var bounds := Rect2(outline[0],Vector2.ZERO)
			for point in outline:
				bounds = bounds.expand(point)
			if bounds.get_area() < 1000:
				continue
			var center := bounds.get_center()/Vector2(atlas.get_size())
			var cell := clampi(int(center.y*3),0,2)*3+clampi(int(center.x*3),0,2)
			if not boxes.has(cell) or bounds.get_area() > (boxes[cell] as Rect2).get_area():
				boxes[cell] = bounds
		assert(boxes.size()==9, "Atlas must contain nine isolated complete components: "+view)
		var directory := CURRENT_ART+"complete/"+view+"/"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		var entry := {"source":source_path,"sha256":FileAccess.get_sha256(source_path),"parts":{}}
		for index in 9:
			var part: String = PART_NAMES[index]
			var bounds: Rect2 = boxes[index]
			var crop := Rect2i(bounds.position.floor(),bounds.size.ceil()).grow(6).intersection(Rect2i(Vector2i.ZERO,atlas.get_size()))
			assert(atlas.get_region(crop).save_png(directory+part+".png")==OK)
			var placement := _placement(view,part,Vector2(crop.size),references)
			placement["rect"] = [crop.position.x,crop.position.y,crop.size.x,crop.size.y]
			entry.parts[part] = placement
		output.views[view] = entry
		print("COMPLETE RABBIT: exported nine full components "+view)
	FileAccess.open("res://art_src/rabbit_skeleton/complete_manifest.json",FileAccess.WRITE).store_string(JSON.stringify(output,"\t"))

func _placement(view: String, part: String, pixels: Vector2, references: Dictionary) -> Dictionary:
	var config: Dictionary = cuts.views[view]
	var pivot := _point(config.pivots[part])
	var scale := 1.0
	var position := Vector2.ZERO
	var flip := false
	if part == "head":
		var original: Array = references.views[view].parts.head.rect
		scale = float(original[2])/pixels.x
		var size := pixels*scale
		position = Vector2(float(original[0])+float(original[2])/2.0-size.x/2.0,float(config.head_bottom)+2.0-size.y)-pivot
	elif part == "body":
		var top := float(config.head_bottom)-5.0
		scale = (231.0-top)/pixels.y
		position = Vector2(pivot.x-pixels.x*scale/2.0,top)-pivot
	elif part.begins_with("ear"):
		scale = 85.0/pixels.y
		position = -pixels*Vector2(0.5,0.90)*scale
	elif part.begins_with("arm"):
		var near := part == "arm_near"
		scale = (39.0 if near else 34.0)/pixels.y
		var root := Vector2(0.35 if near else 0.75,0.12)
		flip = view in ["front","front_right","back"] or (view=="right" and not near)
		if flip:
			root.x = 1.0-root.x
		position = -pixels*root*scale
	elif part.begins_with("foot"):
		var near := part == "foot_near"
		scale = (27.0 if near else 23.0)/pixels.x
		var root := Vector2(0.42 if near else 0.3,0.40)
		flip = near and view in ["front","front_right","back"]
		if flip:
			root.x = 1.0-root.x
		position = -pixels*root*scale
	else:
		scale = 22.0/pixels.x
		position = -pixels*scale/2.0
	return {"position":[position.x,position.y],"scale":scale,"flip_h":flip,"visible":part!="tail" or view in ["right","back_right","back"]}

func _point(value: Array) -> Vector2:
	return Vector2(value[0], value[1])

func _build_view(view: String) -> void:
	current_view = view
	art_dir = CURRENT_ART + "complete/" + view + "/"
	joints = {}
	rig = Node2D.new()
	rig.name = "Rabbit" + view.to_pascal_case()
	rig.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rig.set_meta("source", "rabbit_walk_frames")
	rig.set_meta("view", view)
	rig.set_meta("cycle_seconds", float(source_fit.views[view].cycle_ms) / 1000.0)
	rig.set_meta("source_sha256", FileAccess.get_sha256(SOURCE_ROOT+view+"/%02d.png" % int(cuts.views[view].base_frame)))
	rig.set_meta("artwork", "complete_parts")
	rig.set_meta("artwork_atlas", parts.views[view].source)
	rig.set_meta("artwork_sha256", parts.views[view].sha256)
	rig.set_meta("binding", "rigid_cutouts")
	root.add_child(rig)
	skeleton = Skeleton2D.new()
	skeleton.name = "Skeleton2D"
	_owned(rig, skeleton)
	var p: Dictionary = cuts.views[view].pivots
	_bone("Root", skeleton, Vector2.ZERO, 10)
	_bone("Body", joints.Root, _point(p.body) - source_anchor, 20)
	_bone("Chest", joints.Body, Vector2(0, -25), 10)
	var chest_position: Vector2 = _point(p.body) - source_anchor + Vector2(0, -25)
	_bone("Head", joints.Chest, _point(p.head) - source_anchor - chest_position, 45)
	for part: String in ["foot_far", "foot_near"]:
		_bone(JOINT_NAMES[part], joints.Root, _point(p[part]) - source_anchor, 12, 0)
	_bone("Tail", joints.Body, _point(p.tail) - _point(p.body), 8, PI)
	for part: String in ["arm_far", "arm_near"]:
		var key: String = JOINT_NAMES[part]
		_bone(key, joints.Chest, _point(p[part]) - source_anchor - chest_position, 13, PI / 2)
		_bone(key + "Tip", joints[key], Vector2(0, 14), 9, PI / 2)
	for part: String in ["ear_far", "ear_near"]:
		var key: String = JOINT_NAMES[part]
		_bone(key, joints.Head, _point(p[part]) - _point(p.head), 23)
		_bone(key + "Middle", joints[key], Vector2(0, -23), 23, -PI / 2, "Middle")
		_bone(key + "Tip", joints[key + "Middle"], Vector2(0, -23), 12, -PI / 2, "Tip")
	var depths := {"foot_far":-6, "foot_near":-5, "tail":-2, "body":0, "arm_far":-3, "arm_near":3, "ear_far":4, "ear_near":5, "head":8}
	if view in ["front", "back"]:
		depths.arm_far = 2
	if view in ["back", "back_right"]:
		depths.tail = 2
	for part: String in PART_NAMES:
		var data: Dictionary = parts.views[view].parts[part]
		_cutout_sprite("Visual", part, JOINT_NAMES[part], data, depths[part]+6)
	_make_source_animations(p)
	var packed := PackedScene.new()
	assert(packed.pack(rig) == OK)
	assert(ResourceSaver.save(packed, CURRENT_SCENES + "rabbit_" + view + ".tscn") == OK)
	rig.free()
	print("CURRENT RABBIT: source-fitted native animation " + view)

func _cutout_sprite(label: String, part: String, bone: String, data: Dictionary, depth: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = label
	sprite.texture = load(art_dir+part+".png")
	sprite.centered = false
	sprite.position = _point(data.position)
	sprite.scale = Vector2.ONE * float(data.scale)
	sprite.flip_h = data.flip_h
	sprite.visible = data.visible
	sprite.z_index = depth
	_owned(joints[bone], sprite)
	return sprite

func _make_source_animations(pivots: Dictionary) -> void:
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
	var data: Dictionary = source_fit.views[current_view]
	walk.length = float(data.cycle_ms) / 1000.0
	walk.loop_mode = Animation.LOOP_LINEAR
	var channels := {}
	var times: Array = []
	var elapsed := 0.0
	for index in 8:
		var frame: Dictionary = data.frames[index % 7]
		times.append(elapsed)
		var desired := {"Root": Transform2D.IDENTITY}
		for part: String in PART_NAMES:
			var a: Array = frame.parts[part].transform
			var pivot := _point(pivots[part]) - source_anchor
			# Rigid cutouts only translate and rotate; source-image scale fitting is ignored.
			desired[JOINT_NAMES[part]] = Transform2D(a[2], pivot + Vector2(a[0], a[1]))
		desired.Chest = desired.Body * (joints.Chest as Bone2D).rest
		for side: String in ["Near", "Far"]:
			desired["Arm" + side + "Tip"] = desired["Arm" + side] * (joints["Arm" + side + "Tip"] as Bone2D).rest
			desired["Ear" + side + "Middle"] = desired["Ear" + side] * (joints["Ear" + side + "Middle"] as Bone2D).rest
			desired["Ear" + side + "Tip"] = desired["Ear" + side + "Middle"] * (joints["Ear" + side + "Tip"] as Bone2D).rest
		for key: String in joints:
			var joint: Bone2D = joints[key]
			var parent_transform: Transform2D = Transform2D.IDENTITY
			if joint.get_parent() is Bone2D:
				for parent_key: String in joints:
					if joints[parent_key] == joint.get_parent():
						parent_transform = desired[parent_key]
						break
			var local: Transform2D = parent_transform.affine_inverse() * (desired[key] as Transform2D)
			_append(channels, key + ":position", local.origin)
			_append(channels, key + ":rotation", local.get_rotation())
		if index < 7:
			elapsed += float(data.durations_ms[index]) / 1000.0
	for channel: String in channels:
		var split := channel.split(":")
		_track(walk, joints[split[0]], split[1], channels[channel], times)
	library.add_animation("walk", walk)
	var directory := CURRENT_ART + "motions/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	walk.take_over_path(directory + current_view + "_walk.tres")
	assert(ResourceSaver.save(walk) == OK)
	library.take_over_path(directory + current_view + ".tres")
	assert(ResourceSaver.save(library) == OK)
	player.add_animation_library("", library)
	_owned(rig, player)
