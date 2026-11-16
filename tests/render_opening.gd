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

func run_tests() -> void:
	if not ResourceLoader.exists("res://presentation/opening/opening.tscn"):
		check(false, "Production startup scene must exist")
		finish()
		return
	root.size = Vector2i(720, 1280)
	var audio: Node = root.get_node("ShopAudio")
	var app: Node = root.get_node("App")
	var scene = load("res://presentation/opening/opening.tscn").instantiate()
	var media := Stub.new()
	scene.video = media
	scene.music_track = TRACK
	scene.change_scene_on_start = false
	root.add_child(scene)
	check(app._profile == null, "Welcome does not read ambient progress")
	check(scene.phase == scene.Phase.WELCOME and media.plays == 0, "Welcome waits for a real choice")
	check(scene.welcome.visible and not scene.poster.visible and not scene.start_button.visible, "Welcome image precedes poster and final button")
	check(scene.welcome.size.is_equal_approx(Vector2(720, 1280)), "High-resolution welcome must fit the design canvas without clipping")
	scene.start_shop()
	check(scene.phase == scene.Phase.WELCOME, "Cannot enter a shop from the welcome stage")
	scene.begin_intro()
	scene.begin_intro()
	check(media.plays == 1 and scene.phase == scene.Phase.PLAYING, "Double welcome click plays only once")
	check(root.get_node_or_null("ShopPlay") == null, "Intro has no running shop behind it")
	check(app._profile == null, "Injected intro music never creates a shop session")
	check(audio.get_node("Music").stream == TRACK, "Intro music uses the existing audio service")
	media.finished.emit()
	await process_frame
	check(scene.poster.visible and scene.start_button.visible, "Finished video displays a permanent poster and real button")
	check(scene.start_button.disabled, "Button cannot activate during its pop-in animation")
	await create_timer(0.6).timeout
	check(not scene.start_button.disabled and scene.phase == scene.Phase.READY, "Pop-in settles before enabling entry")
	check(scene.start_button.scale.is_equal_approx(Vector2.ONE), "Final button settles at its intended size")
	var requests: Array = []
	scene.shop_requested.connect(func() -> void: requests.append(true))
	scene.start_shop()
	scene.start_shop()
	check(requests.size() == 1, "Repeated final clicks request exactly one shop")
	scene.free()
	var failed_scene = load("res://presentation/opening/opening.tscn").instantiate()
	var bad_media := Stub.new()
	failed_scene.video = bad_media
	failed_scene.music_track = TRACK
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
	# Read music for existing progress without opening, resetting or saving that shop.
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
	resumed.begin_intro()
	check(resumed.music_track == load("res://art/audio/milk_tea_afternoon.ogg"), "Existing progress chooses the upcoming shop's music")
	check(isolated_profile.to_dict() == before, "Selecting intro music leaves progress untouched")
	var saved_after := FileAccess.get_file_as_bytes(isolated_profile.path) if FileAccess.file_exists(isolated_profile.path) else PackedByteArray()
	check(saved_after == saved_before, "Intro does not write progress to disk")
	resumed.free()
	app.profile = null
	audio.music_enabled = false
	audio.play_music(TRACK)
	check(not audio.get_node("Music").playing or audio.get_node("Music").stream_paused, "Intro respects saved music-off preference")
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
