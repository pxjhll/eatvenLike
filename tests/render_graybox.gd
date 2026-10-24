extends SceneTree
## Real renderer QA: DISPLAY=localhost:100 godot --rendering-method gl_compatibility -s tests/render_graybox.gd
## Fresh QA profile, paused simulation and synthetic input. Never runs from the shipped scene.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var app: Node = root.get_node("App")
	app.profile = Profile.create(app.catalog)
	app._pending_shop_state = {}
	change_scene_to_file("res://presentation/shop.tscn")
	await process_frame
	var shop := current_scene
	var sim: GameSim = shop.sim
	sim.paused = true
	await _advance(sim, 30.0)
	await _capture("res://docs/qa/pxj26-initial.png")
	# Tap the oven: a card opens beside it and its button pays for the upgrade.
	await _click(_center_of(shop, "oven"))
	assert(shop.controls._selected == "oven", "actual scene click selects the oven")
	assert(shop.controls._card.visible, "selecting a station opens its card")
	var gold := sim.economy.gold
	await _click(_button_center(shop, 0))
	sim.step()
	assert(sim.production.to_dict().stations[2].level == 2, "card button upgrades the oven")
	assert(sim.economy.gold <= gold - 40, "upgrade is paid by the existing economy")
	await _capture("res://docs/qa/pxj26-whitebread.png")
	await _advance(sim, 100.0)
	await _click(Vector2(200, 600))
	assert(not shop.controls._card.visible, "tapping empty floor closes the card")
	await _click(_center_of(shop, "oven_b"))
	assert(shop.controls._selected == "oven_b", "actual click selects the parallel ghost")
	await _click(_button_center(shop, 0))
	sim.step()
	assert(sim.production.to_dict().stations[3].status == StationState.Status.ACTIVE, "card button enables parallel slot")
	await _click(Vector2(200, 600))
	# Drag the rabbit from the front hall into the kitchen.
	var rabbit: Node2D = shop.world._staff["rabbit"]
	await _drag(rabbit.position + Vector2(0, -40), Vector2(300, 600))
	await _advance(sim, 4.0)
	for staff in sim.workforce.staff:
		if staff.staff_id == "rabbit":
			assert(staff.zone == "kitchen", "dragging a worker submits the assignment")
	# Releasing a drag over a GUI button must still end the drag.
	var bear: Node2D = shop.world._staff["bear"]
	await _drag(bear.position + Vector2(0, -40), Vector2(615, 55), false)
	assert(shop.world._dragged == "" and not bear.dragging, "a release over a button still ends the drag")
	# Sending a worker away and dropping them back cancels the pending transfer.
	sim.submit(AssignStaffCommand.new("bear", "front"))
	sim.step()
	await create_timer(1.5).timeout
	await _drag(bear.position + Vector2(0, -40), Vector2(200, 600), false)
	sim.step()
	for staff in sim.workforce.staff:
		if staff.staff_id == "bear":
			assert(staff.target_zone == "", "dropping back on the current zone cancels the transfer")
	print("GRAYBOX INPUT QA: card upgrade, parallel activation, drag assignment, drag over GUI, cancel transfer passed")
	await _advance(sim, 20.0)
	await _capture("res://docs/qa/pxj26-parallel.png")
	await _click(_center_of(shop, "dough_table"))
	await create_timer(0.3).timeout
	await _capture("res://docs/qa/pxj26-card.png")
	await _click(Vector2(200, 600))
	root.size = Vector2i(1280, 720)
	await create_timer(0.5).timeout
	assert(is_equal_approx(shop.world.position.x, (root.get_visible_rect().size.x - 720) / 2.0), "landscape world remains centered")
	await _capture("res://docs/qa/pxj26-landscape.png")
	root.size = Vector2i(540, 960)
	await create_timer(0.5).timeout
	await _capture("res://docs/qa/pxj26-small.png")
	root.size = Vector2i(720, 1280)
	var before := sim.to_dict()
	shop.world.unbind()
	shop.world.bind(sim)
	assert(sim.to_dict() == before, "reopening view does not change business state")
	change_scene_to_file("res://presentation/graybox/asset_gallery.tscn")
	for i in 30:
		await process_frame
	await _capture("res://docs/qa/pxj26-assets.png")
	quit()


## Advances the paused simulation in real frames so view animation can follow.
func _advance(sim: GameSim, seconds: float) -> void:
	var steps := int(seconds / sim.step_seconds)
	for i in steps:
		sim.step()
		if i % 4 == 0:
			await process_frame
	await create_timer(0.6).timeout


func _center_of(shop: Node, slot_id: String) -> Vector2:
	return shop.world.station_anchor(slot_id).get_center()


func _button_center(shop: Node, index: int) -> Vector2:
	var button: Button = shop.controls._card_buttons[index]
	return button.get_global_rect().get_center()


func _click(at: Vector2) -> void:
	_move(at)
	for pressed in [true, false]:
		_press(at, pressed)
		await process_frame


func _drag(from: Vector2, to: Vector2, capture: bool = true) -> void:
	_move(from)
	_press(from, true)
	await process_frame
	for i in range(1, 11):
		_move(from.lerp(to, i / 10.0))
		await process_frame
	await create_timer(0.2).timeout
	if capture:
		await _capture("res://docs/qa/pxj26-drag.png")
	_press(to, false)
	await process_frame


func _move(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(motion)


func _press(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	Input.parse_input_event(event)


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var image := root.get_texture().get_image()
	assert(image.save_png(path) == OK, "screenshot is saved")
	print("CAPTURE: ", path, " ", image.get_size())
