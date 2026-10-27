extends "res://tests/test_case.gd"
## 契约第 6 节的 14 条不变量，每条一个固定种子的回归场景。

const Cases := preload("res://tests/fixtures/production_cases.gd")


# 1. 销售只结算一次
func test_1_sale_settles_once() -> void:
	var eco := EconomySystem.new()
	check(eco.settle(7, 10), "第一次结算成功")
	check(not eco.settle(7, 10), "同一 saleId 第二次无效果")
	check_eq(eco.revenue, 10, "营业额只加一次")
	var sim := running_tea()
	sim.run_seconds(120.0)
	var expected := int(sim.progress.sold.get("lemonade", 0)) * 12 + int(sim.progress.sold.get("pearl_milk_tea", 0)) * 24
	check(sim.progress.sold.get("pearl_milk_tea", 0) > 0, "奶茶真的卖出去了")
	check_eq(sim.economy.revenue, expected, "模拟里每份只结算一次")


# 2. 消费金币不倒扣累计营业额
func test_2_spend_keeps_revenue() -> void:
	var sim := running_tea()
	sim.run_seconds(60.0)
	var revenue := sim.economy.revenue
	var gold := sim.economy.gold
	sim.submit(UpgradeStationCommand.new(device_of(sim, "tea_brewer")))
	sim.step()
	var earned := sim.economy.revenue - revenue
	check_eq(sim.economy.gold, gold - 40 + earned, "金币扣掉升级费")
	check(sim.economy.revenue >= revenue, "营业额没被扣")


# 3. 缺料订单不永久占死员工
func test_3_stockout_does_not_hold_staff() -> void:
	var cfg := kitchen_copy()
	cfg.device_def("supply_cabinet").supply_interval = 1000000.0
	cfg.progression.stages[1].order_weights = {"pearl_milk_tea": 1.0}
	var sim := running_tea(cfg)
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
	var sim := running_tea()
	sim.run_seconds(30.0)
	var before := state_json(sim)
	var snap := sim.last_snapshot
	snap.gold = 999999
	snap.production.shelf["pearl_milk_tea"] = 99
	snap.production.stations[0].level = 9
	snap.workforce.staff[0].post = "nowhere"
	snap.layout.devices[0].cell = [9, 9]
	snap.layout.belts[0].path.clear()
	check_eq(state_json(sim), before, "改快照不影响模拟状态")


# 5. 物料守恒（含中途改布局：带上的物料退回上游出口）
func test_5_material_conserved() -> void:
	var sim := running_tea()
	var brewer := device_of(sim, "tea_brewer")
	for i in 3000:
		if i == 900:
			_shift_brewer(sim, brewer)
		sim.step()
		if i % 10 == 0:
			_check_conservation(sim, i)
	check(sim.progress.sold.get("pearl_milk_tea", 0) > 0, "改布局前后都在卖奶茶")


## 把煮茶机连同下游挪一挪：不改变连接关系，但带子全部重铺
func _shift_brewer(sim: GameSim, brewer: String) -> void:
	sim.submit(EnterLayoutCommand.new())
	sim.step()
	for d in sim.layout.draft.devices:
		for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if d.id == brewer and sim.layout.validate_move(brewer, d.cell + dir) == "":
				sim.layout.draft_move(brewer, d.cell + dir)
				if sim.layout.draft_route().failed.is_empty():
					break
				sim.layout.draft_move(brewer, d.cell - dir)
	sim.submit(ConfirmLayoutCommand.new())
	sim.step()


func _check_conservation(sim: GameSim, i: int) -> void:
	var field := sim.production.count_items()
	for item in ["tea_leaf", "milk", "tea_soup", "milk_tea", "pearl_milk_tea"]:
		check_eq(int(field.get(item, 0)), sim.diagnostics.expected_on_field(item), "tick %d 物料 %s 守恒" % [i, item])
	var reserved := {}
	for order_id in sim.production.reservations:
		var r: Dictionary = sim.production.reservations[order_id]
		reserved[r.item] = int(reserved.get(r.item, 0)) + r.count
	for item in reserved:
		check(reserved[item] <= int(sim.production.shelf.get(item, 0)), "tick %d 预留不超过货架库存" % i)


# 6. 命令原子性：被拒绝的命令不改变任何状态
func test_6_rejected_command_changes_nothing() -> void:
	var cfg := kitchen_copy(400)
	var a := running_tea(cfg)
	var b := running_tea(cfg)
	var reasons := []
	b.command_rejected.connect(func(_c: SimCommand, reason: String) -> void: reasons.append(reason))
	a.run_seconds(20.0)
	b.run_seconds(20.0)
	b.submit(UpgradeStationCommand.new("no_such_slot"))
	b.submit(PlaceDeviceCommand.new("tea_brewer", Vector2i(0, 0)))   # 不在布局模式
	b.submit(ConfirmLayoutCommand.new())                              # 不在布局模式
	b.submit(AssignStaffCommand.new(b.workforce.staff[0].staff_id, device_of(b, "tea_brewer")))  # 全自动设备不要人
	a.run_seconds(20.0)
	b.run_seconds(20.0)
	check_eq(reasons, ["没有这个工位", "不在布局模式", "不在布局模式", "这个工位不要员工"], "四条命令都被拒绝")
	check_eq(state_json(b), state_json(a), "被拒绝的命令没有改变任何状态")
	# 布局模式里的经营命令、放不下的设备、钱不够的确认，也都整条拒绝
	var c := make_sim(kitchen_copy(400))
	var d := make_sim(kitchen_copy(400))
	for sim in [c, d]:
		open_front(sim)
		sim.submit(EnterLayoutCommand.new())
		sim.submit(AutoDeployCommand.new())
		sim.step()
		sim.economy.gold = 10
	reasons.clear()
	d.command_rejected.connect(func(_c: SimCommand, reason: String) -> void: reasons.append(reason))
	d.submit(UpgradeStationCommand.new("lemonade_stand"))
	d.submit(HireStaffCommand.new())
	d.submit(PlaceDeviceCommand.new("tea_brewer", Vector2i(-1, 0)))
	d.submit(EnterLayoutCommand.new())
	d.submit(ConfirmLayoutCommand.new())
	c.step()
	d.step()
	check_eq(reasons, ["布局模式中", "布局模式中", "超出后厨", "布局模式中", "金币不足"], "布局模式里不合法的命令都被拒绝")
	check_eq(state_json(d), state_json(c), "被拒绝的布局命令没有改变任何状态")
	check_eq(JSON.stringify(d.layout.snapshot()), JSON.stringify(c.layout.snapshot()), "草稿也没变")


# 7. 一人一任务，一个请求只被一名员工认领
func test_7_one_staff_one_task() -> void:
	var sim := running_tea()
	var server := sim.workforce.staff[0].staff_id
	var second := hire(sim)
	sim.submit(AssignStaffCommand.new(second, "counter"))
	for i in 2000:
		if i == 600:
			sim.submit(AssignStaffCommand.new(server, ""))
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
	var cfg: ShopConfig = load(TEA)
	var before := _fingerprint(cfg)
	var sim := make_sim(cfg)
	open_front(sim)
	sim.economy.revenue = 300
	sim.economy.gold = 5000
	sim.step()
	deploy(sim)
	sim.submit(AssignStaffCommand.new(hire(sim), device_of(sim, "milk_station")))
	sim.submit(UpgradeStationCommand.new(device_of(sim, "tea_brewer")))
	sim.submit(UpgradeStationCommand.new("lemonade_stand"))
	sim.run_seconds(300.0)
	check(sim.progress.sold.get("pearl_milk_tea", 0) > 0, "用磁盘上的配置跑到了奶茶")
	check_eq(_fingerprint(cfg), before, "跑完模拟后 .tres 字段完全没变")
	var levels := {}
	for st in sim.production.stations:
		levels[st.def_id] = st.level
	check_eq(levels.tea_brewer, 2, "升级的那台到 Lv2")
	check_eq(levels.milk_station, 1, "别的设备不受影响")


# 9. 步长无关：改变步长不改变每秒产量和收入（允许不到一件的取整误差）
func test_9_step_independent() -> void:
	var results := {}
	for step in [0.05, 0.1]:
		var sim := running_tea(null, step)
		sim.run_seconds(600.0)
		results[step] = {"tea": Cases.produced(sim, "pearl_milk_tea"), "revenue": sim.economy.revenue}
	var base: Dictionary = results[0.1]
	for step in results:
		var r: Dictionary = results[step]
		check(absi(r.tea - base.tea) <= 2, "步长 %s 奶茶产量 %d vs %d" % [step, r.tea, base.tea])
		check(absi(r.revenue - base.revenue) <= 60, "步长 %s 收入 %d vs %d" % [step, r.revenue, base.revenue])


# 10. 存读档无损：一口气跑 N 秒 == 跑一半 → 存档（JSON）→ 读档 → 再跑一半
func test_10_save_load_lossless() -> void:
	var straight := running_tea()
	var first := running_tea()
	for sim in [straight, first]:
		sim.submit(UpgradeStationCommand.new(device_of(sim, "tea_brewer")))
		sim.run_seconds(150.0)
	var json := state_json(first)
	var save_text := JSON.stringify(SaveUtil.encode_floats(first.to_dict()), "", false)
	var resumed := make_sim(kitchen_copy())
	resumed.load_dict(SaveUtil.decode_floats(JSON.parse_string(save_text)))
	check_eq(state_json(resumed), json, "读档后状态与存档时一致")
	straight.run_seconds(150.0)
	resumed.run_seconds(150.0)
	check_eq(state_json(resumed), state_json(straight), "读档后继续跑，与不中断的结果完全一致")


# 11. 布局模式冻结时间：不走 tick，不推进任何系统
func test_11_layout_mode_freezes_time() -> void:
	var sim := running_tea()
	sim.run_seconds(30.0)
	sim.submit(EnterLayoutCommand.new())
	sim.step()
	var before := state_json(sim)
	var tick := sim.tick
	sim.run_seconds(60.0)
	check_eq(sim.tick, tick, "布局模式里 tick 不走")
	check_eq(state_json(sim), before, "布局模式里订单、加工、员工都不动")
	check_eq(sim.last_snapshot.mode, GameSim.Mode.LAYOUT, "快照显示布局模式")


# 12. 取消布局没有副作用
func test_12_cancel_layout_has_no_side_effects() -> void:
	var sim := running_tea()
	sim.run_seconds(30.0)
	var twin := make_sim(kitchen_copy())
	twin.load_dict(sim.to_dict())
	sim.submit(EnterLayoutCommand.new())
	sim.step()
	var brewer := device_of(sim, "tea_brewer")
	var moved := false
	for y in 5:
		for x in 6:
			if not moved and sim.layout.validate_move(brewer, Vector2i(x, y)) == "":
				sim.submit(MoveDeviceCommand.new(brewer, Vector2i(x, y)))
				moved = true
	sim.submit(PlaceDeviceCommand.new("topping_station", _free_cell(sim, "topping_station")))
	sim.step()
	check(sim.layout.draft_cost() > 0, "草稿里确实多了一台新设备")
	sim.submit(CancelLayoutCommand.new())
	sim.step()
	twin.step()
	check_eq(sim.mode, GameSim.Mode.BUSINESS, "取消后回到经营模式")
	check_eq(state_json(sim), state_json(twin), "取消后和没进过布局模式的店完全一样（只多走了取消那一个 tick）")


# 13. 草稿不花钱：摆多少都不扣，确认时一次扣草稿总价
func test_13_draft_costs_nothing_until_confirm() -> void:
	var sim := make_sim(kitchen_copy(1000))
	open_front(sim)
	var gold := sim.economy.gold
	sim.submit(EnterLayoutCommand.new())
	sim.submit(AutoDeployCommand.new())
	sim.step()
	check_eq(sim.economy.gold, gold, "一键部署不扣钱")
	check_eq(sim.layout.draft_cost(), 250, "草稿总价 = 四台设备的买价")
	check_eq(sim.last_snapshot.layout.draft.cost, 250, "快照里有草稿总价")
	sim.submit(ConfirmLayoutCommand.new())
	sim.step()
	check_eq(sim.economy.gold, gold - 250, "确认时一次扣清")


# 14. 自动铺带是确定的：同样的布局总铺出同样的带子，存读档后不变
func test_14_belt_routing_is_deterministic() -> void:
	var a := running_tea()
	var b := running_tea()
	check_eq(JSON.stringify(a.layout.to_dict()), JSON.stringify(b.layout.to_dict()), "两次部署铺出同样的带子")
	var again := BeltRouter.route(a.config, a.layout.devices)
	var paths := []
	for belt in again.belts:
		paths.append([belt.from, belt.to, belt.item, belt.path])
	var applied := []
	for belt in a.layout.belts:
		applied.append([belt.from, belt.to, belt.item, belt.path])
	check_eq(paths, applied, "对生效布局重算一遍，结果一样")
	var resumed := make_sim(kitchen_copy())
	resumed.load_dict(a.to_dict())
	check_eq(JSON.stringify(resumed.layout.to_dict()), JSON.stringify(a.layout.to_dict()), "读档后带子不变")


## 后厨里第一个能放下这台设备的格
func _free_cell(sim: GameSim, def_id: String) -> Vector2i:
	for y in 5:
		for x in 6:
			if sim.layout.validate_place(def_id, Vector2i(x, y)) == "":
				return Vector2i(x, y)
	return Vector2i(-1, -1)


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
