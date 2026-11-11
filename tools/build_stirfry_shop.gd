extends SceneTree
## 小炒饭馆（北方城第 3 关，Notion《小炒饭馆｜设计稿 v0.3》）的店铺数据，交接方式 serve + 客人自取（dine_rule self_pickup）。
## 两个人开店：流动厨师（取料、炒浇头、盛饭合盘、送出餐口）+ 店长（接单分座）；客人在出餐口端走整单再入座。
## 菜单和解锁按 v0.3：番茄炒蛋盖饭开店 → 青椒肉丝（炒锅A配方 80）→ 炒锅B + 蛋炒饭 150 → 汤桶 + 例汤 220 → 宫保鸡丁（炒锅A配方 250）
## → 扬州炒饭（炒锅B配方 350）。v0.3 的“服务员 50”和“托盘 180”是送桌用的，自取以后不要了。
## 数值取 numbers-sim/stirfry_sim.py 的 fix5（v0.3 定数），客流按解锁次数去掉服务员那一档。写出 content/shops/stirfry/shop.tres：
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


static func item(shop: SpecShop, id: String, name: String) -> void:
	var it := SpecItem.new()
	it.id = id
	it.display_name = name
	shop.items.append(it)


## 盖饭：备料柜拿料 → 炒锅A炒浇头；电饭柜盛饭；装盘台合盘
static func rice_bowl(id: String, name: String, raw: String, topping: String, fry: String, seconds: float, price: float) -> SpecDish:
	var dish := SpecDish.new()
	dish.id = id
	dish.display_name = name
	dish.item = id
	dish.price_parts["base"] = price
	dish.takeaway_process = false
	dish.steps.assign([
		step("pantry", "fetch", 2.0, "拿料", {}, {raw: 1}),
		step("rice_cooker", "scoop", 1.0, "盛饭", {}, {"rice": 1}),
		step("wok_a", "stir_fry", seconds, fry, {raw: 1}, {topping: 1}),
		step("plating", "plate", 7.0, "装盘", {topping: 1, "rice": 1}, {id: 1}),
	])
	return dish


## 炒饭：备料柜拿料、电饭柜盛饭，一起进炒锅B炒成，不经装盘台
static func fried_rice(id: String, name: String, raw: String, fry: String, seconds: float, price: float) -> SpecDish:
	var dish := SpecDish.new()
	dish.id = id
	dish.display_name = name
	dish.item = id
	dish.price_parts["base"] = price
	dish.takeaway_process = false
	dish.steps.assign([
		step("pantry", "fetch", 2.0, "拿料", {}, {raw: 1}),
		step("rice_cooker", "scoop", 1.0, "盛饭", {}, {"rice": 1}),
		step("wok_b", "stir_fry", seconds, fry, {raw: 1, "rice": 1}, {id: 1}),
	])
	return dish


static func task(id: String, name: String, dish: String, amount: int) -> SpecTask:
	var t := SpecTask.new()
	t.id = id
	t.display_name = name
	t.condition = "sell_count"
	t.target = dish
	t.amount = amount
	return t


## 一个阶段：stations 开机器，或 recipe_at 在那台机器面板里买配方
static func stage(id: String, name: String, cost: int, dish: String, per_minute: float, weights: Dictionary, kitchen: int, tasks: Array, stations: Array = [], recipe_at := "", note := "") -> SpecStage:
	var st := SpecStage.new()
	st.id = id
	st.display_name = name
	st.stations.assign(stations)
	st.recipe_at = recipe_at
	st.cost = cost
	st.dish = dish
	st.unlock_note = note
	st.customer_interval = snappedf(60.0 / per_minute, 0.01)
	st.order_weights.assign(weights)
	st.staff_slots["kitchen"] = kitchen
	st.queue_capacity = 6
	st.seat_seconds = 45.0
	st.tasks.assign(tasks)
	return st


static func build() -> SpecShop:
	var shop := SpecShop.new()
	shop.id = "stirfry"
	shop.display_name = "小炒饭馆"
	shop.start_gold = 0
	shop.random_seed = 11
	shop.save_file = "shop_stirfry.json"
	for row in [["tomato_egg_raw", "番茄鸡蛋"], ["pepper_pork_raw", "青椒肉丝料"], ["kungpao_raw", "宫保鸡丁料"], ["egg_rice_raw", "鸡蛋葱花"],
			["yangzhou_raw", "扬州炒饭料"], ["rice", "米饭"], ["tomato_egg", "番茄炒蛋"], ["pepper_pork", "青椒肉丝"], ["kungpao", "宫保鸡丁"],
			["tomato_rice", "番茄炒蛋盖饭"], ["pepper_rice", "青椒肉丝盖饭"], ["kungpao_rice", "宫保鸡丁盖饭"], ["egg_fried_rice", "蛋炒饭"],
			["yangzhou_rice", "扬州炒饭"], ["soup", "例汤"]]:
		item(shop, row[0], row[1])

	# 机器：柜台（前厅接单）、备料柜（原料箱）、电饭柜（自动批量锅，出锅进饭盆共享库存）、炒锅A/B（手工台）、装盘台（要人的组合台）、
	# 汤桶（自动批量锅）、出餐口
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
	rice.description = "每锅蒸出几份米饭放进饭盆；盖饭和炒饭都从这里盛饭"
	var wok := station("wok_a", "炒锅A", "hand", {"seconds": 12.0, "users": 1, "unit": "份"})
	wok.seatable = true
	wok.tracks.append(track(15, 9, func(_lv: int) -> Array: return [effect("speed", "mul", 1.15)]))
	wok.description = "炒盖饭浇头，一次一份；新浇头在配方栏里学"
	var plating := station("plating", "装盘台", "combine", {"manual": true, "seconds": 7.0, "unit": "份"}, "wok_a")
	plating.price_dishes.assign(["tomato_rice", "pepper_rice", "kungpao_rice"])
	plating.tracks.append(track(12, 6, func(lv: int) -> Array: return [effect("price", "mul", 1.05)] + ([effect("price", "mul", 1.25)] if lv == 5 else [])))
	plating.description = "米饭和浇头都到齐了才装盘；升级提高三道盖饭的售价"
	var window := station("window", "出餐口", "pickup", {"unit": "份"}, "wok_a")
	# 炒锅B：Lv2–6 提速，Lv7–10 提高两道炒饭售价（第 3 个售价级加星）
	var wok_b := station("wok_b", "炒锅B", "hand", {"seconds": 14.0, "users": 1, "unit": "份"})
	wok_b.seatable = true
	wok_b.price_dishes.assign(["egg_fried_rice", "yangzhou_rice"])
	wok_b.tracks.append(track(12, 9, func(lv: int) -> Array:
		if lv <= 6: return [effect("speed", "mul", 1.15)]
		return [effect("price", "mul", 1.06)] + ([effect("price", "mul", 1.25)] if lv == 9 else [])))
	wok_b.description = "米饭和配料一起下锅炒成炒饭，不经装盘台"
	var soup := station("soup_pot", "汤桶", "batch_pot", {"cook_seconds": 60.0, "batch": 10, "capacity": 10, "manual_load": false, "manual_unload": false, "unit": "碗"})
	var soup_stock := SpecStockRule.new()
	soup_stock.item = "soup"
	soup_stock.cap = 10
	soup_stock.start = 10
	soup.stock.append(soup_stock)
	soup.price_dishes.assign(["soup"])
	soup.tracks.append(track(12, 5, func(_lv: int) -> Array: return [effect("price", "mul", 1.06)]))
	soup.description = "批量熬汤；约四成客人加一碗例汤，盛好放出餐口和主食一起端走"
	shop.stations.assign([counter, pantry, rice, wok, plating, window, wok_b, soup])

	var soup_dish := SpecDish.new()
	soup_dish.id = "soup"
	soup_dish.display_name = "例汤"
	soup_dish.item = "soup"
	soup_dish.price_parts["base"] = 4.0
	soup_dish.takeaway_process = false
	soup_dish.steps.assign([step("soup_pot", "ladle", 3.0, "盛汤", {}, {"soup": 1})])
	shop.dishes.assign([
		rice_bowl("tomato_rice", "番茄炒蛋盖饭", "tomato_egg_raw", "tomato_egg", "炒番茄炒蛋", 12.0, 12.0),
		rice_bowl("pepper_rice", "青椒肉丝盖饭", "pepper_pork_raw", "pepper_pork", "炒青椒肉丝", 12.0, 14.0),
		fried_rice("egg_fried_rice", "蛋炒饭", "egg_rice_raw", "炒蛋炒饭", 14.0, 11.0),
		soup_dish,
		rice_bowl("kungpao_rice", "宫保鸡丁盖饭", "kungpao_raw", "kungpao", "炒宫保鸡丁", 14.0, 17.0),
		fried_rice("yangzhou_rice", "扬州炒饭", "yangzhou_raw", "炒扬州炒饭", 16.0, 18.0),
	])

	# 阶段（v0.3 §4）：客流按解锁次数 3 / 4.5 / 5.5 / 6.5 / 9 / 9.5 人每分钟；例汤是附加菜，不进权重
	shop.stages.assign([
		stage("open", "开张", 0, "tomato_rice", 3.0, {"tomato_rice": 1.0}, 2,
			[task("sell_tomato", "卖出 20 份番茄炒蛋盖饭", "tomato_rice", 20)], ["wok_a"]),
		stage("pepper", "青椒肉丝盖饭", 80, "pepper_rice", 4.5, {"tomato_rice": 0.5, "pepper_rice": 0.5}, 3,
			[task("sell_pepper", "卖出 20 份青椒肉丝盖饭", "pepper_rice", 20)], [], "wok_a", "炒锅A学会青椒肉丝，盖饭多一种"),
		stage("fried_rice", "炒锅B · 蛋炒饭", 150, "egg_fried_rice", 5.5, {"tomato_rice": 0.3, "pepper_rice": 0.3, "egg_fried_rice": 0.4}, 4,
			[task("sell_egg", "卖出 20 份蛋炒饭", "egg_fried_rice", 20)], ["wok_b"], "", "第二口锅，炒饭和盖饭抢同一盆饭"),
		stage("soup", "汤桶 · 例汤", 220, "soup", 6.5, {"tomato_rice": 0.3, "pepper_rice": 0.3, "egg_fried_rice": 0.4}, 4,
			[task("sell_soup", "卖出 30 碗例汤", "soup", 30)], ["soup_pot"], "", "约四成客人加一碗例汤"),
		stage("kungpao", "宫保鸡丁盖饭", 250, "kungpao_rice", 9.0, {"tomato_rice": 0.2, "pepper_rice": 0.25, "egg_fried_rice": 0.25, "kungpao_rice": 0.3}, 5,
			[task("sell_kungpao", "卖出 15 份宫保鸡丁盖饭", "kungpao_rice", 15)], [], "wok_a", "炒锅A学会宫保鸡丁，客人一下多起来"),
		stage("yangzhou", "扬州炒饭", 350, "yangzhou_rice", 9.5, {"tomato_rice": 0.15, "pepper_rice": 0.2, "egg_fried_rice": 0.2, "kungpao_rice": 0.2, "yangzhou_rice": 0.25}, 5,
			[task("sell_yangzhou", "卖出 15 份扬州炒饭", "yangzhou_rice", 15)], [], "wok_b", "炒锅B学会扬州炒饭，最贵的一道"),
	])

	var f := SpecFulfillment.new()
	f.handoff = "serve"
	f.taker = "front"
	f.dine_rule = "self_pickup"
	f.pay_at = "on_deliver"
	f.price_rounding = "dish_tenth_carry"
	f.leave_queue = "after_take"
	f.wait_area = ""
	f.leave_who = "queued_unclaimed"
	f.leave_after = 60.0
	f.arrival = "exponential"
	f.first_customer_delay = 2.0
	f.customer_walk = 120.0
	f.addon_dish = "soup"
	f.addon_chance = 0.4
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
	for row in [["gray_cat", "小灰猫"], ["cat", "三花猫"], ["rabbit", "兔子"], ["bear", "小熊"], ["dog", "小狗"], ["sheep", "小羊"]]:
		var kind := SpecStaffKind.new()
		kind.id = row[0]
		kind.display_name = row[1]
		kind.stats = {"carry": 1.0, "walk": 360.0, "work": 1.5}
		staff.kinds.append(kind)
	staff.zones.assign(["front", "kitchen"])
	staff.front_base_slots = 1
	# 开局两人：流动厨师（后厨，不坐班）+ 店长（柜台）；招人 60 / 120 / 160 / 220，后厨位按阶段 2/3/4/4/5/5。
	# 这家店人手大半在端菜跑腿（机器人实测），所以员工走路 360、干活 1.5 倍，整店约 46 分钟
	staff.starting.assign(["gray_cat", "cat"])
	staff.starting_posts.assign(["", "counter"])
	staff.hire_pool.assign(["rabbit", "bear", "dog", "sheep"])
	staff.hire_costs.assign([60, 120, 160, 220])
	staff.can_drag = true
	staff.home_anchor = "home"
	shop.staff = staff

	var goals := SpecGoalRules.new()
	goals.order.assign(["open", "stage", "tasks"])
	goals.opening_station = "wok_a"
	goals.complete_when.assign(["all_stages", "all_tasks"])
	goals.rating_minutes.assign([40.0, 50.0])
	goals.rating_lost_share = 0.2
	goals.texts = {"open": "点{name}开张", "stage": "支付 {cost} 金币开{name}", "task": "{name}",
		"done": "小炒饭馆的任务都完成了", "hint_pot": "米饭供不上：升级{name}", "hint_pot_fix": "升级{name}",
		"hint_machine": "{drink}做不过来：升级{name}", "hint_machine_fix": "升级{name}", "hint_staff": "人手不够：多招一位", "hint_staff_fix": "招人"}
	shop.goals = goals

	# 走位按美术场景 presentation/shops/stirfry/stirfry_art.tscn（887×1774）：上面后厨、中间柜台和出餐口、
	# 下面 8 张双人桌（两列四排，开局 3 张 6 座，最多 16 座）。直线走。双灶左边是炒锅A、右边是炒锅B。
	var layout := SpecLayout.new()
	var points: Dictionary[String, Vector2] = {"counter": Vector2(215, 755), "pantry": Vector2(200, 660), "rice_cooker": Vector2(790, 480),
		"wok_a": Vector2(400, 340), "wok_b": Vector2(500, 340), "soup_pot": Vector2(800, 345), "plating": Vector2(720, 650),
		"window": Vector2(640, 755), "home": Vector2(450, 560), "door": Vector2(443, 1740)}
	var rows := [1050, 1233, 1423, 1611]
	var seat_x := [[121, 320], [574, 772]]
	for n in 16:
		var table := n / 2
		points["table/%d" % n] = Vector2(seat_x[table % 2][n % 2], rows[table / 2])
	layout.points = points
	layout.posts = {"counter": Vector2(215, 750), "wok_a": Vector2(400, 335), "wok_b": Vector2(500, 335)}
	layout.spawn_point = "home"
	shop.layout = layout
	shop.scene_path = "res://presentation/shops/stirfry/stirfry_art.tscn"
	return shop
