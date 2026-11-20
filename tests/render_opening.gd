extends SceneTree
## Startup must finish before any shop can run or write a save.

const Stub := preload("res://tests/fixtures/opening_video_stub.gd")
const TRACK := preload("res://art/audio/pancake_morning.ogg")
var failures := 0

func _initialize() -> void:
	call_deferred("run_tests")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func mouse_button(at: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	root.push_input(event, true)

func run_tests() -> void:
	if not ResourceLoader.exists("res://presentation/opening/opening.tscn"):
		check(false, "Production startup scene must exist")
		finish()
		return
	root.size = Vector2i(720, 1280)
	var audio: Node = root.get_node("ShopAudio")
	var app: Node = root.get_node("App")
	audio.music_enabled = true
	var scene = load("res://presentation/opening/opening.tscn").instantiate()
	var media := Stub.new()
	scene.video = media
	scene.change_scene_on_start = false
	root.add_child(scene)
	check(app._profile == null, "Welcome does not read ambient progress")
	check(scene.phase == scene.Phase.WELCOME and media.plays == 0, "Welcome waits for a real choice")
	check(scene.welcome.visible and not scene.poster.visible and not scene.start_button.visible, "Welcome image precedes poster and final button")
	check(scene.welcome.size.is_equal_approx(Vector2(720, 1280)), "High-resolution welcome must fit the design canvas without clipping")
	check(scene.welcome.get("sprite") != null, "Loading background uses the supplied GIF animation in-engine")
	if scene.welcome.get("sprite") == null:
		scene.free()
		finish()
		return
	check(scene.welcome.sprite.is_playing(), "Loading background animates while waiting for entry")
	check(scene.welcome.percent_label.get_theme_font_size("font_size") >= 90, "Engine percentage uses viewport-sized glyphs instead of enlarging small bitmap text")
	var gif_duration := 0.0
	for index in scene.welcome.sprite.sprite_frames.get_frame_count("default"):
		gif_duration += scene.welcome.sprite.sprite_frames.get_frame_duration("default", index) / scene.welcome.sprite.sprite_frames.get_animation_speed("default")
	check(is_equal_approx(gif_duration, 0.63), "Engine animation preserves the original GIF timing")
	var frame_events: Array = []
	scene.welcome.sprite.frame_changed.connect(func() -> void: frame_events.append(true))
	await create_timer(0.20).timeout
	check(not frame_events.is_empty(), "GIF starts advancing immediately at the supplied frame rate")
	scene.welcome.set_progress(68, false)
	check(scene.welcome.percent_label.text == "68%", "Loading percentage is drawn dynamically")
	check(scene.welcome.message_label.text == "美味正在准备中…", "Loading message matches the supplied UI reference")
	check(scene.welcome.caption_button.text == "小厨师们正在赶来，马上开饭！", "Loading caption matches the supplied UI reference")
	check(scene.welcome.caption_button.disabled, "Illustrated caption does not become clickable before readiness")
	scene.welcome.set_progress(100, true)
	scene.start_shop()
	check(scene.phase == scene.Phase.WELCOME, "Cannot enter a shop from the welcome stage")
	scene.begin_intro()
	scene.begin_intro()
	check(media.plays == 1 and scene.phase == scene.Phase.PLAYING, "Double welcome click plays only once")
	check(root.get_node_or_null("ShopPlay") == null, "Intro has no running shop behind it")
	check(app._profile == null, "Playing the intro never reads shop progress")
	check(media.audio_enabled and audio.get_node("Music").stream == null, "The video plays its soundtrack without starting shop music")
	media.finished.emit()
	await process_frame
	check(scene.poster.visible and scene.start_button.visible, "Finished video displays a permanent poster and real button")
	check(not scene.start_button.disabled, "A visible start button accepts the first tap during pop-in")
	var requests: Array = []
	scene.shop_requested.connect(func() -> void: requests.append(true))
	var center: Vector2 = scene.start_button.get_global_rect().get_center()
	var idle_position: Vector2 = scene._button_face.position
	mouse_button(center, true)
	check(scene._button_face.position.y > idle_position.y and scene._button_face.modulate != Color.WHITE, "Holding the button depresses and darkens its face")
	var drag := InputEventMouseMotion.new()
	drag.position = Vector2(10, 10)
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(drag, true)
	mouse_button(Vector2(10, 10), false)
	check(scene._button_face.position == idle_position and scene._button_face.modulate == Color.WHITE and requests.is_empty(), "Releasing outside cancels and restores the button")
	mouse_button(center, true)
	mouse_button(center, false)
	check(scene.start_button.disabled and scene.start_button.text == "正在进店…" and scene._button_face.position.y > idle_position.y, "A valid click displays entering feedback and locks the button")
	scene.start_shop()
	check(requests.size() == 1, "Repeated final clicks request exactly one shop")
	scene.free()
	var failed_scene = load("res://presentation/opening/opening.tscn").instantiate()
	var bad_media := Stub.new()
	failed_scene.video = bad_media
	failed_scene.change_scene_on_start = false
	root.add_child(failed_scene)
	failed_scene.begin_intro()
	bad_media.failed.emit()
	await process_frame
	await create_timer(0.6).timeout
	check(failed_scene.poster.visible and not failed_scene.start_button.disabled, "Media failure still allows starting the game")
	bad_media.finished.emit()
	await process_frame
	check(not failed_scene.start_button.disabled, "Late completion cannot replay the button animation")
	for dimensions in [Vector2(720, 1600), Vector2(1280, 720), Vector2(720, 1280)]:
		failed_scene.size = dimensions
		failed_scene.layout_frame()
		check(is_equal_approx(failed_scene.frame.size.x / failed_scene.frame.size.y, 720.0 / 1280.0), "Opening artwork always retains portrait proportions")
		check(failed_scene.frame.position.x >= 0 and failed_scene.frame.position.y >= 0, "Artwork remains inside the viewport")
	failed_scene.free()
	# Repeat with existing progress and the saved mute preference.
	var profile_script = load("res://game/app/profile.gd")
	var isolated_profile = profile_script.new("user://opening-profile-probe.json")
	isolated_profile.shop = "tea"
	app.profile = isolated_profile
	var before: Dictionary = isolated_profile.to_dict().duplicate(true)
	var saved_before := FileAccess.get_file_as_bytes(isolated_profile.path) if FileAccess.file_exists(isolated_profile.path) else PackedByteArray()
	var resumed = load("res://presentation/opening/opening.tscn").instantiate()
	var resumed_media := Stub.new()
	resumed.video = resumed_media
	root.add_child(resumed)
	audio.music_enabled = false
	resumed.begin_intro()
	check(resumed_media.plays == 1 and not resumed_media.audio_enabled, "Intro respects the music-off preference and still plays")
	check(isolated_profile.to_dict() == before, "Playing the intro leaves progress untouched")
	var saved_after := FileAccess.get_file_as_bytes(isolated_profile.path) if FileAccess.file_exists(isolated_profile.path) else PackedByteArray()
	check(saved_after == saved_before, "Intro does not write progress to disk")
	resumed.free()
	app.profile = null
	audio.play_music(TRACK)
	check(not audio.get_node("Music").playing or audio.get_node("Music").stream_paused, "Shop music also respects the music-off preference")
	audio.music_enabled = true
	audio._can_play = true
	audio.play_music(TRACK)
	await create_timer(0.15).timeout
	var position: float = audio.get_node("Music").get_playback_position()
	audio.enter_shop(null, TRACK)
	check(audio.get_node("Music").get_playback_position() >= position, "Same-track shop handoff does not rewind music")
	audio.play_music(null)
	await create_timer(0.15).timeout
	finish()

func finish() -> void:
	print("OPENING: %d failures" % failures)
	quit(failures)
