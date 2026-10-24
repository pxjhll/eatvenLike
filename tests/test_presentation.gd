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
