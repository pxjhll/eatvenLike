extends "res://tests/test_case.gd"
## 通用店铺数据（规格 §4）和 main 73b0ae3 旧模拟逐项对数：售价、升级价格、等级上限、秒数、每锅份数、
## 封口位、星级、传单、座位、员工、阶段、任务、履约常量。奶茶店旧模拟退役前（第 5 个 PR）这组用例一直保留。
## 煎饼摊旧模拟已在第 4 个 PR 删掉，它的数据由整店回放对照基准（test_shop_rules）。

const TeaSim := preload("res://game/tea_playtest/tea_shop_sim.gd")
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
const PANCAKE: SpecShop = preload("res://content/shops/pancake/shop.tres")
const CAMPAIGN: SpecCampaign = preload("res://content/campaign/campaign.tres")


func _level_track(shop: SpecShop, station_id: String) -> SpecUpgradeTrack:
	return shop.station(station_id).track("level")


# ---------- 奶茶店 ----------

func test_tea_upgrade_costs_and_max_levels_match_old_sim() -> void:
	var sim = TeaSim.new()
	for id in ["lemonade", "boil", "mix", "topping", "press", "seal"]:
		var t := _level_track(TEA, id)
		check_eq(t.max_level(), sim._max_level(id), "%s 最高级" % id)
		var old: Array = sim._upgrade_costs(id)
		for lv in range(1, t.max_level()):
			check_eq(t.cost(lv), int(old[lv - 1]), "%s Lv%d→%d 价格" % [id, lv, lv + 1])
		check_eq(t.cost(t.max_level()), -1, "%s 满级没有价格" % id)
	for pair in [["supply", "tea_leaf"], ["supply", "milk"], ["topping", "pearl"], ["topping", "coconut"],
			["topping", "redbean"], ["topping", "taro"], ["press", "lemon"]]:
		var material := TEA.station(pair[0]).material(pair[1])
		check(material != null, "%s/%s 存在" % pair)
		if material == null: continue
		check_eq(material.track.max_level(), sim._material_max(pair[0], pair[1]), "%s/%s 最高级" % pair)
		var old: Array = sim._material_costs(pair[0], pair[1])
		for lv in range(1, material.track.max_level()):
			check_eq(material.track.cost(lv), int(old[lv - 1]), "%s/%s Lv%d 价格" % [pair[0], pair[1], lv])


func test_tea_box_costs_and_unlock_costs_match_old_sim() -> void:
	var sim = TeaSim.new()
	for material in TEA.station("supply").materials:
		var old = sim._box_def(material.id)
		check_eq(material.box_cost, old.box_cost, material.id + " 原料箱价格")
		check_eq(material.box_station, sim._canonical(old.box_machine), material.id + " 跟哪台机器出现")
	check_eq(TEA.station("lemonade").unlock_cost, sim._unlock_cost("lemonade"), "柠檬水台解锁价")
	for index in range(1, TEA.stages.size()):
		for id in TEA.stages[index].stations:
			check_eq(TEA.stages[index].cost, sim._unlock_cost(id), "阶段 %d %s 解锁价" % [index, id])
			check_eq(TEA.stage_of(id), sim._unlock_stage(id), id + " 所在阶段")


func test_tea_prices_match_old_sim_at_random_levels() -> void:
	var sim = TeaSim.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 73
	for round in 60:
		var levels := {}
		for id in ["lemonade", "boil", "mix", "topping", "press", "seal"]:
			var lv := rng.randi_range(1, _level_track(TEA, id).max_level()) if round > 0 else 1
			levels[id] = lv
			sim.station_levels[id] = lv
		for station in TEA.stations:
			for material in station.materials:
				var lv := rng.randi_range(1, material.track.max_level()) if round > 0 else 1
				levels[station.id + "/" + material.id] = lv
				sim.material_levels[station.id][material.id] = lv
		for dish in TEA.dishes:
			var expected: float = sim._dish_price(dish.id)
			var actual := snappedf(SpecPrice.dish_price(TEA, dish, levels), 0.1)
			if not is_equal_approx(actual, expected):
				check_eq(actual, expected, "第 %d 组 %s 售价 %s" % [round, dish.id, levels])
				return


func test_tea_machine_numbers_match_old_sim_at_every_level() -> void:
	var sim = TeaSim.new()
	var boil := TEA.station("boil")
	var seal := TEA.station("seal")
	for lv in range(1, _level_track(TEA, "boil").max_level() + 1):
		sim.station_levels.boil = lv
		var speed := _level_track(TEA, "boil").fold("speed", lv, 1.0)
		check(is_equal_approx(float(boil.params.cook_seconds) / speed, sim._machine_duration("boil")), "煮茶 Lv%d 秒数" % lv)
		check_eq(int(_level_track(TEA, "boil").fold("batch", lv, 0.0)), sim.brew_batch(lv), "煮茶 Lv%d 每锅杯数" % lv)
		check_eq(_level_track(TEA, "boil").stars(lv), sim.stars("boil", lv), "煮茶 Lv%d 星级" % lv)
	for lv in range(1, _level_track(TEA, "seal").max_level() + 1):
		var t := _level_track(TEA, "seal")
		var slots := int(t.fold("process_slots", lv, 1.0))
		check_eq(slots, sim.seal_slots(lv), "封口 Lv%d 封口位" % lv)
		check(is_equal_approx(float(seal.params.process_seconds) / t.fold("speed", lv, 1.0) / slots, sim.seal_seconds(lv)), "封口 Lv%d 秒数" % lv)
		check_eq(t.stars(lv), sim.stars("seal", lv), "封口 Lv%d 星级" % lv)
	for id in ["lemonade", "mix", "press"]:
		for lv in range(1, _level_track(TEA, id).max_level() + 1):
			check_eq(_level_track(TEA, id).stars(lv), sim.stars(id, lv), "%s Lv%d 星级" % [id, lv])
	sim.station_levels.mix = 1
	check(is_equal_approx(float(TEA.station("mix").params.seconds), sim._machine_duration("mix")), "调奶秒数")
	check(is_equal_approx(float(TEA.station("topping").params.seconds), sim._topping_seconds()), "加料每杯秒数")
	check_eq(int(TEA.station("boil").params.capacity), sim.BOIL_CAPACITY, "煮茶机容量")
	check_eq(int(TEA.station("seal").params.zones.takeaway), sim.PICKUP_CAPACITY, "外带架格数")
	check_eq(TEA.station("boil").stock[0].base, sim.BLACK_TEA_CAP, "红茶备货基础数")
	check_eq(TEA.station("topping").params.flavor_cap, sim._definition("topping").flavor_cap, "每口味上限")
	for station in TEA.stations:
		check_eq(station.counts_for_flow, station.id in sim.FLOW_MACHINES, station.id + " 算不算客流机器")


func test_tea_flavor_unlock_levels_match_old_sim() -> void:
	var sim = TeaSim.new()
	var topping := TEA.station("topping")
	for material in topping.materials:
		var old = sim._definition("topping").material(material.id)
		check_eq(material.track.requires_level, old.unlock_level, material.id + " 几级开放")
		var opened_at := 1
		var t := _level_track(TEA, "topping")
		for index in t.levels.size():
			for e in t.levels[index].effects:
				if e.kind == "open_flavor" and e.target == material.id: opened_at = index + 2
		check_eq(opened_at, old.unlock_level, material.id + " 由加料机哪一级打开")
		check_eq(TEA.dish(material.item).flavor_material, material.id, material.item + " 的口味")


func test_tea_stages_and_tasks_match_old_progression() -> void:
	var sim = TeaSim.new()
	var old_stages: Array = sim.PROGRESSION.stages
	check_eq(TEA.stages.size(), old_stages.size(), "阶段数")
	for index in old_stages.size():
		var old = old_stages[index]
		var stage := TEA.stages[index]
		check_eq(stage.customer_interval, old.customer_interval, "阶段 %d 来客间隔" % index)
		check_eq(stage.queue_capacity, old.queue_capacity, "阶段 %d 队伍上限" % index)
		check_eq(stage.staff_slots.get("kitchen", -1), old.staff_slots, "阶段 %d 后厨人数" % index)
		check_eq(stage.takeaway_share, old.takeaway_share, "阶段 %d 外带比例" % index)
		check(is_equal_approx(stage.seat_seconds, sim.seat_seconds(index)), "阶段 %d 堂食时长" % index)
		check_eq(stage.order_weights.size(), old.order_weights.size(), "阶段 %d 菜品权重" % index)
		for dish in old.order_weights:
			check_eq(stage.order_weights.get(dish, -1.0), old.order_weights[dish], "阶段 %d %s 权重" % [index, dish])
		check_eq(stage.tasks.size(), old.tasks.size(), "阶段 %d 任务数" % index)
		for t in mini(stage.tasks.size(), old.tasks.size()):
			check_eq(stage.tasks[t].amount, old.tasks[t].amount, "阶段 %d 任务 %d 数量" % [index, t])
			check_eq(stage.tasks[t].display_name, old.tasks[t].display_name, "阶段 %d 任务 %d 文案" % [index, t])
			if old.tasks[t].condition == 2:
				check(TEA.station(stage.tasks[t].target) != null, "任务指向的机器 %s 存在" % stage.tasks[t].target)


func test_tea_flyer_seats_staff_and_fulfillment_match_old_sim() -> void:
	var sim = TeaSim.new()
	var p = sim.PROGRESSION
	var flyer := TEA.flyer.track
	check_eq(flyer.max_level(), sim.flyer_max_level(), "传单最高级")
	for lv in range(1, flyer.max_level() + 1):
		check_eq(int(flyer.fold("flyer_customers", lv, 0.0)), sim.flyer_customers(lv), "传单 Lv%d 人数" % lv)
		check(is_equal_approx(flyer.fold("flyer_cooldown", lv, 0.0), sim.flyer_cooldown(lv)), "传单 Lv%d 冷却" % lv)
		if lv < flyer.max_level(): check_eq(flyer.cost(lv), int(p.flyer_upgrade_costs[lv - 1]), "传单 Lv%d 价格" % lv)
	check_eq(TEA.flyer.wave_seconds, p.flyer_seconds, "传单起效秒数")
	var seats := TEA.seat_groups[0]
	check_eq(seats.start, p.seat_start, "开局座位")
	check_eq(seats.step + 0, p.seat_step, "每次加座")
	check_eq(seats.costs.size(), p.seat_costs.size(), "加座次数")
	check_eq(seats.start + seats.step * seats.costs.size(), sim.seat_max(), "最多座位")
	check_eq(TEA.staff.hire_cost_base, sim.hire_cost(), "第一次招人价")
	check_eq(TEA.staff.kinds.size(), sim.ARTS.size(), "员工种类数")
	for kind in TEA.staff.kinds:
		var worker: Dictionary = sim._make_worker(sim.ARTS.find(kind.id))
		check_eq(kind.stats.walk, float(worker.speed), kind.id + " 走速")
		check_eq(kind.stats.work, float(worker.skill), kind.id + " 手速")
		check_eq(int(kind.stats.carry), int(worker.capacity), kind.id + " 搬运")
	for t in TEA.staff.tracks:
		var costs: Array = sim._upgrade_costs_for(t.id)
		check_eq(t.levels.size(), costs.size(), t.id + " 员工升级条数")
		for index in mini(t.levels.size(), costs.size()):
			check_eq(t.levels[index].cost, int(costs[index]), "%s 员工升级 %d 价格" % [t.id, index])
	var f := TEA.fulfillment
	check_eq(f.mood_seconds[0], sim.MOOD_IMPATIENT, "变脸 1")
	check_eq(f.mood_seconds[1], sim.MOOD_ANGRY, "变脸 2")
	check_eq(f.seated_patience, sim.SEATED_PATIENCE, "坐着等的耐心")
	check_eq(f.ramp_start, sim.RAMP_START, "新菜起始权重")
	check_eq(f.ramp_orders, sim.RAMP_ORDERS, "新菜爬坡人数")
	check_eq(TEA.start_gold, sim.CONFIG.starting_gold, "开局金币")
	check_eq(TEA.flavor_flow, p.flavor_flow, "口味客流")


# ---------- 通用 ----------

func test_every_reference_in_shop_data_points_at_something_real() -> void:
	for shop in [TEA, PANCAKE]:
		var items := {}
		for i in shop.items: items[i.id] = true
		for dish in shop.dishes:
			check(items.has(dish.item), "%s/%s 的成品物品存在" % [shop.id, dish.id])
			check(not dish.price_parts.is_empty(), "%s/%s 有价格" % [shop.id, dish.id])
			for s in dish.steps:
				check(shop.station(s.station) != null, "%s/%s 工序用的机器 %s 存在" % [shop.id, dish.id, s.station])
		for station in shop.stations:
			check(station.block in SpecStation.BLOCKS, "%s/%s 积木类型 %s" % [shop.id, station.id, station.block])
			for t in station.tracks:
				for l in t.levels:
					for e in l.effects: check(e.kind in SpecEffect.KINDS, "%s/%s 效果 %s" % [shop.id, station.id, e.kind])
		for stage in shop.stages:
			for id in stage.stations: check(shop.station(id) != null, "%s 阶段机器 %s 存在" % [shop.id, id])
			for dish in stage.order_weights:
				check(shop.dish(dish) != null or dish == stage.flavor_group, "%s 阶段菜 %s 存在" % [shop.id, dish])
			for t in stage.tasks:
				check(t.condition in ["sell_count", "track_level", "flavor_open", "revenue"], "%s 任务条件 %s" % [shop.id, t.condition])


func test_campaign_lists_the_north_city_in_order() -> void:
	check_eq(CAMPAIGN.cities.size(), 1, "一座城")
	check_eq(CAMPAIGN.shop_ids(), ["pancake", "tea", "bakery"] as Array[String], "北方城店铺顺序")
	check_eq(CAMPAIGN.next_shop("pancake"), "tea", "煎饼摊之后是奶茶店")
	check_eq(CAMPAIGN.next_shop("tea"), "", "面包店还没做")
	for city in CAMPAIGN.cities:
		for shop in city.shops:
			if shop.shop_path.is_empty(): continue
			var data: SpecShop = load(shop.shop_path)
			check_eq(data.id, shop.id, shop.id + " 数据 id 一致")


func test_profile_follows_the_campaign_and_keeps_reserved_fields() -> void:
	var path := "user://test_profile_specs.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var Profile := preload("res://game/app/profile.gd")
	var profile = Profile.new(path)
	check_eq(profile.shop, "pancake", "从关卡表第一家店开始")
	check_eq(profile.city, "north", "从第一座城开始")
	check_eq(profile.next_shop("pancake"), "tea", "煎饼摊之后是奶茶店")
	profile.trophies = 7
	profile.staff_kinds = ["gray_cat", "rabbit"]
	profile.finish_shop({"shop": "pancake"})
	var again = Profile.new(path)
	check_eq(again.shop, "tea", "结店后到奶茶店")
	check_eq(again.trophies, 7, "奖杯存下来")
	check_eq(again.staff_kinds, ["gray_cat", "rabbit"], "已开放员工种类存下来")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
