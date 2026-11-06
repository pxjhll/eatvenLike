extends "res://tests/test_case.gd"
## 煎饼摊玩法：开局状态、跟单流程、解锁顺序、招人名额、传单冷却、口味开放，以及基准玩家的节奏。

const Sim := preload("res://game/pancake/pancake_sim.gd")
const Bot := preload("res://game/pancake/pancake_bot.gd")


func test_opening_has_counter_packing_and_one_staff_but_no_customers() -> void:
	var sim := Sim.new(1)
	check(sim.unlocked.get("front_counter", false) and sim.unlocked.get("packing", false), "前台和打包台开局就在")
	check(not sim.is_open(), "豆浆机开之前不营业")
	check_eq(sim.staff.size(), 1, "开局 1 名员工")
	check_eq(sim.next_unlock(), "soy_milk", "第一个解锁是豆浆机")
	sim.run(30.0)
	check(sim.customers.is_empty(), "没开张就没有客人")
	check(sim.unlock("soy_milk"), "开局金币够开豆浆机")
	sim.run(40.0)
	check(int(sim.sold.soy) > 0, "开张后卖出豆浆")


func test_one_staff_follows_a_food_order_through_every_station() -> void:
	var sim := Sim.new(2)
	sim.gold = 9999
	sim.unlock("soy_milk")
	sim.unlock("rear_equipment")
	sim.unlock("fryer")
	sim.unlock("topping")
	check(sim.unlocked.get("raw_ingredients", false), "面粉鸡蛋和鏊子一起开")
	sim.cfg.weights = [{"family": 1.0}, {"family": 1.0}, {"family": 1.0}, {"family": 1.0}]
	sim.cfg.soy_addon = 0.0
	for i in 4: sim.upgrade("topping")
	check("family" in sim.flavors(), "加料台 5 级开全家福")
	sim.next_customer = 0.0
	var visited := {}
	var gold_before := sim.gold
	var paid_at := -1.0
	while sim.clock < 120.0 and int(sim.sold.family) == 0:
		sim.step(0.1)
		var s: Dictionary = sim.staff[0]
		if s.phase == "work": visited[s.task_label] = true
		if paid_at < 0.0 and sim.gold > gold_before: paid_at = sim.clock
	check_eq(int(sim.sold.family), 1, "一名员工把全家福从收钱做到递餐")
	for label in ["收钱", "拿面糊鸡蛋", "摊饼", "拿薄脆", "加料", "卷饼装袋", "递餐"]:
		check(visited.has(label), "跟单经过：" + label)
	check(paid_at > 0.0, "先付钱再等餐")


func test_two_staff_share_one_griddle() -> void:
	var sim := Sim.new(3)
	sim.gold = 9999
	sim.unlock("soy_milk")
	sim.unlock("rear_equipment")
	check(sim.hire(), "第 2 段能招第 2 人")
	check(not sim.hire(), "第 2 段最多 2 人")
	sim.cfg.weights = [{"plain": 1.0}, {"plain": 1.0}, {"plain": 1.0}, {"plain": 1.0}]
	var both_grilling := false
	sim.send_flyers()
	for i in 1200:
		sim.step(0.1)
		var grilling := 0
		for s in sim.staff:
			if s.phase == "work" and s.task_label == "摊饼": grilling += 1
		if grilling > 1: both_grilling = true
	check(not both_grilling, "一口鏊子同时只给一个人摊饼")
	check(int(sim.sold.plain) > 3, "两人轮流用鏊子出饼")


func test_unlock_order_hires_and_flyer_cooldown() -> void:
	var sim := Sim.new(4)
	sim.gold = 9999
	check(not sim.unlock("fryer"), "不能跳过顺序开油锅")
	sim.unlock("soy_milk")
	check_eq(sim.staff_slots(), 1, "豆浆段 1 人")
	check(sim.send_flyers(), "传单免费")
	check(not sim.send_flyers(), "传单有冷却")
	sim.run(float(sim.cfg.flyer_cooldown) + 1.0)
	check(sim.send_flyers(), "冷却结束可以再发")
	for key in ["rear_equipment", "fryer", "topping"]:
		check(sim.unlock(key), "按顺序开放" + key)
	check_eq(sim.staff_slots(), 4, "加料段最多 4 人")
	check_eq(sim.cushion_count(), 9, "加料段 9 个坐垫")
	check(sim.next_unlock().is_empty(), "四台都开了")


func test_upgrades_have_one_effect_and_a_level_cap() -> void:
	var sim := Sim.new(5)
	sim.gold = 99999
	sim.unlock("soy_milk")
	var soy_price := sim.price("soy")
	check(sim.upgrade("soy_milk"), "豆浆机可升级")
	check(sim.price("soy") > soy_price, "豆浆机升级只加售价")
	sim.unlock("rear_equipment")
	while sim.upgrade("rear_equipment"): pass
	check_eq(int(sim.levels.rear_equipment), 9, "鏊子最高 9 级")


func test_baseline_player_finishes_in_about_twenty_minutes() -> void:
	var bot := Bot.new()
	var done := []
	for seed in 6:
		var r: Dictionary = bot.play(seed, 30.0)
		check(r.times.has("topping"), "种子 %d 开出加料台" % seed)
		done.append(r.done_at / 60.0 if r.done_at > 0.0 else 99.0)
	done.sort()
	var median: float = done[done.size() / 2]
	check(median > 16.0 and median < 26.0, "基准玩家约 20 分钟完店（中位 %.1f 分）" % median)
