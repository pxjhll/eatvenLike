extends SceneTree
## Verify every new atlas against exact source pixels and original GIF-relative timing.
const BATCHES := ["rabbit_actions", "gray_cat_actions", "bear_actions", "squirrel_actions", "dog_actions", "sheep_actions", "hamster_actions", "gray_cat_work_actions", "rabbit_work_actions"]
var failures := 0
var count := 0

func _initialize() -> void:
	for batch in BATCHES:
		var source: String = "res://art_src/" + batch + "/"
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source + "source_manifest.json"))
		var frames: SpriteFrames = load("res://art/" + batch + "/" + batch + "_frames.tres")
		# Inspect the lossless PNG; Godot's importer fills hidden transparent RGB at edges.
		var atlas := Image.load_from_file(ProjectSettings.globalize_path("res://art/" + batch + "/" + batch + "_atlas.png"))
		for row: Dictionary in manifest.directions:
			var clip: String = row.animation
			_check(frames.get_frame_count(clip) == row.kept_frames.size() and frames.get_animation_loop(clip), "exact kept poses loop")
			for record: Dictionary in row.frames:
				var path := source + "frames/" + str(row.key) + "/%02d.png" % int(record.index)
				_check(FileAccess.get_sha256(path) == record.sha256, "byte-identical archived source")
				count += 1
			for i in row.kept_frames.size():
				var index := int(row.kept_frames[i]) - 1
				var original := Image.load_from_file(ProjectSettings.globalize_path(source + "frames/" + str(row.key) + "/%02d.png" % (index + 1)))
				original.convert(Image.FORMAT_RGBA8)
				var texture: AtlasTexture = frames.get_frame_texture(clip, i)
				_check(atlas.get_region(Rect2i(texture.region)).get_data() == original.get_data(), "lossless runtime pixels and alpha")
				_check(absf(frames.get_frame_duration(clip, i) / frames.get_animation_speed(clip) - float(row.durations_ms[index]) / 1000.0) < 0.00001, "original frame hold")
		if manifest.has("base_frames"):
			var old: SpriteFrames = load(str(manifest.base_frames))
			for clip: String in old.get_animation_names():
				_check(frames.get_frame_count(clip) == old.get_frame_count(clip) and frames.get_animation_speed(clip) == old.get_animation_speed(clip), "existing tuned walks retained")
				for i in old.get_frame_count(clip):
					var old_texture: AtlasTexture = old.get_frame_texture(clip, i)
					var texture: AtlasTexture = frames.get_frame_texture(clip, i)
					_check(old_texture.region == texture.region and old_texture.atlas.resource_path == texture.atlas.resource_path and frames.get_frame_duration(clip, i) == old.get_frame_duration(clip, i), "reuse existing walk atlas without new source copies")
	_check(count == 493, "448 previous frames plus 45 rabbit assembly frames archived")
	print("WORK ATLAS: %d source frames, %d failures" % [count, failures])
	quit(1 if failures else 0)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
