extends SceneTree
## The counter panel (seats + flyers) must open from the 堂食 chip, its red ↑, the counter and the dining room.
## godot --headless --path . -s tests/render_counter_tap.gd

var view: Node2D
var hud: Control
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(720, 1280)
	view = load("res://presentation/tea_playtest/tea_playtest.tscn").instantiate()
	view.sim = preload("res://game/tea_playtest/tea_shop_sim.gd").new()
	root.add_child(view)
	await process_frame
	hud = view.get_node("Overlay/UI/HUD")
	var sim = view.sim
	sim.gold = 99999
	_check(sim.unlock_station("lemonade") == "", "lemonade unlocks")
	sim.buy_seat()
	for k in 5: await process_frame
	var chip: Control = view._seats
	_check(chip.is_visible_in_tree(), "堂食 chip shows once lemonade is open")
	var canvas: Node2D = view.get_node("Canvas")
	var targets := {
		"chip": Rect2(chip.position, chip.size).get_center(),
		"red ↑ beside the chip": chip.position + Vector2(chip.size.x + 16, chip.size.y / 2.0),
		"counter top": Vector2(420, 800),
		"dining table": view.Layout.DINING_TABLES[0],
	}
	for name in targets:
		hud.open_page("shop")
		await process_frame
		var screen: Vector2 = canvas.get_global_transform_with_canvas() * targets[name] * Vector2(root.size) / view.get_viewport_rect().size
		await _tap(screen)
		_check(hud.page == "station" and hud.station_panel.station_id == "counter", "tapping the %s opens the counter panel" % name)
		_check(hud.station_panel.flyer_button.is_visible_in_tree(), "flyers are offered on the counter panel (%s)" % name)
	print("counter tap: %s" % ("ok" if failures == 0 else "%d failures" % failures))
	view.free()
	quit(1 if failures > 0 else 0)

func _tap(screen: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = screen
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("FAIL ", label)
