extends "res://tests/test_case.gd"
## 第 5 节命令表：校验与提交顺序。


func test_upgrade_routes_to_front_hall() -> void:
	var sim := make_sim()
	sim.submit(UpgradeStationCommand.new("bread_counter"))
	sim.step()
	check_eq(sim.front_hall.counters[0].level, 2, "前厅工位由 FrontHall 升级")
	check_eq(sim.progress.station_levels.get("bread_counter", 1), 2, "ShopProgress 收到等级事件")


func test_unlock_station_adds_dish() -> void:
	var cfg := _with_toast_stage()
	var sim := make_sim(cfg)
	var reasons := []
	sim.command_rejected.connect(func(_c: SimCommand, reason: String) -> void: reasons.append(reason))
	sim.submit(UnlockStationCommand.new("toast_counter"))
	sim.step()
	check_eq(reasons, ["累计营业额不足"], "营业额没到门槛时拒绝")
	sim.run_seconds(60.0)
	check(sim.economy.revenue >= 50, "一分钟后营业额过门槛")
	var gold := sim.economy.gold
	sim.submit(UnlockStationCommand.new("toast_counter"))
	sim.step()
	check_eq(reasons.size(), 1, "过门槛后解锁成功")
	check(sim.economy.gold <= gold - 40 + 10, "扣了解锁价")
	check_eq(sim.progress.stage_index, 1, "进入第 2 阶段")
	check_eq(sim.front_hall.menu_stage, 1, "前厅菜单加入新菜")
	check(sim.front_hall.has_slot("toast_counter"), "新柜台归 FrontHall")
	sim.run_seconds(120.0)
	check(sim.progress.sold.get("toast", 0) > 0, "新菜有人点、能卖出")


func test_assign_staff_finishes_current_step() -> void:
	var sim := make_sim()
	var bear: StaffState
	for s in sim.workforce.staff:
		if s.staff_id == "bear":
			bear = s
	while bear.request_id == -1:
		sim.step()
	var request := bear.request_id
	sim.submit(AssignStaffCommand.new("bear", "front"))
	sim.step()
	check_eq(bear.zone, "kitchen", "做完当前步骤前不走")
	check(bear.request_id == request or bear.request_id == -1, "不认领新请求")
	sim.run_seconds(3.5)
	check_eq(bear.zone, "front", "做完再走 2 秒到前厅")
	check_eq(bear.target_zone, "", "到达后清掉目标")


func test_set_connection_keeps_items_and_clear_removes_them() -> void:
	var sim := make_sim()
	var seg := _segment(sim, "dough_to_oven")
	for i in 2000:
		if seg.items.size() >= 2:
			break
		sim.step()
	sim.submit(SetConnectionCommand.new("dough_table", "oven", false))
	sim.step()
	var frozen := seg.to_dict()
	check(not seg.items.is_empty(), "断开时线上有物料")
	sim.run_seconds(10.0)
	check_eq(seg.to_dict().items, frozen.items, "断开后物料留在原处，不转移、不复制")
	var count := seg.items.size()
	sim.submit(ClearItemsCommand.new("dough_to_oven"))
	sim.step()
	check(seg.items.is_empty(), "清理后这段为空")
	check_eq(sim.diagnostics.items_cleared, count, "Diagnostics 记录清理数量")


func test_switch_shop_needs_completion() -> void:
	var sim := make_sim()
	check_eq(SwitchShopCommand.new().validate(sim), "店铺还没完成", "没完成不能换店")


func _segment(sim: GameSim, id: String) -> BeltSegmentState:
	for seg in sim.production.segments:
		if seg.id == id:
			return seg
	return null


## 在面包店副本上加一个第 2 阶段：解锁吐司柜台（直接卖面包，只为测解锁流程）
func _with_toast_stage() -> ShopConfig:
	var cfg := bakery_copy()
	var dish := DishDef.new()
	dish.id = "toast"
	dish.item_id = "bread"
	dish.price = 18
	cfg.dishes.append(dish)
	var counter: StationDef = cfg.slots[4].station.duplicate_deep()
	counter.id = "toast_counter"
	counter.dishes.assign(["toast"])
	counter.unlock_cost = 40
	var slot := SlotDef.new()
	slot.id = "toast_counter"
	slot.station = counter
	slot.initially_locked = true
	cfg.slots.append(slot)
	var stage := ShopStageDef.new()
	stage.dish_id = "toast"
	stage.revenue_threshold = 50
	stage.unlock_slots.assign(["toast_counter"])
	stage.customer_interval = 3.0
	stage.order_weights["white_bread"] = 1.0
	stage.order_weights["toast"] = 1.0
	cfg.progression.stages.append(stage)
	return cfg
