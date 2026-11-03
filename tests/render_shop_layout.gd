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
	_check(view.sim.unlock_station("lemonade").is_empty(), "unlock lemonade")
	view._toast_left = 0
	view._process(0)
	_check(not view._toast.visible, "front lemonade needs no kitchen employee")
	_check(view.sim.unlock_station("boil").is_empty(), "unlock first kitchen line")
	var pipe: Node2D = view.art.get_node_or_null("Sortables/MachineTable/ConnectorPipe")
	_check(pipe != null, "brewing and milk mixing have an independent rear connector pipe")
	view._refresh(0)
	if pipe != null: _check(not pipe.get_node("Sprite").is_visible_in_tree(), "connector pipe waits for the milk machine to open")
	view._process(0)
	_check(view._toast.visible, "unattended unlocked kitchen still shows staffing warning")
	view.sim.hire()
	_check(view.sim.deploy_worker(view.sim.roster[-1].id).is_empty(), "deploy hired kitchen employee")
	view._process(0)
	_check(not view._toast.visible, "hiring kitchen staff clears permanent staffing warning")
	for id in ["seal", "mix", "press", "topping"]:
		_check(view.sim.unlock_station(id).is_empty(), "unlock " + id)
	for box in view.sim.boxes:
		if not view.sim.boxes[box]: view.sim.unlock_box(box)
	while view.sim.seats < view.sim.seat_max():
		_check(view.sim.buy_seat().is_empty(), "buy visible dining seat")
	for unused in 3: view.sim.hire()
	view.sim.orders.clear()
	for i in 8:
		view.sim.orders.append({"id": 100 + i, "dish": "lemon_tea" if i % 2 else "plain_milk_tea", "wait": 0.0, "reserved": false, "takeaway": i % 2 == 0})
	view.sim.diners = [{"seat": 0, "dish": "lemonade", "left": 20.0}, {"seat": 3, "dish": "black_tea", "left": 20.0}, {"seat": 5, "dish": "lemon_tea", "left": 20.0}, {"seat": 6, "dish": "taro_milk_tea", "left": 20.0}]
	view._refresh(10.0)
	_check_props_on_supports()
	_check_front_counter_revision()
	_check_brewing_assembly()
	_check(view.art.get_node("Sortables/DiningArea").occupied_seats() == [0, 3, 5, 6], "four real diner records occupy their assigned chairs")
	await _world_click(Vector2(255, 685))
	_check(view.ui.page == "station" and view.ui.station_panel.station_id == "press", "clicking the front lemon tools opens the lemon tea panel")
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
	var dispenser := _opaque_rect(sorted.get_node("DisplayCase/Sprite"))
	_check(not sorted.has_node("LemonadeTable"), "lemonade dispenser has no extra support table")
	_check(dispenser.end.y >= counter.position.y and dispenser.end.y < counter.end.y, "lemonade machine rests on the connected front counter")
	_check(dispenser.size.x > 90 * view.get_node("Canvas").scale.x, "lemonade machine remains readable despite transparent canvas padding")
	_check(not _opaque_rect(sorted.get_node("PrepBench/Tongs/Sprite")).intersects(_opaque_rect(sorted.get_node("PrepBench/Tray/Sprite"))), "tongs remain visible beside the topping containers")

func _check_front_counter_revision() -> void:
	var sorted: Node2D = view.art.get_node("Sortables")
	for removed in ["PartitionLeft", "PartitionRight", "DoorLintel"]:
		_check(not sorted.has_node(removed), "middle partition is removed: " + removed)
	var ingredients: Node2D = sorted.get_node("IngredientTable")
	_check(not ingredients.has_node("PearlJar"), "only tea and milk remain on the ingredient table")
	var table := _opaque_rect(ingredients.get_node("Sprite"))
	var factor: float = view.get_node("Canvas").scale.x
	_check(table.size.y > 80 * factor, "ingredient table has substantial depth and apron")
	var tea := _opaque_rect(ingredients.get_node("TeaTin/Sprite"))
	var milk := _opaque_rect(ingredients.get_node("MilkBottle/Sprite"))
	_check(absf((tea.get_center().x + milk.get_center().x) / 2 - table.get_center().x) < 12 * factor, "tea and milk are centered together on the table")
	var ice := _opaque_rect(sorted.get_node("Checkout/FrontLemon/IceBin/Sprite"))
	var steel := _opaque_rect(sorted.get_node("Checkout/FrontLemon/SteelCup/Sprite"))
	_check(absf(ice.get_center().x - steel.get_center().x) < 8 * factor and ice.end.y > steel.end.y, "FigCraft places the ice bin in front of the muddling cup")
	var register := _opaque_rect(sorted.get_node("Checkout/Register/Sprite"))
	var holder := _opaque_rect(sorted.get_node("Checkout/RedDevice/Sprite"))
	_check(register.get_center().x < holder.get_center().x, "cash register is left of the red holder, matching the reference")
	var counter: Sprite2D = sorted.get_node("Checkout/Sprite")
	var picture := counter.texture.get_image()
	var bounds := picture.get_used_rect()
	var left_top := _first_solid_row(picture, bounds.position.x + bounds.size.x / 4)
	var right_top := _first_solid_row(picture, bounds.position.x + bounds.size.x * 3 / 4)
	_check(right_top - left_top > bounds.size.y * 0.18, "counter has a deep left worktop and recessed right bar")

func _first_solid_row(picture: Image, column: int) -> int:
	for y in picture.get_height():
		if picture.get_pixel(column, y).a > 0.5: return y
	return picture.get_height()

func _check_brewing_assembly() -> void:
	var assembly: Node2D = view.art.get_node("Sortables/MachineTable")
	var pipe := assembly.get_node_or_null("ConnectorPipe")
	_check(pipe != null, "the brewing assembly includes its separate connector")
	if pipe == null: return
	_check(pipe.get_node("Sprite").is_visible_in_tree() and pipe.get_index() < assembly.get_node("Brewer").get_index() and pipe.get_index() < assembly.get_node("PearlPot").get_index(), "pipe opens with the mixer and draws behind both machines")
	var factor: float = view.get_node("Canvas").scale.x
	var cabinet := _opaque_rect(assembly.get_node("Sprite"))
	_check(cabinet.size.y > 60 * factor, "powered cabinet has a substantial body, not a thin bench")
	for child in ["PearlPot", "Brewer"]:
		var machine := _opaque_rect(assembly.get_node(child + "/Sprite"))
		_check(machine.position.x >= cabinet.position.x and machine.end.x <= cabinet.end.x, "cabinet supports the full width of " + child)
		_check(machine.end.y >= cabinet.position.y and machine.end.y <= cabinet.position.y + cabinet.size.y * 0.65, "machine rests on the cabinet top: " + child)
	var connector := _opaque_rect(pipe.get_node("Sprite"))
	var pot := _opaque_rect(assembly.get_node("PearlPot/Sprite"))
	var mixer := _opaque_rect(assembly.get_node("Brewer/Sprite"))
	_check(connector.intersects(pot) and connector.intersects(mixer), "both pipe ends overlap the appliance silhouettes rather than floating")

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
