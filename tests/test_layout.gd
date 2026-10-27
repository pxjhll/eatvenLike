extends "res://tests/test_case.gd"
## PXJ-47 布局模式：摆放规则、原料卡位、一键部署、自动铺带、确认与改布局。


func _in_layout(gold: int = 2000) -> GameSim:
	var sim := make_sim(kitchen_copy(gold))
	open_front(sim)
	sim.submit(EnterLayoutCommand.new())
	sim.step()
	check_eq(sim.mode, GameSim.Mode.LAYOUT, "进入布局模式")
	return sim


func test_kitchen_waits_for_the_milk_tea_stage() -> void:
	var sim := make_sim()
	open_front(sim)
	check(not sim.progress.kitchen_open(), "开店时后厨还没开放")
	check_eq(EnterLayoutCommand.new().validate(sim), "解锁新菜后开放后厨", "进不了布局模式")
	sim.economy.revenue = 299
	sim.step()
	check(not sim.progress.kitchen_open(), "营业额差一点不开放")
	sim.economy.revenue = 300
	sim.step()
	check(sim.progress.kitchen_open(), "营业额到门槛自动开放，不用买东西")
	check_eq(sim.progress.open_devices(), ["supply_cabinet", "tea_brewer", "milk_station", "topping_station"], "奶茶阶段开放四台后厨设备")
	check_eq(sim.front_hall.menu_stage, 0, "线还没搭，奶茶不上菜单")


func test_placement_rules() -> void:
	var sim := _in_layout()
	var layout := sim.layout
	check_eq(layout.validate_place("tea_brewer", Vector2i(5, 0)), "超出后厨", "2×2 的煮茶机放不进最右一列")
	check_eq(layout.validate_place("milk_station", Vector2i(1, 0)), "超出后厨", "调奶台的工位格也要在后厨里")
	check_eq(layout.validate_place("tea_brewer", sim.config.grid.shelf_cell - Vector2i(1, 1)), "挡住了通往货架的位置", "不能压住货架口")
	check_eq(layout.validate_place("supply_cabinet", Vector2i(2, 2)), "原料柜要贴着墙放", "原料柜只能贴合法的墙")
	check_eq(layout.validate_place("supply_cabinet", Vector2i(0, 0)), "原料柜要贴着墙放", "墙角不能放原料柜")
	check_eq(layout.validate_place("no_such_device", Vector2i(2, 2)), "没有这种设备", "未知设备")
	sim.submit(PlaceDeviceCommand.new("tea_brewer", Vector2i(2, 2)))
	sim.step()
	check_eq(layout.validate_place("topping_station", Vector2i(3, 3)), "和别的设备重叠", "不能叠在别的设备上")


# 原料卡位（决定⑮）：首店 4 个，一台原料柜 2 个槽占 2 个，第三台放不下。
func test_supply_slot_limit() -> void:
	var sim := _in_layout()
	var placed := 0
	for x in range(1, 5):
		var cmd := PlaceDeviceCommand.new("supply_cabinet", Vector2i(x, 0))
		if cmd.validate(sim) == "":
			sim.submit(cmd)
			sim.step()
			placed += 1
	check_eq(placed, 2, "上墙只够放两台原料柜，正好占满 4 个卡位")
	sim.submit(CancelLayoutCommand.new())
	sim.step()
	var cfg := kitchen_copy()
	cfg.grid.supply_wall_cells.append_array([Vector2i(0, 4), Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4)])
	var wide := make_sim(cfg)
	open_front(wide)
	wide.submit(EnterLayoutCommand.new())
	for c in [Vector2i(1, 0), Vector2i(3, 0)]:
		wide.submit(PlaceDeviceCommand.new("supply_cabinet", c))
	wide.step()
	check_eq(wide.layout.validate_place("supply_cabinet", Vector2i(0, 4)), "原料卡位不够", "墙够长也只能放到卡位上限")


func test_auto_deploy_builds_the_recommended_line() -> void:
	var sim := _in_layout()
	sim.submit(AutoDeployCommand.new())
	sim.step()
	var draft: Array = sim.layout.draft.devices
	check_eq(draft.size(), 4, "四台设备都放到了推荐位")
	for rec in sim.config.grid.recommended:
		var found := false
		for d in draft:
			found = found or (d.def == rec.station and d.cell == rec.cell)
		check(found, "推荐位上有 %s" % rec.station)
	var route := sim.layout.draft_route()
	check(route.failed.is_empty(), "推荐摆法的带子全部铺得通：%s" % [route.failed])
	var links := []
	for b in route.belts:
		links.append("%s>%s" % [_def_of(sim, b.from), _def_of(sim, b.to) if b.to != BeltRouter.SHELF else "shelf"] + ":" + b.item)
	links.sort()
	check_eq(links, ["milk_station>topping_station:milk_tea", "supply_cabinet>milk_station:milk", "supply_cabinet>tea_brewer:tea_leaf", "tea_brewer>milk_station:tea_soup", "topping_station>shelf:pearl_milk_tea"], "按物品推出上下游，一种料一路")
	# 原料柜的两路从同一个出口出来，开头那一段是共用的主带
	var trunk := []
	for b in route.belts:
		if _def_of(sim, b.from) == "supply_cabinet":
			trunk.append(b.path[0])
	check(trunk.size() == 2 and trunk[0] == trunk[1], "原料柜两路从同一格出发")
	var again := AutoDeployCommand.new()
	sim.submit(again)
	sim.step()
	check(again.placed.is_empty(), "已经摆了的设备不会再部署一台")


func test_confirm_applies_layout_and_menu_waits_for_the_line() -> void:
	var sim := _in_layout()
	sim.submit(PlaceDeviceCommand.new("supply_cabinet", sim.config.grid.recommended[0].cell))
	sim.submit(ConfirmLayoutCommand.new())
	sim.step()
	check_eq(sim.production.stations.size(), 1, "确认后只有一台原料柜")
	check_eq(sim.front_hall.menu_stage, 0, "线没通到货架，奶茶不上菜单")
	sim.run_seconds(10.0)
	check(sim.production.count_items().is_empty(), "没有下游的原料柜不出货")
	var added := deploy(sim)
	check_eq(added.size(), 3, "第二次部署补上其余三台")
	check_eq(sim.front_hall.menu_stage, 1, "带子接到货架，奶茶上菜单")
	check_eq(sim.production.segments.size(), 5, "五条带子都铺好了")
	var cook := hire(sim)
	sim.submit(AssignStaffCommand.new(cook, device_of(sim, "milk_station")))
	sim.run_seconds(120.0)
	check(sim.progress.sold.get("pearl_milk_tea", 0) > 0, "奶茶卖出去了")


func test_existing_devices_cannot_be_taken_back_but_can_move() -> void:
	# 首店 6×5 照推荐位摆满后几乎没有挪的余地，这里把后厨放大一圈只为测挪动
	var cfg := kitchen_copy()
	cfg.grid.kitchen_rect = Rect2i(0, 0, 8, 6)
	var sim := running_tea(cfg)
	sim.run_seconds(60.0)
	var topping := device_of(sim, "topping_station")
	var milk := device_of(sim, "milk_station")
	sim.submit(UpgradeStationCommand.new(topping))
	sim.step()
	var on_belts := 0
	for seg in sim.production.segments:
		on_belts += seg.items.size()
	check(on_belts > 0, "改布局前带子上有物料")
	sim.submit(EnterLayoutCommand.new())
	sim.step()
	check_eq(RemoveDraftDeviceCommand.new(milk).validate(sim), "已经摆好的设备不能在这里拿掉", "已生效的设备不能拿回")
	var start: Vector2i = sim.config.grid.recommended[3].cell
	var target := Vector2i(-1, -1)
	for y in 6:
		for x in 8:
			var cell := Vector2i(x, y)
			if target.x >= 0 or cell == start or sim.layout.validate_move(topping, cell) != "":
				continue
			sim.layout.draft_move(topping, cell)
			if sim.layout.draft_route().failed.is_empty():
				target = cell
	check(target.x >= 0, "找到一个能挪过去、带子也铺得通的位置")
	var produced := {}
	for item in sim.diagnostics.item_flow:
		produced[item] = sim.diagnostics.expected_on_field(item)
	var counts := sim.production.count_items()
	sim.layout.discard_draft()
	sim.layout.begin_draft()
	sim.submit(MoveDeviceCommand.new(topping, target))
	sim.submit(ConfirmLayoutCommand.new())
	sim.step()
	check_eq(device_of(sim, "topping_station"), topping, "挪过的设备保留实例 id")
	for d in sim.layout.devices:
		if d.id == topping:
			check_eq(d.cell, target, "设备到了新位置")
	for st in sim.production.stations:
		if st.slot_id == topping:
			check_eq(st.level, 2, "挪动不丢等级")
	for item in ["tea_leaf", "milk", "tea_soup", "milk_tea", "pearl_milk_tea"]:
		check_eq(int(sim.production.count_items().get(item, 0)), sim.diagnostics.expected_on_field(item), "带上的物料退回上游，一件不少：" + item)
	var staffed := false
	for s in sim.workforce.staff:
		staffed = staffed or s.post == milk
	check(staffed, "调奶台上的人还在岗")
	check(counts.size() > 0 and produced.size() > 0, "改之前场上有物料")


func test_unreachable_belt_blocks_confirm() -> void:
	var sim := _in_layout()
	# 煮茶机塞在左上角，入口朝着墙外，茶叶那一路铺不通
	sim.submit(PlaceDeviceCommand.new("supply_cabinet", Vector2i(3, 0)))
	sim.submit(PlaceDeviceCommand.new("tea_brewer", Vector2i(0, 0)))
	sim.step()
	var route := sim.layout.draft_route()
	check(not route.failed.is_empty(), "确实有一路铺不通")
	check_eq(ConfirmLayoutCommand.new().validate(sim), "有传送带铺不通", "铺不通的布局不能确认")
	check_eq(sim.last_snapshot.layout.draft.failed.size(), route.failed.size(), "快照里能看到哪路不通")


func _def_of(sim: GameSim, id: String) -> String:
	for d in sim.layout.draft.devices if sim.layout.in_draft() else sim.layout.devices:
		if d.id == id:
			return d.def
	return id
