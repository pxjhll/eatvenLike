extends SceneTree
## Lossless atlas packing and native SpriteFrames export; no image synthesis.

const SOURCE := "res://art_src/rabbit_walk_frames/"
const OUTPUT := "res://art/rabbit_walk_frames/"
const POLICY := preload("res://art_src/rabbit_walk_frames/frame_policy.gd")


func _initialize() -> void:
	call_deferred("_build")


func _build() -> void:
	var source := SOURCE
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source="):
			source = argument.trim_prefix("--source=").trim_suffix("/") + "/"
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source + "source_manifest.json"))
	var output: String = manifest.get("output", OUTPUT)
	var prefix: String = manifest.get("asset_prefix", "rabbit_walk")
	var playback_cycles: Dictionary = {}
	if FileAccess.file_exists(source + "playback.json"):
		var playback: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source + "playback.json"))
		playback_cycles = playback.get("cycle_ms", {})
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var atlas := Image.create(int(manifest.columns) * 256, int(manifest.rows) * 256, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	var selections: Dictionary = {}
	for row: Dictionary in manifest.directions:
		var images: Array = []
		for frame in int(row.frame_count):
			var image := Image.load_from_file(ProjectSettings.globalize_path(source + "frames/" + str(row.key) + "/%02d.png" % (frame + 1)))
			assert(image.get_size() == Vector2i(256, 256), "Source frames must keep their common canvas")
			image.convert(Image.FORMAT_RGBA8)
			images.append(image)
		var keep: Array = POLICY.loop_indices(images)
		selections[row.key] = keep
		for index in keep.size():
			atlas.blit_rect(images[keep[index]], Rect2i(0, 0, 256, 256), Vector2i(index * 256, int(row.row) * 256))
	if "--atlas" in OS.get_cmdline_user_args():
		assert(atlas.save_png(output + prefix + "_atlas.png") == OK)
		print(prefix + ": losslessly packed source frames")
		quit()
		return
	var texture: Texture2D = load(output + prefix + "_atlas.png")
	assert(texture != null, "Import the atlas before exporting SpriteFrames")
	var animations := SpriteFrames.new()
	animations.remove_animation("default")
	for row: Dictionary in manifest.directions:
		var name: String = row.animation
		animations.add_animation(name)
		animations.set_animation_loop(name, true)
		var keep: Array = selections[row.key]
		# Keep source-relative holds; optional runtime cycles survive future rebuilds.
		var speed := 10.0
		if playback_cycles.has(name):
			var target_ms := float(playback_cycles[name])
			assert(is_finite(target_ms) and target_ms > 0.0, "Playback cycle must be positive")
			var source_ms := 0.0
			for index: int in keep:
				source_ms += float(row.durations_ms[index])
			speed *= source_ms / target_ms
		animations.set_animation_speed(name, speed)
		for index in keep.size():
			var region := AtlasTexture.new()
			region.atlas = texture
			region.region = Rect2(index * 256, int(row.row) * 256, 256, 256)
			region.filter_clip = true
			animations.add_frame(name, region, float(row.durations_ms[keep[index]]) / 100.0)
	assert(ResourceSaver.save(animations, output + prefix + "_frames.tres") == OK)
	print(prefix + ": saved native looping SpriteFrames clips with source-relative timing")
	quit()
