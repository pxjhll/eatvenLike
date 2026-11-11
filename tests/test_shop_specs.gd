extends "res://tests/test_case.gd"
## 通用店铺数据（规格 §4）：数据里引用的机器、物品、效果、任务条件都存在；关卡表和跨店记录。
## 两家店的数值和旧模拟一致，由整店回放对照基准（test_shop_rules）和界面数据基准（test_shop_view）保证。

const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
const PANCAKE: SpecShop = preload("res://content/shops/pancake/shop.tres")
const CAMPAIGN: SpecCampaign = preload("res://content/campaign/campaign.tres")


# ---------- 通用 ----------

func test_every_reference_in_shop_data_points_at_something_real() -> void:
	for shop in [TEA, PANCAKE, preload("res://content/shops/stirfry/shop.tres"), preload("res://tests/fixtures/noodle/shop.tres")]:
		var items := {}
		for i in shop.items: items[i.id] = true
		for dish in shop.dishes:
			check(items.has(dish.item), "%s/%s 的成品物品存在" % [shop.id, dish.id])
			check(not dish.price_parts.is_empty(), "%s/%s 有价格" % [shop.id, dish.id])
			for s in dish.steps:
				check(shop.station(s.station) != null, "%s/%s 工序用的机器 %s 存在" % [shop.id, dish.id, s.station])
		for station in shop.stations:
			check(not station.id in ShopRules.PLACES, "%s/%s 和规则层的交接位置重名" % [shop.id, station.id])
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
	check_eq(CAMPAIGN.shop_ids(), ["pancake", "tea", "stirfry", "bakery"] as Array[String], "北方城店铺顺序")
	check_eq(CAMPAIGN.next_shop("pancake"), "tea", "煎饼摊之后是奶茶店")
	check_eq(CAMPAIGN.next_shop("tea"), "stirfry", "奶茶店之后是小炒饭馆")
	check_eq(CAMPAIGN.next_shop("stirfry"), "", "面包店还没做")
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
