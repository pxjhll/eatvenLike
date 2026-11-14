extends "res://tests/test_case.gd"
const LegacyRules := preload("res://tests/fixtures/legacy_shops/reference_rules.gd")
## Frozen v0 business regression; formal v1 coverage: test_first_shops_migration.
## 煎饼摊玩法跑在通用规则层上（旧 pancake_sim 的行为用例搬过来）：开局、一人跟单走完每台机器、鏊子一次一人、
## 面粉箱单独买、打糊加摊饼同一台、装袋选项、口味升级、解锁顺序、招人名额、传单冷却、升级上限、评分。整店节奏由 test_shop_rules 的整店回放对照基准。

const PANCAKE: SpecShop = preload("res://tests/fixtures/legacy_shops/pancake.tres")


## 只卖一道菜的煎饼摊（不顺带豆浆）
func _only(dish: String) -> SpecShop:
	var shop: SpecShop = PANCAKE.duplicate(true)
	for stage in shop.stages:
		stage.order_weights.clear()
		stage.order_weights[dish] = 1.0
		stage.flavor_group = ""
	shop.fulfillment.addon_chance = 0.0
	return shop


func test_opening_has_counter_roll_and_one_staff_but_no_customers() -> void:
	var rules := LegacyRules.new(PANCAKE)
	check(rules.station_unlocked("front_counter") and rules.station_unlocked("roll"), "前台和柜台上的卷饼开局就在")
	check(not rules.station_unlocked("bag"), "装袋要单独解锁")
	check(not rules.is_open(), "豆浆机开之前不营业")
	check_eq(rules.workers.size(), 1, "开局 1 名员工")
	check_eq(rules.next_unlock(), "soy_milk", "第一个解锁是豆浆机")
	rules.run(30.0)
	check(rules.customers.is_empty(), "没开张就没有客人")
	check_eq(rules.unlock("soy_milk"), "", "开局金币够开豆浆机")
	rules.run(40.0)
	check(int(rules.sold_by_dish.soy) > 0, "开张后卖出豆浆")


func test_flour_box_is_its_own_buy_after_the_griddle() -> void:
	var rules := LegacyRules.new(PANCAKE)
	rules.gold = 9999
	rules.unlock("soy_milk")
	check(rules.box_error("flour") != "", "鏊子没开不能买面粉箱")
	check_eq(rules.unlock("rear_equipment"), "", "开鏊子")
	check(not rules.dish_open("plain"), "光有鏊子还卖不了原味煎饼")
	check_eq(rules.pending_box(), "flour", "鏊子开了就提示买面粉箱")
	var gold := rules.gold
	check_eq(rules.unlock_box("flour"), "", "买面粉箱")
	check_eq(gold - rules.gold, 20.0, "面粉箱 20 金币")
	check(rules.dish_open("plain"), "买了面粉箱就能卖原味煎饼")


func test_flavor_orders_require_the_flour_box_including_the_fallback() -> void:
	var rules := LegacyRules.new(PANCAKE)
	rules.gold = 99999
	for id in ["soy_milk", "rear_equipment", "fryer", "topping"]:
		check_eq(rules.unlock(id), "", "开放" + id)
	check(not rules.dish_open("ham"), "没有面粉箱不能制作火腿煎饼")
	var weights := rules.order_weights()
	check(not weights.has("ham"), "未开放的口味不能被点单")
	check(not weights.has("guozi"), "口味组的回退菜也必须满足原料要求")
	for id in weights: check(rules.dish_open(id), "点单菜单只包含已开放的菜：" + id)
	rules.run(120.0)
	check(int(rules.sold_by_dish.soy) > 0, "没买面粉时仍然能卖豆浆")
	check_eq(int(rules.sold_by_dish.ham), 0, "不能绕过面粉箱卖火腿煎饼")
	check_eq(rules.unlock_box("flour"), "", "购买面粉箱")
	check(rules.order_weights().has("ham"), "买到面粉后口味正常进入菜单")
	rules.run(240.0)
	check(int(rules.sold_by_dish.ham) > 0, "买到原料后正常制作销售火腿煎饼")


func _open_all(rules: ShopRules) -> void:
	rules.gold = 99999
	for id in ["soy_milk", "rear_equipment", "fryer", "topping"]: check_eq(rules.unlock(id), "", "开放" + id)
	check_eq(rules.unlock_box("flour"), "", "买面粉箱")


func test_one_staff_follows_a_food_order_through_every_station() -> void:
	var rules := LegacyRules.new(_only("family"))
	_open_all(rules)
	for i in 2: rules.upgrade("topping")
	check(not rules.dish_open("family"), "加料台 3 级还没有全家福")
	rules.upgrade("topping")
	check(rules.dish_open("family"), "加料台 4 级开全家福")
	var visited := []
	var held := []
	var gold_before := rules.gold
	var paid_before_sale := false
	while rules.clock < 120.0 and int(rules.sold_by_dish.family) == 0:
		rules.step(0.1)
		var s: Dictionary = rules.workers[0]
		if s.phase == "work" and (visited.is_empty() or visited[-1] != s.task_label) and visited.size() < 8: visited.append(s.task_label)
		if s.carry_count > 0 and (held.is_empty() or held[-1] != s.carry_item): held.append(s.carry_item)
		if int(rules.sold_by_dish.family) == 0 and rules.gold > gold_before: paid_before_sale = true
	check_eq(int(rules.sold_by_dish.family), 1, "一名员工把全家福从接单做到递餐")
	check_eq(visited, ["接单", "拿面粉鸡蛋", "打面糊", "摊饼", "拿薄脆", "加料", "卷饼", "递餐收钱"], "跟单顺序：原料 → 鏊子 → 薄脆筐 → 加料台 → 柜台")
	check_eq(held, ["flour", "batter", "pancake", "pancake_crisp", "family_top", "family"], "手上拿的东西跟着工序变")
	check(not paid_before_sale and rules.gold > gold_before, "和奶茶店一样，递餐时才收钱")


func test_batter_is_quick_and_griddle_upgrades_only_speed_up_grilling() -> void:
	var rules := LegacyRules.new(_only("plain"))
	_open_all(rules)
	var times := func() -> Dictionary:
		var out := {}
		var r := LegacyRules.new(_only("plain"))
		_open_all(r)
		for i in rules.level("rear_equipment") - 1: r.upgrade("rear_equipment")
		var started := {}
		while r.clock < 60.0 and int(r.sold_by_dish.plain) == 0:
			r.step(0.1)
			var s: Dictionary = r.workers[0]
			if s.phase == "work" and not started.has(s.task_label): started[s.task_label] = float(s.duration)
		return started
	var before: Dictionary = times.call()
	for i in 4: rules.upgrade("rear_equipment")
	var after: Dictionary = times.call()
	check(float(before["打面糊"]) <= 1.0, "打面糊约 1 秒")
	check_eq(after["打面糊"], before["打面糊"], "鏊子升级不改打面糊")
	check(float(after["摊饼"]) < float(before["摊饼"]), "鏊子升级加快摊饼")


func test_one_griddle_is_held_from_batter_to_pancake() -> void:
	var rules := LegacyRules.new(_only("plain"))
	_open_all(rules)
	check_eq(rules.hire(), "", "招第 2 人")
	rules.send_flyers()
	var both := false
	var cut_in := false
	var owner := -1
	for i in 1500:
		rules.step(0.1)
		var at_griddle := 0
		for s in rules.workers:
			if s.phase == "work" and s.task_label in ["打面糊", "摊饼"]:
				at_griddle += 1
				if s.task_label == "摊饼" and owner != -1 and owner != s.id: cut_in = true
				owner = s.id if s.task_label == "打面糊" else owner
		both = both or at_griddle > 1
	check(not both, "一口鏊子同时只给一个人用（打糊和摊饼算一台）")
	check(not cut_in, "打完面糊接着摊，中间没人插进来")
	check(int(rules.sold_by_dish.plain) > 3, "两人轮流用鏊子出饼")


func test_bag_option_adds_a_step_and_raises_the_price() -> void:
	var rules := LegacyRules.new(_only("guozi"))
	_open_all(rules)
	rules._spawn_single()
	check(not rules.customers[-1].options.has("bag"), "装袋没开时没人要袋子")
	check_eq(rules.unlock("bag"), "", "开装袋")
	var bagged := 0
	for i in 200:
		rules._spawn_single()
		rules.queue.clear()
		if rules.customers[-1].options.has("bag"): bagged += 1
	check(bagged > 50 and bagged < 110, "约 4 成客人要袋子：%d/200" % bagged)
	var plain := {"kind": "guozi", "addon": false, "options": []}
	var bag := {"kind": "guozi", "addon": false, "options": ["bag"]}
	check_eq(rules.order_price_single(bag), int(round(rules.raw_price("guozi") * 1.25)), "装袋的这份贵 25%")
	check(rules.order_price_single(bag) > rules.order_price_single(plain), "比不装袋贵")
	var soy := rules.shop.fulfillment.addon_dish
	check_eq(rules.order_price_single({"kind": soy, "addon": true, "options": ["bag"]}), int(round(rules.raw_price(soy) * 1.25)), "只点豆浆装袋也贵 25%")
	check_eq(rules.order_price_single({"kind": "guozi", "addon": true, "options": ["bag"]}),
		int(round(rules.raw_price("guozi") * 1.25 + rules.raw_price(soy))), "搭配的豆浆不乘装袋倍数")
	var steps: Array = rules._order_steps(bag)
	check_eq(steps[-2].label, "装袋", "装袋在递餐前")
	check_eq(steps[-2].holds, "bagged", "手上拿着手提袋")


func test_flavors_have_two_price_levels_like_the_tea_toppings() -> void:
	var rules := LegacyRules.new(PANCAKE)
	_open_all(rules)
	var price := rules.dish_price("ham")
	check(rules.upgrade_error("topping/ham").is_empty(), "火腿口味能升级")
	check_eq(rules.upgrade("topping/ham"), "", "火腿 Lv2")
	check(rules.dish_price("ham") > price, "口味升级涨价")
	check_eq(rules.upgrade("topping/ham"), "", "火腿 Lv3")
	check_eq(rules.level("topping/ham"), 3, "口味最高 3 级")
	check(rules.upgrade_error("topping/ham") != "", "3 级封顶")


func test_staff_walk_to_every_point() -> void:
	var rules := LegacyRules.new(PANCAKE)
	var pts := PANCAKE.layout.points
	for a in pts:
		for b in pts:
			if a != b: check(not rules.nav.path(pts[a], pts[b]).is_empty(), "%s 走得到 %s" % [a, b])
	check(not "topping" in PANCAKE.layout.obstacle_stations, "中间的加料桌拿掉了，加料台在右边竖桌")


func test_unlock_order_hires_and_flyer_cooldown() -> void:
	var rules := LegacyRules.new(PANCAKE)
	rules.gold = 9999
	check(rules.unlock("fryer") != "", "不能跳过顺序开油锅")
	rules.unlock("soy_milk")
	check_eq(rules.staff_slots(), 1, "豆浆段 1 人")
	check_eq(rules.send_flyers(), "", "传单免费")
	check(rules.send_flyers() != "", "传单有冷却")
	rules.run(rules.flyer_cooldown() + 1.0)
	check_eq(rules.send_flyers(), "", "冷却结束可以再发")
	for id in ["rear_equipment", "fryer", "topping", "bag"]: check_eq(rules.unlock(id), "", "按顺序开放" + id)
	check_eq(rules.staff_slots(), 4, "加料段最多 4 人")
	check_eq(rules.current_stage().wait_seats, 9, "加料段 9 个坐垫")
	check(rules.next_unlock().is_empty(), "五样都开了")


func test_upgrades_raise_soy_price_and_griddle_caps_at_nine() -> void:
	var rules := LegacyRules.new(PANCAKE)
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
	var rules := LegacyRules.new(PANCAKE)
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
	var rules := LegacyRules.new(_only("soy"))
	check_eq(rules.unlock("soy_milk"), "", "开豆浆机")
	rules.workers.clear()
	rules.run(5.0)
	check(not rules.queue.is_empty(), "没人干活时客人排着")
	var first: Dictionary = rules.customer(int(rules.queue[0]))
	rules.run(120.0)
	check_eq(rules.customer(int(first.id)).get("state", ""), "queue", "等了两分钟也不走")
	check_eq(rules.order_mood(first), 2, "等久了生气")


## 试玩记录只问规则层的通用查询：煎饼摊（一人跟单）的排队、生气、空闲、坐垫、走掉的客人都要记得到
func test_playlog_records_queue_staff_seats_and_walkaways() -> void:
	var Recorder := preload("res://presentation/shop/shop_recorder.gd")
	var rules := LegacyRules.new(_only("soy"))
	check_eq(rules.unlock("soy_milk"), "", "开豆浆机")
	var recorder = Recorder.new()
	recorder.file_path = "user://test_playlog_pancake.txt"
	if FileAccess.file_exists(recorder.file_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(recorder.file_path))
	recorder.setup(rules)
	# 第一分钟：一个员工照常干活，不会整分钟都闲着
	for i in 600:
		rules.step(0.1)
		recorder.tick(0.1)
	# 第二分钟：没人干活，队排满、客人等急了、后来的走掉
	rules.workers.clear()
	for i in 600:
		rules.step(0.1)
		recorder.tick(0.1)
	var rows: Array = []
	for line in recorder.text().split("\n", false):
		var row: Dictionary = JSON.parse_string(line)
		if row.has("income"): rows.append(row)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(recorder.file_path))
	check_eq(rows.size(), 2, "两分钟两行")
	check(float(rows[0].idle) < 1.0, "有活干的员工不算空闲：%s" % rows[0].idle)
	check(int(rows[0].cups) > 0, "第一分钟卖出了")
	check_eq(int(rows[1].queue), rules.queue_size(), "排队人数是煎饼摊自己的队")
	check(int(rows[1].queue) > 0 and float(rows[1].full) > 0.0, "没人干活时记到排满")
	check(float(rows[1].angry) > 0.0, "记到等急了的客人")
	check(int(rows[1].lost) > 0, "记到排满后走掉的客人")
	check_eq(int(rows[1].seats), rules.seat_count(), "坐垫数是等位坐垫")


func test_generic_queries_answer_for_the_single_handoff_shop() -> void:
	var rules := LegacyRules.new(_only("soy"))
	check_eq(rules.unlock("soy_milk"), "", "开豆浆机")
	rules.workers.clear()
	rules.run(150.0)
	check_eq(rules.waiting_customers().size(), rules.queue.size(), "等餐的客人 = 排着的队")
	check(rules.angry_count() > 0, "等久了算等急了")
	check(is_equal_approx(rules.customer_interval(), rules.current_stage().customer_interval), "客流间隔按阶段")


func test_playlog_setup_starts_a_full_new_sampling_interval() -> void:
	var Recorder := preload("res://presentation/shop/shop_recorder.gd")
	var rules := LegacyRules.new(_only("soy"))
	var recorder = Recorder.new()
	recorder.file_path = "user://test_playlog_setup_%d.txt" % OS.get_process_id()
	if FileAccess.file_exists(recorder.file_path): DirAccess.remove_absolute(recorder.file_path)
	recorder.setup(rules)
	rules.unlock("soy_milk")
	for i in 300:
		rules.step(0.25)
		recorder.tick(0.25)
	check(rules.sold > 0, "重开之前有营业记录")
	rules.reset()
	recorder.setup(rules)
	var lines: int = recorder.line_count()
	for i in 239:
		rules.step(0.25)
		recorder.tick(0.25)
	check_eq(recorder.line_count(), lines, "新会话要满 60 秒才采样，不沿用上次的计时")
	rules.step(0.25)
	recorder.tick(0.25)
	check_eq(recorder.line_count(), lines + 1, "新会话满一分钟记录一行")
	var rows: PackedStringArray = recorder.text().split("\n", false)
	var row: Dictionary = JSON.parse_string(rows[rows.size() - 1])
	check_eq(int(row.t), 60, "新会话第一行采样时间是 60 秒")
	check_eq(float(row.income), 0.0, "新会话没有负收入")
	check_eq(int(row.cups), 0, "新会话没有负销量")
	check_eq(int(row.lost), 0, "新会话没有负流失")
	DirAccess.remove_absolute(recorder.file_path)
