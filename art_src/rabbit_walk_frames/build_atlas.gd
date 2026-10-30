extends SceneTree
## Lossless atlas packing and native SpriteFrames export; no image synthesis.

const SOURCE := "res://art_src/rabbit_walk_frames/"
const OUTPUT := "res://art/rabbit_walk_frames/"
const POLICY := preload("res://art_src/rabbit_walk_frames/frame_policy.gd")


func _initialize() -> void:
	call_deferred("_build")


func _build() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE + "source_manifest.json"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var atlas := Image.create(1792, 1280, false, Image.FORMAT_RGBA8)
	atlas.fill(Color.TRANSPARENT)
	var selections: Dictionary = {}
	for row: Dictionary in manifest.directions:
		var images: Array = []
		for frame in int(row.frame_count):
			var image := Image.load_from_file(ProjectSettings.globalize_path(SOURCE + "frames/" + str(row.key) + "/%02d.png" % (frame + 1)))
			assert(image.get_size() == Vector2i(256, 256), "Source frames must keep their common canvas")
			image.convert(Image.FORMAT_RGBA8)
			images.append(image)
		var keep: Array = POLICY.loop_indices(images)
		selections[row.key] = keep
		for index in keep.size():
			atlas.blit_rect(images[keep[index]], Rect2i(0, 0, 256, 256), Vector2i(index * 256, int(row.row) * 256))
	if "--atlas" in OS.get_cmdline_user_args():
		assert(atlas.save_png(OUTPUT + "rabbit_walk_atlas.png") == OK)
		print("RABBIT ATLAS: losslessly packed 35 frames, 1792x1280")
		quit()
		return
	var texture: Texture2D = load(OUTPUT + "rabbit_walk_atlas.png")
	assert(texture != null, "Import the atlas before exporting SpriteFrames")
	var animations := SpriteFrames.new()
	animations.remove_animation("default")
	for row: Dictionary in manifest.directions:
		var name: String = row.animation
		animations.add_animation(name)
		animations.set_animation_loop(name, true)
		# A readable 10 FPS base; relative durations retain the source GIF timing.
		animations.set_animation_speed(name, 10.0)
		var keep: Array = selections[row.key]
		for index in keep.size():
			var region := AtlasTexture.new()
			region.atlas = texture
			region.region = Rect2(index * 256, int(row.row) * 256, 256, 256)
			region.filter_clip = true
			animations.add_frame(name, region, float(row.durations_ms[keep[index]]) / 100.0)
	assert(ResourceSaver.save(animations, OUTPUT + "rabbit_walk_frames.tres") == OK)
	print("RABBIT ATLAS: saved five native looping SpriteFrames clips, exact source timing")
	quit()
