extends SceneTree
## Native import tooling: lossless region extraction, followed by an editable PackedScene.

const MANIFEST := "res://art_src/reference/manifest.json"
const OUTPUT := "res://art/reference/"


func _initialize() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if "--verify-assets" in OS.get_cmdline_user_args():
		_extract(manifest, true)
	elif "--assets" in OS.get_cmdline_user_args():
		_extract(manifest)
	else:
		_pack(manifest)
	quit()


func _extract(manifest: Dictionary, verify_only := false) -> void:
	var sources := {}
	for id in manifest.assets:
		var row: Array = manifest.assets[id]
		var cut: Image
		var override_path: String = manifest.get("asset_overrides", {}).get(id, "")
		if not override_path.is_empty():
			cut = Image.load_from_file("res://art_src/reference/" + override_path)
		else:
			if not sources.has(row[0]):
				sources[row[0]] = Image.load_from_file("res://art_src/reference/" + row[0] + ".png")
			var region := Rect2i(int(row[1]), int(row[2]), int(row[3]), int(row[4]))
			cut = sources[row[0]].get_region(region)
		var target: Array = manifest.get("runtime_sizes", {}).get(id, [])
		if target.size() == 2 and Vector2i(cut.get_size()) != Vector2i(int(target[0]), int(target[1])):
			assert(int(target[0]) <= cut.get_width() and int(target[1]) <= cut.get_height(), "do not upscale " + id)
			cut.resize(int(target[0]), int(target[1]), Image.INTERPOLATE_LANCZOS)
		if verify_only:
			var current := Image.load_from_file(ProjectSettings.globalize_path(OUTPUT + id + ".png"))
			assert(current.get_size() == cut.get_size(), "rebuild size differs: " + id)
			assert(current.get_data() == cut.get_data(), "rebuild pixels differ: " + id)
		else:
			var err := cut.save_png(OUTPUT + id + ".png")
			assert(err == OK, "asset extraction failed: " + id)
	print("REFERENCE: %s %d independent sprites" % ["verified" if verify_only else "extracted", manifest.assets.size()])


func _pack(manifest: Dictionary) -> void:
	var art := Node2D.new()
	art.name = "ShopArt"
	var sorted := Node2D.new()
	sorted.name = "Sortables"
	sorted.y_sort_enabled = true
	art.add_child(sorted)
	sorted.owner = art
	var nodes := {"root": art}
	for row in manifest.pieces:
		var parent: Node2D = nodes.get(row.get("parent", ""), sorted)
		var r: Array = row.rect
		var origin := Vector2(float(r[0]) + float(r[2]) / 2.0, float(row.get("depth", float(r[1]) + float(r[3]))))
		var node := Node2D.new()
		node.name = row.id
		node.position = origin - parent.position if parent != sorted and parent != art else origin
		node.z_index = int(row.get("z", 0))
		node.set_meta("art_layer", row.layer)
		node.set_meta("asset_id", row.asset)
		parent.add_child(node)
		node.owner = art
		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
		sprite.texture = load(OUTPUT + row.asset + ".png")
		assert(sprite.texture != null, "import PNG files before packing")
		sprite.centered = false
		sprite.position = Vector2(float(r[0]), float(r[1])) - origin
		sprite.scale = Vector2(float(r[2]), float(r[3])) / sprite.texture.get_size()
		node.add_child(sprite)
		sprite.owner = art
		nodes[row.id] = node
	var packed := PackedScene.new()
	assert(packed.pack(art) == OK)
	assert(ResourceSaver.save(packed, "res://presentation/reference/shop_art.tscn") == OK)
	print("REFERENCE: packed %d independently editable scene pieces" % manifest.pieces.size())
	art.free()
