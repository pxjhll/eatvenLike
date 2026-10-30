extends SceneTree
## Pixel integrity, gait endpoint policy and ready-to-play native resources.

const ROOT := "res://art_src/rabbit_walk_frames/"
const OUTPUT := "res://art/rabbit_walk_frames/"
const KEYS := ["front", "front_right", "right", "back_right", "back"]
const DURATIONS := [[120, 90, 120, 130, 120, 90, 120], [130, 170, 120, 130, 120, 170, 120], [130, 170, 120, 170, 120, 170, 120], [130, 120, 130, 120, 130, 120, 130], [120, 90, 120, 90, 120, 90, 120]]
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(ResourceLoader.exists(ROOT + "frame_policy.gd"), "frame endpoint policy exists")
	if failures:
		quit(1)
		return
	var policy: Script = load(ROOT + "frame_policy.gd")
	var red := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	red.fill(Color.RED)
	var blue := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	blue.fill(Color.BLUE)
	_check(policy.loop_indices([red, blue, red]) == [0, 1], "duplicate final endpoint is omitted")
	_check(policy.loop_indices([red, blue]) == [0, 1], "different terminal pose is preserved")
	_check(policy.loop_indices([red, red, blue]) == [0, 1, 2], "interior repeated holds are preserved")
	var hidden_a := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	hidden_a.fill(Color(1, 0, 0, 0))
	var hidden_b := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	hidden_b.fill(Color(0, 1, 0, 0))
	_check(policy.loop_indices([hidden_a, blue, hidden_b]) == [0, 1], "hidden transparent RGB does not create a false distinct endpoint")
	_check(ResourceLoader.exists(OUTPUT + "rabbit_walk_frames.tres"), "native SpriteFrames resource exists")
	if failures:
		quit(1)
		return
	var frames: SpriteFrames = load(OUTPUT + "rabbit_walk_frames.tres")
	var atlas := Image.load_from_file(ProjectSettings.globalize_path(OUTPUT + "rabbit_walk_atlas.png"))
	_check(atlas.get_size() == Vector2i(1792, 1280), "atlas is seven columns by five rows")
	for row in 5:
		var name := "walk_" + str(KEYS[row])
		_check(frames.has_animation(name), "direction exists: " + name)
		_check(frames.get_frame_count(name) == 7, "seven distinct sampled poses retained for " + name)
		_check(frames.get_animation_loop(name), "clip loops: " + name)
		for frame in 7:
			var texture: AtlasTexture = frames.get_frame_texture(name, frame)
			var expected_rect := Rect2(frame * 256, row * 256, 256, 256)
			_check(texture.region == expected_rect and texture.filter_clip, "correct clipped atlas region")
			var source := Image.load_from_file(ProjectSettings.globalize_path(ROOT + "frames/" + str(KEYS[row]) + "/%02d.png" % (frame + 1)))
			_check(atlas.get_region(Rect2i(expected_rect)).get_data() == source.get_data(), "source pixels preserved, including alpha")
			var duration := frames.get_frame_duration(name, frame) / frames.get_animation_speed(name)
			_check(absf(duration - float(DURATIONS[row][frame]) / 1000.0) < 0.00001, "source frame timing retained")
	var scene := "res://presentation/rabbit_walk_frames/rabbit_walk.tscn"
	_check(ResourceLoader.exists(scene), "reusable frame-only actor scene exists")
	if failures:
		quit(1)
		return
	var actor: Node2D = load(scene).instantiate()
	root.add_child(actor)
	await process_frame
	actor.pause()
	actor.seek_phase(0.37)
	for direction in 8:
		actor.set_direction(direction)
		_check(absf(actor.get_phase() - 0.37) < 0.0001, "direction switch preserves phase")
		_check(actor.sprite.flip_h == (direction > 4), "three left directions mirror shared clips")
		_check(not actor.sprite.is_playing(), "direction switch preserves paused state")
	actor.seek_phase(0.999)
	_check(actor.sprite.frame == 6, "final distinct pose remains before loop wrap")
	actor.seek_phase(0.0)
	_check(actor.sprite.frame == 0, "loop starts directly at first pose")
	_check(actor.sprite.offset == Vector2(-128, -244), "stable shared canvas anchor")
	actor.free()
	print("RABBIT FRAME ATLAS: %d failures" % failures)
	quit(1 if failures else 0)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
