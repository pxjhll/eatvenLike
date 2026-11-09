extends SceneTree
## Actual sessions, files and input events for the isolated third-shop fixture.

const TestSession := preload("res://tests/shop_test_session.gd")
const Profile := preload("res://game/app/profile.gd")
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
const NOODLE: SpecShop = preload("res://tests/fixtures/noodle/shop.tres")
const CAMPAIGN: SpecCampaign = preload("res://tests/fixtures/noodle/campaign.tres")
var errors := preload("res://tests/error_counter.gd").new()
var failures := 0
var checks := 0
var paths: Array[String] = []
var view: Node2D
var hud: Control
var prefix := ""

func _initialize() -> void:
	Input.use_accumulated_input = false
	OS.add_logger(errors)
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(720, 1280)
	root.get_node("ShopAudio")._can_play = false
	for defect in ["missing", "resource_type", "root_type", "anchors", "tap", "metadata", "duplicate", "reference", "number", "combination", "tables_missing", "tables_short", "tables_invalid_per_table"]:
		await _invalid_startup_preserves_progress(defect)
	_session_failure_disposes_candidate()
	await _third_shop_business()
	for path in paths:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	for error in errors.take():
		failures += 1
		print("RUNTIME: " + error)
	OS.remove_logger(errors)
	print("SHOP NOODLE GUI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _path(label: String) -> String:
	var result := "user://scene-contract-%d-%d-%s" % [OS.get_process_id(), Time.get_ticks_usec(), label]
	paths.append(result)
	return result

func _invalid_startup_preserves_progress(defect: String) -> void:
	var spec: SpecShop = TEA.duplicate(true)
	var profile := Profile.new(_path("profile.json"))
	_check(profile.finish_shop({"shop": "pancake"}) == OK, "fresh intent selected")
	var store := ShopSave.new(spec, _path("shop.json"))
	var previous := ShopRules.new(TEA)
	previous.gold = 1234
	_check(store.save_game(previous) == OK, "old shop sentinel written")
	var original := FileAccess.get_file_as_bytes(store.path)
	var profile_bytes := FileAccess.get_file_as_bytes(profile.path)
	match defect:
		"missing": spec.scene_path = "res://tests/fixtures/no_such_art.tscn"
		"resource_type": spec.scene_path = "res://tests/fixtures/noodle/shop.tres"
		"duplicate": spec.stations[1].id = spec.stations[0].id
		"reference": spec.dishes[0].steps[0].station = "missing_station"
		"number": spec.start_gold = -1
		"combination": spec.fulfillment.arrival = "exponential"
		_:
			var art: Node = Node.new() if defect == "root_type" else load(TEA.scene_path).instantiate()
			if defect == "anchors": art.get_node("Anchors").free()
			if defect == "tap": art.get_node("Anchors/Stations/lemonade/Tap").free()
			if defect == "metadata": art.get_node("Anchors").set_meta("world_size", Vector2(NAN, 100))
			if defect == "tables_missing": art.get_node("Anchors/Tables/dine").free()
			if defect == "tables_short": art.get_node("Anchors/Tables/dine/3").free()
			if defect == "tables_invalid_per_table": art.get_node("Anchors/Tables/dine").set_meta("per_table", 0.5)
			var packed := PackedScene.new()
			_check(packed.pack(art) == OK, "pack malformed scene " + defect)
			art.free()
			spec.scene_path = _path("art.tscn")
			_check(ResourceSaver.save(packed, spec.scene_path) == OK, "save malformed scene " + defect)
	var scene: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	scene.session = TestSession.make(spec, store.path, null, store, profile)
	root.add_child(scene)
	await process_frame
	_check(scene.rules == null and scene.session.rules == null and not scene.is_processing(), "bad configuration blocks business: " + defect)
	_check(scene.save_now(false) != OK, "bad scene blocks save")
	scene._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(FileAccess.get_file_as_bytes(store.path) == original, "bad scene never replaces old shop for fresh intent")
	_check(FileAccess.get_file_as_bytes(profile.path) == profile_bytes and profile.fresh_shop, "bad scene never acknowledges fresh intent")
	if scene.rules == null:
		store.shop = TEA
		scene.retry_startup()
		scene.set_process(false)
		_check(scene.rules != null and not profile.fresh_shop, "repair and retry starts fresh only after validation: " + scene.save_status)
		_check(scene.art != null and scene.get_node("Canvas").get_child_count() == 3, "one art candidate adopted")
	scene.free()

func _session_failure_disposes_candidate() -> void:
	var profile := Profile.new(_path("mismatch-profile.json"))
	var store := ShopSave.new(TEA, _path("mismatch-shop.json"))
	var before := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	# Art is valid but the real Profile still selects the first production shop.
	# Session.start must reject the mismatch and release its prepared candidate.
	for unused in 3:
		var scene: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
		scene.session = TestSession.make(TEA, store.path, null, store, profile)
		root.add_child(scene)
		_check(scene._startup_blocked and scene.rules == null and not scene.session.started, "session identity failure blocks after valid art preparation")
		_check(not FileAccess.file_exists(store.path), "session identity failure does not create save")
		scene.free()
	_check(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) == before, "Session.start failure frees every prepared art candidate")

func _third_shop_business() -> void:
	prefix = _path("noodle")
	var production_ids := Profile.shops()
	view = _open_noodle()
	_check(view.rules != null, "third shop starts through real Profile, Store and Session: " + view.save_status)
	if view.rules == null:
		view.free()
		return
	_check(view.profile.shop == "noodle" and view.profile.available_shops() == ["noodle"], "real injected campaign selects only fixture")
	_check(not view.rules.is_open() and int(view.rules.gold) == 10, "cold fixture retains original opening economics")
	await process_frame
	hud = view.ui
	await _click(view._station_buttons.urn)
	_check(hud.page == "station" and hud.page_node("station").station_id == "urn", "opening frame opens urn panel")
	await _click(hud.page_node("station").unlock_button)
	_check(view.rules.is_open() and int(view.rules.gold) == 0, "actual unlock click spends opening coins")
	await _click(hud.tab("shop"))
	_advance_until(func() -> bool: return view.rules.sold > 0, 120)
	_check(view.rules.sold > 0 and view.rules.revenue > 0, "live scene sells first dish")
	_check(view.guide.seen.has("opening"), "real opening guide completes")
	# Funding isolates panel behavior from long earning time; data prices remain unchanged.
	view.rules.gold = 10000
	for id in ["board", "pot", "toppings"]:
		await _frame_click(id)
		await _click(hud.page_node("station").unlock_button)
		_check(view.rules.station_unlocked(id), "actual panel unlocks " + id)
		await _click(hud.tab("staff"))
		var before: int = view.rules.workers.size()
		await _click(hud.page_node("staff").hire_button)
		_check(view.rules.workers.size() == before + 1, "actual staff panel hires into new stage slot")
		await _click(hud.tab("shop"))
		if id == "board":
			_advance_until(func() -> bool: return int(view.rules.sold_by_dish.dry_noodle) > 0, 180)
	await _tap("toppings")
	await _click(hud.page_node("station").upgrade_button)
	_check(view.rules.level("toppings") == 2 and view.rules.dish_open("egg_noodle"), "upgrade unlocks additional dish")
	await _click(hud.tab("shop"))
	_advance_until(func() -> bool: return NOODLE.dishes.all(func(d: SpecDish) -> bool: return int(view.rules.sold_by_dish.get(d.id, 0)) > 0), 900)
	for dish in NOODLE.dishes:
		_check(int(view.rules.sold_by_dish.get(dish.id, 0)) > 0, "real business sells " + dish.id)
	await _click(hud.speed_button)
	_check(view._speed_factor == 2, "actual speed button selects 2x")
	_check(view.save_now(false) == OK, "third shop saves through real store")
	var saved: Dictionary = view.rules.to_dict()
	var seen: Array = view.guide.seen_list()
	var profile_path: String = view.profile.path
	var continuation := ShopRules.new(NOODLE)
	_check(continuation.load_dict(saved).is_empty(), "saved state supports exact continuation oracle")
	view.free()
	_check(Profile.new(profile_path, CAMPAIGN).shop == "noodle", "third shop selection persists with actual campaign")
	view = _open_noodle()
	hud = view.ui
	_check(view.rules.to_dict() == saved, "close/reopen restores every rule field before ticking")
	_check(view._speed_factor == 2 and view.guide.seen_list() == seen, "speed and real guide history restore")
	for unused in 120:
		view._process(0.25)
		continuation.step(0.5)
	_check(view.rules.to_dict() == continuation.to_dict(), "next 60 seconds exactly match uninterrupted run")
	_check(view.next_shop() == null and view.jump_shop(1).is_empty(), "navigation stays inside fixture campaign")
	_check(Profile.shops() == production_ids and not "noodle" in production_ids, "default campaign unchanged")
	await _capture()
	await _click(hud.get_node("%Menu"))
	await _click(hud.page_node("menu").restart_button)
	_check(hud.page == "restart", "restart requires confirmation page")
	await _click(hud.page_node("restart").confirm_button)
	_check(not view.rules.is_open() and view.rules.gold == 10 and view.rules.sold == 0, "restart clears prior business")
	_check(view.rules.roster.size() == 1 and view.rules.level("toppings") == 1, "restart clears hired staff and upgrades")
	_check(view._customers.is_empty() and view.guide.seen_list() == seen, "restart clears guests and retains guide history")
	await _frame_click("urn")
	await _click(hud.page_node("station").unlock_button)
	await _click(hud.tab("shop"))
	_advance_until(func() -> bool: return view.rules.sold > 0, 120)
	_check(view.rules.sold > 0, "new business sells again after restart")
	view.free()

func _open_noodle() -> Node2D:
	var scene: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	scene.session = TestSession.make(NOODLE, prefix, null, null, null, CAMPAIGN)
	scene.session.guide_enabled = true
	for path in [scene.session.profile.path, scene.session.store.path, scene.session.tuning_path, scene.session.recording_path]:
		if not path in paths: paths.append(path)
	root.add_child(scene)
	scene.set_process(false)
	return scene

func _advance_until(done: Callable, seconds: float) -> void:
	for unused in int(seconds * 4):
		if done.call(): return
		view._process(0.25)

func _frame_click(id: String) -> void:
	view.reveal_world(view.anchors.rect("Stations/" + id + "/Frame"))
	await process_frame
	view._refresh(0)
	await _click(view._station_buttons[id])

func _tap(id: String) -> void:
	var rect: Rect2 = view.anchors.station_rects()[id]
	view.reveal_world(rect)
	await process_frame
	await _press(view.get_node("Canvas").get_global_transform_with_canvas() * rect.get_center())
	_check(hud.page == "station" and hud.page_node("station").station_id == id, "world tap opens " + id)

func _click(button: Control) -> void:
	for unused in 4: await process_frame
	view._refresh(0)
	var usable: bool = button != null and button.is_visible_in_tree() and not (button is BaseButton and button.disabled)
	_check(usable, "control visible and enabled: " + (str(button.get("text")) if button != null else "null"))
	if usable: await _press(button.get_global_transform_with_canvas() * (button.size / 2))

func _press(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	view._refresh(0)
	await process_frame

func _capture() -> void:
	var screenshot := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--size="):
			var dimensions := argument.trim_prefix("--size=").split("x")
			root.size = Vector2i(int(dimensions[0]), int(dimensions[1]))
		if argument.begins_with("--screenshot="): screenshot = argument.trim_prefix("--screenshot=")
	if screenshot.is_empty(): return
	view.ui.open_page("shop")
	view._scroll = 0
	view._fit()
	for unused in 4: await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(screenshot) == OK, "screenshot saved")
	print("SCREENSHOT: " + screenshot)
	root.size = Vector2i(720, 1280)
	view._fit()

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: " + label)
