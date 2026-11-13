extends "res://tests/test_case.gd"

const INVENTORY := "res://art/staff_actions_inventory.json"


func test_new_atlases_preserve_original_pixels_alpha_and_gif_timing() -> void:
	var inventory: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(INVENTORY))
	var count := 0
	var clips := 0
	for batch: Dictionary in inventory.batches:
		var frames: SpriteFrames = load(batch.frames_resource)
		var atlas := Image.load_from_file(ProjectSettings.globalize_path(batch.atlas))
		atlas.convert(Image.FORMAT_RGBA8)
		check(atlas.get_width() <= 4096 and atlas.get_height() <= 4096, batch.kind + " fits mobile texture limits")
		for clip: Dictionary in batch.clips:
			clips += 1
			check_eq(frames.get_frame_count(clip.name), clip.frames.size(), batch.kind + " keeps every supplied frame")
			check(frames.get_animation_loop(clip.name), batch.kind + " animation loops")
			var cycle := 0.0
			for index in clip.frames.size():
				count += 1
				var record: Dictionary = clip.frames[index]
				var texture: AtlasTexture = frames.get_frame_texture(clip.name, index)
				check_eq(texture.atlas.resource_path, batch.atlas, "new frames use their own packed atlas")
				var pixels := atlas.get_region(Rect2i(texture.region)).get_data()
				var hash := HashingContext.new()
				hash.start(HashingContext.HASH_SHA256)
				hash.update(pixels)
				check_eq(hash.finish().hex_encode(), record.rgba_sha256, "source RGBA pixels remain exact")
				var seconds := frames.get_frame_duration(clip.name, index) / frames.get_animation_speed(clip.name)
				check(is_equal_approx(seconds, float(record.duration_ms) / 1000.0), "original GIF hold is preserved")
				cycle += seconds
			check(is_equal_approx(cycle, 1.0 if String(clip.name).begins_with("walk_") else 4.0), "source animation cycle is preserved")
	check_eq(clips, 30, "four missing operation views and two complete characters")
	check_eq(count, 362, "only previously missing source frames are newly packed")


func test_completed_gray_cat_and_bear_reuse_existing_animation_textures() -> void:
	var inventory: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(INVENTORY))
	for batch: Dictionary in inventory.batches:
		if String(batch.base_frames).is_empty(): continue
		var base: SpriteFrames = load(batch.base_frames)
		var combined: SpriteFrames = load(batch.frames_resource)
		for clip: String in base.get_animation_names():
			check_eq(combined.get_frame_count(clip), base.get_frame_count(clip), "existing frame counts retained")
			check_eq(combined.get_animation_speed(clip), base.get_animation_speed(clip), "existing tuned cycle retained")
			for i in base.get_frame_count(clip):
				var old: AtlasTexture = base.get_frame_texture(clip, i)
				var current: AtlasTexture = combined.get_frame_texture(clip, i)
				check_eq(current.atlas.resource_path, old.atlas.resource_path, "existing atlas is reused")
				check_eq(current.region, old.region, "existing pose region unchanged")
				check_eq(combined.get_frame_duration(clip, i), base.get_frame_duration(clip, i), "existing frame hold unchanged")
