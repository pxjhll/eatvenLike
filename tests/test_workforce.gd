extends "res://tests/test_case.gd"
## PXJ-22: real backend manual/coop work, independent of animal and machine IDs.

const Cases := preload("res://tests/fixtures/production_cases.gd")


# Catches MANUAL accidentally advancing without an assigned kitchen worker.
func test_manual_waits_for_staff_then_runs_after_assignment() -> void:
	var cfg := _manual_config()
	cfg.staff_start_zones["operator"] = "front"
	var sim := _make(cfg)
	Cases.state(sim, "custom_prep").inputs["flour"] = 4
	sim.run_seconds(6.0)
	check_eq(Cases.produced(sim, "dough"), 0, "manual work cannot produce without a kitchen worker")
	check_eq(Cases.state(sim, "custom_prep").inputs["flour"], 4, "waiting does not consume inputs")
	sim.submit(AssignStaffCommand.new("operator", "kitchen"))
	sim.run_seconds(10.0)
	check(Cases.produced(sim, "dough") > 0, "assigning the worker starts manual production")


# Catches efficiency being ignored or applied twice to a manual step.
func test_manual_uses_staff_efficiency_once() -> void:
	var normal := _make(_manual_config(), 1.0)
	var fast := _make(_manual_config(), 2.0)
	for sim in [normal, fast]:
		Cases.state(sim, "custom_prep").inputs["flour"] = 4
		sim.run_seconds(4.0)
	check_eq(Cases.produced(normal, "dough"), 1, "4 seconds at 1x completes one 4-second step")
	check_eq(Cases.produced(fast, "dough"), 2, "4 seconds at 2x completes two steps")


# Catches mid-step reassignment dropping a job or claiming another old-zone job.
func test_manual_transfer_finishes_exactly_one_step() -> void:
	var sim := _make(_manual_config())
	var prep := Cases.state(sim, "custom_prep")
	prep.inputs["flour"] = 4
	sim.run_seconds(1.0)
	check(sim.workforce.staff[0].request_id != -1, "a manual step is actually in progress")
	var request_id := sim.workforce.staff[0].request_id
	sim.submit(AssignStaffCommand.new("operator", "front"))
	sim.run_seconds(2.0)
	check_eq(sim.workforce.staff[0].zone, "kitchen", "at 3 seconds the original 4-second step is unfinished")
	check_eq(sim.workforce.staff[0].request_id, request_id, "transfer preserves the current request until its normal completion")
	check_eq(Cases.produced(sim, "dough"), 0, "transfer must not complete the step prematurely")
	sim.run_seconds(1.0)
	check_eq(Cases.produced(sim, "dough"), 1, "the original step completes at 4 seconds")
	check_eq(sim.workforce.staff[0].zone, "kitchen", "the walk starts after completion, not while working")
	sim.run_seconds(1.0)
	check_eq(sim.workforce.staff[0].zone, "kitchen", "one second of walking cannot finish a two-second transfer")
	sim.run_seconds(4.0)
	check_eq(sim.workforce.staff[0].zone, "front", "the worker finishes and walks to front")
	check_eq(sim.workforce.staff[0].request_id, -1, "the worker does not claim another kitchen job")
	check_eq(Cases.produced(sim, "dough"), 1, "exactly one output, with no duplicate completion")
	check_eq(prep.inputs["flour"], 3, "exactly one input consumed")
	check_eq(prep.outputs.get("dough", 0), 1, "completed output remains at the station")


# Catches retaining staff through baking or binding a worker to one concrete oven ID.
func test_one_worker_services_two_coop_ovens_and_is_released_during_baking() -> void:
	var left := Cases.slot("heater_alpha", StationDef.Mode.COOP, {"dough": 1}, {"bread": 1}, 4.0)
	var right := Cases.slot("heater_beta", StationDef.Mode.COOP, {"dough": 1}, {"bread": 1}, 4.0)
	right.station = left.station
	var sim := _make(Cases.config([left, right]))
	for st in sim.production.stations:
		st.inputs["dough"] = 4
	var serviced := {}
	var free_during_baking := false
	var another_job_during_baking := false
	for i in 200:
		sim.step()
		var worker := sim.workforce.staff[0]
		var claimed_slot := ""
		for req in sim.production.requests:
			if req.id == worker.request_id:
				claimed_slot = req.slot_id
				serviced[req.slot_id] = true
		for st in sim.production.stations:
			if st.phase == StationState.Phase.PROCESSING:
				free_during_baking = free_during_baking or worker.request_id == -1
				another_job_during_baking = another_job_during_baking or (claimed_slot != "" and claimed_slot != st.slot_id)
	check_eq(sim.workforce.staff.size(), 1, "fixture has exactly one employee")
	check(serviced.has("heater_alpha") and serviced.has("heater_beta"), "that employee serviced both arbitrary oven IDs")
	check(free_during_baking, "machine baking does not retain the employee")
	check(another_job_during_baking, "the employee can work on the other oven while one bakes")
	for id in ["heater_alpha", "heater_beta"]:
		check(sim.diagnostics.produced_by_slot.get(id, 0) > 0, "both ovens produced bread: " + id)


func _manual_config() -> ShopConfig:
	return Cases.config([Cases.slot("custom_prep", StationDef.Mode.MANUAL, {"flour": 1}, {"dough": 1}, 4.0)])


func _make(cfg: ShopConfig, efficiency: float = 1.0) -> GameSim:
	var sim := GameSim.new()
	sim.setup(cfg, [Cases.worker(efficiency)])
	_nodes.append(sim)
	return sim
