extends "res://tests/test_case.gd"
## 小炒饭馆最小原型（Notion《小炒饭馆｜设计稿 v0.3》§8 首个原型通过条件，规格 §10 草案）：
## 交接方式 serve = 订单明细 + 组合台等齐 + 共享米饭库存与预留 + 前厅送餐到座。全部走通用规则层，店铺只给数据。

const STIRFRY: SpecShop = preload("res://content/shops/stirfry/shop.tres")
const ServeFlow := preload("res://game/rules/serve_flow.gd")
const Validator := preload("res://game/rules/shop_spec_validator.gd")


func _open(shop: SpecShop = STIRFRY) -> ShopRules:
	var rules := ShopRules.new(shop)
	rules.unlock("wok_a")
	return rules


func _chef(rules: ShopRules) -> Dictionary:
	for w in rules.workers:
		if w.post != rules.counter_id: return w
	return {}


func _manager(rules: ShopRules) -> Dictionary:
	for w in rules.workers:
		if w.post == rules.counter_id: return w
	return {}


func _count(rules: ShopRules, item: String) -> int:
	var n := 0
	for g in rules.serve.goods:
		if g.item == item: n += 1
	return n


## 每件实物都在合法位置、预留都有对应的活：用存档校验器整体核一遍
func _consistent(rules: ShopRules) -> String:
	var copy := ShopRules.new(rules.shop)
	return copy.load_dict(rules.to_dict())


func _shop_copy() -> SpecShop:
	return STIRFRY.duplicate(true)


func test_data_passes_the_capability_contract() -> void:
	check_eq(Validator.summary(Validator.validate(STIRFRY)), "", "小炒饭馆原型数据过配置校验")
	check(not "stirfry" in preload("res://content/campaign/campaign.tres").shop_ids(), "原型还没进关卡表")


func test_unsupported_serve_combinations_are_rejected() -> void:
	var shop := _shop_copy()
	shop.station("rice_cooker").params["manual_load"] = true
	shop.station("plating").params["manual"] = false
	shop.fulfillment.customer_walk = 0.0
	var text := Validator.summary(Validator.validate(shop))
	check("rice_cooker" in text, "要人装料的批量锅还不支持，明确拒绝")
	check("plating" in text, "自动组合台还不支持，明确拒绝")
	check("customer_walk" in text, "送桌店必须给顾客走路速度")
	var broken := _shop_copy()
	broken.dish("tomato_rice").steps[3].consumes["tomato_egg"] = 1
	broken.dish("tomato_rice").steps.remove_at(2)
	check("Inputs must be produced" in Validator.summary(Validator.validate(broken)), "合流的输入必须由前面的工序做出")


## §8-1：两人、最低等级、不招第三人，第一份番茄炒蛋盖饭走完接单 → 两路取料制作 → 合盘 → 出餐 → 送桌 → 开始用餐
func test_two_staff_serve_the_first_rice_bowl_end_to_end() -> void:
	var rules := _open()
	check_eq(rules.workers.size(), 2, "开局两人")
	check_eq(String(_manager(rules).post), "counter", "店长在柜台")
	check_eq(String(_chef(rules).post), "", "厨师流动")
	var trail: Array = []
	var record := func(message: Dictionary) -> void:
		if message.name in ["order_taken", "made", "delivered", "sale", "seated", "eat_start"]:
			trail.append([message.name, message.data.get("station", ""), rules.clock])
	rules.events.on("*", record)
	var first_eat := -1.0
	var jobs := {}
	while rules.clock < 180.0 and first_eat < 0.0:
		rules.step(0.1)
		for w in rules.workers:
			var job := ServeFlow.job_of(rules, w)
			if not job.is_empty(): jobs["%s:%s" % [w.kind, job.kind]] = true
		for e in trail:
			if e[0] == "eat_start": first_eat = e[2]
	rules.events.off("*", record)
	check(first_eat > 0.0, "三分钟内第一位客人开吃（第 %.1f 秒）" % first_eat)
	var names: Array = trail.map(func(e: Array) -> String: return e[0] + ("@" + e[1] if not e[1].is_empty() else ""))
	var order := ["order_taken", "made@wok_a", "made@plating", "delivered", "sale", "eat_start"]
	var at := 0
	for name in names:
		if at < order.size() and name == order[at]: at += 1
	check_eq(at, order.size(), "事件按 接单 → 炒浇头 → 合盘 → 送达 → 结账 → 开吃 的顺序：%s" % [names])
	check(jobs.has("cat:take") and jobs.has("cat:serve"), "店长接单也送桌")
	for kind in ["carry", "work", "pass"]: check(jobs.has("gray_cat:" + kind), "厨师做 " + kind)
	check(not jobs.has("cat:carry") and not jobs.has("cat:work") and not jobs.has("gray_cat:serve") and not jobs.has("gray_cat:take"), "前厅后厨各管各的")
	check_eq(rules.roster.size(), 2, "没招第三人")
	check(rules.sold >= 1 and rules.serve.served >= 1 and rules.gold >= 12.0, "收了一份钱（%d 金币）" % rules.gold)


## §8-2：缺米饭或缺浇头时不产生完整盖饭；同一份米饭不会被两个任务领走
func test_combine_waits_for_both_inputs_and_rice_is_never_taken_twice() -> void:
	var shop := _shop_copy()
	shop.station("rice_cooker").stock[0].start = 0
	shop.station("rice_cooker").params["cook_seconds"] = 100000.0
	var rules := _open(shop)
	check_eq(int(ServeFlow.stock(rules, "rice_cooker").available), 0, "饭盆空着")
	rules.run(120.0)
	check(_count(rules, "tomato_egg") >= 1, "浇头炒好了（%d 份）" % _count(rules, "tomato_egg"))
	check_eq(_count(rules, "tomato_rice"), 0, "没饭就合不出盖饭")
	for g in rules.serve.goods:
		if g.item == "tomato_egg": check(g.at == "plating" or g.at.begins_with("hand:"), "浇头送到装盘台等饭")
	# 来一份饭：两份浇头都在等，只有一份能领到
	var waiting := _count(rules, "tomato_egg")
	rules.stations.rice_cooker.phase = "cook"
	rules.stations.rice_cooker.processing = 1
	rules.stations.rice_cooker.remaining = 0.1
	rules.stations.rice_cooker.duration = 1.0
	var watch := {"max": 0}
	while rules.clock < 200.0:
		rules.step(0.1)
		var reserved := int(ServeFlow.stock(rules, "rice_cooker").reserved)
		watch.max = maxi(watch.max, reserved)
		check(int(ServeFlow.stock(rules, "rice_cooker").available) >= 0, "库存不为负")
	check(waiting >= 2, "至少两份在等饭（%d）" % waiting)
	var plated := 0
	for g in rules.serve.goods:
		if g.item == "tomato_rice" and not String(g.at).begins_with("seat:"): plated += 1
	check_eq(_count(rules, "rice") + plated + rules.sold, 1, "一份米饭只变成一份盖饭")
	check(watch.max <= 1, "同一时刻最多一份预留")
	check_eq(_consistent(rules), "", "库存、预留、手上的活前后一致")


## §8-3：调岗 / 收回后，未消耗的预留释放；拿在手上的东西放回拿的地方，仍归那份餐
func test_reassigning_a_carrier_releases_reservations_and_keeps_goods() -> void:
	var rules := _open()
	var chef := _chef(rules)
	var picked := false
	while rules.clock < 120.0 and not picked:
		rules.step(0.1)
		var job := ServeFlow.job_of(rules, chef)
		picked = not job.is_empty() and job.kind == "carry" and job.item == "rice" and job.stage == "go_to"
	check(picked, "厨师端着米饭在路上")
	var good: Dictionary = {}
	for g in rules.serve.goods:
		if g.at == "hand:%d" % chef.id: good = g
	var owner := int(good.owner)
	var rice_before := _count(rules, "rice")
	check_eq(rules.recall_worker(chef.id), "", "把厨师收回名册")
	check_eq(String(good.at), "rice_cooker", "米饭放回饭盆旁")
	check_eq(int(good.owner), owner, "仍归原来那份餐，不回共享库存")
	check_eq(int(good.res), -1, "预留释放")
	check_eq(_count(rules, "rice"), rice_before, "米饭件数守恒")
	check(ServeFlow.job_of(rules, chef).is_empty() and chef.carry_count == 0, "手上清空")
	check_eq(_consistent(rules), "", "收回后状态自洽")
	check_eq(rules.deploy_worker(chef.id), "", "再派回后厨")
	rules.run(90.0)
	check(rules.sold >= 1, "接着把那份餐做完送出（卖出 %d）" % rules.sold)
	# 正在炒的时候调岗：炒锅占用释放、原料留在锅前
	var cooking := false
	while rules.clock < 400.0 and not cooking:
		rules.step(0.1)
		var job := ServeFlow.job_of(rules, chef)
		cooking = not job.is_empty() and job.kind == "work" and job.stage == "work" and job.from == "wok_a"
	check(cooking, "厨师在炒")
	var raw := _count(rules, "tomato_egg_raw")
	check_eq(rules.place_worker(chef.id, ""), "", "拖到空地重新流动")
	check_eq(int(rules.stations.wok_a.user), -1, "炒锅占用释放")
	check_eq(_count(rules, "tomato_egg_raw"), raw, "没炒完的原料还在")
	check_eq(_consistent(rules), "", "中断后状态自洽")


## §8-4：开吃由规则状态判定：没坐下或餐没齐都不计时
func test_eating_starts_only_when_seated_and_fully_served() -> void:
	var shop := _shop_copy()
	shop.fulfillment.customer_walk = 2.0
	var rules := _open(shop)
	var early := false
	while rules.clock < 300.0 and rules.sold < 1:
		rules.step(0.1)
		for g in rules.serve.guests:
			if g.state == "eating": early = true
	check(rules.sold >= 1, "餐送到了")
	check(not early, "餐送到时客人还在路上，不开吃")
	var guest: Dictionary = {}
	for g in rules.serve.guests:
		if int(g.order) >= 0 and ServeFlow.order_complete(ServeFlow.order(rules, int(g.order))): guest = g
	check_eq(String(guest.get("state", "")), "to_seat", "整单齐了但还没坐下")
	var sales := {"n": 0}
	var count_sale := func(message: Dictionary) -> void:
		if message.name == "sale": sales.n += 1
	rules.events.on("*", count_sale)
	var paid := int(rules.serve.served)
	while rules.clock < 900.0 and guest.state != "eating": rules.step(0.1)
	rules.events.off("*", count_sale)
	check_eq(String(guest.state), "eating", "走到座位才开吃")
	check(is_equal_approx(float(guest.eat_left), rules.seat_seconds() - 0.1) or float(guest.eat_left) <= rules.seat_seconds(), "从坐下起算用餐时间")
	check_eq(int(rules.serve.served) - paid, sales.n, "每单只结一次账")
	check(bool(ServeFlow.order(rules, int(guest.order)).paid), "这单已经结过")
	# 反过来：坐下了但餐没来，也不吃
	var fast := _open()
	var seated_hungry := false
	while fast.clock < 120.0:
		fast.step(0.1)
		for g in fast.serve.guests:
			if g.state == "seated" and not ServeFlow.order_complete(ServeFlow.order(fast, int(g.order))): seated_hungry = true
			if g.state == "eating": check(ServeFlow.order_complete(ServeFlow.order(fast, int(g.order))), "开吃的都是整单送齐的")
	check(seated_hungry, "有客人坐着等餐")


## §8-5：坐班的厨师只做本机，不会自己搬料；要有流动的人搬，产线才转
func test_seated_cook_does_not_silently_carry() -> void:
	var rules := _open()
	var chef := _chef(rules)
	check_eq(rules.place_worker(chef.id, "wok_a"), "", "厨师坐到炒锅A")
	rules.run(120.0)
	check_eq(_count(rules, "tomato_egg_raw") + _count(rules, "tomato_egg"), 0, "没人搬料，锅前一份原料都没有")
	check_eq(rules.sold, 0, "也就卖不出去")
	check(rules.no_kitchen_carrier(), "瓶颈查询能看出来：后厨没人搬")
	rules.gold = 1000.0
	check_eq(rules.hire(), "", "招一个帮厨")
	var helper: Dictionary = rules.roster[-1]
	check_eq(rules.deploy_worker(helper.id), "", "帮厨流动")
	var kinds := {}
	while rules.clock < 300.0:
		rules.step(0.1)
		var job := ServeFlow.job_of(rules, chef)
		if not job.is_empty(): kinds[job.kind] = true
	check(rules.sold >= 1, "帮厨搬料后开始出餐（%d）" % rules.sold)
	kinds.erase("home")
	check_eq(kinds.keys(), ["work"], "坐班厨师只在本机干活")


## §8-6（本轮能验的部分）：中途存读档后结果连续；人数、单数、件数、流失分开统计
func test_save_resume_and_counters() -> void:
	var rules := _open()
	rules.run(240.0)
	check(rules.serve.guests.size() > 0 and rules.serve.goods.size() > 0, "店里有客人、有东西在做")
	var copy := ShopRules.new(STIRFRY)
	check_eq(copy.load_dict(rules.to_dict()), "", "中途存档能读")
	rules.run(120.0)
	copy.run(120.0)
	check_eq(copy.to_dict(), rules.to_dict(), "读档以后接着跑一模一样")
	check_eq(int(rules.serve.items_sold), rules.sold, "售出件数")
	check_eq(int(rules.serve.orders_done), int(rules.serve.served), "本店一单一人")
	check(rules.arrivals() >= int(rules.serve.served) + rules.lost, "进店人数 ≥ 吃上的 + 流失的")
	var view := ShopView.new(rules)
	check(not String(view.goal().text).is_empty(), "目标栏有字")
	for st in STIRFRY.stations: check(not view.station(st.id).is_empty(), "%s 有机器面板" % st.display_name)
	view.bottleneck()


## 一人开局只能慢慢出：开张头 5 分钟后厨人手是瓶颈（设计稿 §4 第 0 段），招帮厨后出餐变快
func test_helper_relieves_the_opening_bottleneck() -> void:
	var solo := _open()
	solo.run(600.0)
	var duo := _open()
	duo.gold = 60.0
	duo.hire()
	duo.deploy_worker(duo.roster[-1].id)
	duo.gold = 0.0
	duo.run(600.0)
	check(duo.serve.served > solo.serve.served, "有帮厨 10 分钟服务 %d 人，没有 %d 人" % [duo.serve.served, solo.serve.served])
	check(solo.lost > 0, "只有一个厨师时有人等不及走掉（%d）" % solo.lost)
	check_eq(_consistent(duo), "", "两人后厨状态自洽")


## 电饭柜升级到每锅份数超过库存上限后，饭盆空了照样开锅（不会停产）
func test_rice_cooker_keeps_cooking_after_batch_exceeds_capacity() -> void:
	var rules := _open()
	rules.gold = 100000.0
	while rules.upgrade_cost("rice_cooker") >= 0: check_eq(rules.upgrade("rice_cooker"), "", "升级电饭柜")
	check(rules.pot_batch("rice_cooker") > ServeFlow.pot_cap(STIRFRY, "rice_cooker"), "每锅 %d 份，超过上限 %d" % [rules.pot_batch("rice_cooker"), ServeFlow.pot_cap(STIRFRY, "rice_cooker")])
	var start := rules.sold
	rules.run(600.0)
	check(int(rules.stations.rice_cooker.processing) > 0 or int(ServeFlow.stock(rules, "rice_cooker").available) > 0 or rules.sold - start > 8, "饭盆空了照样开锅")
	check(rules.sold - start > 8, "十分钟里卖出的份数超过开局那 8 份米饭（%d）" % (rules.sold - start))


func _working_state(rules: ShopRules) -> Dictionary:
	while rules.clock < 120.0:
		rules.step(0.1)
		for job in rules.serve.jobs.values():
			if job.kind == "work" and job.stage == "work": return rules.to_dict()
	check(false, "应能推进到正在加工的状态")
	return rules.to_dict()


func test_invalid_serve_jobs_are_rejected_without_changing_live_state() -> void:
	var rules := _open()
	var base := _working_state(rules)
	check_eq(_consistent(rules), "", "正常工作状态能读档")
	var key := ""
	for id in base.serve.jobs:
		if base.serve.jobs[id].kind == "work": key = id
	if key.is_empty(): return
	var cases := [
		["step", -1], ["step", 999], ["step", 0],
		["stage", "unknown"], ["stage", "pick"],
		["from", "missing"], ["to", "missing"], ["from", "pantry"],
	]
	for entry in cases:
		var invalid := base.duplicate(true)
		invalid.serve.jobs[key][entry[0]] = entry[1]
		check(not rules.load_dict(invalid).is_empty(), "拒绝任务 %s=%s" % entry)
		check(rules.to_dict() == base, "拒绝后保留原状态")
	var sleeping := base.duplicate(true)
	sleeping.serve.jobs[key].stage = "go_from"
	check(not rules.load_dict(sleeping).is_empty(), "拒绝走路阶段和员工状态不匹配的任务")
	check(rules.to_dict() == base, "阶段不匹配不改变原状态")


func test_serve_guest_cannot_reference_a_missing_order_or_wrong_seat() -> void:
	var rules := _open()
	var base := _working_state(rules)
	var missing := base.duplicate(true)
	missing.serve.orders.clear()
	missing.serve.units.clear()
	missing.serve.goods.clear()
	missing.serve.jobs.clear()
	for st in missing.stations.values(): st.user = -1
	for w in missing.roster:
		w.walking = false
		w.phase = "idle"
		w.carry_item = ""
		w.carry_count = 0
	check(not rules.load_dict(missing).is_empty(), "拒绝已分座顾客引用不存在的订单")
	var wrong := base.duplicate(true)
	wrong.serve.orders[0].seat += 1
	check(not rules.load_dict(wrong).is_empty(), "拒绝顾客和订单座位不一致")
	check(rules.to_dict() == base, "无效引用不改变原状态")


func test_unlock_seeds_only_new_stations_and_keeps_existing_rice() -> void:
	var shop := _shop_copy()
	var wok: SpecStation = shop.station("wok_a").duplicate(true)
	wok.id = "other_wok"
	shop.stations.append(wok)
	shop.layout.points[wok.id] = Vector2(600, 400)
	var pot: SpecStation = shop.station("rice_cooker").duplicate(true)
	pot.id = "other_pot"
	pot.companion_of = wok.id
	pot.stock[0].start = 2
	shop.stations.append(pot)
	shop.layout.points[pot.id] = Vector2(600, 450)
	var stage: SpecStage = shop.stages[0].duplicate(true)
	stage.id = "second"
	stage.stations.assign([wok.id])
	stage.tasks.clear()
	shop.stages[0].tasks.clear()
	shop.stages.append(stage)
	check_eq(Validator.summary(Validator.validate(shop)), "", "两阶段数据合法")
	var rules := _open(shop)
	check_eq(int(ServeFlow.stock(rules, "rice_cooker").available), 4, "首台锅获得开局库存")
	while rules.clock < 120.0:
		rules.step(0.1)
		var stock := ServeFlow.stock(rules, "rice_cooker")
		if int(stock.available) + int(stock.reserved) < 4: break
	var before: Array = rules.serve.goods.duplicate(true)
	var old_stock := ServeFlow.stock(rules, "rice_cooker")
	check_eq(int(old_stock.available) + int(old_stock.reserved), 3, "已取走一份米饭")
	check_eq(rules.unlock(wok.id), "", "解锁下一阶段")
	check_eq(ServeFlow.stock(rules, "rice_cooker"), old_stock, "旧锅库存和在制保持不变")
	check_eq(int(ServeFlow.stock(rules, pot.id).available), 2, "仅新锅得到自己的初始库存")
	for good in before: check(good in rules.serve.goods, "已有实物及预留保持不变")
	check_eq(rules.serve.goods.size(), before.size() + 2, "只生成新锅的两份初始库存")
	check_eq(_consistent(rules), "", "解锁后状态能存读档")


func test_delivery_callbacks_capture_resumable_settled_orders() -> void:
	var rules := _open()
	var snapshots: Array = []
	var listener := func(message: Dictionary) -> void:
		if message.name in ["delivered", "sale", "eat_start"]:
			snapshots.append({"name": message.name, "order": rules.serve.orders[0].id, "state": rules.to_dict()})
	rules.events.on("*", listener)
	while rules.clock < 180.0 and snapshots.size() < 3: rules.step(0.1)
	rules.events.off("*", listener)
	check_eq(snapshots.map(func(s: Dictionary) -> String: return s.name), ["delivered", "sale", "eat_start"], "保留送达、结账、开吃的广播顺序")
	for snapshot in snapshots:
		var resumed := ShopRules.new(STIRFRY)
		var error := resumed.load_dict(snapshot.state)
		check_eq(error, "", snapshot.name + " 回调状态可以读档")
		if not error.is_empty(): continue
		var order := ServeFlow.order(resumed, int(snapshot.order))
		check(bool(order.paid), snapshot.name + " 回调前已结账")
		check_eq(resumed.gold, 12.0, "第一单只收一次钱")
		check_eq(String(ServeFlow.guest(resumed, int(order.guest)).state), "eating", "回调前已完成开吃状态")
		var manager := _manager(resumed)
		check(ServeFlow.job_of(resumed, manager).is_empty(), "已送达的任务已清除")
		resumed.recall_worker(manager.id)
		resumed.run(90.0)
		check(ServeFlow.order(resumed, int(snapshot.order)).is_empty(), "读档后正常吃完离店")
		check_eq(resumed.gold, 12.0, "继续运行不会漏收或重复结账")


func test_active_serve_job_stages_and_work_callbacks_remain_loadable() -> void:
	var rules := _open()
	var seen := {}
	var callbacks := {}
	var listener := func(message: Dictionary) -> void:
		if message.name in ["order_taken", "made"]:
			callbacks[message.name] = true
			check_eq(_consistent(rules), "", message.name + " 回调没有残留的已完成任务")
	rules.events.on("*", listener)
	while rules.clock < 120.0:
		rules.step(0.1)
		for job in rules.serve.jobs.values():
			var key: String = job.kind + ":" + job.stage
			if seen.has(key): continue
			seen[key] = true
			check_eq(_consistent(rules), "", key + " 正常状态可读档")
	rules.events.off("*", listener)
	for kind in ["take", "work", "carry", "pass", "serve"]:
		check(seen.keys().any(func(key: String) -> bool: return key.begins_with(kind + ":")), "覆盖 " + kind + " 任务")
	check(callbacks.has("order_taken") and callbacks.has("made"), "覆盖接单和加工回调")


func test_serve_transport_jobs_require_the_goods_the_worker_is_carrying() -> void:
	var rules := _open()
	var chef := _chef(rules)
	while rules.clock < 120.0:
		rules.step(0.1)
		var job := ServeFlow.job_of(rules, chef)
		if not job.is_empty() and job.kind == "carry" and job.stage == "go_to": break
	var base := rules.to_dict()
	var key := str(chef.id)
	check_eq(_consistent(rules), "", "正常搬运状态能读档")
	for field in ["good", "item"]:
		var invalid := base.duplicate(true)
		invalid.serve.jobs[key][field] = -1 if field == "good" else "rice"
		if field == "good":
			invalid.serve.goods = invalid.serve.goods.filter(func(g: Dictionary) -> bool: return g.at != "hand:" + key)
		check(not rules.load_dict(invalid).is_empty(), "拒绝搬运任务的 " + field + " 不一致")
	var dropped := base.duplicate(true)
	for good in dropped.serve.goods:
		if good.at == "hand:" + key: good.at = "pantry"
	check(not rules.load_dict(dropped).is_empty(), "送往目标的物品必须确实在员工手里")
	check(rules.to_dict() == base, "无效搬运任务不改变原状态")


func _pickup_shop() -> SpecShop:
	var shop := _shop_copy()
	shop.fulfillment.dine_rule = "self_pickup"
	return shop


## 自取（dine_rule = self_pickup）：接单分座后客人走到出餐口等，整单齐了自己端走，走到座位才开吃；前厅不送桌
func test_self_pickup_guest_collects_the_whole_order_then_eats_at_the_seat() -> void:
	var shop := _pickup_shop()
	check_eq(Validator.summary(Validator.validate(shop)), "", "自取是通用 serve 的合法参数")
	var bad := _shop_copy()
	bad.fulfillment.dine_rule = "walk_in"
	check("dine_rule" in Validator.summary(Validator.validate(bad)), "不认识的入座规则明确拒绝")
	var rules := _open(shop)
	var trail: Array = []
	var states := {}
	var jobs := {}
	var record := func(message: Dictionary) -> void:
		if message.name in ["order_taken", "await_pickup", "picked_up", "delivered", "sale", "seated", "eat_start"]:
			trail.append(message.name)
	rules.events.on("*", record)
	var bad_eat := false
	var bad_window := false
	while rules.clock < 300.0 and not "eat_start" in trail:
		rules.step(0.1)
		for w in rules.workers:
			var job := ServeFlow.job_of(rules, w)
			if not job.is_empty(): jobs["%s:%s" % [w.kind, job.kind]] = true
		for g in rules.serve.guests:
			states[g.state] = true
			if g.state == "eating" and not ServeFlow.order_complete(ServeFlow.order(rules, int(g.order))): bad_eat = true
			if g.state in ["to_pickup", "await"]:
				for good in rules.serve.goods:
					var u := ServeFlow.unit(rules, int(good.owner)) if int(good.owner) >= 0 else {}
					if not u.is_empty() and int(u.order) == int(g.order) and String(good.at).begins_with("seat:"): bad_window = true
	rules.events.off("*", record)
	check("eat_start" in trail, "五分钟内第一位客人开吃")
	var order := ["order_taken", "await_pickup", "picked_up", "delivered", "sale", "seated", "eat_start"]
	var at := 0
	for name in trail:
		if at < order.size() and name == order[at]: at += 1
	check_eq(at, order.size(), "接单 → 到出餐口 → 端走 → 结账 → 坐下 → 开吃：%s" % [trail])
	for state in ["to_pickup", "await", "to_seat"]: check(states.has(state), "客人经过 " + state)
	check(not jobs.has("cat:serve") and not jobs.has("gray_cat:serve"), "没人送桌")
	check(jobs.has("cat:take") and jobs.has("gray_cat:pass"), "店长接单，厨师把餐放上出餐口")
	check(not bad_eat, "开吃的都是整单齐的")
	check(not bad_window, "客人没端走前，餐不会自己跑到座位上")
	check_eq(rules.gold, 12.0, "第一单只收一次钱")
	check_eq(_consistent(rules), "", "自取状态自洽")


## 自取：等在出餐口、在路上、坐下吃，任何时刻存读档都接得上，读档后跑出来一模一样；送桌店不受影响
func test_self_pickup_save_resume_matches_and_seat_wait_is_unchanged() -> void:
	var shop := _pickup_shop()
	var rules := _open(shop)
	var saved := {}
	while rules.clock < 600.0 and saved.size() < 3:
		rules.step(0.1)
		for g in rules.serve.guests:
			if g.state in ["await", "to_seat", "eating"] and not saved.has(g.state):
				check_eq(_consistent(rules), "", String(g.state) + " 时可读档")
				saved[g.state] = rules.to_dict()
	check_eq(saved.size(), 3, "等取餐、去座位、用餐三个时刻都存到了")
	for key in saved:
		var a := ShopRules.new(shop)
		var b := ShopRules.new(shop)
		check_eq(a.load_dict(saved[key]), "", key + " 存档能读")
		b.load_dict(saved[key])
		a.run(120.0)
		b.run(120.0)
		check_eq(a.to_dict(), b.to_dict(), key + " 读档后接着跑结果一致")
		check_eq(_consistent(a), "", key + " 读档后跑两分钟仍自洽")
	var long_run := _open(shop)
	long_run.run(900.0)
	check(long_run.serve.served >= 5, "自取店 15 分钟能服务多位客人（%d）" % long_run.serve.served)
	check_eq(int(long_run.serve.orders_done), int(long_run.serve.served), "一单一人")
	check_eq(_consistent(long_run), "", "长跑后状态自洽")
	# 送桌店不受影响：店长照样送桌，客人不会去出餐口
	var classic := _open()
	var serve_job := false
	var went_to_window := false
	while classic.clock < 180.0:
		classic.step(0.1)
		if ServeFlow.job_of(classic, _manager(classic)).get("kind", "") == "serve": serve_job = true
		for g in classic.serve.guests:
			if g.state in ["to_pickup", "await"]: went_to_window = true
	check(serve_job, "送桌店店长照样送桌")
	check(not went_to_window, "送桌店客人不去出餐口")
