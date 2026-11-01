extends SceneTree
## Compare every native atlas cell against its archived source PNG and timing.

const SOURCE := "res://art_src/gray_cat_walk_frames/"
const KEYS := ["front", "front_right", "right", "back_right", "back"]
const DURATIONS := [[130, 160, 130, 120, 130, 170, 120], [130, 120, 130, 170, 120, 130, 120], [120, 90, 120, 130, 120, 90, 120], [130, 80, 130, 80, 130, 80, 120], [80, 130, 80, 130, 80, 130, 80]]
const CYCLES := [0.65 / 1.15, 0.65 / 1.15, 0.80, 0.80, 0.80]
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE + "source_manifest.json"))
	var frames: SpriteFrames = load("res://art/gray_cat_walk_frames/gray_cat_walk_frames.tres")
	var atlas := Image.load_from_file(ProjectSettings.globalize_path("res://art/gray_cat_walk_frames/gray_cat_walk_atlas.png"))
	_check(atlas.get_size() == Vector2i(1792, 1280), "7x5 cells at 256 pixels")
	var policy: Script = load("res://art_src/rabbit_walk_frames/frame_policy.gd")
	for row in 5:
		var clip := "walk_" + str(KEYS[row])
		var source_ms := 0.0
		for duration in DURATIONS[row]: source_ms += duration
		_check(frames.has_animation(clip) and frames.get_frame_count(clip) == 7 and frames.get_animation_loop(clip), "seven authored poses loop for every direction")
		var images: Array = []
		for index in 7:
			var path := SOURCE + "frames/" + str(KEYS[row]) + "/%02d.png" % (index + 1)
			var source := Image.load_from_file(ProjectSettings.globalize_path(path))
			images.append(source)
			_check(FileAccess.get_sha256(path) == manifest.directions[row].frames[index].sha256, "archived PNG remains byte-identical")
			var cell: AtlasTexture = frames.get_frame_texture(clip, index)
			_check(cell.region == Rect2(index * 256, row * 256, 256, 256) and cell.filter_clip, "native clipped atlas region")
			_check(atlas.get_region(Rect2i(cell.region)).get_data() == source.get_data(), "exact source pixels including alpha")
			_check(manifest.directions[row].durations_ms[index] == DURATIONS[row][index], "source timing record remains unchanged")
			var expected: float = DURATIONS[row][index] / source_ms * CYCLES[row]
			_check(absf(frames.get_frame_duration(clip, index) / frames.get_animation_speed(clip) - expected) < 0.00001, "runtime cadence keeps original relative frame holds")
		_check(policy.loop_indices(images).size() == 7, "last source pose is distinct and is not removed")
	var actor = load("res://presentation/gray_cat_walk_frames/gray_cat_walk.tscn").instantiate()
	root.add_child(actor)
	await process_frame
	actor.pause()
	actor.seek_phase(0.37)
	for direction in 8:
		actor.set_direction(direction)
		var row := KEYS.find(str(actor.SUFFIXES[direction]))
		_check(absf(actor.get_cycle_seconds() - CYCLES[row]) < 0.0001, "front group incorporates the selected 1.15x; side/back remain 0.80s")
		_check(actor.sprite.animation == actor.CLIPS[direction] and actor.sprite.flip_h == (direction > 4), "eight directions use correct clip and mirror")
		_check(not actor.sprite.is_playing() and absf(actor.get_phase() - 0.37) < 0.0001, "switch preserves phase and pause")
	_check(actor.sprite.offset == Vector2(-128, -247), "shared fixed canvas anchor")
	actor.free()
	print("GRAY CAT ATLAS: %d failures" % failures)
	quit(1 if failures else 0)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
