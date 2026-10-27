extends "res://tests/test_case.gd"
## Presentation may derive symptoms, but never change the simulation or snapshot.


func test_station_visual_state_uses_actual_mode_and_phase() -> void:
	var script: Script = load("res://presentation/graybox/view_state.gd")
	check(script != null, "graybox state adapter exists")
	if script == null:
		return
	var def: StationDef = load(TEA).device_def("milk_station")
	var row := {"status": StationState.Status.ACTIVE, "phase": StationState.Phase.WAIT_WORK, "inputs": {}, "outputs": {}, "progress": 0.0}
	check_eq(script.station(row, def).kind, "staff", "a manual cup waits for staff")
	row.staff_working = true
	check_eq(script.station(row, def).kind, "working", "a claimed request shows active work, not missing staff")
	row.staff_working = false
	row.phase = StationState.Phase.IDLE
	check_eq(script.station(row, def).kind, "input", "empty input waits for material")
	row.outputs = {"milk_tea": def.output_capacity}
	check_eq(script.station(row, def).kind, "blocked", "a full output buffer shows blocked")
	row.status = StationState.Status.LOCKED
	check_eq(script.station(row, def).kind, "locked", "a locked spot never looks productive")


func test_buffer_visuals_preserve_input_and_output_identities() -> void:
	var script: Script = load("res://presentation/graybox/view_state.gd")
	var row := {"inputs": {"dough": 2}, "outputs": {"bread": 1}}
	var before := JSON.stringify(row)
	var stacks: Array = script.buffers(row)
	check_eq(stacks, [{"item": "dough", "count": 2, "side": "input"}, {"item": "bread", "count": 1, "side": "output"}], "two dough inputs and one bread output remain distinct")
	check_eq(JSON.stringify(row), before, "deriving draw data cannot mutate the snapshot")


func test_graybox_rebind_and_detach_do_not_change_simulation() -> void:
	var script: Script = load("res://presentation/graybox/shop_view.gd")
	check(script != null, "graybox scene adapter exists")
	if script == null:
		return
	var sim := running_tea()
	sim.run_seconds(20.0)
	var before := state_json(sim)
	var snap_before := JSON.stringify(sim.last_snapshot)
	var view: Node = script.new()
	view.bind(sim)
	view.bind(sim)
	check_eq(sim.tick_finished.get_connections().size(), 1, "binding twice keeps one subscription")
	check_eq(state_json(sim), before, "binding a view cannot change business state")
	check_eq(JSON.stringify(sim.last_snapshot), snap_before, "binding cannot mutate its snapshot")
	view.unbind()
	check_eq(sim.tick_finished.get_connections().size(), 0, "detaching disconnects the view")
	view.free()
	sim.run_seconds(20.0)
	check(sim.economy.revenue > 0, "simulation continues without a view")


func test_service_reaches_pickup_before_carrying_and_customer_before_sale() -> void:
	for upgrades in [0, 1, 2]:
		var sim := make_sim(kitchen_copy())
		var server := open_front(sim)
		for i in upgrades:
			sim.submit(UpgradeStationCommand.new("lemonade_stand"))
			sim.step()
		var view: Node = load("res://presentation/graybox/shop_view.gd").new()
		view.bind(sim)
		var actor: Node2D = view._staff[server]
		var layout: Script = load("res://presentation/graybox/layout.gd")
		var pickup: Vector2 = layout.work_spot(view._positions["lemonade_stand"])
		var picked_up := false
		var delivered := false
		var last_target := Vector2.ZERO
		for i in 600:
			var revenue := sim.economy.revenue
			var before_move := actor.position
			sim.step()
			if not actor.carry_item.is_empty() and not picked_up:
				check(before_move.distance_to(pickup) < 3.0, "normal animation reaches pickup without relying on phase-boundary reconciliation")
				check(actor.position.distance_to(pickup) < 3.0, "a drink appears only after the server reaches the stand")
				picked_up = true
			if sim.economy.revenue > revenue:
				check(before_move.distance_to(last_target) < 3.0, "normal animation reaches the customer before the completion snapshot")
				check(actor.position.distance_to(last_target) < 3.0, "the server reaches the customer's place before the sale leaves the view")
				delivered = true
				break
			if not actor.carry_item.is_empty():
				last_target = actor.target
			for a in view._staff.values():
				a._process(0.1)
		check(picked_up and delivered, "a complete service was observed, including upgraded stand timing")
		view.unbind()
		view.free()


func test_ui_font_covers_staff_bar_and_drag_hint() -> void:
	var font: Font = load("res://art/ui/graybox_font.ttf")
	# 员工栏、招人、上岗、拖动：阶段 1 新加的界面文案
	for code in [0x62D6, 0x62DB, 0x680F, 0x5C97]:
		check(font.has_char(code), "bundled font covers new UI character " + String.chr(code))


func test_save_button_reports_real_write_failure_and_success() -> void:
	var app: Node = Engine.get_main_loop().root.get_node("App")
	var old_profile: Profile = app.profile
	var old_sim: GameSim = app.sim
	var old_path: String = app.save_service.path
	var sim := make_sim()
	app.profile = Profile.create(load(CATALOG))
	app.sim = sim
	var view: Node = load("res://presentation/graybox/shop_view.gd").new()
	view.bind(sim)
	var ui: Node = load("res://presentation/graybox/shop_ui.gd").new()
	var debug := CanvasLayer.new()
	ui.bind(sim, view, debug)
	var save: Button
	for child in ui._root.get_children():
		if child is Button and child.tooltip_text == "保存进度":
			save = child
	app.save_service.path = "user://missing-pr5-test-directory/save.json"
	save.pressed.emit()
	check(not FileAccess.file_exists(app.save_service.path), "the failure case did not write a save")
	check(ui._toast.text.contains("失败"), "the user sees failure when the write fails")
	app.save_service.path = "user://pr5-save-ui-test.json"
	save.pressed.emit()
	check(FileAccess.file_exists(app.save_service.path), "success feedback corresponds to a real file")
	check_eq(ui._toast.text, "已保存", "successful save feedback remains available")
	DirAccess.remove_absolute(app.save_service.path)
	ui.free()
	view.free()
	debug.free()
	app.profile = old_profile
	app.sim = old_sim
	app.save_service.path = old_path


# 奶茶从传菜窗口取：服务员先走到货架下面的窗口，再端给自己的顾客。
func test_front_service_fetches_from_window_then_serves_its_customer() -> void:
	var cfg := kitchen_copy()
	cfg.progression.stages[1].order_weights = {"pearl_milk_tea": 1.0}
	var sim := running_tea(cfg)
	var view: Node = load("res://presentation/graybox/shop_view.gd").new()
	view.bind(sim)
	var layout: Script = load("res://presentation/graybox/layout.gd")
	var server: String = sim.workforce.staff[0].staff_id
	var fetched := false
	var served := false
	for i in 1500:
		sim.step()
		var actor: Node2D = view._staff[server]
		if not actor.working:
			continue
		var place := -1
		for staff in sim.last_snapshot.workforce.staff:
			if staff.staff == server:
				for request in sim.last_snapshot.front_hall.requests:
					if request.id == staff.request:
						for p in sim.last_snapshot.front_hall.orders.size():
							if sim.last_snapshot.front_hall.orders[p].id == request.order:
								place = p
		if place == -1:
			continue
		if actor.carry_item == "":
			fetched = fetched or actor.target.x == view._positions.shelf.x - 30
		else:
			served = served or actor.target == layout.serve_spot(place)
	check(fetched, "a server first walks to the pass-through window")
	check(served, "then carries the drink to the customer's own place")
	view.unbind()
	view.free()


# 后厨员工固定站在自己设备的工位格上（决定⑫），不走动。
func test_kitchen_worker_stands_on_the_device_work_cell() -> void:
	var layout: Script = load("res://presentation/graybox/layout.gd")
	var sim := running_tea()
	var view: Node = load("res://presentation/graybox/shop_view.gd").new()
	view.bind(sim)
	var milk := device_of(sim, "milk_station")
	var cook := ""
	for s in sim.workforce.staff:
		if s.post == milk:
			cook = s.staff_id
	var spot: Vector2 = Vector2.ZERO
	for d in sim.layout.devices:
		if d.id == milk:
			spot = layout.device_post(sim.config.device_def(d.def), d.cell)
	for i in 300:
		sim.step()
		check_eq(view._staff[cook].target, spot, "调奶的人一直站在调奶台的工位格上")
		if i > 5:
			break
	view.unbind()
	view.free()


# 布局模式：画的是草稿，确认后画生效的布局；带子的折线长度和模拟里的格数一致。
func test_view_follows_layout_draft_and_belt_lengths() -> void:
	var sim := make_sim(kitchen_copy())
	open_front(sim)
	var view: Node = load("res://presentation/graybox/shop_view.gd").new()
	view.bind(sim)
	sim.submit(EnterLayoutCommand.new())
	sim.submit(AutoDeployCommand.new())
	sim.step()
	check_eq(view._devices.size(), 4, "布局模式里画出草稿的四台设备")
	for id in view._devices:
		check(view._devices[id].draft, "草稿设备画成草稿样式")
	check_eq(view._belts.size(), 5, "草稿的五条带子也预览出来")
	sim.submit(ConfirmLayoutCommand.new())
	sim.step()
	check_eq(view._devices.size(), 4, "确认后画生效的设备")
	for id in view._devices:
		check(not view._devices[id].draft, "生效设备不再是草稿样式")
		check(sim.production.has_slot(id), "画面上的 id 就是模拟里的设备 id")
	var layout: Script = load("res://presentation/graybox/layout.gd")
	for seg in sim.production.segments:
		var points: PackedVector2Array = view._belts[seg.id].points
		var length := 0.0
		for i in points.size() - 1:
			length += points[i].distance_to(points[i + 1])
		check(absf(length / layout.CELL - seg.length) < 0.01, "带子 %s 画出来 %.2f 格，模拟里 %.0f 格" % [seg.id, length / layout.CELL, seg.length])
	view.unbind()
	view.free()
