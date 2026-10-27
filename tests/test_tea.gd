extends "res://tests/test_case.gd"
## 奶茶店：空店开局 → 前厅点解锁 → 招人上柜台 → 卖柠檬水 → 营业额到门槛自动开放后厨 →
## 布局模式一键部署 → 招人上调奶台 → 奶茶开卖 → 任务完成。


func saved_state(sim: GameSim) -> Dictionary:
	var service := SaveService.new("user://tea-roundtrip-test.json")
	check_eq(service.save({"shop": sim.to_dict()}), OK, "tea state writes to disk")
	var data := service.load_data()
	service.delete()
	return data.get("shop", {})


## 卖柠檬水攒到奶茶开放、钱够买后厨四台和第二个人
func earn_kitchen(sim: GameSim) -> void:
	for i in 6000:
		if sim.progress.kitchen_open() and sim.economy.gold >= 250 + sim.workforce.hire_cost():
			return
		sim.step()


func test_fresh_games_start_at_tea() -> void:
	var catalog: GameCatalog = load(CATALOG)
	check_eq(catalog.shops.size(), 1, "老面包店删掉了，只剩奶茶店")
	check_eq(catalog.shops[Profile.create(catalog).current_shop].id, "tea", "fresh games start at tea")


# 完整一轮：从空店到店铺完成，全程只用玩家命令。
func test_full_playthrough_from_empty_shop() -> void:
	var sim := make_sim()
	open_front(sim)
	check(not sim.progress.kitchen_open(), "开局后厨没开")
	earn_kitchen(sim)
	check(sim.progress.kitchen_open(), "卖柠檬水攒到门槛，奶茶自动开放")
	check(sim.economy.revenue >= 300, "门槛是累计营业额 300")
	check_eq(sim.front_hall.menu_stage, 0, "线没搭好前菜单还只有柠檬水")
	deploy(sim)
	var cook := hire(sim)
	sim.submit(AssignStaffCommand.new(cook, device_of(sim, "milk_station")))
	sim.step()
	check_eq(sim.front_hall.menu_stage, 1, "带子接到货架后奶茶上菜单")
	for i in 30:
		if sim.progress.completed:
			break
		sim.run_seconds(60.0)
	print("TEA PLAYTHROUGH %.0fs lemonade=%d tea=%d" % [sim.elapsed_seconds(), sim.progress.sold.get("lemonade", 0), sim.progress.sold.get("pearl_milk_tea", 0)])
	check(sim.progress.sold.get("pearl_milk_tea", 0) >= 20, "奶茶走完茶叶 → 茶汤 → 奶茶 → 加料整条线")
	check(sim.progress.sold.get("lemonade", 0) >= 30, "奶茶开放后柠檬水照常卖")
	check(sim.progress.completed, "菜单和任务都完成，店铺完成")


func test_save_resume_before_and_after_kitchen() -> void:
	var sim := make_sim()
	open_front(sim)
	sim.run_seconds(30.0)
	var closed := make_sim()
	closed.load_dict(saved_state(sim))
	check(not closed.last_snapshot.kitchen_open, "closed access survives reconstruction")
	check_eq(closed.workforce.staff[0].post, "counter", "the hired server keeps their post across a save")
	earn_kitchen(sim)
	deploy(sim)
	sim.submit(AssignStaffCommand.new(hire(sim), device_of(sim, "milk_station")))
	sim.run_seconds(45.0)
	var restored := make_sim()
	restored.load_dict(saved_state(sim))
	check(restored.last_snapshot.kitchen_open, "opened access derives from restored stage")
	check_eq(state_json(restored), state_json(sim), "full active production restores")
	sim.run_seconds(40.0)
	restored.run_seconds(40.0)
	check_eq(state_json(restored), state_json(sim), "restored simulation continues deterministically")


# 存档时正在布局模式：草稿不存，读回来是经营模式、什么都没买。
func test_saving_in_layout_mode_counts_as_cancel() -> void:
	var sim := make_sim(kitchen_copy())
	open_front(sim)
	var before := saved_state(sim)
	sim.submit(EnterLayoutCommand.new())
	sim.submit(AutoDeployCommand.new())
	sim.step()
	var during := saved_state(sim)
	check_eq(JSON.stringify(during), JSON.stringify(before), "布局模式里存档等于没进过布局模式")
	var restored := make_sim(kitchen_copy())
	restored.load_dict(during)
	check_eq(restored.mode, GameSim.Mode.BUSINESS, "读回来是经营模式")
	check(restored.layout.devices.is_empty(), "草稿里的设备没有生效")


func test_counter_serves_both_drinks_and_moving_the_cook_stops_the_line() -> void:
	var sim := running_tea()
	var cook := ""
	var milk := device_of(sim, "milk_station")
	for s in sim.workforce.staff:
		if s.post == milk:
			cook = s.staff_id
	check_eq(sim.front_hall.station_def("counter").dishes, ["lemonade", "pearl_milk_tea"], "every customer orders at the one counter")
	check_eq(sim.front_hall.post_capacity("counter"), 2, "the counter has room for a second server")
	sim.run_seconds(120.0)
	var before: int = sim.progress.sold.get("pearl_milk_tea", 0)
	check(before > 0, "the line sells milk tea")
	sim.submit(AssignStaffCommand.new(cook, "counter"))
	sim.run_seconds(200.0)
	var stalled: int = sim.progress.sold.get("pearl_milk_tea", 0)
	sim.run_seconds(200.0)
	check(sim.progress.sold.get("pearl_milk_tea", 0) - stalled <= 1, "nobody on the milk station: the line runs dry")
	check_eq(sim.workforce.post_occupancy("counter"), 2, "both servers now stand at the counter")
	sim.submit(AssignStaffCommand.new(cook, milk))
	sim.run_seconds(160.0)
	check(sim.progress.sold.get("pearl_milk_tea", 0) > stalled, "back on the milk station, the line resumes")


# 原料柜轮流出货：茶叶和牛奶都按需送到各自的设备，不会一种料堆满另一种饿死。
func test_cabinet_feeds_both_branches() -> void:
	var sim := running_tea()
	sim.run_seconds(300.0)
	var leaf := int(sim.diagnostics.item_flow.get("tea_leaf", {}).get("produced", 0))
	var milk := int(sim.diagnostics.item_flow.get("milk", {}).get("produced", 0))
	check(leaf > 0 and milk > 0, "两种料都出了：茶叶 %d，牛奶 %d" % [leaf, milk])
	check(milk > leaf, "一份茶叶煮 4 份茶汤，牛奶用得多，原料柜就多出牛奶")
	check(sim.progress.sold.get("pearl_milk_tea", 0) > 0, "两路都通，奶茶卖得出去")
