extends "res://tests/test_case.gd"
## 第三家测试店（规格 §7）：只用数据写成的面馆（tests/fixtures/noodle，不上线）不改规则代码就能从开张一路开到完店，
## 骨汤锅的同一锅汤同时供清汤面、牛肉面、鸡蛋面；界面快照、存读档也照常。

const NOODLE: SpecShop = preload("res://tests/fixtures/noodle/shop.tres")
const CAMPAIGN: SpecCampaign = preload("res://content/campaign/campaign.tres")


## 机器人：买得起就开下一台、招人、升浇头台（开鸡蛋面），定时发传单
func _play(rules: ShopRules, minutes: float, on_tick := Callable()) -> void:
	while rules.clock < minutes * 60.0:
		rules.step(0.1)
		if on_tick.is_valid(): on_tick.call()
		if int(rules.clock * 10.0) % 20 != 0: continue
		if not rules.next_unlock().is_empty(): rules.unlock(rules.next_unlock())
		rules.hire()
		if rules.station_unlocked("toppings"): rules.upgrade("toppings")
		rules.send_flyers()


func test_opens_and_sells_its_first_dish() -> void:
	var rules := ShopRules.new(NOODLE)
	check(not rules.is_open(), "开张前不营业")
	check_eq(rules.next_unlock(), "urn", "第一台是茶桶")
	check_eq(rules.unlock("urn"), "", "开局的钱够开茶桶")
	rules.run(60.0)
	check(int(rules.sold_by_dish.barley_tea) > 0, "卖出大麦茶")


func test_plays_from_opening_to_shop_complete() -> void:
	var rules := ShopRules.new(NOODLE)
	rules.unlock("urn")
	var broth_users := {}
	# 闭包按值捕获整数，计数放进字典里
	var pot := {"batches": 0, "last": -1}
	var watch := func() -> void:
		for worker in rules.workers:
			if worker.phase == "work" and worker.order >= 0 and worker.step >= 0 and worker.step < worker.steps.size() \
					and worker.steps[worker.step].action == "ladle" and worker.steps[worker.step].station == "pot":
				broth_users[String(rules.customer(worker.order).get("kind", ""))] = true
		var stock := int(rules.stations.pot.stock)
		if pot.last >= 0 and stock > pot.last: pot.batches += 1
		pot.last = stock
	_play(rules, 40.0, watch)
	for d in NOODLE.dishes: check(int(rules.sold_by_dish[d.id]) > 0, "卖出 " + d.display_name)
	check(rules.stage_index == NOODLE.stages.size() - 1, "四段都开了")
	check(rules.dish_open("egg_noodle"), "浇头台升级开出鸡蛋面")
	check(pot.batches >= 2, "骨汤锅熬了好几锅（%d）" % pot.batches)
	var shared: Array = ["clear_noodle", "beef_noodle", "egg_noodle"].filter(func(id: String) -> bool: return broth_users.has(id))
	check_eq(shared.size(), 3, "同一锅汤供了三道面：%s" % [broth_users.keys()])
	check(rules.shop_complete(), "任务做完就能完店（第 %.1f 分钟）" % (rules.completed_at / 60.0))
	check(rules.lost < rules.sold, "大多数客人都吃上了（走了 %d，卖了 %d）" % [rules.lost, rules.sold])


func test_view_save_and_resume_work_for_a_new_shop() -> void:
	var rules := ShopRules.new(NOODLE)
	rules.unlock("urn")
	_play(rules, 12.0)
	var view := ShopView.new(rules)
	check(not String(view.goal().text).is_empty(), "目标栏有字")
	for st in NOODLE.stations: check(not view.station(st.id).is_empty(), "%s 有机器面板" % st.display_name)
	view.bottleneck()
	var copy := ShopRules.new(NOODLE)
	check_eq(copy.load_dict(rules.to_dict()), "", "中途存档能读")
	rules.run(30.0)
	copy.run(30.0)
	check_eq(copy.to_dict(), rules.to_dict(), "读档以后接着跑一模一样")


func test_test_shop_is_not_in_the_campaign() -> void:
	check(not "noodle" in CAMPAIGN.shop_ids(), "测试面馆不上线")
