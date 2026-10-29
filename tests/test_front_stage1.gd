extends "res://tests/test_case.gd"
## PXJ-46 阶段 1：空店开局、前厅点解锁、招人与一人一岗、饮水机式出品台。
## PXJ-49 起柜台开局就在，只有柠檬茶台要买。

const TEA := "res://content/tea/tea.tres"


func tea() -> GameSim:
	return make_sim(load(TEA))


func hire(sim: GameSim) -> String:
	var command := HireStaffCommand.new()
	sim.submit(command)
	sim.step()
	return command.staff_id


# 验收：新档从空店开始，只靠点解锁柠檬水台和柜台、招一个服务员拖到柜台，就能卖出柠檬水。
func test_empty_shop_sells_lemonade_after_unlock_hire_and_assign() -> void:
	var sim := tea()
	check_eq(sim.workforce.staff.size(), 0, "an empty shop starts with nobody in it")
	check_eq(sim.economy.gold, 50, "the player starts with the placeholder 50 gold")
	check(not sim.front_hall.is_active("lemonade_stand"), "the stand starts as a price plate")
	check(sim.front_hall.is_active("counter"), "the counter is there from the start")
	sim.run_seconds(30.0)
	check_eq(sim.economy.revenue, 0, "customers arrive but nothing can be sold yet")
	check(sim.front_hall.orders.size() < sim.config.queue_capacity + 1, "unserved customers leave instead of piling up forever")

	sim.submit(UnlockFrontSpotCommand.new("lemonade_stand"))
	sim.step()
	check_eq(sim.economy.gold, 40, "the stand costs its price plate")
	sim.run_seconds(20.0)
	check_eq(sim.economy.revenue, 0, "an unstaffed counter still sells nothing")

	var server := hire(sim)
	check_eq(sim.economy.gold, 25, "the first hire costs 15")
	check_eq(sim.workforce.staff[0].post, "", "a new hire waits in the staff bar")
	sim.run_seconds(20.0)
	check_eq(sim.economy.revenue, 0, "a hired but unassigned server does not work")

	sim.submit(AssignStaffCommand.new(server, "counter"))
	sim.step()
	check_eq(sim.workforce.staff[0].post, "counter", "dragging onto the counter puts them on that post")
	sim.run_seconds(60.0)
	check(sim.progress.sold.get("lemonade", 0) > 0, "the shop sells lemonade")
	check(sim.economy.gold > 25, "sales pay out")


func test_lemonade_stand_pours_on_demand_and_never_runs_out() -> void:
	var sim := tea()
	sim.submit(UnlockFrontSpotCommand.new("lemonade_stand"))
	sim.submit(UnlockFrontSpotCommand.new("counter"))
	sim.step()
	sim.submit(AssignStaffCommand.new(hire(sim), "counter"))
	sim.run_seconds(300.0)
	check(sim.progress.sold.get("lemonade", 0) >= 30, "a single server keeps pouring")
	check(sim.production.count_items().is_empty(), "the stand holds no stock of its own")
	check(sim.progress.stockout.is_empty(), "a dispenser drink never reports a stockout")
	check(sim.progress.no_stockout.get("lemonade", 0.0) > 200.0, "and never interrupts the no-stockout task either")
	# 服务时间 = 柜台接单递杯 + 在台前打一杯，所以升级柠檬水台会提高前厅产能
	var slow: int = sim.progress.sold.get("lemonade", 0)
	var fast := make_sim(load(TEA))
	fast.submit(UnlockFrontSpotCommand.new("lemonade_stand"))
	fast.submit(UnlockFrontSpotCommand.new("counter"))
	fast.step()
	fast.submit(AssignStaffCommand.new(hire(fast), "counter"))
	fast.run_seconds(60.0)
	for i in 4:
		fast.submit(UpgradeStationCommand.new("lemonade_stand"))
		fast.step()
	fast.run_seconds(240.0)
	check(fast.progress.sold.get("lemonade", 0) > slow, "a faster stand pours more cups in the same 300 seconds")


func test_one_staff_per_post_and_swapping_them() -> void:
	var sim := tea()
	sim.submit(UnlockFrontSpotCommand.new("lemonade_stand"))
	sim.submit(UnlockFrontSpotCommand.new("counter"))
	sim.step()
	var first := hire(sim)
	check_eq(AssignStaffCommand.new(first, "lemonade_stand").validate(sim), "这个工位不要员工", "nobody can be posted to the dispenser")
	sim.submit(AssignStaffCommand.new(first, "counter"))
	sim.run_seconds(120.0)
	var second := hire(sim)
	var third := hire(sim)
	sim.submit(AssignStaffCommand.new(second, "counter"))
	sim.step()
	check_eq(sim.workforce.post_occupancy("counter"), 2, "the counter holds two servers")
	check_eq(AssignStaffCommand.new(third, "counter").validate(sim), "这个工位满了", "a third server cannot squeeze in")
	sim.submit(SwapStaffCommand.new(third, second))
	sim.step()
	check_eq(sim.workforce.post_occupancy("counter"), 2, "swapping keeps the post full, never overfull")
	var posts := {}
	for s in sim.workforce.staff:
		posts[s.staff_id] = s.post
	check_eq(posts[third], "counter", "the dragged server took the post")
	check_eq(posts[second], "", "and the one who was there went back to the staff bar")
	sim.submit(AssignStaffCommand.new(first, ""))
	sim.step()
	check_eq(sim.workforce.post_occupancy("counter"), 1, "dragging someone back to the bar frees their post")
	var sold: int = sim.progress.sold.get("lemonade", 0)
	sim.run_seconds(60.0)
	check(sim.progress.sold.get("lemonade", 0) > sold, "the remaining server keeps the shop running")


func test_rejected_front_commands_change_nothing() -> void:
	var sim := tea()
	var rejected := []
	sim.command_rejected.connect(func(_c: SimCommand, reason: String) -> void: rejected.append(reason))
	var commands: Array[SimCommand] = [
		UnlockFrontSpotCommand.new("no_such_spot"),
		AssignStaffCommand.new("nobody", "counter"),
		SwapStaffCommand.new("nobody", "nobody"),
	]
	for command in commands:
		var before := _ownership(sim)
		sim.submit(command)
		sim.step()
		check_eq(_ownership(sim), before, "a rejected command leaves gold, staff and spots alone")
	check_eq(rejected.size(), 3, "each bad command is rejected with a reason")
	# 钱不够也是拒绝，不是半成交
	var poor := tea()
	poor.economy.gold = 5
	poor.submit(UnlockFrontSpotCommand.new("lemonade_stand"))
	poor.step()
	check_eq(poor.economy.gold, 5, "an unaffordable spot does not charge")
	check(not poor.front_hall.is_active("lemonade_stand"), "and does not open")


## 命令该改的东西：金币、员工与岗位、前厅位点状态（时间照走的部分不在内）
func _ownership(sim: GameSim) -> String:
	var staff := []
	for s in sim.workforce.staff:
		staff.append([s.staff_id, s.post, s.zone])
	var spots := []
	for c in sim.front_hall.counters:
		spots.append([c.slot_id, c.status, c.level])
	return JSON.stringify({"gold": sim.economy.gold, "staff": staff, "spots": spots})


func test_staff_bar_hires_and_drag_to_post_uses_commands() -> void:
	var sim := tea()
	var view: Node2D = load("res://presentation/graybox/shop_view.gd").new()
	view.bind(sim)
	var ui: CanvasLayer = load("res://presentation/graybox/shop_ui.gd").new()
	ui.bind(sim, view, ShopHud.new())
	check(ui._hire.text.contains("15"), "the staff bar shows the next hire price")
	check_eq(ui._staff_cards.size(), 0, "an empty shop has no staff cards")
	ui._hire.pressed.emit()
	sim.step()
	check_eq(sim.workforce.staff.size(), 1, "the hire button submits a real command")
	check_eq(ui._staff_cards.size(), 1, "the new hire appears in the staff bar")
	# 后厨还没开，拖进后厨什么也不发生
	ui._bar_drag = sim.workforce.staff[0].staff_id
	ui._finish_bar_drag(Vector2(300, 600))
	sim.step()
	check_eq(sim.workforce.staff[0].zone, "", "a closed kitchen is not a drop target")
	ui._bar_drag = sim.workforce.staff[0].staff_id
	ui._finish_bar_drag(_counter_point(view))
	sim.step()
	check_eq(sim.workforce.staff[0].post, "counter", "dropping a card on the open counter puts them on post")
	# 后厨开了以后，新招的人可以直接从员工栏拖进后厨
	sim.economy.revenue = 300
	sim.economy.gold += 400
	sim.submit(UnlockLineCommand.new())
	sim.step()
	check(sim.progress.kitchen_open(), "the kitchen opened for the drop test")
	ui._hire.pressed.emit()
	sim.step()
	var cook: String = sim.workforce.staff[1].staff_id
	ui._bar_drag = cook
	ui._finish_bar_drag(Vector2(300, 600))
	sim.step()
	check_eq(sim.workforce.staff[1].zone, "kitchen", "dropping a card on the open kitchen sends them there")
	ui.free()
	view.free()


## 柜台在画面上的落点（表现层坐标），用来模拟一次拖拽
func _counter_point(view: Node2D) -> Vector2:
	var box: Rect2 = view._stations["counter"].bounds()
	return box.get_center()
