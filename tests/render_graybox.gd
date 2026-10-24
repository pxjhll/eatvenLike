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
	sim.run_seconds(30.0)
	await create_timer(2.0).timeout
	await _capture("res://docs/qa/pxj26-initial.png")
	await _click(Vector2(486, 300))
	assert(shop.controls._selected == "oven", "actual scene click selects the oven")
	var gold := sim.economy.gold
	await _click(Vector2(570, 1160))
	sim.step()
	assert(sim.production.to_dict().stations[2].level == 2, "actual button upgrades the oven")
	assert(sim.economy.gold <= gold - 40, "upgrade is paid by the existing economy")
	await _capture("res://docs/qa/pxj26-whitebread.png")
	sim.run_seconds(100.0)
	await _click(Vector2(486, 470))
	assert(shop.controls._selected == "oven_b", "actual click selects the parallel ghost")
	await _click(Vector2(570, 1160))
	sim.step()
	assert(sim.production.to_dict().stations[3].status == StationState.Status.ACTIVE, "actual button enables parallel slot")
	await _click(Vector2(270, 150))
	sim.run_seconds(4.0)
	for staff in sim.workforce.staff:
		if staff.staff_id == "rabbit":
			assert(staff.zone == "kitchen", "staff control submits assignment")
	print("GRAYBOX INPUT QA: oven selection + upgrade, parallel activation, staff assignment passed")
	await create_timer(1.5).timeout
	await _capture("res://docs/qa/pxj26-parallel.png")
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


func _click(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		Input.parse_input_event(event)
		await process_frame


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var image := root.get_texture().get_image()
	assert(image.save_png(path) == OK, "screenshot is saved")
	print("CAPTURE: ", path, " ", image.get_size())
