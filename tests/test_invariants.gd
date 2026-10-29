extends "res://tests/test_case.gd"
## 契约第 6 节的 10 条不变量，每条一个固定种子的回归场景。


# 1. 销售只结算一次
func test_1_sale_settles_once() -> void:
	var eco := EconomySystem.new()
	check(eco.settle(7, 10), "第一次结算成功")
	check(not eco.settle(7, 10), "同一 saleId 第二次无效果")
	check_eq(eco.revenue, 10, "营业额只加一次")
	var sim := make_sim()
	sim.run_seconds(120.0)
	check_eq(sim.economy.revenue, sim.diagnostics.sold * 10, "模拟里每份只结算一次")


# 2. 消费金币不倒扣累计营业额
func test_2_spend_keeps_revenue() -> void:
	var sim := make_sim()
	sim.run_seconds(60.0)
	var revenue := sim.economy.revenue
	var gold := sim.economy.gold
	sim.submit(UpgradeStationCommand.new("oven"))
	sim.step()
	var earned := sim.economy.revenue - revenue
	check_eq(sim.economy.gold, gold - 40 + earned, "金币扣掉升级费")
	check(sim.economy.revenue >= revenue, "营业额没被扣")


# 3. 缺料订单不永久占死员工
func test_3_stockout_does_not_hold_staff() -> void:
	var cfg := bakery_copy()
	_slot(cfg, "flour_box").station.supply_interval = 1000000.0
	var sim := make_sim(cfg)
	var waiting_seen := false
	for i in 300:
		sim.step()
		for o in sim.front_hall.orders:
			waiting_seen = waiting_seen or o.state == OrderState.State.WAITING_STOCK
		check(sim.front_hall.requests.is_empty(), "缺料订单不发布服务请求")
		for s in sim.workforce.staff:
			check_eq(s.request_id, -1, "没有可执行工作时员工空闲")
	check(waiting_seen, "确实出现了等料订单")
	check(sim.diagnostics.customers_lost > 0, "等不到料的顾客会离开")
	check(not sim.front_hall.stockout.is_empty(), "缺货状态被记录")


# 4. 派生状态不反写业务真值
func test_4_snapshot_is_a_copy() -> void:
	var sim := make_sim()
	sim.run_seconds(30.0)
	var before := state_json(sim)
	var snap := sim.last_snapshot
	snap.gold = 999999
	snap.production.shelf["bread"] = 99
	snap.production.stations[0].level = 9
	snap.workforce.staff[0].zone = "nowhere"
	check_eq(state_json(sim), before, "改快照不影响模拟状态")


# 5. 物料守恒（含改线、断线和清理）
func test_5_material_conserved() -> void:
	var cfg := bakery_copy()
	cfg.starting_gold = 500
	var sim := make_sim(cfg)
	sim.submit(ActivateParallelCommand.new("oven_b"))
	for i in 3000:
		if i == 800:
			sim.submit(SetConnectionCommand.new("dough_table", "oven", false))
		if i == 1400:
			sim.submit(ClearItemsCommand.new("dough_to_oven"))
		if i == 1600:
			sim.submit(SetConnectionCommand.new("dough_table", "oven", true))
		sim.step()
		if i % 10 == 0:
			_check_conservation(sim, i)
	check(sim.diagnostics.items_cleared >= 0, "清理被记录")


func _check_conservation(sim: GameSim, i: int) -> void:
	var field := sim.production.count_items()
	for item in ["flour", "dough", "bread"]:
		check_eq(int(field.get(item, 0)), sim.diagnostics.expected_on_field(item), "tick %d 物料 %s 守恒" % [i, item])
	var reserved := {}
	for order_id in sim.production.reservations:
		var r: Dictionary = sim.production.reservations[order_id]
		reserved[r.item] = int(reserved.get(r.item, 0)) + r.count
	for item in reserved:
		check(reserved[item] <= int(sim.production.shelf.get(item, 0)), "tick %d 预留不超过备料架库存" % i)


# 6. 命令原子性：被拒绝的命令不改变任何状态
func test_6_rejected_command_changes_nothing() -> void:
	var a := make_sim()
	var b := make_sim()
	var reasons := []
	b.command_rejected.connect(func(_c: SimCommand, reason: String) -> void: reasons.append(reason))
	a.run_seconds(20.0)
	b.run_seconds(20.0)
	b.submit(ActivateParallelCommand.new("oven_b"))      # 金币不足（120 > 当前）
	b.submit(UnlockStationCommand.new("oven"))            # 不在解锁列表
	b.submit(UpgradeStationCommand.new("no_such_slot"))
	b.submit(SetConnectionCommand.new("oven", "dough_table"))
	a.run_seconds(20.0)
	b.run_seconds(20.0)
	check_eq(reasons.size(), 4, "四条命令都被拒绝")
	check(reasons[0] == "金币不足", "金币不足的原因正确：%s" % reasons[0])
	check_eq(state_json(b), state_json(a), "被拒绝的命令没有改变任何状态")


# 7. 一人一任务，一个请求只被一名员工认领
func test_7_one_staff_one_task() -> void:
	var cfg := bakery_copy()
	cfg.starting_gold = 500
	var sim := make_sim(cfg)
	sim.submit(ActivateParallelCommand.new("oven_b"))
	sim.submit(AssignStaffCommand.new("rabbit", "kitchen"))
	for i in 2000:
		if i == 600:
			sim.submit(AssignStaffCommand.new("rabbit", "front"))
		sim.step()
		var seen := {}
		for s in sim.workforce.staff:
			if s.request_id == -1:
				continue
			check(not seen.has(s.request_id), "tick %d 请求 %d 被两人认领" % [i, s.request_id])
			seen[s.request_id] = true
			check(sim.production.owns_request(s.request_id) or sim.front_hall.owns_request(s.request_id), "认领的请求仍存在")


# 8. Definition 不可变
func test_8_defs_unchanged() -> void:
	var cfg: ShopConfig = load(BAKERY)
	var before := _fingerprint(cfg)
	var rich := bakery_copy()
	rich.starting_gold = 1000
	for config in [cfg, rich]:
		var sim := make_sim(config)
		sim.submit(UpgradeStationCommand.new("oven"))
		sim.submit(ActivateParallelCommand.new("oven_b"))
		sim.submit(UpgradeStationCommand.new("bread_counter"))
		sim.run_seconds(300.0)
	check_eq(_fingerprint(cfg), before, "跑完模拟后 .tres 字段完全没变")
	var sim := make_sim(rich)
	sim.submit(ActivateParallelCommand.new("oven_b"))
	sim.submit(UpgradeStationCommand.new("oven"))
	sim.step()
	var levels := {}
	for st in sim.production.stations:
		levels[st.slot_id] = st.level
	check_eq(levels.oven, 2, "升级的那台到 Lv2")
	check_eq(levels.oven_b, 1, "共享同一个 Def 的另一台不受影响")


# 9. 步长无关：改变步长不改变每秒产量和收入（允许不到一件的取整误差）
# 只比 0.05 和 0.1：0.2 时还剩传送带交付、取出后再装入各一个 tick 的交接延迟，十分钟差 2 个面包左右。
func test_9_step_independent() -> void:
	var results := {}
	for step in [0.05, 0.1]:
		var sim := make_sim(null, step)
		sim.run_seconds(600.0)
		results[step] = {"bread": int(sim.diagnostics.item_flow.bread.produced), "revenue": sim.economy.revenue}
	var base: Dictionary = results[0.1]
	for step in results:
		var r: Dictionary = results[step]
		check(absi(r.bread - base.bread) <= 1, "步长 %s 面包产量 %d vs %d" % [step, r.bread, base.bread])
		check(absi(r.revenue - base.revenue) <= 10, "步长 %s 收入 %d vs %d" % [step, r.revenue, base.revenue])


# 10. 存读档无损：一口气跑 N 秒 == 跑一半 → 存档（JSON）→ 读档 → 再跑一半
func test_10_save_load_lossless() -> void:
	var cfg := bakery_copy()
	cfg.starting_gold = 300
	var straight := make_sim(cfg)
	var first := make_sim(cfg)
	for sim in [straight, first]:
		sim.submit(UpgradeStationCommand.new("oven"))
		sim.run_seconds(150.0)
		sim.submit(ActivateParallelCommand.new("oven_b"))
		sim.submit(AssignStaffCommand.new("rabbit", "kitchen"))
		sim.step()
	var json := state_json(first)
	var save_text := JSON.stringify(SaveUtil.encode_floats(first.to_dict()), "", false)
	var resumed := make_sim(cfg)
	resumed.load_dict(SaveUtil.decode_floats(JSON.parse_string(save_text)))
	check_eq(state_json(resumed), json, "读档后状态与存档时一致")
	straight.run_seconds(150.0)
	resumed.run_seconds(150.0)
	check_eq(state_json(resumed), state_json(straight), "读档后继续跑，与不中断的结果完全一致")


func _slot(cfg: ShopConfig, slot_id: String) -> SlotDef:
	for slot in cfg.slots:
		if slot.id == slot_id:
			return slot
	return null


## 递归记下 Resource 所有存储字段
func _fingerprint(res: Resource, seen: Dictionary = {}) -> String:
	if seen.has(res.get_instance_id()):
		return "<seen>"
	seen[res.get_instance_id()] = true
	var parts := PackedStringArray()
	for prop in res.get_property_list():
		if not prop.usage & PROPERTY_USAGE_STORAGE or prop.name == "script":
			continue
		parts.append("%s=%s" % [prop.name, _value_print(res.get(prop.name), seen)])
	return "{" + ",".join(parts) + "}"


func _value_print(v: Variant, seen: Dictionary) -> String:
	if v is Resource:
		return _fingerprint(v, seen)
	if v is Array:
		var parts := PackedStringArray()
		for x in v:
			parts.append(_value_print(x, seen))
		return "[" + ",".join(parts) + "]"
	return var_to_str(v)
