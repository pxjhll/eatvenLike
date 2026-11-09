extends SceneTree

const TestSession := preload("res://tests/shop_test_session.gd")
## Isolated live startup/retry regression. Run with an isolated APPDATA.
## Optional -- --screenshot=absolute.png exports the blocked startup at 480x800.

const Suite := preload("res://tests/test_profile_safety.gd")
const Profile := preload("res://game/app/profile.gd")
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
var suite := Suite.new()
var errors := preload("res://tests/error_counter.gd").new()

func _initialize() -> void:
	OS.add_logger(errors)
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(480, 800)
	# This fixture validates persistence and screen layout; avoid starting an
	# Ogg mixer thread immediately before quitting graphical screenshot runs.
	root.get_node("ShopAudio")._can_play = false
	var profile := Suite.FailingProfile.new(suite._path("live-profile"))
	profile.finish_shop({"shop": "pancake"})
	var store := Suite.FailingStore.new(TEA, suite._path("live-shop"))
	var previous := ShopRules.new(TEA)
	previous.gold = 1234.0
	store.save_game(previous)
	var original := FileAccess.get_file_as_bytes(store.path)
	store.fail_write = true
	var scene := _open(profile, store)
	await process_frame
	suite.check(not scene.is_processing() and scene.rules == null, "failed startup cannot play")
	suite.check(scene.get_node("Overlay/ProgressRetry").visible, "retry screen visible")
	suite.check(scene.save_now(false) != OK, "blocked startup cannot save")
	for control in scene.get_node("Overlay/ProgressRetry").find_children("*", "Control", true, false):
		var rect: Rect2 = control.get_global_rect()
		var viewport_rect: Rect2 = root.get_visible_rect()
		suite.check(viewport_rect.encloses(rect), "retry controls fit viewport: %s %s in %s" % [control.get_class(), rect, viewport_rect])
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--screenshot="):
			await RenderingServer.frame_post_draw
			var screenshot := argument.trim_prefix("--screenshot=")
			root.get_texture().get_image().save_png(screenshot)
			print("SCREENSHOT: " + screenshot)
	scene.free()
	suite.check_eq(FileAccess.get_file_as_bytes(store.path), original, "failed startup exit preserves previous file")
	# Restart preserves the intent, and marker write failure must stay blocked.
	profile = Suite.FailingProfile.new(profile.path)
	profile.fail_write = true
	store.fail_write = false
	scene = _open(profile, store)
	await process_frame
	suite.check(scene.rules == null and profile.fresh_shop, "restart acknowledgement failure stays blocked")
	var empty_bytes := FileAccess.get_file_as_bytes(store.path)
	scene._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	suite.check_eq(FileAccess.get_file_as_bytes(store.path), empty_bytes, "blocked notification cannot write")
	profile.fail_write = false
	scene.retry_startup()
	scene.set_process(false)
	await process_frame
	suite.check(scene.rules != null and not Profile.new(profile.path).fresh_shop, "retry commits marker before play")
	suite.check(not scene.has_node("Overlay/ProgressRetry"), "successful retry removes blocker")
	suite.check(scene.rules.clock == 0.0, "retry starts an empty shop")
	scene.free()
	await process_frame
	await _content_compatibility_retry()
	suite.cleanup()
	for error in errors.take(): suite.failures.append("runtime error: " + error)
	OS.remove_logger(errors)
	for failure in suite.failures: print("FAIL: " + failure)
	print("Startup/retry live checks: %d failures" % suite.failures.size())
	quit(0 if suite.failures.is_empty() else 1)

func _content_compatibility_retry() -> void:
	var profile := Profile.new(suite._path("content-profile"))
	suite.check_eq(profile.select_shop("tea"), OK, "compatible profile prepared")
	var store := ShopSave.new(TEA, suite._path("content-shop"))
	var previous := ShopRules.new(TEA)
	previous.gold = 6789.0
	suite.check_eq(store.save_game(previous), OK, "compatible shop prepared")
	var compatible := FileAccess.get_file_as_string(store.path)
	var payload: Dictionary = JSON.parse_string(compatible)
	# 更高版本程序写的存档：停止写入、等修好重试（内容改版不会走到这里，见 test_content_save）
	payload.content.version = 99
	suite._write(store.path, JSON.stringify(payload))
	var original := FileAccess.get_file_as_bytes(store.path)
	var scene := _open(profile, store)
	await process_frame
	suite.check(scene.rules == null and scene.session.rules == null, "incompatible scene and session expose no rules")
	suite.check(not scene.is_processing() and not scene.session.started, "incompatible business is stopped")
	suite.check(scene.get_node("Overlay/ProgressRetry").visible, "incompatible blocker is visible")
	suite.check(not scene.session.last_error.is_empty(), "incompatible blocker explains error")
	scene._process(11.0)
	suite.check(scene.save_now(false) != OK, "incompatible autosave cannot write")
	scene._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	scene._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	suite.check(FileAccess.get_file_as_bytes(store.path) == original, "blocked autosave and focus preserve file")
	scene.free()
	await process_frame
	suite.check(FileAccess.get_file_as_bytes(store.path) == original, "blocked scene exit preserves incompatible bytes")
	# Repair and retry the very same scene and store, without replacing dependencies.
	scene = _open(profile, store)
	await process_frame
	var same_session: RefCounted = scene.session
	suite._write(store.path, compatible)
	scene.retry_startup()
	suite.check(scene.session == same_session, "retry reuses explicit session")
	suite.check(scene.rules != null and scene.session.started, "repair retry restores rules")
	suite.check(scene.is_processing(), "repair retry resumes processing")
	suite.check(not scene.has_node("Overlay/ProgressRetry"), "repair retry removes blocker")
	if scene.rules != null:
		suite.check_eq(scene.rules.gold, 6789.0, "repair retry restores saved gold")
		suite.check_eq(scene.save_now(false), OK, "repair retry permits save")
	scene.set_process(false)
	scene.free()
	await process_frame

func _open(profile: RefCounted, store: ShopSave) -> Node2D:
	var scene: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	scene.session = TestSession.make(TEA, store.path, null, store, profile)
	root.add_child(scene)
	return scene
