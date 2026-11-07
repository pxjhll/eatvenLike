extends SceneTree
## 调参面板: the header button opens it, a slider changes the live sim, 还原 puts everything back.

var view: Node2D
var failures := 0
var errors := preload("res://tests/error_counter.gd").new()

func _initialize() -> void:
	Input.use_accumulated_input = false
	OS.add_logger(errors)
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(720, 1280)
	view = load("res://presentation/tea_playtest/tea_playtest.tscn").instantiate()
	view.sim = load("res://game/tea_playtest/tea_shop_sim.gd").new()
	root.add_child(view)
	await process_frame
	view.set_process(false)
	var panel: PanelContainer = view.tuning
	_check(panel != null and not panel.visible, "the tuning panel starts closed")
	_check(view.recorder != null and not view.recorder.enabled, "test scenes never write the playtest log")
	view.ui.open_page("menu")
	await process_frame
	await process_frame
	await _press(view.tuning_button.get_global_transform_with_canvas() * (view.tuning_button.size / 2.0))
	_check(panel.visible, "the header button opens the panel")
	var seat: float = view.sim.seat_seconds()
	panel.set_value("seat", 0.5)
	_check(is_equal_approx(view.sim.seat_seconds(), seat * 0.5), "halving dine-in time halves how long a customer sits")
	var interval: float = view.sim._order_interval()
	panel.set_value("customer", 2.0)
	_check(is_equal_approx(view.sim._order_interval(), interval * 2.0), "the customer knob stretches the arrival interval")
	panel.set_value("customer", 9.0)
	_check(is_equal_approx(view.sim.tuned("customer"), view.sim.TUNE_MAX), "knobs stop at their maximum")
	await _capture()
	await _press(panel.find_child("Reset", true, false).get_global_transform_with_canvas() * Vector2(40, 20))
	_check(is_equal_approx(view.sim.seat_seconds(), seat) and is_equal_approx(view.sim._order_interval(), interval), "还原 restores the designed numbers")
	await _press(panel.find_child("Close", true, false).get_global_transform_with_canvas() * Vector2(40, 20))
	_check(not panel.visible, "收起 closes the panel")
	await _check_recorder()
	for error in errors.take(): _check(false, "engine error: " + error)
	OS.remove_logger(errors)
	print("TUNING GUI: %d failures" % failures)
	view.free()
	quit(1 if failures > 0 else 0)

## A real-game recorder (pointed at a scratch file) logs minutes, purchases, knob moves and marks.
func _check_recorder() -> void:
	var recorder = view.recorder
	recorder.file_path = "user://playlog-test-%d.txt" % OS.get_process_id()
	recorder.enabled = true
	recorder.clear()
	view.sim.unlock_station("lemonade")
	view.sim.gold = 500
	for unused in 650:
		var before: float = view.sim.elapsed
		view.sim.advance(0.1)
		recorder.tick(view.sim.elapsed - before)
	view.station_action("upgrade", "lemonade")
	view.tuning.set_value("seat", 0.8)
	view.tuning._mark()
	var lines: PackedStringArray = recorder.text().strip_edges().split("\n")
	var kinds := {}
	for line in lines:
		var entry: Variant = JSON.parse_string(line)
		_check(entry is Dictionary, "every line is JSON: " + line)
		if entry is Dictionary:
			for key in ["session", "income", "buy", "set", "mark"]:
				if entry.has(key): kinds[key] = entry
	for key in ["session", "income", "buy", "set", "mark"]: _check(kinds.has(key), "the log has a %s line" % key)
	if kinds.has("buy"): _check(kinds.buy.cost > 0 and "lemonade" in kinds.buy.buy, "a purchase line names what was bought and its cost")
	if kinds.has("income"): _check(kinds.income.has("full") and kinds.income.has("levels"), "a minute line carries queue and level data")
	if OS.get_environment("SHOWLOG") != "": print(recorder.text())
	view.tuning.set_value("seat", 1.0)
	recorder.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(recorder.file_path))
	recorder.enabled = false


func _press(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	await process_frame

func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://docs/qa/tuning-panel.png") == OK, "capture saved")

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		print("FAIL: " + label)
