extends "res://tests/test_case.gd"
## 通用规则层 ShopRules（规格 §3、§7）：整店回归对旧模拟基准、加成栈、事件总线、奇遇与扩展点、干净检查。

const Replay := preload("res://tests/baselines/replay_rules.gd")
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
const PANCAKE: SpecShop = preload("res://content/shops/pancake/shop.tres")


func _baseline(id: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/baselines/%s_73b0ae3.json" % id))


func _open_tea() -> ShopRules:
	var rules := ShopRules.new(TEA)
	check_eq(rules.unlock("lemonade"), "", "奶茶店开张")
	return rules


# ---------- 整店回归（§7：±5%，现在两家店都逐帧一致） ----------

func _check_replay(id: String, shop: SpecShop) -> void:
	var base := _baseline(id)
	var result := Replay.replay(shop, base)
	check_eq(result.failed_actions, [], "%s 机器人的每条操作都能执行" % id)
	for row in Replay.compare(base, result):
		check(row.ok, "%s %s：旧 %s 新 %s" % [id, row.name, row.old, row.new])


func test_tea_whole_shop_matches_old_sim_baseline() -> void:
	_check_replay("tea", TEA)


func test_pancake_whole_shop_matches_old_sim_baseline() -> void:
	_check_replay("pancake", PANCAKE)


# ---------- 加成栈 ----------

func test_modifier_stack_order_is_set_then_mul_then_add() -> void:
	var mods := RuleModifiers.new()
	mods.add("upgrade", "a", "speed", "mul", 2.0)
	mods.add("upgrade", "a", "speed", "set", 3.0)
	mods.add("event", "b", "speed", "add", 1.0)
	check_eq(mods.value("speed", 1.0), 7.0, "3 × 2 + 1")
	mods.remove("event")
	check_eq(mods.value("speed", 1.0), 6.0, "移除来源 event 后")


func test_modifier_targets_dishes_and_expiry() -> void:
	var mods := RuleModifiers.new()
	mods.add("upgrade", "x", "price", "mul", 1.5, "", ["a"])
	mods.add("event", "y", "walk", "mul", 2.0, "kitchen", [], "", 1.0)
	check_eq(mods.value("price", 10.0, "", "a"), 15.0, "只涨 a 的价")
	check_eq(mods.value("price", 10.0, "", "b"), 10.0, "b 不涨")
	check_eq(mods.value("walk", 100.0, "front"), 100.0, "前台不受后厨加成")
	check_eq(mods.value("walk", 100.0, "kitchen"), 200.0, "后厨走得快")
	check_eq(mods.timed().size(), 1, "一条限时加成")
	var expired := mods.tick(1.0)
	check_eq(expired.size(), 1, "1 秒后到期")
	check_eq(mods.value("walk", 100.0, "kitchen"), 100.0, "到期后恢复")


# ---------- 事件总线 ----------

func test_event_bus_listeners_and_log() -> void:
	var bus := RuleEvents.new()
	var got: Array = []
	bus.on("sale", func(data: Dictionary) -> void: got.append(data.dish))
	bus.on("*", func(data: Dictionary) -> void: got.append("*" + data.name))
	bus.emit("sale", {"dish": "x"})
	bus.emit("tick_second", {})
	check_eq(got, ["x", "*sale", "*tick_second"], "具名监听 + 通配监听")
	check_eq(bus.log.size(), 1, "计时广播不进日志")


func test_rules_broadcast_sales_and_unlocks() -> void:
	var rules := ShopRules.new(TEA)
	var names: Array = []
	rules.events.on("*", func(data: Dictionary) -> void:
		if not String(data.name).begins_with("tick_") and not data.name in names: names.append(data.name))
	rules.unlock("lemonade")
	rules.run(120.0)
	for name in ["unlocked", "arrived", "sale"]: check(name in names, "广播了 " + name)


# ---------- 扩展点（§3.13）：不改规则层，只写数据 ----------

func _event(id: String, effects: Array, duration := 0.0, choices: Array = []) -> SpecEvent:
	var ev := SpecEvent.new()
	ev.id = id
	ev.trigger = "tick_minute"
	ev.chance = 1.0
	ev.duration = duration
	ev.effects.assign(effects)
	ev.choices.assign(choices)
	return ev


func test_influencer_doubles_flow_for_sixty_seconds() -> void:
	var rules := _open_tea()
	var base := rules.flow_multiplier()
	rules.trigger_event(_event("influencer", [SpecEffect.make("flow", "mul", 2.0)], 60.0))
	check(is_equal_approx(rules.flow_multiplier(), base * 2.0), "网红来了客流 ×2")
	check_eq(rules.mods.timed().size(), 1, "顶栏有一个进行中加成")
	rules.run(59.0)
	check(is_equal_approx(rules.flow_multiplier(), base * 2.0), "59 秒时还在")
	rules.run(1.1)
	check(is_equal_approx(rules.flow_multiplier(), base), "60 秒后恢复")


func test_investor_card_grants_gold_after_accept() -> void:
	var rules := _open_tea()
	var ev := _event("investor", [SpecEffect.make("grant_gold", "add", 500.0)], 0.0,
		[{"label": "接受", "accept": true}, {"label": "拒绝", "accept": false}])
	ev.once = true
	rules.add_event(ev)
	var gold := rules.gold
	rules.run(60.0)
	check_eq(rules.pending_events.size(), 1, "整分钟弹出投资人卡片")
	check_eq(rules.answer_event(0), "", "接受")
	check(rules.gold >= gold + 500.0, "到账 500 金币")
	rules.run(120.0)
	check_eq(rules.pending_events.size(), 0, "一次性奇遇不再出现")


func test_staff_work_modifier_targets_one_worker() -> void:
	var rules := ShopRules.new(TEA)
	var worker: Dictionary = rules.workers[0]
	var before := rules.skill(worker)
	var effect := SpecEffect.make("work", "mul", 1.5, "staff:%d" % worker.id)
	rules.apply_effect("training", "w1", effect)
	check(is_equal_approx(rules.skill(worker), before * 1.5), "培养后这位员工手速 ×1.5")
	rules.mods.remove("training")
	check(is_equal_approx(rules.skill(worker), before), "撤掉后恢复")


func test_luck_raises_event_chance() -> void:
	var rules := ShopRules.new(TEA)
	var ev := _event("lucky", [])
	ev.chance = 0.1
	check(is_equal_approx(rules.event_chance(ev), 0.1), "没有幸运值时按基础概率")
	rules.apply_effect("training", "luck", SpecEffect.make("luck", "add", 0.5, "staff:%d" % rules.workers[0].id))
	check(is_equal_approx(rules.event_chance(ev), 0.15), "幸运值 0.5 → 概率 ×1.5")


func test_manager_visit_opens_staff_kind_without_touching_shop_data() -> void:
	var rules := ShopRules.new(PANCAKE)
	var before := PANCAKE.staff.hire_pool.duplicate()
	rules.apply_effect("event", "manager_visit", SpecEffect.make("unlock_staff_kind", "add", 1.0, "fox"))
	check("fox" in rules.hire_pool, "本局可招狐狸")
	check_eq(PANCAKE.staff.hire_pool, before, "店铺数据没被改")


func test_customer_wave_effect_brings_customers() -> void:
	var rules := ShopRules.new(PANCAKE)
	rules.unlock("soy_milk")
	var before := rules.arrivals()
	rules.apply_effect("event", "wave", SpecEffect.make("customer_wave", "add", 3.0))
	rules.run(12.0)
	check(rules.arrivals() >= before + 3, "一波 3 位客人进店")


# ---------- 干净检查（§7）：规则层不出现店铺、机器、菜品的名字 ----------

func test_rules_layer_has_no_shop_specific_names() -> void:
	var names: Array = []
	for shop in [TEA, PANCAKE]:
		names.append(shop.id)
		for st in shop.stations: names.append(st.id)
		for d in shop.dishes: names.append(d.id)
		for item in shop.items: names.append(item.id)
		for kind in shop.staff.kinds: names.append(kind.id)
	# 通用部件名（规则层常量）不算店铺专有
	names = names.filter(func(n: String) -> bool: return not n in ["counter", "supply", "topping", "rack"])
	for file in DirAccess.get_files_at("res://game/rules"):
		if not file.ends_with(".gd"): continue
		var text := FileAccess.get_file_as_string("res://game/rules/" + file)
		for name in names:
			check(not ('"%s"' % name) in text, "%s 里写死了 \"%s\"" % [file, name])


# ---------- 命令细节 ----------

func test_deploy_to_a_kitchen_post_seats_the_worker() -> void:
	var rules := _open_tea()
	rules.gold = 100000.0
	for id in ["boil"]: check_eq(rules.unlock(id), "", "解锁 " + id)
	check_eq(rules.hire(), "", "招人")
	var worker: Dictionary = rules.roster[-1]
	check_eq(rules.deploy_worker(worker.id, "boil"), "", "派到煮茶机坐班")
	check_eq(worker.post, "boil", "坐在煮茶机")
	check_eq(rules.post_owner("boil"), worker.id, "煮茶机有人了")
	check(rules.deploy_worker(worker.id, "nowhere") == "", "已上岗的员工再派一次不报错")


func test_reset_clears_single_mode_customers() -> void:
	var rules := ShopRules.new(PANCAKE)
	rules.unlock("soy_milk")
	rules.run(60.0)
	check(rules.arrivals() > 0, "有客人来过")
	rules.reset()
	check_eq(rules.queue.size(), 0, "重开后没有排队的人")
	check_eq(rules.customers.size(), 0, "重开后没有顾客")
	check_eq(rules.arrivals(), 0, "来客计数归零")
