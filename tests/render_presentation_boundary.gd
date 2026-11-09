extends SceneTree
## Live production controls, disposable services and fatal runtime errors.
const Suite := preload("res://tests/test_presentation_boundary.gd")
const TestSession := preload("res://tests/shop_test_session.gd")
const PANCAKE: SpecShop = preload("res://content/shops/pancake/shop.tres")
var suite := Suite.new()
var errors := preload("res://tests/error_counter.gd").new()
var paths: Array[String] = []
var cases := 0
var checks := 0
var prefix := "user://boundary-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]

class SpySession extends "res://game/app/shop_session.gd":
	var commands: Array[Dictionary] = []
	func execute_command(command: String, arguments: Dictionary = {}) -> Dictionary:
		commands.append({"command": command, "arguments": arguments.duplicate(true)})
		return super.execute_command(command, arguments)

class CountingStore extends ShopSave:
	var writes := 0
	func save_game(rules: ShopRules, speed := 1.0, guides: Array = []) -> Error:
		writes += 1
		return super.save_game(rules, speed, guides)

class CountingView extends ShopView:
	var frames := 0
	var captured: Dictionary = {}
	func render_snapshot() -> Dictionary:
		frames += 1
		captured = super.render_snapshot()
		return captured

func _initialize() -> void:
	OS.add_logger(errors)
	call_deferred("_run")

func _open(spec: SpecShop, label: String, services := true) -> Node2D:
	var stem := prefix + label
	var original := TestSession.make(spec, stem, ShopRules.new(spec), CountingStore.new(spec, stem + "-shop.json"))
	var session := SpySession.new(original.profile, original.store, original.rules)
	session.tuning_path = original.tuning_path
	session.recording_path = original.recording_path
	session.persist_tuning = services
	session.recording_enabled = services
	for path in [session.profile.path, session.store.path, session.tuning_path, session.recording_path]: paths.append(path)
	if not services:
		var config_file := FileAccess.open(session.tuning_path, FileAccess.WRITE)
		config_file.store_string("[tune]\nwalk=2.75\n")
		config_file.close()
		var recording_file := FileAccess.open(session.recording_path, FileAccess.WRITE)
		recording_file.store_string("sentinel\n")
		recording_file.close()
	var scene: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	scene.session = session
	scene.change_scene_on_leave = false
	root.add_child(scene)
	# Freeze immediately before the first await or readback.
	scene.set_process(false)
	return scene

func _run() -> void:
	create_timer(25.0).timeout.connect(func() -> void: print("PRESENTATION BOUNDARY timed out"); quit(1))
	if not OS.get_user_data_dir().replace("\\", "/").split("/").has("session-lifecycle-userdata"):
		print("PRESENTATION BOUNDARY requires disposable userdata"); quit(1); return
	root.size = Vector2i(720, 1280)
	root.get_node("ShopAudio")._can_play = false
	for method in suite.get_method_list():
		if String(method.name).begins_with("test_"):
			cases += 1
			suite.call(method.name)
	var scene := _open(Suite.TEA, "-tea")
	await process_frame
	await _controls(scene)
	_config(scene)
	await _interactions(scene)
	_inactive(scene)
	scene.free()
	var single := _open(PANCAKE, "-single")
	await process_frame
	_single_marker_and_leave(single)
	single.free()
	var disabled := _open(Suite.TEA, "-disabled", false)
	await process_frame
	_disabled_services(disabled)
	disabled.free()
	await process_frame
	for path in paths:
		for file in DirAccess.get_files_at(path.get_base_dir()):
			if file == path.get_file() or file.begins_with(path.get_file() + "."):
				DirAccess.remove_absolute(path.get_base_dir().path_join(file))
	var runtime := errors.take()
	for error in runtime: suite.failures.append("runtime error: " + error)
	OS.remove_logger(errors)
	for failure in suite.failures: print("FAIL: " + failure)
	print("PRESENTATION BOUNDARY: %d cases, %d live checks, %d runtime errors, %d failures" % [cases, checks, runtime.size(), suite.failures.size()])
	quit(0 if suite.failures.is_empty() else 1)

func _check(condition: bool, label: String) -> void:
	checks += 1
	suite.check(condition, label)

func _bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()

func _last(scene: Node2D, command: String, arguments: Dictionary) -> void:
	_check(not scene.session.commands.is_empty(), command + " reaches the session")
	if scene.session.commands.is_empty(): return
	_check(scene.session.commands.back() == {"command": command, "arguments": arguments}, command + " forwards exact arguments")

func _click(scene: Node2D, button: Control) -> void:
	for unused in 4: await process_frame
	scene._refresh(0.0)
	var enabled: bool = button != null and button.is_visible_in_tree() and not (button is BaseButton and button.disabled)
	_check(enabled, "real input target is visible and enabled")
	if not enabled: return
	var point: Vector2 = button.get_global_transform_with_canvas() * (button.size / 2.0)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	scene._refresh(0.0)

func _controls(scene: Node2D) -> void:
	cases += 1
	var session: RefCounted = scene.session
	var menu: Control = scene.ui.page_node("menu")
	scene.ui.open_page("menu")
	var writes: int = scene.store.writes
	var count: int = session.commands.size()
	await _click(scene, menu.pause_button)
	_check(scene.rules.paused, "actual pause click changes state")
	_last(scene, "set_paused", {"paused": true})
	_check(scene.store.writes == writes, "pause retains existing deferred save timing")
	await _click(scene, menu.pause_button)
	_check(not scene.rules.paused, "actual resume click changes state")
	scene.tuning.set_value("walk", 1.137)
	_check(is_equal_approx(scene.rules.tuned("walk"), 1.15), "slider command snaps 1.137 to 1.15")
	_last(scene, "set_tuning", {"key": "walk", "value": 1.137, "snap": true})
	_check(session.commands.size() == count + 3, "pause, resume and tuning use owner spy")
	var slider: HSlider = scene.tuning._sliders.walk
	_check(slider.min_value == 0.25 and slider.max_value == 3.0 and slider.step == 0.05, "real slider uses central bounds")
	var lines: int = scene.recorder.line_count()
	scene.tuning.set_value("walk", 1.15)
	_check(scene.recorder.line_count() == lines, "unchanged successful tuning does not log")
	scene.tuning.set_value("walk", 9.0)
	_check(scene.rules.tuned("walk") == 3.0, "high slider request clamps")
	scene.tuning.set_value("walk", -9.0)
	_check(scene.rules.tuned("walk") == 0.25, "low slider request clamps")
	scene.ui.open_page("shop")
	scene.tuning.toggle()
	await _click(scene, scene.tuning.find_child("Reset", true, false))
	for row in scene.tuning.rows: _check(scene.rules.tuned(row[0]) == 1.0, "reset uses owned command for " + row[0])
	scene.tuning.hide()
	_check(scene.store.writes == writes, "tuning config is separate from shop save")

func _config(scene: Node2D) -> void:
	cases += 1
	var config := ConfigFile.new()
	config.set_value("tune", "walk", 1.137)
	config.set_value("tune", "customer", true)
	config.set_value("tune", "work", "broken")
	config.set_value("tune", "price", INF)
	config.set_value("tune", "seat", 100.0)
	config.set_value("tune", "unknown_saved_key", 2.0)
	_check(config.save(scene.tuning.file_path) == OK, "seed independent config")
	var bytes := _bytes(scene.tuning.file_path)
	var log_bytes := _bytes(scene.recorder.file_path)
	var writes: int = scene.store.writes
	var commands: int = scene.session.commands.size()
	scene.tuning._load()
	_check(scene.rules.tuned("walk") == 1.137, "raw config load preserves unsnapped precision")
	_check(scene.rules.tuned("seat") == 3.0, "raw config still clamps")
	for key in ["customer", "work", "price"]: _check(scene.rules.tuned(key) == 1.0, "invalid config independently skipped: " + key)
	_check(_bytes(scene.tuning.file_path) == bytes, "load never rewrites ConfigFile")
	_check(_bytes(scene.recorder.file_path) == log_bytes, "load never logs tuning")
	_check(scene.store.writes == writes, "load never saves shop")
	var loaded := false
	for entry in scene.session.commands.slice(commands):
		if entry.arguments.get("key") == "walk": loaded = entry.command == "set_tuning" and entry.arguments.value == 1.137 and entry.arguments.snap == false
	_check(loaded, "config uses owner raw command")
	_reject(scene, func() -> void: scene.tuning.set_value("walk", NAN), "nonfinite UI write")
	_reject(scene, func() -> void: scene.tuning.set_value("unknown_saved_key", 1.2), "unknown UI key")
	scene.tuning.set_value("work", 1.3)
	var persisted := ConfigFile.new()
	_check(persisted.load(scene.tuning.file_path) == OK, "successful control writes real config")
	_check(persisted.get_value("tune", "walk") == 1.137 and persisted.get_value("tune", "work") == 1.3, "config roundtrip keeps other raw precision")

func _interactions(scene: Node2D) -> void:
	cases += 1
	var rules: ShopRules = scene.rules
	var counter := CountingView.new(rules)
	scene.view = counter
	var old: Array = scene.all_staff()
	rules.gold = 100000.0
	scene.ui.open_station("lemonade")
	await _click(scene, scene.ui.page_node("station").unlock_button)
	_last(scene, "unlock", {"id": "lemonade"})
	_check(rules.gold == 99990.0, "standard opening feedback retains exact debit")
	scene.station_action("unlock", "boil")
	scene.ui.open_page("staff")
	await _click(scene, scene.ui.page_node("staff").hire_button)
	_check(scene.all_staff().size() == old.size() + 1 and old.size() == 1, "hire gives fresh roster while old roster remains retained")
	_check(scene.staff_is_deployed(scene.selected_worker), "hired employee is deployed")
	var before := var_to_bytes(rules.to_dict())
	var fresh: Array = scene.all_staff()
	fresh.back().stats.walk = 9999
	fresh.back().job["probe"] = true
	_check(var_to_bytes(rules.to_dict()) == before, "real scene roster nested mutation cannot change state")
	var frames_before: int = counter.frames
	scene._refresh(0.0)
	_check(counter.frames == frames_before + 1, "one root refresh captures one render snapshot")
	var captured: Dictionary = counter.captured
	captured.workers[0].pos = Vector2(-900, -900)
	scene._refresh(0.0)
	_check(scene._actors[rules.workers[0].id].position == rules.workers[0].pos, "fresh refresh ignores caller-edited retained frame")
	var last: int = counter.frames
	scene._update_cups()
	scene._update_customers(0.0)
	_check(counter.frames == last + 2, "direct visual helpers independently capture fresh state")
	scene.ui.open_page("shop")
	var drag: Node2D = scene._drag
	var id: int = scene.selected_worker
	var screen := Vector2.INF
	for x in range(120, 1100, 40):
		for y in range(160, 1200, 40):
			var candidate: Vector2 = scene.get_node("Canvas").get_global_transform_with_canvas() * Vector2(x, y)
			var target: Dictionary = drag._drop_target(candidate)
			if target.get("kind") != "mobile": continue
			if rules.command_status("place_worker", {"id": id, "post": "", "point": target.point}).code != "ok": continue
			screen = candidate
			break
		if screen.is_finite(): break
	_check(screen.is_finite(), "real navigation and anchors provide mobile drop")
	if screen.is_finite():
		# Enter through the production input handler from a real deployed body.
		var body: Vector2 = scene.view.worker_snapshot(id).pos + Vector2(0, -60)
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = scene.get_node("Canvas").get_global_transform_with_canvas() * body
		drag._input(press)
		_check(drag.worker_id == id, "mouse press selects deployed body through fresh roster")
		var motion := InputEventMouseMotion.new()
		motion.position = screen
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		# Ensure the drag threshold is crossed even if the candidate is adjacent.
		if motion.position.distance_to(press.position) < 8: motion.position += Vector2(20, 0)
		drag._input(motion)
		_check(drag.dragging, "mouse motion starts production drag")
		var point: Vector2 = drag.target.point
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.position = motion.position
		release.pressed = false
		drag._input(release)
		_last(scene, "place_worker", {"id": id, "post": "", "point": point})
		_check(scene.view.worker_snapshot(id).pos == point, "placement fresh getter reflects drop")
	var retained: Dictionary = scene.view.render_snapshot()
	scene.execute_command("set_paused", {"paused": true})
	scene.restart()
	_check(not rules.paused and scene.all_staff().size() == 1, "restart resumes with fresh starting roster")
	_check(scene.rules.tuned("walk") == 1.137 and scene.rules.tuned("work") == 1.3, "restart retains tuning")
	_check(retained.roster.size() == 2 and scene.view.render_snapshot().roster.size() == 1, "retained frame differs from new restart frame")
	_check(scene.store.load_game().to_dict() == rules.to_dict(), "real save reload roundtrip keeps exact business state")

func _reject(scene: Node2D, action: Callable, label: String) -> void:
	var state := var_to_bytes(scene.rules.to_dict())
	var cfg := _bytes(scene.tuning.file_path)
	var log_bytes := _bytes(scene.recorder.file_path)
	var store: RefCounted = scene.session.store
	var writes: int = store.writes
	var save_bytes := _bytes(store.path)
	action.call()
	_check(var_to_bytes(scene.rules.to_dict()) == state, label + " preserves rules, RNG and events")
	_check(_bytes(scene.tuning.file_path) == cfg, label + " preserves config")
	_check(_bytes(scene.recorder.file_path) == log_bytes, label + " preserves log")
	_check(store.writes == writes and _bytes(store.path) == save_bytes, label + " never saves")

func _inactive(scene: Node2D) -> void:
	cases += 1
	scene.session.started = false
	_reject(scene, func() -> void: scene.ui.page_node("menu").pause_button.pressed.emit(), "inactive pause")
	_reject(scene, func() -> void: scene.tuning.set_value("walk", 2.0), "inactive tuning")
	_reject(scene, scene.tuning.reset_all, "inactive reset")
	_reject(scene, scene.tuning._load, "inactive config load")
	_reject(scene, func() -> void: scene.station_action("unlock", "lemonade"), "inactive business command")
	scene.session.started = true

func _single_marker_and_leave(scene: Node2D) -> void:
	cases += 1
	scene.rules.execute_command("unlock", {"id": "soy_milk"})
	scene.rules.workers.clear()
	scene.rules.run(35.0)
	_check(scene.rules.queue_size() > 0 and scene.rules.orders.is_empty(), "single mode fixture has real queue without handoff orders")
	scene.tuning._mark()
	var lines: PackedStringArray = scene.recorder.text().split("\n", false)
	var marker: Dictionary = JSON.parse_string(lines[-1])
	_check(int(marker.queue) == scene.rules.queue_size(), "single tuning marker records actual queue")
	_check(scene.tuning._now("customer") == "%.1f 秒一位" % scene.rules.customer_interval(), "customer caption uses actual single-mode public interval")
	# Restore a valid saved employee roster before actual leave/save.
	scene.rules.workers.assign(scene.rules.roster)
	scene.rules.completed_at = scene.rules.clock
	_check(scene.can_leave(), "completed pancake has actual next shop")
	scene.leave_shop()
	_check(scene.session.transition_committed and scene._transition_committed, "actual leave seals owner session")
	_reject(scene, func() -> void: scene.ui.page_node("menu").pause_button.pressed.emit(), "closed pause")
	_reject(scene, func() -> void: scene.tuning.set_value("walk", 2.0), "closed tuning")
	_reject(scene, scene.hire_worker, "closed hire")

func _disabled_services(scene: Node2D) -> void:
	cases += 1
	_check(scene.rules.tuned("walk") == 1.0, "disabled persistence skips existing config on startup")
	var config_before := _bytes(scene.tuning.file_path)
	scene.tuning.set_value("walk", 1.4)
	scene.recorder.tick(60.0)
	_check(is_equal_approx(scene.rules.tuned("walk"), 1.4), "disabled services still permit active business controls")
	_check(_bytes(scene.tuning.file_path) == config_before, "disabled tuning persistence preserves config")
	_check(FileAccess.get_file_as_string(scene.recorder.file_path) == "sentinel\n", "disabled recording preserves existing bytes")
	_check(scene.recorder.text().is_empty(), "disabled recorder hides existing records")
