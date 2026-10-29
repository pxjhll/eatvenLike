extends SceneTree
## Real-renderer QA; no player session or save is opened by this preview.

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var preview: Node2D = load("res://presentation/reference/art_preview.tscn").instantiate()
	root.add_child(preview)
	root.size = Vector2i(720, 1280)
	await _capture("reference-shop")
	for layer in ["walls", "furniture", "belts", "equipment", "actors", "drinks"]:
		preview.set_layer_visible(false, layer)
	await _capture("reference-floor-only")
	preview.set_layer_visible(true, "walls")
	preview.set_probe_position(Vector2(160, 805))
	await _capture("reference-behind-wall")
	preview.set_probe_position(Vector2(160, 925))
	await _capture("reference-in-front-of-wall")
	preview.set_probe_position(Vector2(360, 805))
	await _capture("reference-doorway")
	preview.set_occlusion_probe(false)
	for layer in ["furniture", "belts", "equipment", "actors", "drinks"]:
		preview.set_layer_visible(true, layer)
	root.size = Vector2i(360, 640)
	await _capture("reference-small")
	root.size = Vector2i(1280, 720)
	await _capture("reference-landscape")
	preview.free()
	await _capture_assets()
	await _capture_comparison()
	await _verify_game_entry()
	print("REFERENCE RENDER: portrait, small, landscape, floor isolation and wall/door occlusion captured")
	print("REFERENCE INPUT: %d failures" % _failures)
	quit(1 if _failures else 0)


func _capture_assets() -> void:
	root.size = Vector2i(720, 1280)
	var gallery := Node2D.new()
	root.add_child(gallery)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://art_src/reference/manifest.json"))
	var index := 0
	for id in manifest.assets:
		var cell := Vector2((index % 4) * 180, (index / 4) * 154)
		var sprite := Sprite2D.new()
		sprite.texture = load("res://art/reference/" + id + ".png")
		var size := sprite.texture.get_size()
		sprite.scale = Vector2.ONE * minf(156.0 / size.x, 120.0 / size.y)
		sprite.position = cell + Vector2(90, 70)
		gallery.add_child(sprite)
		var label := Label.new()
		label.text = id
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color("583724"))
		label.position = cell + Vector2(8, 132)
		gallery.add_child(label)
		index += 1
	await _capture("reference-assets")
	gallery.free()


func _capture_comparison() -> void:
	root.size = Vector2i(1440, 1280)
	var comparison := Node2D.new()
	root.add_child(comparison)
	comparison.add_child(load("res://presentation/reference/shop_art.tscn").instantiate())
	var source := Sprite2D.new()
	source.texture = load("res://art/reference/reference.png")
	source.centered = false
	source.position.x = 720
	source.scale = Vector2(720, 1280) / source.texture.get_size()
	comparison.add_child(source)
	await _capture("reference-comparison")
	comparison.free()


func _verify_game_entry() -> void:
	root.size = Vector2i(720, 1280)
	var app: Node = root.get_node("App")
	var old_profile: Profile = app.profile
	var old_pending: Dictionary = app._pending_shop_state
	var old_path: String = app.save_service.path
	app.save_service.path = "user://reference-art-render-test.json"
	app.profile = Profile.create(app.catalog)
	app._pending_shop_state = {}
	change_scene_to_file("res://presentation/shop.tscn")
	await process_frame
	await process_frame
	var shop := current_scene
	shop.sim.paused = true
	shop.sim.submit(HireStaffCommand.new())
	shop.sim.step()
	var staff_id: String = shop.sim.workforce.staff[0].staff_id
	shop.sim.submit(AssignStaffCommand.new(staff_id, "counter"))
	shop.sim.step()
	await process_frame
	var before := JSON.stringify(shop.sim.to_dict(), "", false, true)
	var art_button: Button
	for child in shop.controls._root.get_children():
		if child is Button and child.text == "ART":
			art_button = child
	_check(art_button != null, "game exposes the art entry")
	if art_button != null:
		# Actual pointer input exercises the live UI and its signal connection.
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.position = art_button.get_global_rect().get_center()
		mouse.pressed = true
		Input.parse_input_event(mouse)
		await process_frame
		mouse = mouse.duplicate()
		mouse.pressed = false
		Input.parse_input_event(mouse)
		await process_frame
	_check(is_instance_valid(shop._art_preview), "clicking ART opens the preview")
	if is_instance_valid(shop._art_preview):
		_check(shop.sim.paused, "preview keeps production paused")
		_check(not shop.world.visible and not shop.controls.visible, "graybox is hidden")
		await _capture("reference-in-game")
		await _drag_over_hidden_worker(shop, staff_id)
		_check(JSON.stringify(shop.sim.to_dict(), "", false, true) == before, "preview does not change business state")
		var keyboard := InputEventKey.new()
		keyboard.keycode = KEY_ESCAPE
		keyboard.pressed = true
		Input.parse_input_event(keyboard)
		await process_frame
		_check(shop._art_preview == null, "Escape returns to the same game")
		_check(shop.sim.paused, "the previous paused state is restored")
		_check(shop.world.visible and shop.controls.visible, "graybox returns")
	shop.sim.paused = false
	shop.open_art_preview()
	shop._art_preview.close()
	_check(not shop.sim.paused, "a running game resumes when art is closed")
	_check(JSON.stringify(shop.sim.to_dict(), "", false, true) == before, "close and reopen preserve business state")
	app.sim = null
	app.profile = old_profile
	app._pending_shop_state = old_pending
	app.save_service.path = old_path
	if FileAccess.file_exists("user://reference-art-render-test.json"):
		DirAccess.remove_absolute("user://reference-art-render-test.json")
	current_scene.free()


func _drag_over_hidden_worker(shop: Node, staff_id: String) -> void:
	var pending_before: int = shop.sim._commands.size()
	var actor: Node2D = shop.world._staff[staff_id]
	var origin: Vector2 = shop.world.get_global_transform_with_canvas() * (actor.position + Vector2(0, -50))
	var destination: Vector2 = shop.world.get_global_transform_with_canvas() * Vector2(100, 1000)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = origin
	Input.parse_input_event(press)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = destination
	motion.relative = destination - origin
	Input.parse_input_event(motion)
	await process_frame
	press = press.duplicate()
	press.pressed = false
	press.position = destination
	Input.parse_input_event(press)
	await process_frame
	_check(shop.sim._commands.size() == pending_before, "dragging preview cannot queue commands for a hidden worker")
	_check(shop.world._held == "" and shop.world._dragged == "", "hidden gameplay cannot begin a drag")


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("REFERENCE INPUT: " + message)


func _capture(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var err := image.save_png("res://docs/qa/" + name + ".png")
	assert(err == OK, "capture must save successfully")
