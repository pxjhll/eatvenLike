extends SceneTree
## 小炒饭馆最小原型（Notion《小炒饭馆｜设计稿 v0.3》§8，规格 §10 草案）的店铺数据。还没进关卡表；美术场景已有，灰盒观察器拿它当底图。
## 两个人开店：流动厨师（取料、炒浇头、取饭合盘、送出餐口）+ 店长（接单分座、送桌）；一道番茄炒蛋盖饭。
## 数值取 numbers-sim/stirfry_sim.py 的 fix5（v0.3 定数）。写出 content/shops/stirfry/shop.tres：
##   godot --headless --path . -s tools/build_stirfry_shop.gd

const OUT := "res://content/shops/stirfry/shop.tres"


func _initialize() -> void:
	var error := ResourceSaver.save(build(), OUT)
	print("%s %s" % ["写出" if error == OK else "失败", OUT])
	quit(0 if error == OK else 1)


static func effect(kind: String, op: String, value: float, target := "") -> SpecEffect:
	var e := SpecEffect.new()
	e.kind = kind
	e.op = op
	e.value = value
	e.target = target
	return e


## 费用按 v0.3：首级 c0 × 1.1，逐级 ×1.3（模拟里的 geo）
static func track(c0: float, count: int, effects: Callable) -> SpecUpgradeTrack:
	var t := SpecUpgradeTrack.new()
	t.id = "level"
	t.display_name = "等级"
	for i in count:
		var l := SpecUpgradeLevel.new()
		l.cost = roundi(c0 * 1.1 * pow(1.3, i))
		l.effects.assign(effects.call(i + 2))
		t.levels.append(l)
	return t


static func station(id: String, name: String, block: String, params: Dictionary, companion := "") -> SpecStation:
	var st := SpecStation.new()
	st.id = id
	st.display_name = name
	st.block = block
	st.params = params
	st.companion_of = companion
	st.zone = "front" if block == "counter" else "kitchen"
	return st


static func step(at: String, action: String, seconds: float, label: String, consumes := {}, produces := {}) -> SpecStep:
	var s := SpecStep.new()
	s.station = at
	s.action = action
	s.seconds = seconds
	s.label = label
	s.consumes.assign(consumes)
	s.produces.assign(produces)
	return s


static func build() -> SpecShop:
	var shop := SpecShop.new()
	shop.id = "stirfry"
	shop.display_name = "小炒饭馆"
	shop.start_gold = 0
	shop.random_seed = 11
	shop.save_file = "shop_stirfry_proto.json"
	for row in [["tomato_egg_raw", "番茄鸡蛋"], ["rice", "米饭"], ["tomato_egg", "番茄炒蛋"], ["tomato_rice", "番茄炒蛋盖饭"]]:
		var item := SpecItem.new()
		item.id = row[0]
		item.display_name = row[1]
		shop.items.append(item)

	# 机器：柜台（前厅接单）、备料柜（原料箱）、电饭柜（自动批量锅，出锅进饭盆共享库存）、炒锅A（手工台）、装盘台（要人的组合台）、出餐口
	var counter := station("counter", "柜台", "counter", {"take_seconds": 5.0, "hand_seconds": 1.0, "posts": 1, "unit": "份"})
	counter.starts_unlocked = true
	var pantry := station("pantry", "备料柜", "supply", {"fetch_seconds": 2.0, "unit": "份"}, "wok_a")
	var rice := station("rice_cooker", "电饭柜", "batch_pot", {"cook_seconds": 60.0, "batch": 4, "capacity": 8, "manual_load": false, "manual_unload": false, "unit": "份"}, "wok_a")
	var rice_stock := SpecStockRule.new()
	rice_stock.item = "rice"
	rice_stock.cap = 8
	rice_stock.start = 4
	rice.stock.append(rice_stock)
	rice.tracks.append(track(25, 7, func(lv: int) -> Array: return [effect("batch", "set", 4.0 + 2.0 * (lv - 1))]))
	rice.description = "每锅蒸出几份米饭放进饭盆；饭要有人来盛"
	var wok := station("wok_a", "炒锅A", "hand", {"seconds": 12.0, "users": 1, "unit": "份"})
	wok.seatable = true
	wok.tracks.append(track(15, 9, func(_lv: int) -> Array: return [effect("speed", "mul", 1.15)]))
	wok.description = "炒盖饭浇头，一次一份，人要一直站在锅前"
	var plating := station("plating", "装盘台", "combine", {"manual": true, "seconds": 7.0, "unit": "份"}, "wok_a")
	plating.price_dishes.assign(["tomato_rice"])
	plating.tracks.append(track(12, 6, func(lv: int) -> Array: return [effect("price", "mul", 1.05)] + ([effect("price", "mul", 1.25)] if lv == 5 else [])))
	plating.description = "米饭和浇头都到齐了才装盘"
	var window := station("window", "出餐口", "pickup", {"unit": "份"}, "wok_a")
	shop.stations.assign([counter, pantry, rice, wok, plating, window])

	# 番茄炒蛋盖饭：两路（备料柜 → 炒锅A 炒浇头；电饭柜 → 米饭）在装盘台合流
	var dish := SpecDish.new()
	dish.id = "tomato_rice"
	dish.display_name = "番茄炒蛋盖饭"
	dish.item = "tomato_rice"
	dish.price_parts["base"] = 12.0
	dish.takeaway_process = false
	dish.steps.assign([
		step("pantry", "fetch", 2.0, "拿番茄鸡蛋", {}, {"tomato_egg_raw": 1}),
		step("rice_cooker", "scoop", 1.0, "盛饭", {}, {"rice": 1}),
		step("wok_a", "stir_fry", 12.0, "炒番茄炒蛋", {"tomato_egg_raw": 1}, {"tomato_egg": 1}),
		step("plating", "plate", 7.0, "装盘", {"tomato_egg": 1, "rice": 1}, {"tomato_rice": 1}),
	])
	shop.dishes.assign([dish])

	var stage := SpecStage.new()
	stage.id = "open"
	stage.display_name = "开张"
	stage.stations.assign(["wok_a"])
	stage.cost = 0
	stage.dish = "tomato_rice"
	stage.customer_interval = 20.0
	stage.order_weights.assign({"tomato_rice": 1.0})
	stage.staff_slots["kitchen"] = 2
	stage.queue_capacity = 6
	stage.seat_seconds = 45.0
	var sell := SpecTask.new()
	sell.id = "sell20"
	sell.display_name = "卖出 20 份番茄炒蛋盖饭"
	sell.condition = "sell_count"
	sell.target = "tomato_rice"
	sell.amount = 20
	stage.tasks.append(sell)
	shop.stages.assign([stage])

	var f := SpecFulfillment.new()
	f.handoff = "serve"
	f.taker = "front"
	f.dine_rule = "seat_wait"
	f.pay_at = "on_deliver"
	f.price_rounding = "dish_tenth_carry"
	f.leave_queue = "after_take"
	f.wait_area = ""
	f.leave_who = "queued_unclaimed"
	f.leave_after = 60.0
	f.arrival = "exponential"
	f.first_customer_delay = 2.0
	f.customer_walk = 120.0
	shop.fulfillment = f
	var d := SpecDispatch.new()
	d.base_scores = {"take": 60.0, "serve": 70.0, "pass": 55.0, "work": 50.0, "carry": 45.0}
	d.wait_bonus_per_second = 0.5
	d.wait_bonus_cap = 30.0
	d.travel_penalty = 0.01
	d.hop_seconds = 0.5
	d.merge = "fixed"
	d.merge_cap = 1
	shop.dispatch = d

	var flyer := SpecFlyer.new()
	flyer.gap = 3.0
	flyer.when_full = "lost"
	flyer.track = SpecUpgradeTrack.new()
	flyer.track.id = "flyer"
	flyer.track.display_name = "传单"
	flyer.track.base_effects.assign([effect("flyer_customers", "set", 3.0), effect("flyer_cooldown", "set", 90.0)])
	shop.flyer = flyer
	var tables := SpecSeatGroup.new()
	tables.id = "table"
	tables.purpose = "dine"
	tables.start = 6
	tables.step = 2
	tables.costs.assign([80, 100, 120, 140, 160])
	tables.seconds = 45.0
	shop.seat_groups.append(tables)

	var staff := SpecStaffRules.new()
	for row in [["gray_cat", "小灰猫"], ["cat", "三花猫"], ["rabbit", "兔子"], ["bear", "小熊"]]:
		var kind := SpecStaffKind.new()
		kind.id = row[0]
		kind.display_name = row[1]
		kind.stats = {"carry": 1.0, "walk": 180.0, "work": 1.0}
		staff.kinds.append(kind)
	staff.zones.assign(["front", "kitchen"])
	staff.front_base_slots = 1
	# 开局两人：流动厨师（后厨，不坐班）+ 店长（柜台）
	staff.starting.assign(["gray_cat", "cat"])
	staff.starting_posts.assign(["", "counter"])
	staff.hire_pool.assign(["rabbit", "bear"])
	staff.hire_costs.assign([60, 120, 220])
	staff.can_drag = true
	staff.home_anchor = "home"
	shop.staff = staff

	var goals := SpecGoalRules.new()
	goals.order.assign(["open", "stage", "tasks"])
	goals.opening_station = "wok_a"
	goals.complete_when.assign(["all_stages", "all_tasks"])
	goals.rating_minutes.assign([10.0, 15.0])
	goals.rating_lost_share = 0.2
	goals.texts = {"open": "点{name}开张", "stage": "支付 {cost} 金币开{name}", "task": "{name}",
		"done": "小炒饭馆原型的任务都完成了", "hint_pot": "米饭供不上：升级{name}", "hint_pot_fix": "升级{name}",
		"hint_machine": "{drink}做不过来：升级{name}", "hint_machine_fix": "升级{name}", "hint_staff": "人手不够：多招一位", "hint_staff_fix": "招人"}
	shop.goals = goals

	# 走位按美术场景 presentation/shops/stirfry/stirfry_art.tscn（887×1774）：上面后厨、中间柜台和出餐口、
	# 下面 8 张双人桌（两列四排，开局 3 张 6 座，最多 16 座）。直线走。场景 Anchors/Nav 里摆着同一份点，测试核对两边一致。
	var layout := SpecLayout.new()
	var points: Dictionary[String, Vector2] = {"counter": Vector2(215, 755), "pantry": Vector2(200, 660), "rice_cooker": Vector2(790, 480),
		"wok_a": Vector2(450, 340), "plating": Vector2(720, 650), "window": Vector2(640, 755), "home": Vector2(450, 560), "door": Vector2(443, 1740)}
	var rows := [1050, 1233, 1423, 1611]
	var seat_x := [[121, 320], [574, 772]]
	for n in 16:
		var table := n / 2
		points["table/%d" % n] = Vector2(seat_x[table % 2][n % 2], rows[table / 2])
	layout.points = points
	layout.posts = {"counter": Vector2(215, 750), "wok_a": Vector2(450, 335)}
	layout.spawn_point = "home"
	shop.layout = layout
	shop.scene_path = "res://presentation/shops/stirfry/stirfry_art.tscn"
	return shop
