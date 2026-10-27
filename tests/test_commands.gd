extends "res://tests/test_case.gd"
## 第 5 节命令表：校验与提交顺序。


func test_upgrade_routes_to_owner_system() -> void:
	var sim := running_tea()
	sim.economy.gold = 1000
	sim.submit(UpgradeStationCommand.new("lemonade_stand"))
	sim.submit(UpgradeStationCommand.new(device_of(sim, "tea_brewer")))
	sim.step()
	var levels := {}
	for st in sim.front_hall.counters + sim.production.stations:
		levels[st.def_id] = st.level
	check_eq(levels.lemonade_stand, 2, "前厅位点由 FrontHall 升级")
	check_eq(levels.tea_brewer, 2, "后厨设备由 Production 升级")
	check_eq(sim.progress.station_levels.get("tea_brewer", 1), 2, "ShopProgress 收到等级事件")


func test_layout_commands_only_in_layout_mode() -> void:
	var sim := running_tea()
	var rejected := []
	sim.command_rejected.connect(func(_c: SimCommand, reason: String) -> void: rejected.append(reason))
	for command in [PlaceDeviceCommand.new("tea_brewer", Vector2i(0, 3)), MoveDeviceCommand.new("d1", Vector2i(0, 3)), RemoveDraftDeviceCommand.new("d1"), AutoDeployCommand.new(), ConfirmLayoutCommand.new(), CancelLayoutCommand.new()]:
		sim.submit(command)
	sim.step()
	check_eq(rejected.size(), 6, "经营模式里布局命令都被拒绝")
	rejected.clear()
	sim.submit(EnterLayoutCommand.new())
	sim.step()
	for command in [EnterLayoutCommand.new(), HireStaffCommand.new(), AssignStaffCommand.new(sim.workforce.staff[0].staff_id, ""), UpgradeStationCommand.new("lemonade_stand"), UnlockFrontSpotCommand.new("counter")]:
		sim.submit(command)
	sim.step()
	check_eq(rejected, ["布局模式中", "布局模式中", "布局模式中", "布局模式中", "布局模式中"], "布局模式里经营命令都被拒绝")


func test_place_and_remove_draft_device() -> void:
	var sim := make_sim(kitchen_copy())
	open_front(sim)
	sim.submit(EnterLayoutCommand.new())
	var rec: Dictionary = sim.config.grid.recommended[1]
	var place := PlaceDeviceCommand.new(String(rec.station), rec.cell)
	sim.submit(place)
	sim.step()
	check(place.device_id.begins_with("new"), "草稿里的设备先用临时 id")
	check_eq(sim.layout.draft_cost(), sim.config.device_def(String(rec.station)).price, "草稿总价算上它")
	sim.submit(RemoveDraftDeviceCommand.new(place.device_id))
	sim.step()
	check_eq(sim.layout.draft_cost(), 0, "拿回后草稿是空的")
	check(sim.layout.draft.devices.is_empty(), "设备回到设备栏")


func test_switch_shop_needs_completion() -> void:
	var sim := make_sim()
	check_eq(SwitchShopCommand.new().validate(sim), "店铺还没完成", "没完成不能换店")


func test_long_frame_catchup_is_capped() -> void:
	var sim := make_sim()
	sim._process(3600.0)
	check(sim.tick <= roundi(GameSim.MAX_CATCHUP_SECONDS / sim.step_seconds), "一帧只补跑有限的 tick：%d" % sim.tick)
	check(sim.tick > 0, "仍然会推进")
