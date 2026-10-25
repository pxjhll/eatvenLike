extends SceneTree
## PXJ-40 real renderer QA: xvfb-run -a godot --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/render_toast.gd
## Fresh QA profile, paused simulation and synthetic input: the slicer ghost, buying it, and the split line selling toast.


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
	# Before the threshold the slicer card names the revenue goal and cannot be bought.
	await _click(_center_of(shop, "slicer"))
	assert(shop.controls._selected == "slicer", "actual scene click selects the slicer ghost")
	assert(shop.controls._card_buttons[0].disabled, "slicer cannot be bought before the revenue threshold")
	await create_timer(0.3).timeout
	await _capture("res://docs/qa/pxj40-slicer-locked.png")
	await _click(Vector2(200, 600))
	while sim.economy.revenue < 600:
		sim.step()
	await _advance(sim, 1.0)
	await _click(_center_of(shop, "slicer"))
	assert(not shop.controls._card_buttons[0].disabled, "slicer can be bought once revenue reaches 600")
	await _click(_button_center(shop, 0))
	sim.step()
	assert(sim.progress.stage_index == 1, "card button buys the slicer and unlocks toast")
	await _click(Vector2(200, 600))
	await _advance(sim, 90.0)
	assert(int(sim.progress.sold.get("toast", 0)) > 0, "toast sells in the live scene")
	await _capture("res://docs/qa/pxj40-toast-line.png")
	print("TOAST QA: slicer ghost card, purchase, split line and toast sales passed")
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
