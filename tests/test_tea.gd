extends "res://tests/test_case.gd"

const TEA := "res://content/tea/tea.tres"


func tea() -> GameSim:
	return make_sim(load(TEA))


func open_kitchen(sim: GameSim) -> void:
	sim.run_seconds(100.0)
	sim.submit(UnlockStationCommand.new("pearl_pot"))
	sim.step()
	check(sim.progress.kitchen_open(), "milk tea stage opens the kitchen")


func test_fresh_tea_and_legacy_bakery_identity() -> void:
	var catalog: GameCatalog = load(CATALOG)
	check_eq(catalog.shops[0].id, "bakery", "old save index zero is still bakery")
	check_eq(catalog.shops[Profile.create(catalog).current_shop].id, "tea", "fresh games start at tea")
	var old := Profile.from_dict({"current_shop": 0, "completed_shops": [], "roster": ["rabbit", "bear"], "records": {}})
	check_eq(catalog.shops[old.current_shop].id, "bakery", "legacy profile keeps its shop")
	check(make_sim().progress.kitchen_open(), "bakery stage zero remains accessible")


func test_closed_kitchen_rejects_commands_without_partial_commit() -> void:
	var sim := tea()
	check(not sim.progress.kitchen_open(), "new tea kitchen is closed")
	var commands: Array[SimCommand] = [UpgradeStationCommand.new("lemon_press"), ActivateParallelCommand.new("pearl_pot_b"), SetConnectionCommand.new("raw_box", "pearl_pot", false), ClearItemsCommand.new("raw_to_pot"), AssignStaffCommand.new("bear", "kitchen"), UnlockStationCommand.new("pearl_pot")]
	for command in commands:
		var before := state_json(sim)
		check(command.validate(sim) != "", "locked command has a rejection reason")
		# The actual command runner is the transaction boundary; stepping would also advance business.
		sim._run_command(command)
		check_eq(state_json(sim), before, "rejection changes no gold, staff, connections or progress")
	sim.run_seconds(100.0)
	check(sim.economy.revenue >= 120, "front lemonade business earns the unlock gate while closed")
	check_eq(sim.progress.unlocked_dishes(), ["lemonade"], "only lemonade is on the starting menu")
	check(not sim.production.count_items().has("cooked_pearl"), "kitchen does not produce before access")


func test_unlock_and_save_resume_before_and_after_gate() -> void:
	var sim := tea()
	sim.run_seconds(30.0)
	var closed := make_sim(load(TEA))
	closed.load_dict(JSON.parse_string(state_json(sim)))
	check(not closed.last_snapshot.kitchen_open, "closed access survives reconstruction")
	open_kitchen(sim)
	check_eq(sim.progress.stage_index, 1, "unlock changes menu stage")
	check_eq(sim.front_hall.menu_stage, 1, "hall uses the same menu stage")
	var gold := sim.economy.gold
	check(UnlockStationCommand.new("pearl_pot").validate(sim) != "", "repeated unlock rejects")
	check_eq(sim.economy.gold, gold, "repeated unlock does not charge")
	sim.submit(AssignStaffCommand.new("bear", "kitchen"))
	sim.run_seconds(45.0)
	var restored := make_sim(load(TEA))
	restored.load_dict(JSON.parse_string(state_json(sim)))
	check(restored.last_snapshot.kitchen_open, "opened access derives from restored stage")
	check_eq(state_json(restored), state_json(sim), "full active production restores")
	sim.run_seconds(40.0)
	restored.run_seconds(40.0)
	check_eq(state_json(restored), state_json(sim), "restored simulation continues deterministically")


func test_parallel_pots_improve_physical_output_and_tasks_complete() -> void:
	var single := tea()
	open_kitchen(single)
	single.submit(AssignStaffCommand.new("bear", "kitchen"))
	single.run_seconds(40.0)
	var parallel := make_sim(load(TEA))
	parallel.load_dict(JSON.parse_string(state_json(single)))
	parallel.submit(ActivateParallelCommand.new("pearl_pot_b"))
	parallel.step()
	check_eq(parallel.production.validate_parallel("pearl_pot_b"), "并联槽已启用", "parallel purchase activated its physical slot")
	single.run_seconds(600.0)
	parallel.run_seconds(600.0)
	var a := int(single.progress.sold.get("pearl_milk_tea", 0))
	var b := int(parallel.progress.sold.get("pearl_milk_tea", 0))
	print("TEA THROUGHPUT single=%d parallel=%d" % [a, b])
	check(b > a, "parallel pots yield more actual milk tea sales under the same demand")
	check(b >= 20, "tea physically traverses raw pearl, cooked pearl and mixed drink")
	check(parallel.progress.completed, "both drink tasks and menu complete in playable core")
	check(parallel.progress.sold.get("lemonade", 0) >= 10, "lemonade remains sold after milk tea unlock")


func test_shared_service_and_reassignment_have_real_capacity_cost() -> void:
	var sim := tea()
	open_kitchen(sim)
	check_eq(sim.front_hall.counters.size(), 1, "one shared sealing/service counter")
	check_eq(sim.front_hall.station_def("seal_counter").dishes, ["lemonade", "pearl_milk_tea"], "both drinks share the manual service step")
	sim.submit(AssignStaffCommand.new("bear", "kitchen"))
	sim.submit(ActivateParallelCommand.new("pearl_pot_b"))
	sim.run_seconds(100.0)
	var saw_service_queue := false
	for i in 600:
		sim.step()
		if sim.front_hall.requests.size() > 1:
			saw_service_queue = true
	check(saw_service_queue, "ready drinks queue for the shared front service workforce")
	var before := sim.progress.sold.get("pearl_milk_tea", 0)
	sim.submit(AssignStaffCommand.new("bear", "front"))
	sim.run_seconds(200.0)
	var stalled := sim.progress.sold.get("pearl_milk_tea", 0)
	sim.run_seconds(200.0)
	check(sim.progress.sold.get("pearl_milk_tea", 0) - stalled <= 2, "moving the cook front eventually exhausts physical pearls")
	check(stalled >= before, "existing stock is served during transfer")
	sim.submit(AssignStaffCommand.new("bear", "kitchen"))
	sim.run_seconds(120.0)
	check(sim.progress.sold.get("pearl_milk_tea", 0) > stalled, "reassignment back to kitchen resumes production")
