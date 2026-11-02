extends SceneTree
## Visual QA plus real input checks for the upper front counter and expanded dining floor.
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
	view.sim = preload("res://game/tea_playtest/tea_shop_sim.gd").new()
	root.add_child(view)
	await process_frame
	view.set_process(false)
	view._toast_left = 0
	view._process(0)
	_check(not view._toast.visible, "opening front-only shop has no permanent kitchen-staff warning")
	_check(not view.art.get_node("Sortables/Checkout/GlassPartition").visible, "glass begins hidden")
	await _capture("opening")
	view.sim.gold = 100000
	view.sim.revenue = 100000
	for id in ["lemonade", "lemon_front"]:
		_check(view.sim.unlock_station(id).is_empty(), "unlock " + id)
	view._toast_left = 0
	view._process(0)
	_check(not view._toast.visible, "front lemonade and hand muddling need no kitchen employee")
	_check(view.sim.unlock_station("boil").is_empty(), "unlock first kitchen line")
	view._process(0)
	_check(view._toast.visible, "unattended unlocked kitchen still shows staffing warning")
	view.sim.hire()
	_check(view.sim.deploy_worker(view.sim.roster[-1].id).is_empty(), "deploy hired kitchen employee")
	view._process(0)
	_check(not view._toast.visible, "hiring kitchen staff clears permanent staffing warning")
	for id in ["seal", "mix", "topping", "press"]:
		_check(view.sim.unlock_station(id).is_empty(), "unlock " + id)
	for box in view.sim.boxes:
		if not view.sim.boxes[box]: view.sim.unlock_box(box)
	while view.sim.seats < view.sim.seat_max():
		_check(view.sim.buy_seat().is_empty(), "buy visible dining seat")
	for unused in 3: view.sim.hire()
	view.sim.orders.clear()
	for i in 8:
		view.sim.orders.append({"id": 100 + i, "dish": "lemon_tea" if i % 2 else "plain_milk_tea", "wait": 0.0, "reserved": false, "takeaway": i % 2 == 0})
	view.sim.diners = [{"seat": 0, "dish": "lemonade", "left": 20.0}, {"seat": 3, "dish": "black_tea", "left": 20.0}, {"seat": 5, "dish": "lemon_tea", "left": 20.0}, {"seat": 6, "dish": "banana_tea", "left": 20.0}]
	view._refresh(10.0)
	_check_props_on_supports()
	_check(view.art.get_node("Sortables/DiningArea").occupied_seats() == [0, 3, 5, 6], "four real diner records occupy their assigned chairs")
	await _world_click(Vector2(335, 774))
	_check(view.ui.page == "station" and view.ui.station_panel.station_id == "lemon_front", "clicking the independent front workstation opens its own panel")
	view.ui.open_page("shop")
	view._refresh(0)
	for row in [["portrait", Vector2i(720, 1280)], ["small", Vector2i(360, 640)], ["wide", Vector2i(1280, 720)]]:
		root.size = row[1]
		await process_frame
		view._fit()
		await process_frame
		var canvas: Node2D = view.get_node("Canvas")
		var shop_left := canvas.global_position.x
		var shop_right := shop_left + 720 * canvas.scale.x
		for path in ["Header", "Navigation"]:
			var bounds: Rect2 = view.ui.get_node(path).get_global_rect()
			_check(bounds.position.x >= shop_left and bounds.end.x <= shop_right, "HUD follows shop width in " + row[0] + ": " + path)
			_check(bounds.position.y >= 0 and bounds.end.y <= view.get_viewport_rect().size.y, "HUD stays inside viewport height in " + row[0] + ": " + path)
		await _capture(row[0])
	root.size = Vector2i(720, 1280)
	await process_frame
	view._fit()
	# A second overview makes the independent furniture and tabletop props easy to inspect.
	view.sim.orders.clear()
	view.sim.diners.clear()
	view._refresh(0)
	for mark in view._upgrade_marks.values(): mark.visible = false
	view._staff_mark.visible = false
	view._toast.visible = false
	await _capture("overview")
	var before: Dictionary = view.sim.to_dict()
	view.ui.open_page("menu")
	await process_frame
	await _click(view._glass_button)
	_check(view.art.get_node("Sortables/Checkout/GlassPartition").visible, "menu toggle shows glass")
	_check(view.sim.to_dict() == before, "glass toggle has no simulation side effects")
	view.ui.open_page("shop")
	await _capture("glass")
	for message in errors.take(): _check(false, message)
	OS.remove_logger(errors)
	view.free()
	print("SHOP LAYOUT: %d failures" % failures)
	quit(1 if failures else 0)

func _world_click(point: Vector2) -> void:
	await _pointer(view.get_node("Canvas").get_global_transform_with_canvas() * point)

func _check_props_on_supports() -> void:
	var sorted: Node2D = view.art.get_node("Sortables")
	var counter := _opaque_rect(sorted.get_node("Checkout/Sprite"))
	for path in ["Checkout/FrontLemon/Muddler/Sprite", "Checkout/FrontLemon/IceBin/Sprite", "Checkout/FrontLemon/SteelCup/Sprite", "Checkout/FrontLemon/SmallCup/Sprite", "Checkout/RedDevice/Sprite", "Checkout/Register/Sprite"]:
		var base := _opaque_rect(sorted.get_node(path)).end.y
		_check(base >= counter.position.y and base < counter.end.y, "prop base rests on the opaque counter surface: " + path)
	var support := _opaque_rect(sorted.get_node("LemonadeTable/Sprite"))
	var dispenser := _opaque_rect(sorted.get_node("DisplayCase/Sprite"))
	_check(dispenser.end.y >= support.position.y and dispenser.end.y < support.end.y, "lemonade machine rests on its independent table")
	_check(dispenser.size.x > 90 * view.get_node("Canvas").scale.x, "lemonade machine remains readable despite transparent canvas padding")
	_check(not _opaque_rect(sorted.get_node("PrepBench/Tongs/Sprite")).intersects(_opaque_rect(sorted.get_node("PrepBench/Tray/Sprite"))), "tongs remain visible beside the topping containers")

func _opaque_rect(sprite: Sprite2D) -> Rect2:
	var used := Rect2(sprite.texture.get_image().get_used_rect())
	used.position += sprite.get_rect().position
	return sprite.get_global_transform() * used

func _click(button: Button) -> void:
	await process_frame
	await process_frame
	var scroll: ScrollContainer = view.ui.get_node("Sheet/Margin/Column/Scroll")
	scroll.ensure_control_visible(button)
	await process_frame
	await process_frame
	await _pointer(button.get_global_rect().get_center())

func _pointer(point: Vector2) -> void:
	var native_point := point * Vector2(root.size) / view.get_viewport_rect().size
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = native_point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame

func _capture(suffix: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://docs/qa/shop-layout-" + suffix + ".png") == OK, "save " + suffix)

func _check(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	push_error("SHOP LAYOUT: " + message)
