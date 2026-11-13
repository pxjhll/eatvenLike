extends "res://tests/test_case.gd"

const Library := preload("res://presentation/characters/character_library.gd")
const INVENTORY := "res://art/customer_actions_inventory.json"


func test_customer_actions_expose_all_supplied_walking_views() -> void:
	for id in ["squirrel", "dog", "sheep", "hamster"]:
		var frames: SpriteFrames = Library.FRAME_ASSETS[id]
		check_eq(Library.actions(id).map(func(a): return a.id), ["walk", "idle", "sit"], id + " keeps its three customer actions")
		check(frames.has_animation("walk_front"), id + " has its authored front walk")
		check(frames.has_animation("walk_right"), id + " retains its side walk")
		if id != "hamster": check(frames.has_animation("walk_back_right"), id + " has its authored back diagonal walk")
		check(id not in Library.STAFF_IDS, id + " stays a customer")
	check_eq(Library.CUSTOMER_IDS, ["squirrel", "dog", "sheep", "hamster"], "customer identities and rotation remain stable")


func test_new_customer_atlases_preserve_source_pixels_and_one_second_timing() -> void:
	check(FileAccess.file_exists(INVENTORY), "customer source inventory is present")
	if not FileAccess.file_exists(INVENTORY): return
	var inventory: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(INVENTORY))
	var count := 0
	var clips := 0
	for batch: Dictionary in inventory.batches:
		var frames: SpriteFrames = load(batch.frames_resource)
		check(frames == Library.FRAME_ASSETS[batch.kind], "gameplay uses the completed customer resources")
		var atlas := Image.load_from_file(ProjectSettings.globalize_path(batch.atlas))
		atlas.convert(Image.FORMAT_RGBA8)
		check(atlas.get_width() <= 4096 and atlas.get_height() <= 4096, "customer atlas fits mobile texture limits")
		for clip: Dictionary in batch.clips:
			clips += 1
			check_eq(frames.get_frame_count(clip.name), 7, "new walk keeps all seven authored poses")
			check(frames.get_animation_loop(clip.name), "new walk loops")
			var cycle := 0.0
			for i in clip.frames.size():
				count += 1
				var record: Dictionary = clip.frames[i]
				var texture: AtlasTexture = frames.get_frame_texture(clip.name, i)
				check_eq(texture.atlas.resource_path, batch.atlas, "new walk uses its own packed atlas")
				var hash := HashingContext.new()
				hash.start(HashingContext.HASH_SHA256)
				hash.update(atlas.get_region(Rect2i(texture.region)).get_data())
				check_eq(hash.finish().hex_encode(), record.rgba_sha256, "source RGBA pixels and transparency are exact")
				var seconds := frames.get_frame_duration(clip.name, i) / frames.get_animation_speed(clip.name)
				check(is_equal_approx(seconds, float(record.duration_ms) / 1000.0), "source GIF hold is retained")
				cycle += seconds
			check(is_equal_approx(cycle, 1.0), "new walk retains the one-second source cycle")
	check_eq(clips, 6, "six missing walk views are added")
	check_eq(count, 42, "only 42 previously missing source frames are newly packed")


func test_existing_customer_clips_and_source_mirroring_remain_unchanged() -> void:
	check(FileAccess.file_exists(INVENTORY), "customer reuse inventory is present")
	if not FileAccess.file_exists(INVENTORY): return
	var inventory: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(INVENTORY))
	for batch: Dictionary in inventory.batches:
		var base: SpriteFrames = load(batch.base_frames)
		var combined: SpriteFrames = load(batch.frames_resource)
		check_eq(combined.get_meta("source_mirrored", {}), base.get_meta("source_mirrored", {}), "old source-facing metadata is preserved")
		for clip: String in base.get_animation_names():
			check_eq(combined.get_frame_count(clip), base.get_frame_count(clip), "old customer frame count is retained")
			check_eq(combined.get_animation_speed(clip), base.get_animation_speed(clip), "old customer cycle is retained")
			for i in base.get_frame_count(clip):
				var old: AtlasTexture = base.get_frame_texture(clip, i)
				var current: AtlasTexture = combined.get_frame_texture(clip, i)
				check_eq(current.atlas.resource_path, old.atlas.resource_path, "old customer atlas is reused")
				check_eq(current.region, old.region, "old customer pose region is unchanged")
				check_eq(combined.get_frame_duration(clip, i), base.get_frame_duration(clip, i), "old customer holds are retained")
