extends SceneTree
## Live lifecycle tests require a disposable user-data root because production-path
## sentinels intentionally contain unreadable data. All scene dependencies are explicit.

const TestSession := preload("res://tests/shop_test_session.gd")
const Suite := preload("res://tests/test_scene_session.gd")
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
const PANCAKE: SpecShop = preload("res://content/shops/pancake/shop.tres")
const Profile := preload("res://game/app/profile.gd")
const DEFAULTS := ["user://profile.json", "user://tuning.cfg", "user://playlog.txt"]
var suite := Suite.new()
var errors := preload("res://tests/error_counter.gd").new()
var originals := {}
var prefix := "user://lifecycle-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]

func _initialize() -> void:
	OS.add_logger(errors)
	call_deferred("_run")

func _write(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()

func _open(session: RefCounted) -> Node2D:
	var scene: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	scene.session = session
	root.add_child(scene)
	scene.set_process(false)
	return scene

func _fixture(suffix: String, rules: ShopRules = null) -> RefCounted:
	var session := TestSession.make(TEA, prefix + suffix, rules)
	for path in [session.profile.path, session.store.path, session.tuning_path, session.recording_path]: suite.paths.append(path)
	return session

func _run() -> void:
	create_timer(25.0).timeout.connect(func() -> void:
		_restore_defaults()
		print("SESSION LIFECYCLE: timed out")
		quit(1))
	if not OS.get_user_data_dir().replace("\\", "/").split("/").has("session-lifecycle-userdata"):
		print("SESSION LIFECYCLE: set APPDATA (Windows) or XDG_DATA_HOME to a disposable session-lifecycle-userdata directory")
		OS.remove_logger(errors)
		quit(1)
		return
	root.size = Vector2i(720, 1280)
	root.get_node("ShopAudio")._can_play = false
	for path in DEFAULTS:
		originals[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	_write(DEFAULTS[0], '{"version":99,"shop":"pancake","trophies":9876}')
	_write(DEFAULTS[1], "[tune]\nprice=3.0\n")
	_write(DEFAULTS[2], "production sentinel\n")
	var sentinels := {}
	for path in DEFAULTS: sentinels[path] = FileAccess.get_file_as_bytes(path)
	var app: Node = root.get_node("App")
	suite.check(app.get("_profile") == null, "autoload never reads production profile")
	# Partial legacy injection fails before App.profile access, even when a real store is supplied.
	var rejected: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	var dependency := _fixture("-rejected", ShopRules.new(TEA))
	rejected.store = dependency.store
	root.add_child(rejected)
	suite.check(rejected._startup_blocked and rejected.session == null and rejected.rules == null, "partial dependency injection is rejected")
	suite.check(app.get("_profile") == null, "partial injection does not initialize ambient App profile")
	rejected.free()
	var tutorial := _fixture("-tutorial")
	tutorial.guide_enabled = true
	var scene := _open(tutorial)
	suite.check(scene.rules != null and scene.rules.shop == TEA, "explicit session loads requested shop despite ambient future profile")
	suite.check(scene.guide.enabled and not scene.recorder.enabled and not scene.tuning.persist, "tutorial does not enable persistent services")
	suite.check_eq(scene.rules.tuned("price"), 1.0, "disabled tuning ignores production tuning")
	suite.check_eq(scene.recorder.text(), "", "disabled scene recorder cannot expose production record")
	scene.recorder.clear()
	suite.check_eq(scene.recorder.export_file(), "还没有录制内容", "disabled scene recorder cannot export")
	scene.free()
	# Reload exact fixture state and guide history, still without ambient services.
	var reopened := TestSession.make(TEA, prefix + "-tutorial")
	scene = _open(reopened)
	suite.check_eq(scene.rules.tuned("price"), 1.0, "isolated reload does not load production tuning")
	scene.free()
	var session := _fixture("-restart", ShopRules.new(TEA))
	session.persist_tuning = true
	session.recording_enabled = true
	_write(session.tuning_path, "[tune]\nprice=1.5\n")
	scene = _open(session)
	suite.check(not scene.guide.enabled and scene.recorder.enabled and scene.tuning.persist, "recording and tuning work with tutorial disabled")
	suite.check_eq(scene.rules.tuned("price"), 1.5, "enabled tuning loads injected destination")
	scene.tuning.set_value("work", 1.25)
	var tuning_bytes := FileAccess.get_file_as_bytes(session.tuning_path)
	var profile_bytes := FileAccess.get_file_as_bytes(session.profile.path)
	var rules: ShopRules = scene.rules
	rules.unlock("lemonade")
	rules.gold = 10000.0
	rules.hire()
	for unused in 300: scene._process(0.25)
	suite.check(rules.sold > 0, "fixture records real prior sales")
	var bus: RuleEvents = rules.events
	var subscriptions: int = bus._listeners.get("*", []).size()
	var probes: Array = []
	bus.on("probe", func(data: Dictionary) -> void: probes.append(data))
	for step in TEA.guide: scene.guide.seen[step.id] = true
	scene.guide.enabled = true
	scene.guide.active = "opening"
	scene.guide._angry_pending = true
	scene.guide._lost_seen = 123
	scene.guide._staff_at_start = 3
	scene.guide._time = 20.0
	var seen: Array = scene.guide.seen_list()
	var callbacks: Array = []
	scene.ui.popups.push({"id": "old-summary", "title": "Test", "buttons": [{"label": "Test", "action": func() -> void: callbacks.append(true)}]})
	var old_button: Button = scene.ui.popups.button(0)
	scene.ui.open_page("menu")
	scene.tuning.show()
	scene.ui.speed_button.pressed.emit()
	scene.ui.speed_button.pressed.emit()
	suite.check_eq(scene._speed_factor, 4.0, "HUD selects four times speed")
	scene._autosave_elapsed = 9.9
	rules.paused = true
	scene._drag._candidate(int(rules.workers[0].id), Vector2(300, 500), false)
	scene._drag._start_drag()
	suite.check(scene._drag.dragging, "fixture starts a real drag")
	scene.restart()
	suite.check(not rules.paused and rules.clock == 0.0 and rules.sold == 0, "restart resumes fresh business")
	suite.check(not scene._drag.dragging and scene._drag.worker_id == -1 and scene._drag._ghost == null, "restart cancels drag before replacing actors")
	suite.check(not scene.ui.popups.has_card() and scene.ui.page == "shop" and not scene.ui.show_selection, "restart clears popup and selection and returns to shop")
	old_button.pressed.emit()
	suite.check(callbacks.is_empty(), "detached old popup button cannot execute stale action")
	suite.check(not scene.tuning.visible and not scene.get_node("Overlay/UI/TuningShade").visible, "restart removes tuning shade")
	suite.check(scene.guide.active.is_empty() and not scene.guide._angry_pending and scene.guide._lost_seen == -1 and scene.guide._staff_at_start == 0 and scene.guide._time == 0.0, "restart clears guide transients")
	suite.check(scene.guide.enabled and scene.guide.seen_list() == seen, "restart retains seen guides and tutorial preference")
	suite.check(scene._speed_factor == 4.0 and rules.tuned("price") == 1.5 and rules.tuned("work") == 1.25, "restart retains speed and tuning")
	suite.check_eq(FileAccess.get_file_as_bytes(session.tuning_path), tuning_bytes, "restart leaves tuning settings intact")
	suite.check_eq(FileAccess.get_file_as_bytes(session.profile.path), profile_bytes, "restart leaves cross-shop profile intact")
	suite.check(scene._autosave_elapsed == 0.0 and scene.recorder._clock == 0.0, "restart resets autosave and sampling clocks")
	suite.check(bus == rules.events and bus._listeners.get("*", []).size() == subscriptions, "restart retains stable single audio subscription")
	bus.emit("probe")
	suite.check_eq(probes.size(), 1, "restart subscription fires once")
	var rows: PackedStringArray = scene.recorder.text().split("\n", false)
	var row: Dictionary = JSON.parse_string(rows[-1])
	suite.check(row.has("session") and int(row.t) == 0, "restart appends fresh recording marker")
	var count: int = scene.recorder.line_count()
	# Four times speed: 59 seconds then the first whole minute of the new session.
	for unused in 59: scene._process(0.25)
	suite.check_eq(scene.recorder.line_count(), count, "new sample waits a full minute")
	scene._process(0.25)
	rows = scene.recorder.text().split("\n", false)
	row = JSON.parse_string(rows[-1])
	suite.check_eq(scene.recorder.line_count(), count + 1, "first restart sample occurs at 60 seconds")
	suite.check(int(row.t) == 60 and float(row.income) == 0.0 and int(row.cups) == 0 and int(row.lost) == 0, "sample excludes prior income sales and loss")
	scene.restart()
	suite.check_eq(bus._listeners.get("*", []).size(), subscriptions, "repeated restart does not multiply audio subscriptions")
	scene.ui.speed_button.pressed.emit()
	scene.ui.speed_button.pressed.emit()
	suite.check_eq(scene.save_now(false), OK, "HUD speed can be saved")
	session.store.load_game()
	suite.check_eq(session.store.loaded_speed, 2.0, "save synchronizes HUD speed into session")
	scene.ui.speed_button.pressed.emit()
	scene.change_scene_on_leave = false
	suite.check_eq(scene.jump_shop(-1), "pancake", "explicit session jumps after saving current shop")
	session.store.load_game()
	suite.check_eq(session.store.loaded_speed, 4.0, "jump synchronizes HUD speed into session")
	scene.free()
	suite.check(app.get("_profile") == null, "explicit scene lifecycle never initializes App profile")
	for path in DEFAULTS: suite.check_eq(FileAccess.get_file_as_bytes(path), sentinels[path], "production sentinel unchanged: " + path)
	_test_dining_restart()
	_test_production_profile_repair(app)
	var warning_session := _fixture("-warning")
	_write(warning_session.store.path, JSON.stringify({"format": ShopSave.FORMAT, "version": 99, "shop": "tea"}))
	scene = _open(warning_session)
	suite.check(not scene._startup_blocked and not String(scene.session.last_error).is_empty() and scene.save_status == scene.session.last_error, "successful startup retains a real shop-load warning")
	scene.free()
	_restore_defaults()
	await process_frame
	suite.cleanup()
	for error in errors.take(): suite.failures.append("runtime error: " + error)
	OS.remove_logger(errors)
	for failure in suite.failures: print("FAIL: " + failure)
	print("SESSION LIFECYCLE: %d failures" % suite.failures.size())
	quit(0 if suite.failures.is_empty() else 1)

func _test_dining_restart() -> void:
	var scene := _open(_fixture("-dining", ShopRules.new(TEA)))
	var dining: Node2D = scene._dining
	var furniture: Array = dining._chairs.duplicate()
	furniture.append_array(dining._tables)
	var anchors: ShopAnchors = dining.anchors
	_open_until_dining(scene)
	suite.check(not dining._diners.is_empty(), "real business generates a seated dining customer")
	dining.queue_exit(scene.anchors.point("Entrance") + Vector2(50, 50), "rabbit", "lemonade")
	scene._refresh(0.0)
	suite.check(dining.walking_count() > 0, "dining owns an active exit walker before restart")
	var old_nodes: Array = dining._diners.values()
	old_nodes.append_array(dining._cups.values())
	for walker in dining._walkers: old_nodes.append(walker.actor)
	var old_ids: Array = old_nodes.map(func(node: Node) -> int: return node.get_instance_id())
	dining.queue_arrival(0, scene.anchors.point("Entrance"), "rabbit")
	dining.queue_exit(scene.anchors.point("Entrance"), "rabbit", "lemonade")
	scene.restart()
	suite.check(dining._diners.is_empty() and dining._cups.is_empty() and dining._walkers.is_empty(), "restart discards dining actors cups and walkers")
	suite.check(dining._arrivals.is_empty() and dining._exits.is_empty() and dining.occupied_seats().is_empty(), "restart clears pending dining movements and occupied seats")
	suite.check(old_nodes.all(func(node: Variant) -> bool: return not is_instance_valid(node)), "restart immediately frees prior dining actors and cups")
	suite.check(dining.anchors == anchors and furniture.all(func(node: Node) -> bool: return is_instance_valid(node) and node.get_parent() == dining), "restart preserves dining anchors and static furniture")
	scene._refresh(0.25)
	suite.check(dining.walking_count() == 0, "old arrivals and exits cannot create actors on next refresh")
	_open_until_dining(scene)
	suite.check(not dining._diners.is_empty(), "new session still creates its first dining guests")
	for actor in dining._diners.values(): suite.check(actor.get_instance_id() not in old_ids, "new diner never reuses an old actor")
	scene.free()

func _open_until_dining(scene: Node2D) -> void:
	scene.rules.unlock("lemonade")
	scene.rules.gold = 10000.0
	scene.rules.hire()
	for unused in 2400:
		scene._process(0.25)
		if not scene._dining._diners.is_empty(): return

func _test_production_profile_repair(app: Node) -> void:
	var original_profile: RefCounted = app.get("_profile")
	var profile_path := prefix + "-repair-profile.json"
	suite.paths.append(profile_path)
	_write(profile_path, '{"version":99,"shop":"tea"}')
	var damaged_profile := Profile.new(profile_path)
	app.profile = damaged_profile
	var pancake_store := ShopSave.new(PANCAKE)
	var tea_store := ShopSave.new(TEA)
	for store in [pancake_store, tea_store]:
		originals[store.path] = FileAccess.get_file_as_bytes(store.path) if FileAccess.file_exists(store.path) else null
		var saved := ShopRules.new(store.shop)
		saved.gold = 1234.0 if store.shop == PANCAKE else 4321.0
		suite.check_eq(store.save_game(saved), OK, "production retry fixture saves isolated shop")
	var unrelated_bytes := FileAccess.get_file_as_bytes(pancake_store.path)
	var scene: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	root.add_child(scene)
	var original_store: ShopSave = scene.session.store
	suite.check(scene._startup_blocked and scene.rules == null and original_store.shop == PANCAKE, "future profile blocks production startup with fallback shop dependency")
	_write(profile_path, '{"version":1,"shop":"tea"}')
	scene.retry_startup()
	scene.set_process(false)
	suite.check(not scene._startup_blocked and scene.rules != null, "production retry starts after backup selects another shop")
	suite.check_eq(scene.save_status, "自动存档已开启", "successful repaired-profile retry clears stale failure status")
	if scene.rules != null:
		suite.check(scene.rules.shop == TEA and scene.session.profile == damaged_profile, "production retry uses repaired profile and selected shop")
		suite.check(scene.store.path == tea_store.path and scene.store != original_store and scene.rules.gold == 4321.0, "production retry reassembles store and restores selected shop bytes")
		suite.check(not scene.has_node("Overlay/ProgressRetry"), "successful repaired-profile retry removes blocker")
	scene._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	scene.free()
	suite.check_eq(FileAccess.get_file_as_bytes(pancake_store.path), unrelated_bytes, "repaired production retry and exit preserve unrelated shop bytes")
	app.profile = original_profile
	# Explicit callers retain responsibility for dependency identity; retry must not replace a fault store.
	_write(profile_path, '{"version":99,"shop":"tea"}')
	var explicit_profile := Profile.new(profile_path)
	var fault_store := preload("res://tests/test_profile_safety.gd").FailingStore.new(PANCAKE, prefix + "-repair-explicit.json")
	fault_store.fail_write = true
	scene = _open(TestSession.make(PANCAKE, prefix + "-repair-explicit", null, fault_store, explicit_profile))
	_write(profile_path, '{"version":1,"shop":"tea"}')
	scene.retry_startup()
	suite.check(scene._startup_blocked and scene.rules == null and scene.session.store == fault_store, "explicit repaired mismatch stays blocked and retains injected fault store")
	scene.free()

func _restore_defaults() -> void:
	for path in originals:
		if originals[path] == null:
			if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
		else:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(originals[path])
			file.close()
	originals.clear()
