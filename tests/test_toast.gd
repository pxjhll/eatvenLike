extends "res://tests/test_case.gd"
## 面包店第 2 阶段：切片机 + 切片吐司（单店节奏页第 2 行）。


func test_slicer_locked_until_revenue_threshold() -> void:
	var sim := make_sim()
	var reasons := []
	sim.command_rejected.connect(func(_c: SimCommand, reason: String) -> void: reasons.append(reason))
	sim.submit(UnlockStationCommand.new("slicer"))
	sim.run_seconds(120.0)
	check_eq(reasons, ["累计营业额不足"], "累计营业额没到 600 时不能买切片机")
	check_eq(sim.progress.stage_index, 0, "仍在第 1 阶段")
	check_eq(_slicer_bread(sim), 0, "切片机未解锁时烤炉不往它那一路送面包")
	check_eq(sim.progress.sold.get("toast", 0), 0, "没有人点吐司")


func test_unlock_slicer_splits_bread_and_sells_toast() -> void:
	var cfg := bakery_copy()
	cfg.starting_gold = 1000
	var sim := make_sim(cfg)
	_run_until_revenue(sim, 600)
	check(sim.economy.revenue >= 600, "不操作也能攒到 600 营业额")
	var gold := sim.economy.gold
	sim.submit(UnlockStationCommand.new("slicer"))
	sim.step()
	check_eq(sim.progress.stage_index, 1, "买下切片机进入第 2 阶段")
	check_eq(sim.front_hall.menu_stage, 1, "前厅菜单加入切片吐司")
	check(sim.economy.gold <= gold - 200 + 18, "扣了切片机的价格")
	var white_before: int = sim.progress.sold.get("white_bread", 0)
	sim.run_seconds(300.0)
	check(sim.diagnostics.produced_by_slot.get("slicer", 0) > 0, "烤炉把一部分面包分给切片机")
	check(sim.progress.sold.get("toast", 0) > 0, "切片吐司有人点、能卖出")
	check(sim.progress.sold.get("white_bread", 0) > white_before, "白面包照样在卖，旧线没有被废弃")
	var task_ids := []
	for task in sim.last_snapshot.tasks:
		task_ids.append(task.id)
	check_eq(task_ids, ["sell_white_bread_30", "sell_toast_50"], "任务列表加上吐司任务")


func test_new_stage_keeps_old_dish_majority_and_raises_traffic() -> void:
	var stages: Array[ShopStageDef] = load(BAKERY).progression.stages
	check_eq(stages.size(), 2, "面包店目前有 2 个阶段")
	var weights := stages[1].order_weights
	var total := 0.0
	for dish_id in weights:
		total += weights[dish_id]
	check(weights.get("white_bread", 0.0) / total >= 0.5, "新菜解锁后旧菜仍占一半以上")
	check(stages[1].customer_interval < stages[0].customer_interval, "解锁新菜同时客流上一档")


func _run_until_revenue(sim: GameSim, amount: int) -> void:
	var limit := 1800.0
	while sim.economy.revenue < amount and sim.elapsed_seconds() < limit:
		sim.run_seconds(1.0)


func _slicer_bread(sim: GameSim) -> int:
	var n := 0
	for st in sim.production.stations:
		if st.slot_id == "slicer":
			n += int(st.inputs.get("bread", 0))
	for seg in sim.production.segments:
		if seg.to_slot == "slicer":
			n += seg.items.size()
	return n
