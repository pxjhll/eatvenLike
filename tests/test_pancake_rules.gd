extends "res://tests/test_case.gd"
## 煎饼摊玩法跑在通用规则层上（旧 pancake_sim 的行为用例搬过来）：开局、一人跟单走完每台机器、鏊子一次一人、
## 解锁顺序、招人名额、传单冷却、升级上限、评分。整店节奏由 test_shop_rules 的整店回放对照基准。

const PANCAKE: SpecShop = preload("res://content/shops/pancake/shop.tres")


## 只卖一道菜的煎饼摊（不顺带豆浆）
func _only(dish: String) -> SpecShop:
	var shop: SpecShop = PANCAKE.duplicate(true)
	for stage in shop.stages:
		stage.order_weights.clear()
		stage.order_weights[dish] = 1.0
		stage.flavor_group = ""
	shop.fulfillment.addon_chance = 0.0
	return shop


func test_opening_has_counter_packing_and_one_staff_but_no_customers() -> void:
	var rules := ShopRules.new(PANCAKE)
	check(rules.station_unlocked("front_counter") and rules.station_unlocked("packing"), "前台和打包台开局就在")
	check(not rules.is_open(), "豆浆机开之前不营业")
	check_eq(rules.workers.size(), 1, "开局 1 名员工")
	check_eq(rules.next_unlock(), "soy_milk", "第一个解锁是豆浆机")
	rules.run(30.0)
	check(rules.customers.is_empty(), "没开张就没有客人")
	check_eq(rules.unlock("soy_milk"), "", "开局金币够开豆浆机")
	rules.run(40.0)
	check(int(rules.sold_by_dish.soy) > 0, "开张后卖出豆浆")


func test_one_staff_follows_a_food_order_through_every_station() -> void:
	var rules := ShopRules.new(_only("family"))
	rules.gold = 9999
	for id in ["soy_milk", "rear_equipment", "fryer", "topping"]: check_eq(rules.unlock(id), "", "开放" + id)
	check(rules.station_unlocked("raw_ingredients"), "面粉鸡蛋和鏊子一起开")
	for i in 2: rules.upgrade("topping")
	check(not rules.dish_open("family"), "加料台 3 级还没有全家福")
	rules.upgrade("topping")
	check(rules.dish_open("family"), "加料台 4 级开全家福")
	var visited := {}
	var gold_before := rules.gold
	var paid_at := -1.0
	while rules.clock < 120.0 and int(rules.sold_by_dish.family) == 0:
		rules.step(0.1)
		var s: Dictionary = rules.workers[0]
		if s.phase == "work": visited[s.task_label] = true
		if paid_at < 0.0 and rules.gold > gold_before: paid_at = rules.clock
	check_eq(int(rules.sold_by_dish.family), 1, "一名员工把全家福从收钱做到递餐")
	for label in ["收钱", "拿面糊鸡蛋", "摊饼", "拿薄脆", "加料", "卷饼装袋", "递餐"]:
		check(visited.has(label), "跟单经过：" + label)
	check(paid_at > 0.0, "先付钱再等餐")


func test_two_staff_share_one_griddle() -> void:
	var rules := ShopRules.new(_only("plain"))
	rules.gold = 9999
	rules.unlock("soy_milk")
	rules.unlock("rear_equipment")
	check_eq(rules.hire(), "", "第 2 段能招第 2 人")
	check(rules.hire() != "", "第 2 段最多 2 人")
	rules.send_flyers()
	var both_grilling := false
	for i in 1200:
		rules.step(0.1)
		var grilling := 0
		for s in rules.workers:
			if s.phase == "work" and s.task_label == "摊饼": grilling += 1
		both_grilling = both_grilling or grilling > 1
	check(not both_grilling, "一口鏊子同时只给一个人摊饼")
	check(int(rules.sold_by_dish.plain) > 3, "两人轮流用鏊子出饼")


func test_staff_hold_what_they_made_until_handing_over() -> void:
	var rules := ShopRules.new(_only("plain"))
	rules.gold = 9999
	rules.unlock("soy_milk")
	rules.unlock("rear_equipment")
	rules.send_flyers()
	var held := {}
	var sold_before := 0
	var empty_after_sale := true
	for i in 1200:
		rules.step(0.1)
		var s: Dictionary = rules.workers[0]
		if s.carry_count > 0: held[s.carry_item] = true
		if int(rules.sold_by_dish.plain) > sold_before:
			sold_before = int(rules.sold_by_dish.plain)
			empty_after_sale = empty_after_sale and s.carry_count == 0
	check(held.has("batter") and held.has("pancake") and held.has("plain"), "手上依次拿着面糊、煎饼、包好的饼：%s" % [held.keys()])
	check(sold_before > 0 and empty_after_sale, "递给客人后手上空了")


func test_staff_walk_around_tables_that_are_out() -> void:
	var rules := ShopRules.new(PANCAKE)
	var pts := PANCAKE.layout.points
	var table: Rect2 = PANCAKE.layout.obstacles[PANCAKE.layout.obstacle_stations.find("topping")]
	var crosses := func() -> bool:
		for p in rules.nav.path(pts.topping, pts.front_counter):
			if table.has_point(p): return true
		return false
	check(crosses.call(), "加料台没开时中间没有桌子，直接走过去")
	rules.gold = 99999
	for i in 6:
		var n := rules.next_unlock()
		if n != "": rules.unlock(n)
	check(not crosses.call(), "加料台开了，员工绕开中间的桌子")
	for a in pts:
		for b in pts:
			if a != b: check(not rules.nav.path(pts[a], pts[b]).is_empty(), "%s 走得到 %s" % [a, b])


func test_unlock_order_hires_and_flyer_cooldown() -> void:
	var rules := ShopRules.new(PANCAKE)
	rules.gold = 9999
	check(rules.unlock("fryer") != "", "不能跳过顺序开油锅")
	rules.unlock("soy_milk")
	check_eq(rules.staff_slots(), 1, "豆浆段 1 人")
	check_eq(rules.send_flyers(), "", "传单免费")
	check(rules.send_flyers() != "", "传单有冷却")
	rules.run(rules.flyer_cooldown() + 1.0)
	check_eq(rules.send_flyers(), "", "冷却结束可以再发")
	for id in ["rear_equipment", "fryer", "topping"]: check_eq(rules.unlock(id), "", "按顺序开放" + id)
	check_eq(rules.staff_slots(), 4, "加料段最多 4 人")
	check_eq(rules.current_stage().wait_seats, 9, "加料段 9 个坐垫")
	check(rules.next_unlock().is_empty(), "四台都开了")


func test_upgrades_raise_soy_price_and_griddle_caps_at_nine() -> void:
	var rules := ShopRules.new(PANCAKE)
	rules.gold = 99999
	rules.unlock("soy_milk")
	var soy := rules.dish_price("soy")
	check_eq(rules.upgrade("soy_milk"), "", "豆浆机可升级")
	check(rules.dish_price("soy") > soy, "豆浆机升级只加售价")
	rules.unlock("rear_equipment")
	var costs: Array = []
	while rules.upgrade_cost("rear_equipment") >= 0:
		costs.append(rules.upgrade_cost("rear_equipment"))
		check_eq(rules.upgrade("rear_equipment"), "", "鏊子升级")
	check_eq(rules.level("rear_equipment"), 9, "鏊子最高 9 级")
	var rising := true
	for i in range(1, costs.size()): rising = rising and costs[i] > costs[i - 1]
	check(rising, "每级都比上一级贵")


func test_rating_uses_finish_time_and_walkouts() -> void:
	var rules := ShopRules.new(PANCAKE)
	var view := ShopView.new(rules)
	check_eq(view.rating(), 0, "没完店没有评分")
	rules.completed_at = 20 * 60.0
	rules.sold = 100
	check_eq(view.rating(), 3, "22 分钟内完店、流失少：3 星")
	rules.completed_at = 26 * 60.0
	check_eq(view.rating(), 2, "28 分钟内：2 星")
	rules.lost = 50
	check_eq(view.rating(), 1, "走掉的客人超过两成扣一星")
	var summary := view.summary()
	check_eq(summary.shop, "pancake", "结店纪录记店铺 id")
	check(summary.levels.has("rear_equipment") and summary.levels.has("topping"), "结店纪录有各台等级")


func test_waiting_customers_never_leave_they_get_angry() -> void:
	var rules := ShopRules.new(_only("soy"))
	check_eq(rules.unlock("soy_milk"), "", "开豆浆机")
	rules.workers.clear()
	rules.run(5.0)
	check(not rules.queue.is_empty(), "没人干活时客人排着")
	var first: Dictionary = rules.customer(int(rules.queue[0]))
	rules.run(120.0)
	check_eq(rules.customer(int(first.id)).get("state", ""), "queue", "等了两分钟也不走")
	check_eq(rules.order_mood(first), 2, "等久了生气")
