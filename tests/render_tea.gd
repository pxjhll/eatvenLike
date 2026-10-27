extends SceneTree
## Real portrait renderer/input QA:
## xvfb-run -a godot --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/render_tea.gd
## Fresh profile, paused simulation and synthetic input. PXJ-46: empty shop, price plates, hiring, dragging a
## card onto the counter. PXJ-47: the milk tea stage opens by itself, layout mode, dragging a device from the
## device bar, one-click deploy, confirm, a cook on the milk station, milk tea sold.

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("TEA INPUT: " + message)


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
	sim.command_rejected.connect(func(c: SimCommand, reason: String) -> void: print("REJECTED ", c.get_script().resource_path.get_file(), " ", reason))
	_check(sim.config.id == "tea", "fresh scene opens tea")
	_check(sim.workforce.staff.is_empty(), "the shop opens empty, with nobody in it")
	_check(not shop.controls._layout_button.visible, "no layout button before the kitchen opens")
	await _advance(sim, 10.0)
	await _capture("res://docs/qa/pxj47-empty-shop.png")

	# 价格牌：点一下柠檬水台，卡片上是它的价格，再点按钮就摆上
	await _click(_center_of(shop, "lemonade_stand"))
	_check(shop.controls._selected == "lemonade_stand", "the locked stand can actually be tapped")
	await _click(_button_center(shop, 0))
	sim.step()
	_check(sim.front_hall.is_active("lemonade_stand"), "the card button really opens the stand")
	await _click(_center_of(shop, "counter"))
	await _click(_button_center(shop, 0))
	sim.step()
	_check(sim.front_hall.is_active("counter"), "and the counter after it")
	await _click(Vector2(60, 600))

	# 员工栏：招一个人，把卡片拖到柜台上岗
	var hire: Button = shop.controls._hire
	await _click(hire.get_global_rect().get_center())
	sim.step()
	await process_frame
	_check(shop.controls._staff_cards.size() == 1, "the new hire shows up in the staff bar")
	await _drag(shop.controls._staff_cards[0].get_global_rect().get_center(), _center_of(shop, "counter"))
	sim.step()
	_check(sim.workforce.staff[0].post == "counter", "dragging the card onto the counter puts them on post")
	await _advance(sim, 40.0)
	_check(int(sim.progress.sold.get("lemonade", 0)) > 0, "the server pours and sells lemonade in the live scene")

	# 营业额到门槛：奶茶自动开放，出现「布局模式」按钮
	while not sim.progress.kitchen_open() or sim.economy.gold < 275:
		sim.step()
	await _advance(sim, 1.0)
	_check(shop.controls._layout_button.visible, "the layout button appears once milk tea opens")
	await _capture("res://docs/qa/pxj47-kitchen-open.png")
	await _click(shop.controls._layout_button.get_global_rect().get_center())
	sim.step()
	await process_frame
	_check(sim.mode == GameSim.Mode.LAYOUT, "the button enters layout mode")
	var tick := sim.tick
	await _advance(sim, 3.0)
	_check(sim.tick == tick, "time is frozen in layout mode")
	_check(shop.controls._device_cards.size() == 4, "the device bar lists the four open kitchen devices")
	await _capture("res://docs/qa/pxj47-layout-ghosts.png")

	# 从设备栏把原料柜拖到它的推荐位
	var rec: Dictionary = sim.config.grid.recommended[0]
	var def := sim.config.device_def(String(rec.station))
	var layout: Script = load("res://presentation/graybox/layout.gd")
	var target: Vector2 = shop.world.to_screen(layout.device_rect(def, rec.cell).get_center())
	await _drag(shop.controls._device_cards[0].get_global_rect().get_center(), target)
	sim.step()
	await process_frame
	_check(sim.layout.draft.devices.size() == 1, "dragging a device card places it in the draft")
	if not sim.layout.draft.devices.is_empty():
		_check(sim.layout.draft.devices[0].cell == rec.cell, "the cabinet lands on the cell under the finger")
	await _click(shop.controls._deploy.get_global_rect().get_center())
	sim.step()
	await process_frame
	_check(sim.layout.draft.devices.size() == 4, "one-click deploy fills the other recommended spots")
	_check(not shop.controls._confirm.disabled, "the confirm button is enabled with enough gold")
	await create_timer(0.3).timeout
	await _capture("res://docs/qa/pxj47-layout-draft.png")
	var gold := sim.economy.gold
	await _click(shop.controls._confirm.get_global_rect().get_center())
	sim.step()
	await process_frame
	_check(sim.mode == GameSim.Mode.BUSINESS, "confirm returns to business mode")
	_check(gold - sim.economy.gold >= 250, "confirm charges the four devices")
	_check(sim.production.segments.size() == 5, "five belts are laid")

	# 招第二个人，拖到调奶台的工位格上
	await _click(hire.get_global_rect().get_center())
	sim.step()
	await process_frame
	var milk := ""
	for d in sim.layout.devices:
		if d.def == "milk_station":
			milk = d.id
			var mdef := sim.config.device_def("milk_station")
			await _drag(shop.controls._staff_cards[0].get_global_rect().get_center(), shop.world.to_screen(layout.cell_rect(d.cell + mdef.work_cell).get_center()))
	sim.step()
	var cook_posted := false
	for s in sim.workforce.staff:
		cook_posted = cook_posted or s.post == milk
	_check(cook_posted, "dragging the card onto the milk station's work cell posts the cook")
	await _advance(sim, 90.0)
	_check(int(sim.progress.sold.get("pearl_milk_tea", 0)) > 0, "milk tea sells in the live scene")
	await _capture("res://docs/qa/pxj47-milk-tea.png")

	# 点后厨设备出升级卡片
	await _click(_center_of(shop, milk))
	_check(shop.controls._selected == milk, "a kitchen device can be tapped for its card")
	await _capture("res://docs/qa/pxj47-device-card.png")
	await _click(Vector2(60, 1100))

	var saved := sim.to_dict()
	var restored := GameSim.new()
	restored.setup(sim.config, app.roster_defs())
	restored.load_dict(saved)
	_check(restored.to_dict() == saved, "live scene state restores exactly")
	restored.free()
	root.size = Vector2i(540, 960)
	await create_timer(0.5).timeout
	await _capture("res://docs/qa/pxj47-small.png")
	print("TEA INPUT QA failures=", _failures)
	quit(1 if _failures > 0 else 0)


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


func _drag(from: Vector2, to: Vector2) -> void:
	_move(from)
	_press(from, true)
	await process_frame
	for i in range(1, 11):
		_move(from.lerp(to, i / 10.0))
		await process_frame
	await create_timer(0.2).timeout
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
	_check(image.save_png(path) == OK, "screenshot is saved")
	print("CAPTURE: ", path, " ", image.get_size())
