extends "res://tests/test_case.gd"
## 奶茶店（固定产线方向，PXJ-49）：柜台货架开局就在 → 买柠檬茶台、招人 → 营业额够了整条奶茶线一次解锁 →
## 加料机（珍珠默认，升级依次开椰果 / 红豆 / 芋泥）→ 机器和每个物料槽按需升级。

const TEA := "res://content/tea/tea.tres"
const LINE := ["cabinet", "brewer", "milk_station"]


func tea() -> GameSim:
	return make_sim(load(TEA))


func saved_state(sim: GameSim) -> Dictionary:
	var service := SaveService.new("user://tea-roundtrip-test.json")
	check_eq(service.save({"shop": sim.to_dict()}), OK, "tea state writes to disk")
	var data := service.load_data()
	service.delete()
	return data.get("shop", {})


func hire(sim: GameSim, post: String) -> String:
	var command := HireStaffCommand.new()
	sim.submit(command)
	sim.step()
	sim.submit(AssignStaffCommand.new(command.staff_id, post))
	sim.step()
	return command.staff_id


## 开场：买柠檬茶台，招一个人拖到柜台（柜台开局就在）
func open_front(sim: GameSim) -> String:
	sim.submit(UnlockFrontSpotCommand.new("lemonade_stand"))
	sim.step()
	return hire(sim, "counter")


## 卖柠檬茶攒到门槛和线价，整条奶茶线一次解锁，再招一名后厨员工
func open_line(sim: GameSim) -> String:
	var stage: ShopStageDef = sim.config.progression.stages[1]
	for i in 6000:
		if sim.economy.revenue >= stage.revenue_threshold and sim.economy.gold >= stage.line_cost + sim.workforce.hire_cost():
			break
		sim.step()
	sim.submit(UnlockLineCommand.new())
	sim.step()
	check(sim.progress.kitchen_open(), "buying the milk tea line opens the kitchen")
	return hire(sim, "kitchen")


## 测试用：直接给钱给营业额，跳过攒钱
func fund(sim: GameSim, gold: int, revenue: int = 0) -> void:
	sim.economy.gold += gold
	sim.economy.revenue = maxi(sim.economy.revenue, revenue)


func status(sim: GameSim, slot_id: String) -> int:
	for st in sim.production.stations:
		if st.slot_id == slot_id:
			return st.status
	return -1


func station(sim: GameSim, slot_id: String) -> StationState:
	for st in sim.production.stations:
		if st.slot_id == slot_id:
			return st
	return null


func test_fresh_tea_and_legacy_bakery_identity() -> void:
	var catalog: GameCatalog = load(CATALOG)
	check_eq(catalog.shops[0].id, "bakery", "old save index zero is still bakery")
	check_eq(catalog.shops[Profile.create(catalog).current_shop].id, "tea", "fresh games start at tea")
	check(make_sim().progress.kitchen_open(), "bakery stage zero remains accessible")


# 首店流程稿 1–2：后厨空、柜台和货架开局就在、柠檬茶要花钱、开局只需买柠檬茶台和招人。
func test_opening_counter_is_there_and_lemonade_is_bought() -> void:
	var sim := tea()
	check(sim.front_hall.is_active("counter"), "the counter is there from the start")
	check(not sim.front_hall.is_active("lemonade_stand"), "the lemon tea stand is a price plate")
	for slot_id in LINE + ["topping"]:
		check_eq(status(sim, slot_id), StationState.Status.LOCKED, "the kitchen starts empty: " + slot_id)
	check(not sim.progress.kitchen_open(), "kitchen is closed before the line is bought")
	sim.submit(UnlockFrontSpotCommand.new("counter"))
	sim.step()
	check_eq(sim.economy.gold, 50, "the counter cannot be bought again")
	open_front(sim)
	check_eq(sim.economy.gold, 50 - 10 - 15, "stand 10 + first hire 15")
	sim.run_seconds(60.0)
	check(sim.progress.sold.get("lemonade", 0) > 0, "lemon tea sells with just the stand and one server")


# 首店流程稿 3：整条线一次点解锁，三台机器和传送带一起出现，不能单台买。
func test_milk_tea_line_unlocks_as_one_purchase() -> void:
	var sim := tea()
	open_front(sim)
	var stage: ShopStageDef = sim.config.progression.stages[1]
	fund(sim, 1000)
	check_eq(UnlockLineCommand.new().validate(sim), "累计营业额不足", "the line waits for the revenue gate")
	fund(sim, 0, stage.revenue_threshold)
	check_eq(UnlockStationCommand.new("brewer").validate(sim), "这条线要整条一起解锁", "single machines of the line cannot be bought")
	var before := sim.economy.gold
	sim.submit(UnlockLineCommand.new())
	sim.step()
	check_eq(sim.economy.gold, before - stage.line_cost, "the whole line costs its one price")
	for slot_id in LINE:
		check_eq(status(sim, slot_id), StationState.Status.ACTIVE, "machine appears with the line: " + slot_id)
	check_eq(status(sim, "topping"), StationState.Status.LOCKED, "the topping machine is a later unlock")
	check_eq(sim.progress.stage_index, 1, "milk tea stage reached")
	check_eq(sim.front_hall.menu_stage, 1, "hall uses the milk tea menu")
	check(UnlockLineCommand.new().validate(sim) != "", "the next line (topping) still needs its own gate")
	hire(sim, "kitchen")
	sim.run_seconds(240.0)
	check(sim.progress.sold.get("plain_milk_tea", 0) > 0, "plain milk tea runs cabinet → brewer → milk station → shelf")


# 原料柜：一个柜两个槽，一种料的下游满了不挡另一种（布局基线⑮）。
func test_cabinet_slot_backed_up_does_not_block_the_other() -> void:
	var sim := tea()
	fund(sim, 1000, 300)
	sim.submit(UnlockLineCommand.new())
	sim.step()
	# 断开茶叶那条带：茶叶在柜子出口堆满，牛奶照样送到调奶台
	sim.submit(SetConnectionCommand.new("cabinet", "brewer", false))
	sim.run_seconds(40.0)
	var cabinet := station(sim, "cabinet")
	check_eq(int(cabinet.outputs.get("tea_leaf", 0)), sim.production.station_def("cabinet").output_capacity, "tea leaves back up at the cabinet")
	check(int(station(sim, "milk_station").inputs.get("milk", 0)) > 0, "milk still reaches the milk station")
	check_eq(int(station(sim, "brewer").inputs.get("tea_leaf", 0)), 0, "nothing reaches the cut-off brewer")


# 物料槽升级：原料柜的茶叶槽 = 茶叶出货变快，牛奶槽不受影响；没钱、未知槽都是拒绝且不扣钱。
func test_cabinet_material_upgrade_speeds_only_that_raw() -> void:
	# 出口放大、下游断开，只看柜子自己每种料出多少
	var cfg: ShopConfig = load(TEA).duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	for slot in cfg.slots:
		if slot.id == "cabinet":
			slot.station.output_capacity = 1000
	var counts := []
	for upgraded in [false, true]:
		var sim := make_sim(cfg)
		fund(sim, 1000, 300)
		sim.submit(UnlockLineCommand.new())
		sim.submit(SetConnectionCommand.new("cabinet", "brewer", false))
		sim.submit(SetConnectionCommand.new("cabinet", "milk_station", false))
		sim.step()
		if upgraded:
			var gold := sim.economy.gold
			var cost := sim.production.material_upgrade_cost("cabinet", "tea_leaf")
			sim.submit(UpgradeMaterialCommand.new("cabinet", "tea_leaf"))
			sim.step()
			check_eq(sim.economy.gold, gold - cost, "the slot upgrade costs its price")
			check_eq(station(sim, "cabinet").mat_level("tea_leaf"), 2, "tea leaf slot is Lv2")
			check_eq(station(sim, "cabinet").mat_level("milk"), 1, "milk slot untouched")
		sim.run_seconds(60.0)
		var out := station(sim, "cabinet").outputs
		counts.append([int(out.get("tea_leaf", 0)), int(out.get("milk", 0))])
	check(counts[1][0] > counts[0][0], "upgraded tea leaf slot releases more tea leaves (%d > %d)" % [counts[1][0], counts[0][0]])
	check(absi(counts[1][1] - counts[0][1]) <= 1, "milk output unchanged (%d vs %d)" % [counts[1][1], counts[0][1]])
	var poor := tea()
	fund(poor, 240, 300)
	poor.submit(UnlockLineCommand.new())
	poor.step()
	check_eq(poor.economy.gold, 50, "line bought with exact money")
	poor.economy.gold = 5
	var before := state_json(poor)
	poor._run_command(UpgradeMaterialCommand.new("cabinet", "tea_leaf"))
	check_eq(state_json(poor), before, "an unaffordable slot upgrade changes nothing")
	check(UpgradeMaterialCommand.new("cabinet", "sugar").validate(poor) != "", "an unknown slot is rejected")


# 加料机：接上以后原味奶茶改走加料机；默认只有珍珠；升级依次开椰果、红豆、芋泥。
func test_topping_machine_starts_with_pearl_and_upgrades_open_flavors() -> void:
	var sim := tea()
	open_front(sim)
	fund(sim, 5000, 300)
	sim.submit(UnlockLineCommand.new())
	sim.step()
	hire(sim, "kitchen")
	check_eq(UnlockLineCommand.new().validate(sim), "累计营业额不足", "topping machine has its own revenue gate")
	fund(sim, 0, sim.config.progression.stages[2].revenue_threshold)
	sim.submit(UnlockLineCommand.new())
	sim.step()
	check_eq(status(sim, "topping"), StationState.Status.ACTIVE, "topping machine bought")
	check_eq(sim.progress.stage_index, 2, "topping stage reached")
	var available := sim.production.available_items()
	check(available.has("pearl_milk_tea"), "pearl is there by default")
	check(not available.has("coconut_milk_tea"), "coconut waits for machine Lv2")
	check(UpgradeMaterialCommand.new("topping", "coconut").validate(sim).contains("Lv2"), "a closed flavor slot cannot be upgraded")
	var plain_before := 0
	for seg in sim.production.segments:
		if seg.id == "milk_to_shelf":
			plain_before = seg.items.size()
	sim.run_seconds(60.0)
	var plain_on_belt := 0
	for seg in sim.production.segments:
		if seg.id == "milk_to_shelf":
			plain_on_belt = seg.items.size()
	check(plain_on_belt <= plain_before, "plain milk tea stops going straight to the shelf")
	check(sim.progress.sold.get("pearl_milk_tea", 0) > 0, "pearl milk tea sells")
	var order := ["coconut", "redbean", "taro"]
	for i in order.size():
		sim.submit(UpgradeStationCommand.new("topping"))
		sim.step()
		check(sim.production.available_items().has(sim.production.station_def("topping").material(order[i]).item_id), "machine Lv%d opens %s" % [i + 2, order[i]])
	sim.run_seconds(200.0)
	for flavor in ["pearl_milk_tea", "coconut_milk_tea", "redbean_milk_tea", "taro_milk_tea"]:
		check(sim.progress.sold.get(flavor, 0) > 0, "every opened flavor gets sold: " + flavor)
	check(sim.progress.done_tasks.has("topping4"), "the Lv4 topping task completes")


# 每个口味货架格上限 3（含在途），满了跳过、全满就停；没人卖时不会无限囤。
func test_flavor_cap_counts_in_flight_and_skips_full_flavors() -> void:
	var sim := tea()
	fund(sim, 5000, 1500)
	sim.submit(UnlockLineCommand.new())
	sim.step()
	sim.submit(UnlockLineCommand.new())
	sim.step()
	sim.submit(UpgradeStationCommand.new("topping"))
	sim.step()
	hire(sim, "kitchen")
	# 柜台没人：只做不卖
	sim.run_seconds(400.0)
	var cap := sim.production.station_def("topping").flavor_cap
	for item in ["pearl_milk_tea", "coconut_milk_tea"]:
		check(sim.production._in_flight(item) <= cap, "%s never exceeds %d including belts" % [item, cap])
		check_eq(int(sim.production.shelf.get(item, 0)), cap, "%s fills its shelf cell" % item)
	check_eq(int(sim.production.shelf.get("redbean_milk_tea", 0)), 0, "a closed flavor is never made")
	check_eq(station(sim, "topping").phase, StationState.Phase.IDLE, "all opened flavors full: the topping machine stops")


# 配料槽升级 = 这个口味涨价，结算时按等级算。
func test_topping_slot_upgrade_raises_that_flavor_price() -> void:
	var sim := tea()
	open_front(sim)
	fund(sim, 5000, 1500)
	sim.submit(UnlockLineCommand.new())
	sim.step()
	sim.submit(UnlockLineCommand.new())
	sim.step()
	hire(sim, "kitchen")
	for i in 2:
		sim.submit(UpgradeMaterialCommand.new("topping", "pearl"))
		sim.step()
	var pearl := sim.production.station_def("topping").material("pearl")
	check_eq(station(sim, "topping").mat_level("pearl"), 3, "pearl slot at Lv3")
	var amounts := []
	sim.sale_settled.connect(func(_id: int, amount: int) -> void: amounts.append(amount))
	var dish_price := 0
	for dish in preload("res://content/tea/tea.tres").dishes:
		if dish.id == "pearl_milk_tea": dish_price = dish.price
	sim.run_seconds(200.0)
	check(roundi(dish_price * pearl.bonus(3)) in amounts, "pearl sells at the upgraded price %d" % roundi(dish_price * pearl.bonus(3)))
	check(not dish_price in amounts, "no pearl sale at the old base price")


# 顾客只点现在能做的：加料机开之前不点珍珠，开了以后不点还没开放的口味。
func test_customers_only_order_what_the_shop_can_make() -> void:
	var sim := tea()
	open_front(sim)
	open_line(sim)
	var ordered := {}
	sim.run_seconds(120.0)
	for o in sim.front_hall.orders:
		ordered[o.dish_id] = true
	fund(sim, 2000, 1500)
	sim.submit(UnlockLineCommand.new())
	sim.step()
	var later := {}
	for i in 1500:
		sim.step()
		for e in sim._events:
			if e.type == "customer_arrived":
				later[e.dish] = true
	check(not ordered.has("pearl_milk_tea"), "no pearl orders before the topping machine")
	check(later.has("pearl_milk_tea"), "pearl orders arrive once it is made")
	for dish in ["coconut_milk_tea", "redbean_milk_tea", "taro_milk_tea"]:
		check(not later.has(dish), "a closed flavor is never ordered: " + dish)


func test_save_resume_keeps_line_flavors_and_slot_levels() -> void:
	var sim := tea()
	open_front(sim)
	fund(sim, 5000, 1500)
	sim.submit(UnlockLineCommand.new())
	sim.step()
	hire(sim, "kitchen")
	sim.submit(UnlockLineCommand.new())
	sim.submit(UpgradeMaterialCommand.new("cabinet", "milk"))
	sim.step()
	sim.submit(UpgradeStationCommand.new("topping"))
	sim.submit(UpgradeMaterialCommand.new("topping", "pearl"))
	sim.run_seconds(47.3)
	var restored := make_sim(load(TEA))
	restored.load_dict(saved_state(sim))
	check_eq(state_json(restored), state_json(sim), "line, slot levels and the cup being topped restore")
	sim.run_seconds(60.0)
	restored.run_seconds(60.0)
	check_eq(state_json(restored), state_json(sim), "restored shop continues deterministically")


# 不操作优化也能把店做完（只买必要的东西 + 升加料机到 Lv4），顺带打印节奏
func test_shop_completes_with_plain_play() -> void:
	var sim := tea()
	open_front(sim)
	open_line(sim)
	var topping_at := -1.0
	for i in 30000:
		sim.step()
		if sim.progress.stage_index == 1 and UnlockLineCommand.new().validate(sim) == "":
			sim.submit(UnlockLineCommand.new())
			topping_at = sim.elapsed_seconds()
		elif sim.progress.stage_index == 2 and UpgradeStationCommand.new("topping").validate(sim) == "":
			sim.submit(UpgradeStationCommand.new("topping"))
		if sim.progress.completed:
			break
	print("TEA PACE topping=%ds done=%ds revenue=%d gold=%d" % [int(topping_at), int(sim.elapsed_seconds()), sim.economy.revenue, sim.economy.gold])
	check(topping_at > 0, "the topping machine gets bought")
	check(sim.progress.completed, "the shop completes without optimising")
