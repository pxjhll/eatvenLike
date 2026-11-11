extends "res://tests/test_case.gd"
## Frozen v0 business regression; formal v1 coverage: test_first_shops_migration.

const TEA: SpecShop = preload("res://tests/fixtures/legacy_shops/tea.tres")
const PANCAKE: SpecShop = preload("res://tests/fixtures/legacy_shops/pancake.tres")


func ready_rules(shop: SpecShop) -> ShopRules:
	var rules := ShopRules.new(shop, 9)
	rules.gold = 1e8
	rules.stage_index = shop.stages.size() - 1
	for station in shop.stations: rules.unlocked[station.id] = true
	for key in rules.boxes: rules.boxes[key] = true
	return rules


func test_cultivation_card_uses_effective_stats() -> void:
	for shop in [PANCAKE, TEA]:
		var rules := ready_rules(shop)
		var worker: Dictionary = rules.workers[0]
		var zone := rules.side_of(worker)
		check_eq(rules.upgrade("staff/" + zone), "", "真实培养成功")
		rules.tune.walk = 1.5
		var card := ShopView.new(rules).worker_card(worker)
		check_eq(card.stats.walk, rules.walk_speed(worker), "卡片显示当前有效移速")
		check_eq(card.stats.work, rules.skill(worker), "卡片显示当前有效操作")
		check_eq(card.stats.carry, rules.carry(worker), "卡片显示当前有效搬运")
		check(card.get("cultivation", "").contains("1/"), "显示区域已购培养而非个人 Lv1")
		check(card.cultivation.begins_with("培养"), "培养进度不可误读为员工人数")
		check(rules.has_method("worker_stat_limits"), "属性条上限来自培养数据")
		if rules.has_method("worker_stat_limits"):
			var before := rules.to_dict()
			var limits: Dictionary = rules.call("worker_stat_limits", worker)
			check(limits.walk > rules.walk_speed(worker), "仍可培养的移速不提前满条")
			check_eq(rules.to_dict(), before, "上限查询不改变运行状态")


func test_every_recipe_action_tuning_changes_actual_timer() -> void:
	var rules := ready_rules(PANCAKE)
	var worker: Dictionary = rules.workers[0]
	worker.order = 7
	worker.steps = rules._order_steps({"kind": "family", "addon": true, "options": ["bag"]})
	for index in worker.steps.size():
		var step: Dictionary = worker.steps[index]
		if step.station == rules.counter_id: continue
		worker.step = index
		rules.stations.fryer.stock = 10
		rules.tune[step.station] = 1.0
		rules._arrived_single(worker)
		var baseline := float(worker.timer)
		rules.tune[step.station] = 3.0
		rules._arrived_single(worker)
		check(is_equal_approx(worker.timer, baseline * 3.0), "%s/%s 调参影响真实动作" % [step.station, step.action])
		if rules.has_method("manual_operation_seconds"):
			check_eq(worker.timer, rules.call("manual_operation_seconds", step.station, step.seconds, worker, step.get("fixed", false)), "执行使用共享查询")
		rules.tune[step.station] = 1.0


func test_fixed_and_pot_pickup_ignore_cook_upgrade_but_allow_tuning() -> void:
	var rules := ready_rules(PANCAKE)
	var worker: Dictionary = rules.workers[0]
	worker.order = 7
	worker.steps = rules._order_steps({"kind": "guozi", "addon": false})
	for index in worker.steps.size():
		var step: Dictionary = worker.steps[index]
		if not step.get("fixed", false) and step.station != "fryer": continue
		worker.step = index
		rules.stations.fryer.stock = 10
		rules._arrived_single(worker)
		var baseline := float(worker.timer)
		check_eq(rules.upgrade(step.station), "", "真实设备升级")
		rules._arrived_single(worker)
		check_eq(worker.timer, baseline, "固定工序/取料不受烹饪升级影响")
		rules.tune[step.station] = 3.0
		rules._arrived_single(worker)
		check(is_equal_approx(worker.timer, baseline * 3.0), "固定工序/取料仍受时间调参影响")


func test_manual_and_automatic_timing_snapshots_use_execution_units() -> void:
	var rules := ready_rules(TEA)
	var view := ShopView.new(rules)
	rules.tune.lemonade = 3.0
	var worker: Dictionary = rules.workers[0].duplicate(true)
	worker.stats.work = 1.0
	var duration := rules._action_duration({"kind": "work", "src": "lemonade", "count": 1}, worker)
	check_eq(view.seconds("lemonade"), duration, "无员工加成的快照等于实际操作")
	check(view.has_method("station_timing"), "提供带单位时间快照")
	if not view.has_method("station_timing"): return
	check_eq(view.call("station_timing", "mix").unit, "批", "自动组合按每批")
	check_eq(view.call("station_timing", "boil").unit, "锅", "批量锅按每锅")
	var single := ShopView.new(ready_rules(PANCAKE))
	check_eq(single.seconds("rear_equipment"), 10.0, "人工台选实际主要非固定工序")
	check_eq(single.call("station_timing", "bag").unit, "次", "选项工序按每次")


func test_material_price_keeps_fraction_and_partial_scope() -> void:
	var rules := ready_rules(TEA)
	var view := ShopView.new(rules)
	check_eq(view.price_preview("supply/tea_leaf").next, 31.5, "保留小数报价")
	var row := view.material_row(TEA.station("supply"), TEA.station("supply").material("tea_leaf"))
	check(row.effect.contains("31.5"), "原料展示不能截断为31")
	var single := ShopView.new(ready_rules(PANCAKE))
	check(single.track_row("topping").effect.contains("部分"), "配料倍率说明作用在部分价格")


func test_quotes_match_real_single_receipts_and_order_options() -> void:
	var rules := ready_rules(PANCAKE)
	rules.upgrade("soy_milk")
	check(rules.has_method("dish_quote"), "规则提供计算价和结算政策")
	if not rules.has_method("dish_quote"): return
	var quote: Dictionary = rules.call("dish_quote", "soy")
	check(is_equal_approx(quote.calculated, 6.3), "计算价保留小数")
	check_eq(quote.solo_payment, 6, "单点整单取整")
	for order in [{"kind": "soy", "addon": false, "options": []}, {"kind": "guozi", "addon": true, "options": ["bag"]}]:
		order.merge({"id": 7, "claimed": true, "state": "queue"})
		rules.customers = [order]
		var worker: Dictionary = rules.workers[0]
		worker.order = 7
		worker.steps = rules._order_steps(order)
		worker.step = 0
		var before := rules.gold
		rules._finish_work_single(worker)
		worker.step = worker.steps.size() - 1
		rules._finish_work_single(worker)
		check_eq(rules.gold - before, float(rules.order_price_single(order)), "真实收款遵循整单选项规则")
		if order.kind == "soy": check_eq(rules.gold - before, float(quote.solo_payment), "报价等于实际单点收款")
		else: check_eq(rules.gold - before, 34.0, "22×1.25+6.3整单33.8收34，附加菜不乘选项")
	var preview := ShopView.new(rules).price_preview("soy_milk")
	check_eq(preview.payment_now, 6, "预览单独提供实收")
	check(ShopView.new(rules).track_row("soy_milk").effect.contains("实收"), "设备价格明确实收")


func test_cook_progress_captures_duration_and_accepts_old_state() -> void:
	var rules := ready_rules(PANCAKE)
	var worker: Dictionary = rules.workers[0]
	worker.chore = "load:fryer"
	rules._finish_work_single(worker)
	var pot: Dictionary = rules.stations.fryer
	pot.remaining = 9.0
	var view := ShopView.new(rules)
	check_eq(view.machine_status("fryer").progress, 0.5, "开锅中途一半")
	rules.tune.fryer = 3.0
	rules.upgrade("fryer")
	check_eq(view.machine_status("fryer").progress, 0.5, "升级调参不改变本锅进度")
	pot.duration = 0.0
	check(is_finite(view.machine_status("fryer").progress), "旧档无duration仍可显示")
	check_eq(view.machine_status("fryer").progress, clampf(1.0 - 9.0 / rules.pot_seconds("fryer"), 0.0, 1.0), "旧档按当前基准回退")
	var old := rules.to_dict()
	var restored := ShopRules.new(PANCAKE)
	check_eq(restored.load_dict(old), "", "恢复没有本锅duration的旧状态")
	var resumed := ShopView.new(restored)
	var before: float = resumed.machine_status("fryer").progress
	restored.tune.fryer = 0.25
	check_eq(resumed.machine_status("fryer").progress, before, "旧档恢复捕获回退值，调参前不必等下一帧")


func test_time_sliders_change_complete_order_delivery() -> void:
	var durations := []
	for factor in [1.0, 3.0]:
		var rules := ready_rules(PANCAKE)
		rules.tune.roll = factor
		rules.tune.bag = factor
		rules._spawn_single()
		rules.customers[0].kind = "plain"
		rules.customers[0].addon = false
		rules.customers[0].options = ["bag"]
		rules._next_customer = 10000.0
		while rules.sold == 0 and rules.clock < 120.0: rules.step(0.1)
		check_eq(rules.sold, 1, "完整走路制作装袋递餐后卖出")
		durations.append(rules.clock)
	# Roll 2.5s + bag 2s, each lengthened by 2x at skill 1.
	check(absf(durations[1] - durations[0] - 9.0) <= 0.21, "滑杆改变完整订单约9秒人工工作（逐帧量化）：%s" % str(durations))


func test_tea_quote_keeps_fractional_carry_at_real_sale_boundary() -> void:
	var rules := ready_rules(TEA)
	check_eq(rules.upgrade("lemonade"), "", "升级产生小数单价")
	var quote: Dictionary = rules.call("dish_quote", "lemonade")
	check(is_equal_approx(quote.calculated, 12.6), "查询保留12.6单价")
	check(not quote.has("solo_payment"), "累计结算不伪造固定单杯实收")
	var receipts := []
	for unused in 5:
		var before := rules.gold
		rules._record_sale({"item": "lemonade", "count": 1, "order_id": -1, "src": "lemonade", "dst": "counter", "takeaway": true})
		receipts.append(int(rules.gold - before))
	check_eq(receipts, [12, 13, 12, 13, 13], "真实交付累计五杯63金币")
	check(ShopView.new(rules).quote_text(quote).contains("小数累计"), "展示解释累计结算")
