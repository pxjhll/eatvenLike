extends "res://tests/test_case.gd"
## 奶茶店：空店开局 → 前厅点解锁 → 招人上柜台 → 卖柠檬水 → 营业额到门槛开后厨。

const TEA := "res://content/tea/tea.tres"


func tea() -> GameSim:
	return make_sim(load(TEA))


func saved_state(sim: GameSim) -> Dictionary:
	var service := SaveService.new("user://tea-roundtrip-test.json")
	check_eq(service.save({"shop": sim.to_dict()}), OK, "tea state writes to disk")
	var data := service.load_data()
	service.delete()
	return data.get("shop", {})


## 开场：点开柠檬水台和柜台，招一个人拖到柜台
func open_front(sim: GameSim) -> String:
	sim.submit(UnlockFrontSpotCommand.new("lemonade_stand"))
	sim.submit(UnlockFrontSpotCommand.new("counter"))
	var hire := HireStaffCommand.new()
	sim.submit(hire)
	sim.step()
	sim.submit(AssignStaffCommand.new(hire.staff_id, "counter"))
	sim.step()
	return hire.staff_id


## 卖柠檬水攒到门槛，再买煮珍珠锅开后厨，并招一名后厨员工
func open_kitchen(sim: GameSim) -> String:
	for i in 4000:
		if sim.economy.revenue >= 300 and sim.economy.gold >= 60 + sim.workforce.hire_cost():
			break
		sim.step()
	sim.submit(UnlockStationCommand.new("pearl_pot"))
	var hire := HireStaffCommand.new()
	sim.submit(hire)
	sim.step()
	check(sim.progress.kitchen_open(), "milk tea stage opens the kitchen")
	sim.submit(AssignStaffCommand.new(hire.staff_id, "kitchen"))
	sim.step()
	return hire.staff_id


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
	open_front(sim)
	var commands: Array[SimCommand] = [UpgradeStationCommand.new("pearl_pot"), ActivateParallelCommand.new("pearl_pot_b"), SetConnectionCommand.new("raw_box", "pearl_pot", false), ClearItemsCommand.new("raw_to_pot"), AssignStaffCommand.new("staff3", "kitchen"), UnlockStationCommand.new("pearl_pot")]
	for command in commands:
		var before := state_json(sim)
		check(command.validate(sim) != "", "locked command has a rejection reason")
		# The actual command runner is the transaction boundary; stepping would also advance business.
		sim._run_command(command)
		check_eq(state_json(sim), before, "rejection changes no gold, staff, connections or progress")
	sim.run_seconds(200.0)
	check(sim.economy.revenue >= 300, "front lemonade business earns the unlock gate while closed")
	check_eq(sim.progress.unlocked_dishes(), ["lemonade"], "only lemonade is on the starting menu")
	check(not sim.production.count_items().has("cooked_pearl"), "kitchen does not produce before access")


# 后厨锁只拦后厨：开厨前前厅位点照常解锁、照常升级。
func test_closed_kitchen_still_allows_front_changes() -> void:
	var sim := tea()
	open_front(sim)
	check(sim.front_hall.is_active("lemonade_stand"), "the stand opens before the kitchen exists")
	var gold := sim.economy.gold
	sim.run_seconds(40.0)
	check(sim.economy.gold > gold, "lemonade earns money with the kitchen still closed")
	check_eq(UpgradeStationCommand.new("lemonade_stand").validate(sim), "", "front upgrade is allowed before the kitchen opens")
	sim.submit(UpgradeStationCommand.new("lemonade_stand"))
	sim.step()
	var levels := {}
	for st in sim.front_hall.counters:
		levels[st.slot_id] = st.level
	check_eq(levels["lemonade_stand"], 2, "the stand upgrades while the kitchen is closed")
	check(not sim.progress.kitchen_open(), "front upgrade does not open the kitchen")


func test_unlock_and_save_resume_before_and_after_gate() -> void:
	var sim := tea()
	open_front(sim)
	sim.run_seconds(30.0)
	var closed := make_sim(load(TEA))
	closed.load_dict(saved_state(sim))
	check(not closed.last_snapshot.kitchen_open, "closed access survives reconstruction")
	check_eq(closed.workforce.staff[0].post, "counter", "the hired server keeps their post across a save")
	open_kitchen(sim)
	check_eq(sim.progress.stage_index, 1, "unlock changes menu stage")
	check_eq(sim.front_hall.menu_stage, 1, "hall uses the same menu stage")
	var gold := sim.economy.gold
	check(UnlockStationCommand.new("pearl_pot").validate(sim) != "", "repeated unlock rejects")
	check_eq(sim.economy.gold, gold, "repeated unlock does not charge")
	sim.run_seconds(45.0)
	var restored := make_sim(load(TEA))
	restored.load_dict(saved_state(sim))
	check(restored.last_snapshot.kitchen_open, "opened access derives from restored stage")
	check_eq(state_json(restored), state_json(sim), "full active production restores")
	sim.run_seconds(40.0)
	restored.run_seconds(40.0)
	check_eq(state_json(restored), state_json(sim), "restored simulation continues deterministically")


func test_parallel_pots_improve_physical_output_and_tasks_complete() -> void:
	var single := tea()
	open_front(single)
	open_kitchen(single)
	single.run_seconds(40.0)
	var parallel := make_sim(load(TEA))
	parallel.load_dict(saved_state(single))
	parallel.submit(ActivateParallelCommand.new("pearl_pot_b"))
	parallel.step()
	check_eq(parallel.production.validate_parallel("pearl_pot_b"), "并联槽已启用", "parallel purchase activated its physical slot")
	single.run_seconds(900.0)
	parallel.run_seconds(900.0)
	var a := int(single.progress.sold.get("pearl_milk_tea", 0))
	var b := int(parallel.progress.sold.get("pearl_milk_tea", 0))
	print("TEA THROUGHPUT single=%d parallel=%d" % [a, b])
	check(b > a, "parallel pots yield more actual milk tea sales under the same demand")
	check(b >= 20, "tea physically traverses raw pearl, cooked pearl and mixed drink")
	check(parallel.progress.sold.get("lemonade", 0) >= 30, "lemonade remains sold after milk tea unlock")
	check(parallel.progress.completed, "both drink tasks and menu complete in playable core")


func test_counter_serves_both_drinks_and_reassignment_costs_capacity() -> void:
	var sim := tea()
	var server := open_front(sim)
	var cook := open_kitchen(sim)
	check_eq(sim.front_hall.station_def("counter").dishes, ["lemonade", "pearl_milk_tea"], "every customer orders at the one counter")
	check_eq(sim.front_hall.post_capacity("counter"), 2, "the counter has room for a second server")
	check_eq(sim.front_hall.post_capacity("lemonade_stand"), 0, "the lemonade stand takes no staff at all")
	sim.submit(ActivateParallelCommand.new("pearl_pot_b"))
	sim.run_seconds(100.0)
	var saw_service_queue := false
	for i in 600:
		sim.step()
		if sim.front_hall.requests.size() > 1:
			saw_service_queue = true
	check(saw_service_queue, "ready drinks queue for the shared front service workforce")
	var before: int = sim.progress.sold.get("pearl_milk_tea", 0)
	sim.submit(AssignStaffCommand.new(cook, "counter"))
	sim.run_seconds(200.0)
	var stalled: int = sim.progress.sold.get("pearl_milk_tea", 0)
	sim.run_seconds(200.0)
	check(sim.progress.sold.get("pearl_milk_tea", 0) - stalled <= 2, "moving the cook front eventually exhausts physical pearls")
	check(stalled >= before, "existing stock is served during transfer")
	check_eq(sim.workforce.post_occupancy("counter"), 2, "both servers now stand at the counter")
	check(sim.progress.sold.get("lemonade", 0) > 0, "the second server keeps lemonade moving")
	sim.submit(AssignStaffCommand.new(cook, "kitchen"))
	sim.run_seconds(160.0)
	check(sim.progress.sold.get("pearl_milk_tea", 0) > stalled, "reassignment back to kitchen resumes production")
	check_eq(sim.workforce.post_occupancy("counter"), 1, "the cook left the counter post")
	check_eq(server, sim.workforce.staff[0].staff_id, "the first hire is still the one on the counter")


func test_all_presentation_controls_follow_access_snapshot() -> void:
	var sim := tea()
	var world: Node2D = load("res://presentation/graybox/shop_view.gd").new()
	world.bind(sim)
	var debug := ShopHud.new()
	debug.bind(sim)
	var ui: CanvasLayer = load("res://presentation/graybox/shop_ui.gd").new()
	ui.bind(sim, world, debug)
	check(not debug._status.text.contains("pearl_pot"), "debug snapshot text hides the closed kitchen")
	for entry in debug._buttons:
		if entry.kitchen_only:
			check(not entry.button.visible, "debug kitchen controls are hidden")
		else:
			check(entry.button.visible and not entry.button.disabled, "debug front controls stay usable before access")
	ui._selected = "lemonade_stand"
	ui._selected_kind = "station"
	ui._card.visible = true
	ui._refresh_card()
	check(ui._card_buttons[0].text.contains("10"), "the locked stand shows its price plate")
	check(not ui._card_buttons[0].disabled, "50 starting gold buys the stand")
	open_front(sim)
	ui._refresh_card()
	check(ui._card_title.text.contains("柠檬水台"), "an opened stand shows its own card")
	open_kitchen(sim)
	check(world._stations["pearl_pot"].visible, "open snapshot reveals physical kitchen")
	check(debug._status.text.contains("pearl_pot"), "debug kitchen state appears only after access")
	for entry in debug._buttons:
		if entry.kitchen_only:
			check(entry.button.visible, "open snapshot reveals kitchen controls")
	ui.free()
	debug.free()
	world.free()


func test_debug_hud_rebind_disconnects_previous_sim() -> void:
	var first := tea()
	var second := make_sim()
	var debug := ShopHud.new()
	debug.bind(first)
	var count := debug._buttons.size()
	debug.bind(first)
	check_eq(debug._buttons.size(), count, "rebinding does not retain old button tracking")
	check_eq(first.tick_finished.get_connections().size(), 1, "one HUD subscription after rebinding")
	debug.bind(second)
	check_eq(first.tick_finished.get_connections().size(), 0, "previous shop is disconnected")
	var status := debug._status.text
	first.run_seconds(2.0)
	check_eq(debug._status.text, status, "old simulation cannot update rebound HUD")
	second.step()
	check(debug._status.text != status, "current simulation still updates HUD")
	debug.unbind()
	check_eq(second.tick_finished.get_connections().size(), 0, "explicit detach disconnects HUD")
	debug.free()
