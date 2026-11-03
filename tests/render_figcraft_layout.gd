extends SceneTree
## Coordinates and grouped progression must agree with the user's edited FigCraft document.
var failures := 0
var view: Node2D
var errors := preload("res://tests/error_counter.gd").new()
var fixture: Dictionary

func _initialize() -> void:
	Input.use_accumulated_input = false
	OS.add_logger(errors)
	call_deferred("_run")

func _run() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string("res://art_src/figcraft_layout_2026_11_03/placement.json"))
	root.size = Vector2i(720, 1280)
	view = load("res://presentation/tea_playtest/tea_playtest.tscn").instantiate()
	view.sim = preload("res://game/tea_playtest/tea_shop_sim.gd").new()
	root.add_child(view)
	await process_frame
	view.set_process(false)
	view._refresh(0)
	_check_geometry()
	_check_groups("opening")
	view._toast.visible = false
	await _capture("figcraft-opening")
	view.sim.gold = 100000
	for station in ["lemonade", "boil", "seal", "mix", "press"]:
		_check(view.sim.unlock_station(station).is_empty(), "unlock " + station)
		view._refresh(0)
		_check_groups(station)
		if station == "boil":
			_check(view.sim.unlock_box("tea_leaf").is_empty(), "buy first ingredient box")
			view._refresh(0)
			_check_groups("ingredient_box")
		if station == "mix":
			_check(view.sim.buy_belt("seal_to_shelf").is_empty(), "buy the sealer conveyor")
			view._refresh(0)
			_check_groups("belt")
	_check(view._station_buttons.has("topping"), "the final topping stage has an in-world entry")
	if view._station_buttons.has("topping"):
		_check(view._station_buttons.topping.is_visible_in_tree(), "final stage offers its unlock")
		view.guide.enabled = true
		view.guide.active = "line_5"
		view.guide.refresh(0)
		_check(view.guide.freezes(), "final-stage guidance can focus its entry")
		await _click(view._station_buttons.topping)
		_check(view.ui.page == "station" and view.ui.station_panel.station_id == "topping", "final stage opens through the actual UI")
		await _click(view.ui.station_panel.unlock_button)
		_check(view.sim.station_unlocked("topping") and view.sim.stage_index == 5, "final stage unlocks through the actual UI")
		view.guide.enabled = false
	view.ui.open_page("shop")
	view._refresh(0)
	view._toast.visible = false
	await _capture("figcraft-fully-unlocked")
	view.sim.reset_shop()
	view._refresh(0)
	_check_groups("reset")
	view.free()
	root.size = Vector2i(720, 1500)
	var art: Node2D = load("res://presentation/reference/shop_art.tscn").instantiate()
	root.add_child(art)
	await process_frame
	for node in art.find_children("*", "Node2D", true, false):
		if node.get_meta("art_layer", "") in ["actors", "drinks"]: node.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://docs/qa/figcraft-restored-layout.png") == OK, "save full artwork")
	art.free()
	for message in errors.take(): _check(false, message)
	OS.remove_logger(errors)
	print("FIGCRAFT LAYOUT: %d failures" % failures)
	quit(1 if failures else 0)

func _check_geometry() -> void:
	for row in fixture.sprites:
		var sprite: Sprite2D = view.art.get_node_or_null(row.node)
		_check(sprite != null, "preserve independent image " + row.node)
		if sprite == null: continue
		_check(sprite.texture != null and sprite.texture.resource_path == row.texture, "source texture " + row.node)
		var basis: Transform2D = view.art.global_transform.affine_inverse() * sprite.global_transform
		var actual := basis * sprite.get_rect().position
		var expected := Vector2(row.transform[4], row.transform[5])
		_check(actual.distance_to(expected) < 0.02, "FigCraft origin " + row.node + ": " + str(actual) + " expected " + str(expected))
		var across := basis.basis_xform(Vector2(sprite.get_rect().size.x, 0))
		var down := basis.basis_xform(Vector2(0, sprite.get_rect().size.y))
		_check(across.distance_to(Vector2(row.width, 0)) < 0.02 and down.distance_to(Vector2(0, row.height)) < 0.02, "FigCraft size " + row.node)
		_check(sprite.get_meta("layout_group", "") == row.group, "FigCraft unlock group " + row.node)
	_check(not view.art.get_node("Sortables/BeltHorizontal").is_visible_in_tree(), "deleted horizontal conveyor remains absent")
	var cup: Node2D = view.art.get_node("Sortables/Checkout/FrontLemon/SteelCup")
	var ice: Node2D = view.art.get_node("Sortables/Checkout/FrontLemon/IceBin")
	_check(cup.get_index() < ice.get_index(), "muddling cup draws behind the foreground ice bin")
	var arrow: CanvasItem = view.art.get_node_or_null("Sortables/BeltVertical/Direction")
	_check(arrow != null, "the downward arrow is an independent conveyor part")

func _check_groups(phase: String) -> void:
	for row in fixture.sprites:
		var sprite: Sprite2D = view.art.get_node_or_null(row.node)
		if sprite == null: continue
		var rule: String = fixture.rules[row.group]
		var expected := rule == "always"
		if rule == "ingredient_box": expected = view.sim.boxes.values().has(true)
		elif rule.begins_with("belt:"): expected = view.sim.belts.has(rule.trim_prefix("belt:"))
		elif rule != "always": expected = view.sim.station_unlocked(rule)
		_check(sprite.is_visible_in_tree() == expected, phase + ": grouped visibility " + row.group + "/" + row.node)
	var arrow: CanvasItem = view.art.get_node_or_null("Sortables/BeltVertical/Direction")
	if arrow != null: _check(arrow.is_visible_in_tree() == view.sim.belts.has("seal_to_shelf"), phase + ": arrow shows with the bought conveyor")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FIGCRAFT LAYOUT: " + message)

func _capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://docs/qa/" + name + ".png") == OK, "save " + name)

func _click(button: Button) -> void:
	await process_frame
	await process_frame
	var scroll: ScrollContainer = view.ui.get_node("Sheet/Margin/Column/Scroll")
	if scroll.is_ancestor_of(button): scroll.ensure_control_visible(button)
	await process_frame
	if view.guide.enabled: view.guide.refresh(0)
	var point := button.get_global_rect().get_center() * Vector2(root.size) / view.get_viewport_rect().size
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await process_frame
	if view.guide.enabled: view.guide.refresh(0)
