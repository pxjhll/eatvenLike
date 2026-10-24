extends SceneTree
## godot --headless --path . -s art_src/graybox/rasterize.gd


func _initialize() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art/graybox_manifest.json"))
	for asset in manifest.assets:
		var image := Image.new()
		var error := image.load_svg_from_string(FileAccess.get_file_as_string("res://" + asset.source))
		if error != OK:
			push_error("Cannot rasterize " + asset.id)
			quit(1)
			return
		DirAccess.make_dir_recursive_absolute("res://" + String(asset.path).get_base_dir())
		if image.save_png("res://" + asset.path) != OK:
			quit(1)
			return
	print("Exported %d transparent PNG assets" % manifest.assets.size())
	quit()
