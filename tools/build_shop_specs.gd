extends SceneTree
## 把 main 73b0ae3 两家店的数值原样搬进通用店铺数据（规格 §4）：
##   godot --headless --path . -s tools/build_shop_specs.gd
## 读旧数据（tea.tres / art_shop_progression.tres / press_table.tres / 奶茶店模拟里的常量），
## 写出 content/shops/tea/shop.tres、content/shops/pancake/shop.tres、content/campaign/campaign.tres。
## 煎饼摊旧模拟已删（第 4 个 PR），它的数值直接在 shop.tres 里编辑，这里只补界面数据。
## 这是一次性迁移工具：奶茶店旧模拟删除后（第 5 个 PR）它也一起删，之后直接在 Godot 里编辑 shop.tres。
## 这里允许出现店铺和机器的名字，规则层不允许（§7 干净检查只扫 game/rules 和共用界面）。

const TeaSim := preload("res://game/tea_playtest/tea_shop_sim.gd")

const OUT_TEA := "res://content/shops/tea/shop.tres"
const OUT_PANCAKE := "res://content/shops/pancake/shop.tres"
const OUT_CAMPAIGN := "res://content/campaign/campaign.tres"
const TEA_ART := "res://presentation/shops/tea/tea_art.tscn"


func _initialize() -> void:
	var tea := build_tea()
	var pancake := build_pancake()
	var campaign := build_campaign()
	var failed := false
	for pair in [[tea, OUT_TEA], [pancake, OUT_PANCAKE], [campaign, OUT_CAMPAIGN]]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(String(pair[1]).get_base_dir()))
		var error := ResourceSaver.save(pair[0], pair[1])
		print("%s %s" % ["写出" if error == OK else "失败", pair[1]])
		failed = failed or error != OK
	quit(1 if failed else 0)


# ---------- 小工具 ----------

static func effect(kind: String, op: String, value: float, target := "", dishes: Array = [], part := "") -> SpecEffect:
	var e := SpecEffect.make(kind, op, value, target)
	e.dishes.assign(dishes)
	e.price_part = part
	return e


static func level(cost: int, effects: Array, star := false) -> SpecUpgradeLevel:
	var l := SpecUpgradeLevel.new()
	l.cost = cost
	l.effects.assign(effects)
	l.star = star
	return l


static func track(id: String, name: String, label := "") -> SpecUpgradeTrack:
	var t := SpecUpgradeTrack.new()
	t.id = id
	t.display_name = name
	t.effect_label = label
	return t


static func item(id: String, name: String) -> SpecItem:
	var i := SpecItem.new()
	i.id = id
	i.display_name = name
	return i


static func step(station: String, action: String, seconds: float, label: String, consumes := {}, produces := {}, repeat := 1) -> SpecStep:
	var s := SpecStep.new()
	s.station = station
	s.action = action
	s.seconds = seconds
	s.label = label
	for k in consumes: s.consumes[k] = consumes[k]
	for k in produces: s.produces[k] = produces[k]
	s.repeat = repeat
	return s


static func task(id: String, name: String, condition: String, target: String, amount: float) -> SpecTask:
	var t := SpecTask.new()
	t.id = id
	t.display_name = name
	t.condition = condition
	t.target = target
	t.amount = amount
	return t


## 旧“美术店”涨价机器 → 升级轨：每级售价 ×(1 + step)，到星级再 ×star_mult；可选每级速度 / 每锅份数（set）。
static func art_track(id: String, name: String, label: String, costs: Array, price_step: float, price_dishes: Array,
		star_levels: Array, star_mult: float, speeds: Array = [], batch: Array = []) -> SpecUpgradeTrack:
	var t := track(id, name, label)
	if not speeds.is_empty(): t.base_effects.append(effect("speed", "set", speeds[0]))
	if not batch.is_empty(): t.base_effects.append(effect("batch", "set", batch[0]))
	for index in costs.size():
		var lv := index + 2
		var effects: Array = []
		if price_step > 0.0: effects.append(effect("price", "mul", 1.0 + price_step, "", price_dishes))
		var star: bool = lv in star_levels
		if star and star_mult != 1.0: effects.append(effect("price", "mul", star_mult, "", price_dishes))
		if not speeds.is_empty(): effects.append(effect("speed", "set", speeds[mini(lv, speeds.size()) - 1]))
		if not batch.is_empty(): effects.append(effect("batch", "set", batch[mini(lv, batch.size()) - 1]))
		t.levels.append(level(int(costs[index]), effects, star))
	# 旧面板的举例顺序和简称（柠檬茶 > 奶茶 > 红茶 > 柠檬水）
	var names := {"lemon_tea": "柠檬茶", "plain_milk_tea": "奶茶", "black_tea": "红茶", "lemonade": "柠檬水"}
	var shown: Array = []
	for dish in ["lemonade", "black_tea", "plain_milk_tea", "lemon_tea"]:
		if dish in price_dishes: shown.append(names[dish])
	for dish in ["lemon_tea", "plain_milk_tea", "black_tea", "lemonade"]:
		if dish in price_dishes: t.preview_dishes.append(dish)
	t.preview_label = "、".join(shown)
	return t


# ---------- 奶茶店 ----------

func build_tea() -> SpecShop:
	var sim = TeaSim.new()
	var config = sim.CONFIG
	var progression = sim.PROGRESSION
	var press = sim.PRESS_DEF
	var shop := SpecShop.new()
	shop.id = "tea"
	shop.display_name = config.display_name
	shop.start_gold = config.starting_gold
	shop.random_seed = config.random_seed
	shop.flavor_flow = progression.flavor_flow
	shop.level_flow = progression.level_flow
	# 通用界面层 + 奶茶店美术场景（锚点在场景里，§6.1）
	shop.scene_path = TEA_ART
	shop.save_file = "shop_tea.json"
	shop.scale_anchor = "cup"

	for definition in config.items: shop.items.append(item(definition.id, definition.display_name))
	shop.items.append(item("lemon_tea", "柠檬茶"))

	var lemonade = sim._definition("lemonade")
	var boil = sim._definition("boil")
	var mix = sim._definition("mix")
	var topping = sim._definition("topping")
	var supply = sim._definition("supply")

	# 菜品与工序链（§3.1）。茶汤 = 煮茶机一锅的中间品；红茶 = 茶汤直接出餐。
	var fetch_leaf := step("supply", "fetch", 0.6, "拿茶叶", {}, {"tea_leaf": 1})
	var brew := step("boil", "boil", 0.0, "煮茶", {"tea_leaf": 1}, {"tea": 1})
	var mix_step := step("mix", "mix", 0.0, "调奶", {"tea": 1, "milk": 1}, {"plain_milk_tea": 1})
	for definition in config.dishes:
		var dish := SpecDish.new()
		dish.id = definition.id
		dish.display_name = definition.display_name
		dish.item = definition.item_id
		dish.price_parts["base"] = float(definition.price)
		dish.front = definition.id in sim.FRONT_DISHES
		dish.takeaway_process = not dish.front
		match definition.id:
			"lemonade":
				dish.steps.append(step("lemonade", "pour", lemonade.cycle_seconds, "打柠檬水", {}, {"lemonade": 1}))
			"lemon_tea":
				dish.steps.append(step("lemonade", "pour", lemonade.cycle_seconds, "打柠檬水", {}, {"lemonade": 1}))
				dish.steps.append(step("press", "press", press.art_seconds, "捣柠檬", {"lemonade": 1}, {"lemon_tea": 1}))
				dish.flavor_station = "press"
				dish.flavor_material = "lemon"
			"black_tea":
				dish.steps.append_array([fetch_leaf, brew, step("seal", "place", 0.0, "放出餐口", {"tea": 1}, {"black_tea": 1})])
			"plain_milk_tea":
				dish.steps.append_array([fetch_leaf, brew, mix_step, step("seal", "place", 0.0, "放出餐口", {"plain_milk_tea": 1}, {})])
			_:
				var material = null
				for m in topping.materials:
					if m.item_id == definition.id: material = m
				dish.flavor_station = "topping"
				dish.flavor_material = material.id
				dish.topping_count = 1
				dish.steps.append_array([fetch_leaf, brew, mix_step,
					step("topping", "top", sim._topping_seconds(), "加" + material.display_name, {"plain_milk_tea": 1}, {definition.id: 1}),
					step("seal", "place", 0.0, "放出餐口", {definition.id: 1}, {})])
		shop.dishes.append(dish)
	# 菜单顺序照旧模拟（同一顺序抽单，随机数才对得上）
	shop.dishes.sort_custom(func(a: SpecDish, b: SpecDish) -> bool: return sim.DISHES.find(a.id) < sim.DISHES.find(b.id))

	# 机器（§3.3）
	var stations := {}
	var s := SpecStation.new()
	s.id = "counter"
	s.display_name = "柜台"
	s.block = "counter"
	s.zone = "front"
	s.starts_unlocked = true
	s.params = {"take_seconds": 0.0, "hand_seconds": 0.6, "posts": 2}
	stations[s.id] = s

	s = SpecStation.new()
	s.id = "lemonade"
	s.display_name = lemonade.display_name
	s.block = "dispenser"
	s.zone = "front"
	s.params = {"seconds": lemonade.cycle_seconds}
	s.unlock_cost = sim._unlock_cost("lemonade")
	s.price_dishes.assign(lemonade.art_price_dishes)
	s.counts_for_flow = "lemonade" in sim.FLOW_MACHINES
	s.tracks.append(art_track("level", lemonade.display_name, "售价", lemonade.art_costs, lemonade.art_price_step,
		lemonade.art_price_dishes, lemonade.art_star_levels, lemonade.art_star_mult))
	stations[s.id] = s

	s = SpecStation.new()
	s.id = "supply"
	s.display_name = supply.display_name
	s.block = "supply"
	s.zone = "kitchen"
	s.starts_unlocked = true
	s.params = {"fetch_seconds": 0.6}
	for definition in supply.materials:
		var material := SpecMaterial.new()
		material.id = definition.id
		material.display_name = definition.display_name
		material.item = definition.item_id
		material.box_cost = definition.box_cost
		material.box_station = sim._canonical(definition.box_machine)
		material.track = art_track(definition.id, definition.display_name, "售价", definition.art_costs, definition.art_price_step,
			definition.art_price_dishes, [], 1.0)
		s.materials.append(material)
	stations[s.id] = s

	s = SpecStation.new()
	s.id = "boil"
	s.display_name = boil.display_name
	s.block = "batch_pot"
	s.zone = "kitchen"
	s.seatable = true
	s.seated_bonus = sim.SEATED_BONUS
	s.params = {"cook_seconds": boil.art_seconds, "load_seconds": 0.6, "capacity": sim.BOIL_CAPACITY,
		"manual_load": true, "manual_unload": true, "stir_points": sim.STIR_POINTS, "stir_seconds": sim.STIR_SECONDS}
	s.counts_for_flow = "boil" in sim.FLOW_MACHINES
	s.tracks.append(art_track("level", boil.display_name, "煮茶速度", boil.art_costs, 0.0, [], boil.art_star_levels,
		boil.art_star_mult, boil.art_speeds, boil.art_batch))
	var stock := SpecStockRule.new()
	stock.item = "black_tea"
	stock.base = sim.BLACK_TEA_CAP
	stock.per_waiting = 1
	s.stock.append(stock)
	stations[s.id] = s

	s = SpecStation.new()
	s.id = "mix"
	s.display_name = mix.display_name
	s.block = "combine"
	s.zone = "kitchen"
	s.params = {"seconds": 4.0, "manual": false}
	s.price_dishes.assign(mix.art_price_dishes)
	s.counts_for_flow = "mix" in sim.FLOW_MACHINES
	s.tracks.append(art_track("level", mix.display_name, "售价", mix.art_costs, mix.art_price_step, mix.art_price_dishes,
		mix.art_star_levels, mix.art_star_mult))
	stations[s.id] = s

	s = SpecStation.new()
	s.id = "topping"
	s.display_name = topping.display_name
	s.block = "topping"
	s.zone = "kitchen"
	s.seatable = true
	s.seated_bonus = sim.SEATED_BONUS
	s.params = {"seconds": sim._topping_seconds(), "users": 1, "flavor_cap": topping.flavor_cap}
	s.counts_for_flow = "topping" in sim.FLOW_MACHINES
	var level_track := track("level", topping.display_name, "新口味")
	level_track.base_effects.append(effect("speed", "set", topping.level_speed[0]))
	for index in topping.upgrade_costs.size():
		var lv: int = index + 2
		var effects: Array = [effect("speed", "set", topping.level_speed[mini(lv, topping.level_speed.size()) - 1])]
		for m in topping.materials:
			if m.unlock_level == lv: effects.append(effect("open_flavor", "set", 1.0, m.id))
		level_track.levels.append(level(int(topping.upgrade_costs[index]), effects))
	s.tracks.append(level_track)
	for definition in topping.materials:
		var material := SpecMaterial.new()
		material.id = definition.id
		material.display_name = definition.display_name
		material.item = definition.item_id
		material.track = _bonus_track(definition)
		s.materials.append(material)
	stations[s.id] = s

	s = SpecStation.new()
	s.id = "press"
	s.display_name = press.display_name
	s.block = "hand"
	s.zone = "front"
	s.params = {"seconds": press.art_seconds, "users": 1}
	s.price_dishes.assign(press.art_price_dishes)
	s.counts_for_flow = "press" in sim.FLOW_MACHINES
	s.tracks.append(art_track("level", press.display_name, "售价", press.art_costs, press.art_price_step, press.art_price_dishes,
		press.art_star_levels, press.art_star_mult))
	for definition in press.materials:
		var material := SpecMaterial.new()
		material.id = definition.id
		material.display_name = definition.display_name
		material.item = definition.item_id
		material.track = _bonus_track(definition)
		s.materials.append(material)
	stations[s.id] = s

	# 封口机 = 出餐口的加工环节（§3.3）；外带架 = 外带分区 6 位。
	s = SpecStation.new()
	s.id = "seal"
	s.display_name = "封口机"
	s.block = "pickup"
	s.zone = "kitchen"
	# 堂食区每种菜的格数 = max(店铺货架容量, 当前队伍上限)（跟单模式），外带架 6 格
	s.params = {"zones": {"dine": config.shelf_capacity, "takeaway": sim.PICKUP_CAPACITY}, "dine_per_dish": true,
		"dine_at_least_queue": sim.follow_orders, "process_seconds": progression.seal_seconds,
		"process_slots": progression.seal_slots[0], "process_into": "takeaway"}
	s.counts_for_flow = "seal" in sim.FLOW_MACHINES
	var seal_track := track("level", "封口机", "封口速度")
	seal_track.base_effects.append(effect("speed", "set", progression.seal_speeds[0]))
	seal_track.base_effects.append(effect("process_slots", "set", progression.seal_slots[0]))
	for index in progression.seal_costs.size():
		var lv: int = index + 2
		var slots: int = progression.seal_slots[mini(lv, progression.seal_slots.size()) - 1]
		var star: bool = slots > progression.seal_slots[mini(lv - 1, progression.seal_slots.size()) - 1]
		seal_track.levels.append(level(int(progression.seal_costs[index]), [
			effect("speed", "set", progression.seal_speeds[mini(lv, progression.seal_speeds.size()) - 1]),
			effect("process_slots", "set", slots)], star))
	s.tracks.append(seal_track)
	stations[s.id] = s

	for id in ["counter", "lemonade", "supply", "boil", "seal", "mix", "press", "topping"]:
		shop.stations.append(stations[id])
	for st in shop.stations: st.description = sim.station_info(st.id).description

	# 阶段（§3.9）：阶段 0 = 开张（柠檬水台），之后每阶段开一组机器。
	for index in progression.stages.size():
		var old = progression.stages[index]
		var stage := SpecStage.new()
		stage.id = "stage%d" % index
		stage.display_name = old.line_name if index > 0 else "开张"
		stage.stations.assign(sim.STAGE_MACHINES[index] if index > 0 else ["lemonade"])
		stage.cost = old.line_cost if index > 0 else sim._unlock_cost("lemonade")
		stage.dish = old.dish_id
		stage.unlock_note = old.unlock_note
		stage.customer_interval = old.customer_interval
		for k in old.order_weights: stage.order_weights[k] = old.order_weights[k]
		stage.takeaway_share = old.takeaway_share
		stage.staff_slots["kitchen"] = old.staff_slots
		stage.queue_capacity = old.queue_capacity
		stage.seat_seconds = old.seat_seconds if old.seat_seconds > 0 else progression.seat_seconds
		for old_task in old.tasks:
			var target: String = old_task.target_id
			var condition := "sell_count"
			if old_task.condition == 2:
				condition = "track_level"
				target = sim._canonical(target)
			stage.tasks.append(task(old_task.id, old_task.display_name, condition, target, old_task.amount))
		shop.stages.append(stage)

	# 履约（§3.2）
	var f := SpecFulfillment.new()
	f.dine_rule = "seat_first"
	f.takeaway_station = "seal"
	f.taker = "front"
	f.handoff = "handoff"
	f.pay_at = "on_deliver"
	f.price_rounding = "dish_tenth_carry"
	f.leave_queue = "after_deliver"
	f.mood_seconds.assign([sim.MOOD_IMPATIENT, sim.MOOD_ANGRY])
	f.seated_patience = sim.SEATED_PATIENCE
	f.leave_who = "none"
	f.ramp_start = sim.RAMP_START
	f.ramp_orders = sim.RAMP_ORDERS
	f.arrival = "fixed"
	f.opening_customers = 3
	shop.fulfillment = f

	# 传单
	var flyer := SpecFlyer.new()
	flyer.wave_seconds = progression.flyer_seconds
	flyer.when_full = "wait_outside"
	flyer.track = track("flyer", "传单", "传单")
	flyer.track.base_effects.append(effect("flyer_customers", "set", progression.flyer_customers[0]))
	flyer.track.base_effects.append(effect("flyer_cooldown", "set", progression.flyer_cooldowns[0]))
	for index in progression.flyer_upgrade_costs.size():
		var lv: int = index + 2
		flyer.track.levels.append(level(int(progression.flyer_upgrade_costs[index]), [
			effect("flyer_customers", "set", progression.flyer_customers[mini(lv, progression.flyer_customers.size()) - 1]),
			effect("flyer_cooldown", "set", progression.flyer_cooldowns[mini(lv, progression.flyer_cooldowns.size()) - 1])]))
	shop.flyer = flyer

	# 座位
	var seats := SpecSeatGroup.new()
	seats.id = "dine"
	seats.purpose = "dine"
	seats.start = progression.seat_start
	seats.step = progression.seat_step
	seats.costs.assign(progression.seat_costs)
	seats.seconds = progression.seat_seconds
	seats.patience = sim.SEATED_PATIENCE
	shop.seat_groups.append(seats)

	# 调度（§3.6）：照搬奶茶店的打分常量
	var d := SpecDispatch.new()
	var scores := {"follow": 90.0, "follow_step": 95.0, "serve": 110.0, "chore": 55.0, "topping": 72.0, "stir": 80.0,
		"load_short": 70.0, "load": 26.0, "pot_short_bonus": 30.0,
		"to_rack": 105.0, "to_process": 100.0}
	for k in scores: d.base_scores[k] = scores[k]
	d.wait_bonus_per_second = 0.1
	d.wait_bonus_cap = 20.0
	d.shortage_per = 45.0
	d.shortage_cap = 90.0
	d.travel_penalty = 1.2
	d.merge = "carry"
	d.resume_from_stock = true
	d.help_while_waiting = true
	d.chores_first = false
	d.leave_seated_segments = true
	d.throughput_weight = 18.0
	d.fatigue_weight = 0.18
	d.fatigue_gain = 0.004
	d.fatigue_recover = 0.025
	d.hop_seconds = 0.6
	d.ticket_give_up = sim.TICKET_GIVE_UP
	shop.dispatch = d
	shop.layout = tea_layout_from_scene() if ResourceLoader.exists(TEA_ART) else tea_layout()

	# 员工（§3.5）
	var staff := SpecStaffRules.new()
	var probe = TeaSim.new()
	for art in sim.ARTS:
		var worker: Dictionary = probe._make_worker(sim.ARTS.find(art))
		var kind := SpecStaffKind.new()
		kind.id = art
		kind.display_name = worker.name
		kind.stats["walk"] = float(worker.speed)
		kind.stats["work"] = float(worker.skill)
		kind.stats["carry"] = float(worker.capacity)
		staff.kinds.append(kind)
	staff.starting.assign([sim.ARTS[0]])
	staff.starting_post = "counter"
	staff.hire_pool.assign(sim.ARTS)
	staff.hire_rule = "fewest"
	staff.hire_cost_base = sim.hire_cost()
	staff.hire_cost_step = 25
	staff.zones.assign(["front", "kitchen"])
	staff.front_base_slots = 1
	staff.can_drag = true
	for side in ["front", "kitchen"]:
		var t := track(side, "前台" if side == "front" else "后厨", "员工")
		var kinds: Array = sim._upgrade_kinds(side)
		var costs: Array = sim._upgrade_costs_for(side)
		for index in kinds.size():
			var e: SpecEffect
			match kinds[index]:
				"walk": e = effect("walk", "mul", 1.0 + progression.walk_step, side)
				"work": e = effect("work", "mul", 1.0 + progression.work_step, side)
				"carry": e = effect("carry", "add", 1.0, side)
				"slot": e = effect("staff_slot", "add", 1.0, side)
			t.levels.append(level(int(costs[index]), [e]))
		staff.tracks.append(t)
	staff.home_anchor = "counter"
	shop.staff = staff

	# 连接（§3.7）：游戏里只开放 封口机 → 外带架 一段
	for belt in progression.belts:
		var c := SpecConnection.new()
		c.id = belt.id
		c.display_name = belt.display_name
		c.from = sim._canonical(belt.from)
		c.to = "rack" if belt.to == "pickup" else belt.to
		c.seconds = belt.seconds
		c.interval = belt.interval
		c.cost = belt.cost
		c.stage = belt.stage
		c.enabled = belt.id in sim.GAME_BELTS
		shop.connections.append(c)

	# 目标（§3.9）
	var g := SpecGoalRules.new()
	g.opening_station = "lemonade"
	g.texts["open"] = "支付 {cost} 金币解锁{name}，开始营业"
	g.texts["box"] = "支付 {cost} 金币在原料柜解锁{name}箱"
	g.texts["stage"] = "支付 {cost} 金币解锁{name}"
	g.texts["task"] = "{name}（{current} / {target}）"
	g.texts["done"] = "经营任务已全部完成，继续营业"
	g.texts["open_short"] = "解锁{name}，开始营业"
	g.texts["box_short"] = "解锁{name}箱"
	g.texts["stage_short"] = "攒金币 · 解锁{name}"
	g.texts["done_short"] = "经营任务已全部完成"
	g.texts["need_take"] = "待取茶"
	g.texts["need_operate"] = "待操作"
	g.texts["hint_front"] = "前台跟不上，{drink}排起了长队：升级前台员工或多招一位"
	g.texts["hint_front_fix"] = "升级前台员工"
	g.texts["hint_no_kitchen"] = "没有后厨员工，{drink}做不出来：派一位员工去后厨"
	g.texts["hint_no_kitchen_fix"] = "派员工去后厨"
	g.texts["hint_pot"] = "{drink}做不过来，{name}一直在煮：升级{name}"
	g.texts["hint_pot_fix"] = "升级{name}"
	g.texts["hint_staff"] = "后厨跑不过来，{drink}排起了长队：升级后厨员工或多招一位"
	g.texts["hint_staff_fix"] = "升级后厨员工"
	g.texts["hint_machine"] = "{drink}做不过来：升级{name}"
	g.texts["hint_machine_fix"] = "升级{name}"
	g.complete_when.assign(["all_stages", "all_tasks"])
	shop.goals = g
	# 界面：图标、计量单位（旧界面 station_panel 里的对照表搬到数据里）
	var icons := {"supply": "tea_leaf", "counter": "shop", "topping": "drink_pearl_milk_tea", "press": "drink_lemon_tea"}
	var material_icons := {"pearl": "drink_pearl_milk_tea", "coconut": "drink_coconut_milk_tea", "redbean": "drink_redbean_milk_tea",
		"taro": "drink_taro_milk_tea", "lemon": "drink_lemon_tea"}
	for st in shop.stations:
		st.icon = icons.get(st.id, "")
		st.params["unit"] = "杯"
		for m in st.materials: m.icon = material_icons.get(m.id, "")
	shop.station("seal").params["slot_label"] = "封口位"
	# 干活朝向（8 方向）：旧 staff_actor.WORK_DIRECTIONS
	for pair in [["boil", 3], ["mix", 3], ["topping", 5], ["press", 6], ["lemonade", 6]]: shop.station(pair[0]).params["facing"] = pair[1]
	# 物品怎么画：旧 staff_actor.item_asset / item_color
	var tints := {"black_tea": Color("d9935f"), "coconut_milk_tea": Color("fff8df"), "redbean_milk_tea": Color("ffd8cf"),
		"taro_milk_tea": Color("e1d0ff"), "lemon_tea": Color("f2b36a")}
	for it in shop.items:
		it.art = "tea_tin" if it.id == "raw" else "fruit_tea" if it.id in ["lemonade", "lemon_tea"] \
			else "cream_tea" if it.id in ["tea", "black_tea", "milk_tea", "plain_milk_tea", "coconut_milk_tea", "taro_milk_tea"] else "pearl_tea"
		it.tint = tints.get(it.id, Color.WHITE)
	# 员工类型：旧 shop_hud 的 ROLES / descriptions
	var roles := {"speed": "速度型", "carry": "力量型", "skill": "操作型"}
	var descriptions := {"cat": "跑得快的多面手", "raccoon": "擅长批量搬运", "fox": "擅长手工制作", "rabbit": "擅长快速搬运",
		"gray_cat": "跑得快的多面手", "bear": "擅长批量搬运"}
	for kind in shop.staff.kinds:
		kind.role = roles.get(probe._make_worker(sim.ARTS.find(kind.id)).role, "")
		kind.description = descriptions.get(kind.id, "")
	# 员工头顶的字：旧 staff_actor.TASKS，按规则层的通用动作名
	for pair in [["idle", "待命"], ["load", "补原料"], ["pot_start", "人工投料"], ["pot_take", "取出茶汤"], ["stir", "待操作"],
			["transfer", "送去{to}"], ["transfer@topping", "送去加料"], ["work", "手工加料"], ["work@press", "捣柠檬"],
			["carry_to_process", "送去封口"], ["carry_to_rack", "送上外带格"], ["carry_to_shelf", "成品上架"], ["serve", "取杯送餐"]]:
		g.texts["task_" + pair[0]] = pair[1]
	# 员工页：岗位名、名额、拖人说明（旧 shop_hud）
	for pair in [["post_", "流动"], ["post_counter", "前台"], ["post_boil", "煮茶"], ["post_topping", "加料"]]: g.texts[pair[0]] = pair[1]
	g.texts["staff_slots"] = "前台 {front_used}/{front} · 后厨 {kitchen_used}/{kitchen}"
	g.texts["unit"] = "杯"
	g.texts["icon_press"] = "mix"
	g.texts["icon_topping"] = "mix"
	g.texts["drag_hint"] = "拖到柜台 = 前台（接待客人）；拖到工位或空地 = 后厨"
	shop.station("counter").params["panel_title"] = "收银台"
	shop.station("boil").params["frame_title"] = "stage"
	# 面板标题下的升级种类（旧 tea_shop_sim：一台机器一种）
	for pair in [["boil", "capacity"], ["seal", "capacity"], ["topping", "menu"], ["mix", "price"], ["supply", "price"], ["press", "price"], ["lemonade", "price"]]:
		var t := shop.station(pair[0]).track("level")
		if t != null: t.kind = pair[1]
	# 拖人：松手前的提示、放下后的提示（旧 staff_drag_controller）
	for pair in [["drop_", "恢复流动"], ["drop_counter", "前台接单"], ["drop_boil", "坐班煮茶台"], ["drop_topping", "坐班加料台"],
			["placed_", "已安排到后厨"], ["placed_counter", "已安排到前台：只负责接待客人、取杯上菜。"],
			["placed_boil", "已安排到煮茶台坐班"], ["placed_topping", "已安排到加料台坐班"]]:
		g.texts[pair[0]] = pair[1]
	for pair in [["press", "水果"], ["topping", "配料"], ["supply", "原料"]]: shop.station(pair[0]).params["materials_label"] = pair[1]
	shop.guide.assign(tea_guide())
	return shop


static func guide_step(id: String, trigger: String, when: Array, done_when: Array, cues: Array, skip := "以后再说") -> SpecGuideStep:
	var s := SpecGuideStep.new()
	s.id = id
	s.trigger = trigger
	s.when.assign(when)
	s.done_when.assign(done_when)
	s.cues.assign(cues)
	s.skip_label = skip
	return s


static func guide_card(id: String, title: String, confirm: String, text := "") -> SpecGuideStep:
	var s := SpecGuideStep.new()
	s.id = id
	s.style = "card"
	s.title = title
	s.confirm_label = confirm
	s.text = text
	return s


## 奶茶店引导（旧 guide_overlay.gd 的步骤和原句，搬成数据）
static func tea_guide() -> Array:
	var steps: Array = []
	var welcome := guide_card("welcome", "欢迎，店长！", "开始营业")
	welcome.shop_page_only = false
	welcome.when.assign(["!open"])
	welcome.seen_when.assign(["open", "stage>=1"])
	welcome.art = "raccoon"
	welcome.rows = [["lemonade", "招待顾客，卖饮品收金币"], ["boil", "开通后厨生产线，做新饮品"], ["goals", "完成经营任务，把小店做大"]]
	welcome.cancel_label = "跳过引导"
	welcome.skip_marks.assign(["opening"])
	welcome.next = "opening"
	steps.append(welcome)
	var opening := guide_step("opening", "start", [], [], [
		{"if": ["!open", "page:station:lemonade"], "at": "ui:unlock", "text": "点「解锁」，花 10 金币摆上柠檬水台"},
		{"if": ["!open", "!page:shop"], "go": "shop"},
		{"if": ["!open"], "at": "frame:lemonade", "text": "先开张！点这里摆上柠檬水台"},
		{"if": ["sold:0"], "at": "area:Guide/CounterArea", "pause": false, "text": "小猫会自己做柠檬水、招呼客人。\n看看第一杯卖出去！"},
		{"if": ["staff<opening", "waiting", "!page:staff"], "at": "ui:tab:staff", "text": "新伙伴在名册里，点「员工」"},
		{"if": ["staff<opening", "waiting"], "select_waiting": true, "at": "ui:deploy", "text": "点「派到店内」，让伙伴一起干活"},
		{"if": ["staff<opening", "!can_hire"], "wait": true},
		{"if": ["staff<opening", "!page:staff"], "at": "ui:tab:staff", "text": "收到金币了！人手多出杯更快，点「员工」"},
		{"if": ["staff<opening"], "at": "ui:hire", "text": "招一位新伙伴，招来直接上岗"},
		{"then": "done"}], "跳过引导")
	opening.shop_page_only = false
	opening.seen_when.assign(["stage>=1", "open&staff>=opening"])
	opening.skip_marks.assign(["welcome"])
	steps.append(opening)
	var done := guide_card("done", "开店上手了！", "继续营业", "接下来自己经营：攒够 {cost} 金币，就能开{line}。\n点机器可以升级，点「员工」可以调整岗位。")
	done.trigger = "next"
	done.params = {"stage": 1}
	done.finish_marks.assign(["opening"])
	steps.append(done)
	var signs := ["", "boil", "seal", "mix", "press", "topping"]
	for n in range(1, signs.size()):
		var sign: String = signs[n]
		var line := guide_step("line_%d" % n, "start", ["stage>=%d" % (n - 1), "stage<%d" % n, "affordable:" + sign],
			["stage>=%d" % n, "!affordable:" + sign], [
			{"if": ["page:station:" + sign], "at": "ui:unlock", "text": "点「解锁」开通{line}"},
			{"if": ["!page:shop"], "go": "shop"},
			{"at": "frame:" + sign, "text": "金币够了！开通{line}，能卖新饮品"}])
		line.params = {"stage": n}
		steps.append(line)
	var shop_done := guide_card("shop_done", "首店完成！", "继续营业", "第二家店还在准备中，可以继续把这家店做大。")
	shop_done.when.assign(["complete"])
	shop_done.title_size = 64
	shop_done.medal = "medal"
	shop_done.stats = [["clock", "用时", "time"], ["coin", "总营业额", "revenue"]]
	steps.append(shop_done)
	for m in ["tea_leaf", "milk"]:
		steps.append(guide_step("box_" + m, "start", ["box:" + m, "box_affordable"], ["!box:" + m, "!box_affordable"], [
			{"if": ["page:station:supply"], "at": "ui:material:" + m, "text": "解锁{box}箱，{machine}才有原料"},
			{"if": ["!page:shop"], "go": "shop"},
			{"at": "frame:supply", "text": "{machine}要用{box}：去原料柜解锁{box}箱"}]))
	steps.append(guide_step("kitchen", "start", ["stage>=1", "kitchen_staff:0", "no_box", "can_staff"], ["!kitchen_staff:0"], [
		{"if": ["waiting", "!page:staff"], "at": "ui:tab:staff", "text": "后厨还没人！新伙伴在名册里，点「员工」"},
		{"if": ["waiting"], "select_waiting": true, "at": "ui:deploy", "text": "点「派到店内」，让伙伴去后厨煮茶"},
		{"if": ["!can_hire"], "back": true},
		{"if": ["!page:staff"], "at": "ui:tab:staff", "text": "前台只管接待客人，煮茶要后厨员工：点「员工」"},
		{"at": "ui:hire", "text": "招一位伙伴，招来直接去后厨"}]))
	steps.append(guide_step("more_staff", "start", ["stage>=5", "room", "can_staff"], ["hired", "!room"], [
		{"if": ["waiting", "!page:staff"], "at": "ui:tab:staff", "text": "加料机开通了，每杯要多走一段路。\n还有空岗位，点「员工」派伙伴上岗"},
		{"if": ["waiting"], "select_waiting": true, "at": "ui:deploy", "text": "点「派到店内」，让伙伴一起干活"},
		{"if": ["!can_hire"], "back": true},
		{"if": ["!page:staff"], "at": "ui:tab:staff", "text": "加料机开通了，每杯要多走一段路。\n还有空岗位，点「员工」再招一位，\n煮茶机也要升级跟上"},
		{"at": "ui:hire", "text": "招一位新伙伴，招来直接上岗"}]))
	steps.append(guide_step("lost_seats", "angry", ["angry:seats"], ["!page:shop"], [
		{"at": "ui:chip:seats", "text": "有客人等急了！堂食坐满了，\n点这里加座位，客人才能坐下"}], "知道了"))
	steps.append(guide_step("lost_staff", "angry", ["angry:staff"], ["!page:shop"], [
		{"at": "ui:tab:staff", "text": "有客人等急了！还有空岗位，\n点「员工」招一位伙伴"}], "知道了"))
	steps.append(guide_step("lost_machine", "angry", ["angry:machine"], ["!page:shop"], [
		{"at": "station:{slow_id}", "text": "有客人等急了！{slow}跟不上，\n点它升级，出杯更快"}], "知道了"))
	return steps


static func _bonus_track(definition) -> SpecUpgradeTrack:
	## 口味槽：每级这一杯售价 = 基础价 × level_bonus[lv-1]（set，不和别的口味连乘）
	var t := track(definition.id, definition.display_name, "售价")
	t.requires_level = definition.unlock_level
	t.base_effects.append(effect("price", "set", definition.bonus(1), "", [definition.item_id]))
	for index in definition.max_level() - 1:
		t.levels.append(level(int(definition.upgrade_costs[index]),
			[effect("price", "set", definition.bonus(index + 2), "", [definition.item_id])]))
	return t


# ---------- 煎饼摊 ----------

## 煎饼摊的数值在第 4 个 PR 冻结在 shop.tres 里（旧模拟已删，整店回放对照 tests/baselines/pancake_73b0ae3.json）。
## 这里只补界面要的东西：美术场景、图标、文案、引导。
func build_pancake() -> SpecShop:
	var shop: SpecShop = load(OUT_PANCAKE)
	pancake_presentation(shop)
	return shop


const PANCAKE_ICONS := "res://art/pancake/icons/"


static func pancake_presentation(shop: SpecShop) -> void:
	shop.scene_path = "res://presentation/shops/pancake/pancake_art.tscn"
	shop.save_file = "shop_pancake.json"
	# 订单气泡、面板上的图：原画图集里的豆浆杯、纸袋煎饼
	var item_icons := {"soy": "soy_cup", "crisp": "crisps", "batter": "batter", "pancake": "pancake_packet"}
	for it in shop.items:
		it.icon = load(PANCAKE_ICONS + String(item_icons.get(it.id, "pancake_packet")) + ".tres")
	var icons := {"soy_milk": "soy_milk", "rear_equipment": "griddle", "fryer": "fryer", "topping": "topping",
		"packing": "packing", "raw_ingredients": "batter"}
	var descriptions := {"soy_milk": "打豆浆：单点一杯，或者买饼顺带一杯",
		"rear_equipment": "摊煎饼：一口鏊子同时只能一个人用",
		"fryer": "炸薄脆：一锅 4 份，下锅和捞出都要人",
		"topping": "加火腿、肉松、培根：升级涨价，到级开新口味",
		"front_counter": "收钱、递餐；点这里发传单招客人"}
	for st in shop.stations:
		st.icon = PANCAKE_ICONS + icons[st.id] + ".tres" if icons.has(st.id) else "shop" if st.block == "counter" else ""
		st.description = descriptions.get(st.id, st.description)
		st.params["unit"] = "份"
		for m in st.materials: m.icon = PANCAKE_ICONS + "pancake_packet.tres"
	# 干活朝向（8 方向）：收钱面向客人，打豆浆面向豆浆机（旧 pancake_play.WORK_FACING）
	shop.station("front_counter").params["facing"] = 0
	shop.station("soy_milk").params["facing"] = 7
	shop.station("soy_milk").track("level").kind = "price"
	shop.station("rear_equipment").track("level").kind = "capacity"
	shop.station("fryer").track("level").kind = "capacity"
	shop.station("topping").track("level").kind = "both"
	var g := shop.goals
	g.texts.clear()
	g.texts["open"] = "支付 {cost} 金币解锁{name}，开始营业"
	g.texts["stage"] = "支付 {cost} 金币解锁{name}"
	g.texts["task"] = "{name}（{current} / {target}）"
	g.texts["done"] = "经营任务已全部完成，继续营业"
	g.texts["open_short"] = "点亮{name}开张（{cost} 金币）"
	g.texts["stage_short"] = "攒金币 · 开放{name}"
	g.texts["done_short"] = "完店了！去「目标」结店，也可以接着营业"
	g.texts["need_take"] = "待捞"
	g.texts["hint_pot"] = "薄脆供不上，{drink}排起了长队：升级{name}"
	g.texts["hint_pot_fix"] = "升级{name}"
	g.texts["hint_staff"] = "队伍满了：人手不够，招人"
	g.texts["hint_staff_fix"] = "招人"
	g.texts["hint_machine"] = "{drink}做不过来：升级{name}"
	g.texts["hint_machine_fix"] = "升级{name}"
	g.texts["unit"] = "份"
	g.texts["staff_slots"] = "员工 {used}/{all}"
	g.texts["icon_stat_sold"] = PANCAKE_ICONS + "pancake_packet.tres"
	for key in icons: g.texts["icon_" + key] = PANCAKE_ICONS + icons[key] + ".tres"
	for kind in shop.staff.kinds:
		kind.description = {"rabbit": "擅长快速搬运", "gray_cat": "跑得快的多面手", "bear": "擅长批量搬运"}.get(kind.id, "")
	shop.guide.assign(pancake_guide())


## 煎饼摊引导（旧 pancake_guide.gd 的步骤和原句）：欢迎 → 点豆浆机开张 → 看第一单卖出去 → 招第二个人 → 完成
static func pancake_guide() -> Array:
	var steps: Array = []
	var welcome := guide_card("welcome", "欢迎来到煎饼果子摊", "开始",
		"早点摊刚支起来，先卖豆浆，攒钱再开鏊子、油锅和加料台。\n员工会自己接单，从收钱一直做到递餐。")
	welcome.shop_page_only = false
	welcome.when.assign(["!open"])
	welcome.seen_when.assign(["open"])
	welcome.cancel_label = "跳过引导"
	welcome.skip_marks.assign(["opening", "hire", "done"])
	welcome.next = "opening"
	steps.append(welcome)
	var opening := guide_step("opening", "start", [], ["!sold:0"], [
		{"if": ["!open", "page:station:soy_milk"], "at": "ui:unlock", "text": "点「解锁」，花 10 金币开张"},
		{"if": ["!open", "!page:shop"], "go": "shop"},
		{"if": ["!open"], "at": "frame:soy_milk", "text": "点豆浆机，花 10 金币开张"},
		{"at": "station:front_counter", "pause": false, "text": "员工去前台收钱、打豆浆。\n看第一单卖出去"}], "跳过引导")
	opening.shop_page_only = false
	opening.seen_when.assign(["stage>=1"])
	opening.skip_marks.assign(["welcome"])
	steps.append(opening)
	var hire := guide_step("hire", "start", ["stage>=1", "staff<2", "can_hire"], ["hired", "!room"], [
		{"if": ["!page:staff"], "at": "ui:tab:staff", "text": "一个人又收钱又摊饼，忙不过来了。\n点「员工」招第二个人"},
		{"at": "ui:hire", "text": "一个人又收钱又摊饼，忙不过来了。\n招第二个人"}])
	hire.seen_when.assign(["staff>=2"])
	steps.append(hire)
	var done := guide_card("done", "开张完成", "知道了",
		"之后每分钟回来看一眼就行：\n攒够钱开下一台；队伍排满了就招人；台子上出现红色 ↑ 就点它升级。")
	done.when.assign(["seen:hire"])
	steps.append(done)
	var shop_done := guide_card("shop_done", "完店了！", "接着营业", "可以去「目标」点「结店」去奶茶店，也可以接着营业。")
	shop_done.when.assign(["complete"])
	shop_done.title_size = 56
	shop_done.medal = "medal"
	shop_done.stats = [["clock", "用时", "time"], ["coin", "总营业额", "revenue"]]
	steps.append(shop_done)
	return steps


# ---------- 走位 ----------

const TeaLayout := preload("res://content/tea/art_playtest_layout.gd")


## 奶茶店的走位从美术场景的锚点导出（规格 §6.1）
static func tea_layout_from_scene() -> SpecLayout:
	var art: Node = load(TEA_ART).instantiate()
	var layout := ShopAnchors.new(art.get_node("Anchors")).layout(tea_layout())
	art.free()
	return layout


static func tea_layout() -> SpecLayout:
	var layout := SpecLayout.new()
	layout.nav = "grid"
	layout.cell = TeaLayout.CELL
	var grid := TeaLayout.grid()
	layout.areas.assign([grid.kitchen_rect, grid.front_rect])
	layout.grid_size = Vector2i(36, 75)
	# 和 art_playtest_layout.grid() 同一组障碍（家具 + 堂食桌）
	var obstacles := [Rect2(23, 269, 122, 348), Rect2(267, 235, 290, 70), Rect2(22, 220, 235, 75), Rect2(590, 367, 72, 213),
		Rect2(560, 205, 132, 185), Rect2(522, 530, 178, 154), Rect2(32, 595, 122, 185), Rect2(32, 709, 291, 148),
		Rect2(323, 752, 365, 105)]
	for seat_table in TeaLayout.DINING_TABLES: obstacles.append(Rect2(seat_table - Vector2(110, 68), Vector2(220, 120)))
	layout.obstacles.assign(obstacles)
	for k in TeaLayout.POINTS: layout.points[k] = TeaLayout.POINTS[k]
	for k in TeaLayout.POST_POINTS: layout.posts[k] = TeaLayout.POST_POINTS[k]
	layout.spawn_point = "counter"
	return layout


# ---------- 关卡表 ----------

func build_campaign() -> SpecCampaign:
	var campaign := SpecCampaign.new()
	var north := SpecCity.new()
	north.id = "north"
	north.display_name = "北方"
	north.theme = "北方风味"
	for row in [["pancake", "煎饼果子摊", OUT_PANCAKE, 20.0], ["tea", "奶茶店", OUT_TEA, 30.0], ["bakery", "面包店", "", 35.0]]:
		var shop := SpecCampaignShop.new()
		shop.id = row[0]
		shop.display_name = row[1]
		shop.shop_path = row[2]
		shop.target_minutes = row[3]
		north.shops.append(shop)
	campaign.cities.append(north)
	return campaign
