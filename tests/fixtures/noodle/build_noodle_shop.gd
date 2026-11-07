extends SceneTree
## 第三家测试店（规格 §7，不上线）：一家面馆，只用数据写成，不改任何规则代码。
## 有一条“几道菜共用同一样中间品”的链：骨汤锅一锅熬好几碗汤，清汤面、牛肉面、鸡蛋面都从这锅里舀；拉面台拉出的面也是几道菜共用。
## 写出 tests/fixtures/noodle/shop.tres：
##   godot --headless --path . -s tests/fixtures/noodle/build_noodle_shop.gd

const OUT := "res://tests/fixtures/noodle/shop.tres"


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


static func track(costs: Array, effects: Callable) -> SpecUpgradeTrack:
	var t := SpecUpgradeTrack.new()
	t.id = "level"
	t.display_name = "等级"
	for i in costs.size():
		var l := SpecUpgradeLevel.new()
		l.cost = costs[i]
		l.effects.assign(effects.call(i + 2))
		t.levels.append(l)
	return t


static func station(id: String, name: String, block: String, cost: int, params: Dictionary) -> SpecStation:
	var st := SpecStation.new()
	st.id = id
	st.display_name = name
	st.block = block
	st.unlock_cost = cost
	st.params = params
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


static func dish(id: String, name: String, base: float, steps: Array, flavor := "", topping := 0.0) -> SpecDish:
	var d := SpecDish.new()
	d.id = id
	d.display_name = name
	d.item = id
	d.price_parts["base"] = base
	if topping > 0.0: d.price_parts["topping"] = topping
	d.steps.assign(steps)
	d.takeaway_process = false
	if not flavor.is_empty():
		d.flavor_station = "toppings"
		d.flavor_material = flavor
		d.topping_count = 1
	return d


static func task(id: String, name: String, condition: String, target: String, amount: float) -> SpecTask:
	var t := SpecTask.new()
	t.id = id
	t.display_name = name
	t.condition = condition
	t.target = target
	t.amount = amount
	return t


static func stage(id: String, stations: Array, cost: int, dish_id: String, interval: float, weights: Dictionary, slots: int, queue: int, seats: int) -> SpecStage:
	var s := SpecStage.new()
	s.id = id
	s.display_name = id
	s.stations.assign(stations)
	s.cost = cost
	s.dish = dish_id
	s.customer_interval = interval
	s.order_weights.assign(weights)
	s.staff_slots[""] = slots
	s.queue_capacity = queue
	s.wait_seats = seats
	return s


static func build() -> SpecShop:
	var shop := SpecShop.new()
	shop.id = "noodle"
	shop.display_name = "测试面馆"
	shop.start_gold = 10
	shop.random_seed = 7
	shop.save_file = "shop_noodle_test.json"
	for row in [["dough", "面团"], ["noodle", "拉面"], ["broth", "骨汤"], ["barley_tea", "大麦茶"], ["dry_noodle", "拌面"],
			["clear_noodle", "清汤面"], ["beef_noodle", "牛肉面"], ["egg_noodle", "鸡蛋面"]]:
		var item := SpecItem.new()
		item.id = row[0]
		item.display_name = row[1]
		shop.items.append(item)

	# 机器：柜台、茶桶（开张那台）、面粉缸（随拉面台开）、拉面台（手工台，一次一人）、骨汤锅（批量锅，备汤）、浇头台、装碗台
	var counter := station("counter", "柜台", "counter", 0, {"hand_seconds": 0.5, "posts": 1, "take_seconds": 1.0, "unit": "碗"})
	counter.starts_unlocked = true
	var urn := station("urn", "茶桶", "dispenser", 10, {"seconds": 1.0, "unit": "杯"})
	urn.price_dishes.assign(["barley_tea"])
	urn.tracks.append(track([10, 20, 40], func(_lv: int) -> Array: return [effect("price", "mul", 1.1)]))
	var flour := station("flour", "面粉缸", "supply", 0, {"fetch_seconds": 1.0, "unit": "份"})
	flour.companion_of = "board"
	var board := station("board", "拉面台", "hand", 40, {"seconds": 6.0, "users": 1, "unit": "碗"})
	board.tracks.append(track([30, 60, 120], func(_lv: int) -> Array: return [effect("duration", "mul", 0.85)]))
	var pot := station("pot", "骨汤锅", "batch_pot", 120, {"batch": 6, "cook_seconds": 20.0, "fetch_seconds": 0.5, "load_seconds": 1.5,
		"manual_load": true, "manual_unload": true, "unload_seconds": 1.5, "load_label": "加水下骨头", "unload_label": "盛汤", "unit": "碗"})
	var broth := SpecStockRule.new()
	broth.item = "broth"
	broth.cap = 12
	broth.low = 3
	broth.start = 6
	pot.stock.append(broth)
	pot.tracks.append(track([80, 160], func(_lv: int) -> Array: return [effect("duration", "mul", 0.85)]))
	var toppings := station("toppings", "浇头台", "topping", 240, {"seconds": 1.0, "users": 0, "unit": "碗"})
	toppings.price_dishes.assign(["beef_noodle", "egg_noodle"])
	toppings.tracks.append(track([90, 180], func(lv: int) -> Array:
		return [effect("price", "mul", 1.1), effect("open_flavor", "set", 1.0, "egg_noodle")] if lv == 2 else [effect("price", "mul", 1.1)]))
	var bowl := station("bowl", "装碗台", "combine", 0, {"manual": true, "seconds": 1.5, "unit": "碗"})
	bowl.starts_unlocked = true
	shop.stations.assign([counter, urn, flour, board, pot, toppings, bowl])

	# 菜：清汤面、牛肉面、鸡蛋面都舀同一锅骨汤，拉面台的面四道面都用
	var pull := [step("flour", "fetch", 1.0, "拿面团", {}, {"dough": 1}), step("board", "pull", 6.0, "拉面", {"dough": 1}, {"noodle": 1})]
	var ladle := step("pot", "ladle", 0.5, "舀汤", {"broth": 1}, {})
	shop.dishes.assign([
		dish("barley_tea", "大麦茶", 4.0, [step("urn", "pour", 1.0, "倒茶", {}, {"barley_tea": 1})]),
		dish("dry_noodle", "拌面", 12.0, pull + [step("bowl", "bowl", 1.5, "装碗", {"noodle": 1}, {"dry_noodle": 1})]),
		dish("clear_noodle", "清汤面", 16.0, pull + [ladle, step("bowl", "bowl", 1.5, "装碗", {"noodle": 1}, {"clear_noodle": 1})]),
		dish("beef_noodle", "牛肉面", 16.0, pull + [ladle, step("toppings", "top", 1.0, "加牛肉"), step("bowl", "bowl", 1.5, "装碗", {"noodle": 1}, {"beef_noodle": 1})], "beef", 8.0),
		dish("egg_noodle", "鸡蛋面", 16.0, pull + [ladle, step("toppings", "top", 1.0, "加鸡蛋"), step("bowl", "bowl", 1.5, "装碗", {"noodle": 1}, {"egg_noodle": 1})], "egg", 5.0),
	])

	# 四段：开张卖大麦茶 → 拉面台卖拌面 → 骨汤锅卖清汤面 → 浇头台卖牛肉面、鸡蛋面
	shop.stages.assign([
		stage("stage0", ["urn"], 10, "barley_tea", 9.0, {"barley_tea": 1.0}, 1, 3, 0),
		stage("stage1", ["board"], 40, "dry_noodle", 7.0, {"dry_noodle": 0.6, "barley_tea": 0.4}, 2, 4, 2),
		stage("stage2", ["pot"], 120, "clear_noodle", 6.0, {"clear_noodle": 0.5, "dry_noodle": 0.2, "barley_tea": 0.3}, 3, 4, 4),
		stage("stage3", ["toppings"], 240, "beef_noodle", 5.0, {"clear_noodle": 0.3, "noodles": 0.5, "barley_tea": 0.2}, 4, 5, 6),
	])
	shop.stages[3].flavor_group = "noodles"
	shop.stages[3].tasks.assign([task("clear20", "卖出 20 碗清汤面", "sell_count", "clear_noodle", 20), task("egg", "开出鸡蛋面", "flavor_open", "egg_noodle", 1),
		task("beef10", "卖出 10 碗牛肉面", "sell_count", "beef_noodle", 10)])

	# 履约、调度、传单、员工、目标：一人跟单，和煎饼摊同一套规则，只是参数不同
	var f := SpecFulfillment.new()
	f.addon_dish = "barley_tea"
	f.addon_chance = 0.2
	f.addon_first = true
	f.dine_rule = "takeaway_only"
	f.taker = "follower"
	f.handoff = "single"
	f.pay_at = "on_take"
	f.price_rounding = "order_round"
	f.leave_queue = "after_pay"
	f.wait_area = "wait_seats"
	f.leave_after = 50.0
	f.leave_who = "queued_unclaimed"
	f.arrival = "exponential"
	f.first_customer_delay = 1.0
	shop.fulfillment = f
	var d := SpecDispatch.new()
	d.base_scores = {"chore": 100.0, "take": 50.0}
	d.merge = "fixed"
	d.merge_cap = 1
	d.help_while_waiting = true
	d.chores_first = true
	shop.dispatch = d
	var flyer := SpecFlyer.new()
	flyer.gap = 2.0
	flyer.when_full = "lost"
	flyer.track = SpecUpgradeTrack.new()
	flyer.track.id = "flyer"
	flyer.track.display_name = "传单"
	flyer.track.base_effects.assign([effect("flyer_customers", "set", 3.0), effect("flyer_cooldown", "set", 90.0)])
	shop.flyer = flyer
	var cushions := SpecSeatGroup.new()
	cushions.id = "bench"
	cushions.purpose = "wait"
	shop.seat_groups.append(cushions)
	var staff := SpecStaffRules.new()
	for row in [["sheep", "小羊"], ["dog", "小狗"], ["hamster", "仓鼠"]]:
		var kind := SpecStaffKind.new()
		kind.id = row[0]
		kind.display_name = row[1]
		kind.stats = {"carry": 1.0, "walk": 180.0, "work": 1.0}
		staff.kinds.append(kind)
	staff.starting.assign(["sheep"])
	staff.hire_pool.assign(["sheep", "dog", "hamster"])
	staff.hire_rule = "cycle"
	staff.hire_order.assign(["dog", "hamster", "sheep"])
	staff.hire_costs.assign([25, 80, 160])
	staff.home_anchor = "home"
	shop.staff = staff
	var goals := SpecGoalRules.new()
	goals.order.assign(["open", "box", "stage", "tasks"])
	goals.opening_station = "urn"
	goals.complete_when.assign(["all_stages", "all_flavors", "all_tasks"])
	goals.rating_minutes.assign([15.0, 20.0])
	goals.rating_lost_share = 0.2
	goals.texts = {"open": "支付 {cost} 金币开{name}，开始营业", "stage": "支付 {cost} 金币开{name}", "task": "{name}",
		"done": "测试面馆的任务都完成了", "hint_pot": "骨汤供不上：升级{name}", "hint_pot_fix": "升级{name}",
		"hint_machine": "{drink}做不过来：升级{name}", "hint_machine_fix": "升级{name}", "hint_staff": "人手不够：多招一位", "hint_staff_fix": "招人"}
	shop.goals = goals

	# 直线走：每台机器前一个站位
	var layout := SpecLayout.new()
	layout.points = {"counter": Vector2(360, 700), "urn": Vector2(200, 680), "flour": Vector2(560, 420), "board": Vector2(420, 420),
		"pot": Vector2(260, 460), "toppings": Vector2(500, 540), "bowl": Vector2(600, 620), "home": Vector2(480, 640)}
	layout.spawn_point = "home"
	shop.layout = layout
	return shop
