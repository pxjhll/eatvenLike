extends "res://tests/test_case.gd"
## Presentation may derive symptoms, but never change the simulation or snapshot.


func test_station_visual_state_uses_actual_mode_and_phase() -> void:
	var script: Script = load("res://presentation/graybox/view_state.gd")
	check(script != null, "graybox state adapter exists")
	if script == null:
		return
	var def: StationDef = load("res://content/bakery/stations/oven.tres")
	var row := {"status": StationState.Status.ACTIVE, "phase": StationState.Phase.PROCESSING, "inputs": {}, "outputs": {}, "progress": 0.5}
	check_eq(script.station(row, def).kind, "working", "an actual baking phase shows working")
	row.phase = StationState.Phase.WAIT_UNLOAD
	check_eq(script.station(row, def).kind, "staff", "baked product waits for staff")
	row.staff_working = true
	check_eq(script.station(row, def).kind, "working", "a claimed unload request shows active work, not missing staff")
	row.staff_working = false
	row.phase = StationState.Phase.IDLE
	check_eq(script.station(row, def).kind, "input", "empty input waits for material")
	row.outputs = {"bread": def.output_capacity}
	check_eq(script.station(row, def).kind, "blocked", "a full output buffer shows blocked")
	row.status = StationState.Status.EMPTY_PARALLEL
	check_eq(script.station(row, def).kind, "locked", "inactive parallel slots never look productive")


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
	var sim := make_sim()
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
		var config := bakery_copy()
		config.starting_gold = 200
		var sim := make_sim(config)
		for i in upgrades:
			sim.submit(UpgradeStationCommand.new("bread_counter"))
			sim.step()
		var view: Node = load("res://presentation/graybox/shop_view.gd").new()
		view.bind(sim)
		var rabbit: Node2D = view._staff["rabbit"]
		var pickup := Vector2(530, 914)
		var picked_up := false
		var delivered := false
		var last_target := Vector2.ZERO
		for i in 600:
			var revenue := sim.economy.revenue
			var before_move := rabbit.position
			sim.step()
			if not rabbit.carry_item.is_empty() and not picked_up:
				check(before_move.distance_to(pickup) < 3.0, "normal animation reaches pickup without relying on phase-boundary reconciliation")
				check(rabbit.position.distance_to(pickup) < 3.0, "a dish appears only after the server reaches the pickup window")
				picked_up = true
			if sim.economy.revenue > revenue:
				check(before_move.distance_to(last_target) < 3.0, "normal animation reaches the customer before the completion snapshot")
				check(rabbit.position.distance_to(last_target) < 3.0, "the server reaches the customer's place before the sale leaves the view")
				delivered = true
				break
			if not rabbit.carry_item.is_empty():
				last_target = rabbit.target
			for actor in view._staff.values():
				actor._process(0.1)
		check(picked_up and delivered, "a complete service was observed, including upgraded counter timing")
		view.unbind()
		view.free()


func test_ui_font_covers_drag_hint_and_parallel_card() -> void:
	var font: Font = load("res://art/ui/graybox_font.ttf")
	for code in [0x62D6, 0x64CD, 0x6837, 0x7FFB]:
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


# Catches servers stacking on one fixed point instead of fetching from the window and serving a customer.
func test_front_service_fetches_from_window_then_serves_its_customer() -> void:
	var layout: Script = load("res://presentation/graybox/layout.gd")
	var sim := make_sim()
	var view: Node = load("res://presentation/graybox/shop_view.gd").new()
	view.bind(sim)
	var fetched := false
	var served := false
	for i in 1200:
		sim.step()
		var rabbit: Node2D = view._staff["rabbit"]
		if not rabbit.working:
			continue
		var place := -1
		for staff in sim.last_snapshot.workforce.staff:
			if staff.staff == "rabbit":
				for request in sim.last_snapshot.front_hall.requests:
					if request.id == staff.request:
						for p in sim.last_snapshot.front_hall.orders.size():
							if sim.last_snapshot.front_hall.orders[p].id == request.order:
								place = p
		if place == -1:
			continue
		if rabbit.carry_item == "":
			fetched = fetched or rabbit.target.x == layout.WINDOW.x - 30
		else:
			served = served or rabbit.target == layout.serve_spot(place)
	check(fetched, "a server first walks to the pass-through window")
	check(served, "then carries the dish to the customer's own place")
	view.unbind()
	view.free()


# Catches kitchen workers snapping back to a home point between jobs.
func test_idle_kitchen_worker_stays_at_last_station() -> void:
	var layout: Script = load("res://presentation/graybox/layout.gd")
	var sim := make_sim()
	var view: Node = load("res://presentation/graybox/shop_view.gd").new()
	view.bind(sim)
	var bear: Node2D = view._staff["bear"]
	var last_job := Vector2.INF
	var stayed := false
	for i in 600:
		sim.step()
		if bear.working:
			last_job = bear.target
		elif last_job != Vector2.INF:
			stayed = stayed or bear.target == last_job
			check_eq(bear.target, last_job, "an idle kitchen worker keeps the last work spot")
			break
	check(stayed, "the worker finished a job and was observed idle")
	check(last_job != layout.KITCHEN_HOME, "the work spot is beside a station, not the home point")
	view.unbind()
	view.free()
