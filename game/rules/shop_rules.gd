class_name ShopRules
extends RefCounted
## 通用店铺规则（规格 §3）。所有店跑这一份代码，店铺之间只有 SpecShop 数据不同。
## 这里不出现任何店铺、机器、菜品的名字：机器按工序积木类型（block）认，菜按工序链认。
## 两种交接方式（§3.2 handoff）：
##   handoff = 后厨跟单员把一单从锅一路搬到出餐口，前厅员工取杯递给顾客（每一段是一次“搬运”）
##   single  = 一名员工从收钱跟到递餐，每一步走到机器前做完（煎饼摊）
## 纯逻辑，不依赖场景；界面只读快照、只发命令（§3.11）。

const STEP := 0.1
const SUPPLY := "supply"
const SHELF := "shelf"
const RACK := "rack"
const COUNTER := "counter"
const UNLIMITED := 999

var shop: SpecShop
var nav: RuleNav
var mods := RuleModifiers.new()
var events := RuleEvents.new()
var rng := RandomNumberGenerator.new()

# ---------- 店铺状态 ----------
var clock := 0.0
var gold := 0.0
var revenue := 0.0
var sold := 0
var sold_by_dish: Dictionary = {}
var lost := 0
var stage_index := 0
var unlocked: Dictionary = {}
## 升级轨等级："机器id" = 机器主轨；"机器id/物料id" = 物料槽；"staff/front"、"flyer"、"seat/<组>"
var levels: Dictionary = {}
var boxes: Dictionary = {}
var completed_at := -1.0
var paused := false
## 调参倍率（调参面板）：key → 倍率
var tune: Dictionary = {}

# ---------- 运行时 ----------
var stations: Dictionary = {}
var shelf_stock: Dictionary = {}
var shelf_count := 0
var shelf_reserved_in := 0
var shelf_reserved_out := 0
var generated := 0
var orders: Array = []
var diners: Array = []
var workers: Array = []
var roster: Array = []
## 本局可招的员工种类：开局 = 店铺数据里的，店长回访等效果往里加（不改店铺数据本身）
var hire_pool: Array[String] = []
## 奇遇（§3.13）：可触发的奇遇、各自冷却到哪一秒、触发过的一次性奇遇、等玩家选的卡片（界面弹窗队列读这里）
var event_defs: Array[SpecEvent] = []
var event_ready_at: Dictionary = {}
var events_seen: Array[String] = []
var pending_events: Array = []
## 奇遇另用一个随机数，不打乱客流和点单的抽取顺序
var event_rng := RandomNumberGenerator.new()
var belts: Dictionary = {}
var belt_clock: Dictionary = {}
var belt_items: Array = []
var order_ramp: Dictionary = {}
var flyer_wave := 0.0
var flyer_wait := 0.0
var flyer_clock := 0.0
var flyer_pending := 0
var flyer_ready_at := 0.0
var flyer_left := 0
var flyer_timer := 0.0
var seats: Dictionary = {}
var _accumulator := 0.0
var _order_clock := 0.0
var _next_order := 1
var _next_staff := 1
var _sale_carry := 0.0
var _next_customer := 0.0
var _courier := false

# ---------- 从数据推出来的角色（按积木类型，不按 id） ----------
var counter_id := ""
var supply_id := ""
var pickup_id := ""
var pots: Array[String] = []
var autos: Array[String] = []
var seatables: Array[String] = []
var dish_ids: Array[String] = []
var front_dishes: Array[String] = []
var kitchen_dishes: Array[String] = []
## 菜 → 后厨工序站点链（不含原料箱），如 [锅, 调制台, 加料台]
var chains: Dictionary = {}
## 站点 → 产出物（锅：中间品；自动组合台：中间品；加料台：按菜）
var station_output: Dictionary = {}
var station_input: Dictionary = {}


func _init(shop_: SpecShop, seed := -1) -> void:
	shop = shop_
	nav = RuleNav.new(shop.layout)
	_derive_roles()
	reset(seed)


func _derive_roles() -> void:
	for st in shop.stations:
		match st.block:
			"counter": counter_id = st.id
			"supply":
				if supply_id.is_empty(): supply_id = st.id
			"pickup":
				if st.params.has("process_seconds"): pickup_id = st.id
			"batch_pot": pots.append(st.id)
			"combine":
				if not bool(st.params.get("manual", false)): autos.append(st.id)
		if st.seatable: seatables.append(st.id)
	for dish in shop.dishes:
		dish_ids.append(dish.id)
		if dish.front: front_dishes.append(dish.id)
		else: kitchen_dishes.append(dish.id)
		var chain: Array[String] = []
		# 机器的投入 = 前面工序做出来、送到这台机器的那样东西（原料箱里直接取的辅料不算）
		var made: Array = []
		for s in dish.steps:
			var st := shop.station(s.station)
			var counted: bool = st != null and not st.block in ["supply", "pickup", "counter"] and st.zone != "front"
			if counted:
				if not s.station in chain: chain.append(s.station)
				for item in s.consumes:
					if item in made and not station_input.has(s.station): station_input[s.station] = item
			made.append_array(s.produces.keys())
			if not counted: continue
			for item in s.produces:
				station_output[s.station + "|" + dish.id] = item
		chains[dish.id] = chain


func reset(seed := -1) -> void:
	clock = 0.0
	gold = float(shop.start_gold)
	revenue = 0.0
	sold = 0
	lost = 0
	stage_index = 0
	completed_at = -1.0
	_sale_carry = 0.0
	_accumulator = 0.0
	_order_clock = 0.0
	_next_order = 1
	_next_staff = 1
	rng.seed = shop.random_seed if seed < 0 else seed
	mods = RuleModifiers.new()
	events = RuleEvents.new()
	unlocked = {}
	levels = {}
	boxes = {}
	sold_by_dish = {}
	shelf_stock = {}
	for id in dish_ids:
		sold_by_dish[id] = 0
		shelf_stock[id] = 0
	shelf_count = 0
	shelf_reserved_in = 0
	shelf_reserved_out = 0
	generated = 0
	orders = []
	diners = []
	customers = []
	queue = []
	_next_customer_id = 1
	belts = {}
	belt_clock = {}
	belt_items = []
	order_ramp = {"takeaway": 0}
	for id in dish_ids: order_ramp[id] = 0
	flyer_wave = 0.0
	flyer_wait = 0.0
	flyer_clock = 0.0
	flyer_pending = 0
	flyer_ready_at = 0.0
	flyer_left = 0
	flyer_timer = 0.0
	seats = {}
	for group in shop.seat_groups: seats[group.id] = group.start
	_next_customer = 2.0
	for st in shop.stations:
		unlocked[st.id] = st.starts_unlocked
		for t in st.tracks: levels[st.id] = 1
		for m in st.materials:
			levels[st.id + "/" + m.id] = 1
			if m.box_cost > 0: boxes[m.id] = false
	for t in shop.staff.tracks: levels["staff/" + t.id] = 0
	levels["flyer"] = 1
	_build_stations()
	_refresh_all_modifiers()
	workers = []
	roster = []
	hire_pool = shop.staff.hire_pool.duplicate()
	event_rng.seed = rng.seed + 1
	event_ready_at = {}
	events_seen = []
	pending_events = []
	event_defs = []
	full_seconds = 0.0
	pot_busy = {}
	side_idle = {}
	for ev in shop.events: add_event(ev)
	events.on("*", _on_broadcast)
	for kind in shop.staff.starting:
		var worker := _new_worker(kind)
		worker.deployed = true
		worker.source = "初始"
		roster.append(worker)
		workers.append(worker)
		if not shop.staff.starting_post.is_empty(): _seat_at(worker, shop.staff.starting_post)


func _build_stations() -> void:
	stations = {}
	for st in shop.stations:
		var s := {"input": {}, "output": {}, "phase": "idle", "progress": 0.0, "processing": 0, "processing_item": "",
			"remaining": 0.0, "duration": 0.0, "reserved_in": 0, "reserved_out": {}, "work_reserved": false,
			"capacity": int(st.params.get("capacity", 6)), "user": -1, "stock": 0}
		match st.block:
			"batch_pot":
				var input: String = station_input.get(st.id, "")
				if not input.is_empty(): s.input[input] = 0
				for key in station_output:
					if key.begins_with(st.id + "|"): s.output[station_output[key]] = 0
				for rule in st.stock:
					s.stock = rule.start
			"combine", "topping":
				var input: String = station_input.get(st.id, "")
				if not input.is_empty(): s.input[input] = 0
				for key in station_output:
					if key.begins_with(st.id + "|"): s.output[station_output[key]] = 0
			"pickup":
				for id in dish_ids:
					s.input[id] = 0
					s.output[id] = 0
		stations[st.id] = s
	# 外带架（出餐口的外带分区）
	if not pickup_id.is_empty():
		var zones: Dictionary = shop.station(pickup_id).params.get("zones", {})
		var rack := {"input": {}, "output": {}, "phase": "idle", "progress": 0.0, "processing": 0, "processing_item": "",
			"remaining": 0.0, "duration": 0.0, "reserved_in": 0, "reserved_out": {}, "work_reserved": false,
			"capacity": int(zones.get("takeaway", 6)), "user": -1, "stock": 0}
		for id in dish_ids: rack.output[id] = 0
		stations[RACK] = rack


# ---------- 加成栈：升级轨折算 ----------

const SET_KINDS := ["batch", "process_slots", "flyer_customers", "flyer_cooldown"]
const ADD_KINDS := ["carry", "staff_slot", "seats"]


func _refresh_all_modifiers() -> void:
	for st in shop.stations:
		for t in st.tracks: _refresh_track(st, t, st.id, levels[st.id], st.id)
		for m in st.materials: _refresh_track(st, m.track, st.id + "/" + m.id, levels[st.id + "/" + m.id], st.id)
	for t in shop.staff.tracks: _refresh_track(null, t, "staff/" + t.id, levels["staff/" + t.id] + 1, t.id)
	_refresh_track(null, shop.flyer.track, "flyer", levels.flyer, "")


## 一条升级轨在 level 级时的全部效果折成加成：同种效果、同一对象、同一范围合成一条。
func _refresh_track(st: SpecStation, t: SpecUpgradeTrack, key: String, level: int, default_target: String) -> void:
	mods.remove("upgrade", key)
	var groups := {}
	var effects: Array[SpecEffect] = []
	effects.append_array(t.base_effects)
	for index in mini(level - 1, t.levels.size()): effects.append_array(t.levels[index].effects)
	for e in effects:
		if e.one_shot() or e.kind == "open_flavor": continue
		var dishes: Array = e.dishes
		if dishes.is_empty() and e.kind == "price" and st != null: dishes = st.price_dishes
		var target: String = e.target if not e.target.is_empty() else ("" if e.kind == "price" else default_target)
		var group_key := "%s|%s|%s|%s" % [e.kind, target, ",".join(dishes), e.price_part]
		if not groups.has(group_key):
			groups[group_key] = {"kind": e.kind, "target": target, "dishes": dishes, "part": e.price_part,
				"value": 0.0 if e.kind in SET_KINDS or e.kind in ADD_KINDS else 1.0, "set": false}
		var g: Dictionary = groups[group_key]
		match e.op:
			"set":
				g.value = e.value
				g.set = true
			"add": g.value += e.value
			_: g.value *= e.value
	for g in groups.values():
		var op := "mul"
		if g.kind in SET_KINDS: op = "set"
		elif g.kind in ADD_KINDS: op = "add"
		mods.add("upgrade", key, g.kind, op, g.value, g.target, g.dishes, g.part)


func track_of(key: String) -> SpecUpgradeTrack:
	if key == "flyer": return shop.flyer.track
	if key.begins_with("staff/"):
		for t in shop.staff.tracks:
			if "staff/" + t.id == key: return t
		return null
	var parts := key.split("/")
	var st := shop.station(parts[0])
	if st == null: return null
	if parts.size() == 1: return st.track("level") if not st.tracks.is_empty() else null
	var m := st.material(parts[1])
	return m.track if m != null else null


func tuned(key: String) -> float:
	return clampf(float(tune.get(key, 1.0)), 0.25, 3.0)


# ---------- 查询 ----------

func station_unlocked(id: String) -> bool:
	return unlocked.get(id, false)


func level(id: String) -> int:
	return int(levels.get(id, 1))


func speed(id: String) -> float:
	return mods.value("speed", 1.0, id)


func duration_mult(id: String) -> float:
	return mods.value("duration", 1.0, id)


func pot_batch(id: String) -> int:
	return int(mods.value("batch", float(shop.station(id).params.get("batch", 3)), id))


func process_slots(id: String) -> int:
	return int(mods.value("process_slots", float(shop.station(id).params.get("process_slots", 1)), id))


func stars(id: String) -> int:
	var t := track_of(id)
	return t.stars(level(id)) if t != null else 0


## 一道菜现在的售价（保留 1 位小数前的原值）：每部分价格 × 作用在这部分上的所有加成。
func raw_price(dish_id: String) -> float:
	var dish := shop.dish(dish_id)
	var total := 0.0
	for part in dish.price_parts:
		total += dish.price_parts[part] * mods.value("price", 1.0, "", dish_id) * mods.value("price", 1.0, "", dish_id, part)
	return total * tuned("price")


func dish_price(dish_id: String) -> float:
	return snappedf(raw_price(dish_id), 0.1) if shop.fulfillment.price_rounding == "dish_tenth_carry" else raw_price(dish_id)


func flavor_open(dish: SpecDish) -> bool:
	if dish.flavor_station.is_empty(): return true
	var st := shop.station(dish.flavor_station)
	var m := st.material(dish.flavor_material)
	if m == null: return true
	return station_unlocked(st.id) and level(st.id) >= m.track.requires_level


func _box_ready(item: String) -> bool:
	var st := shop.station(supply_id)
	if st == null: return true
	for m in st.materials:
		if m.item == item and boxes.has(m.id): return boxes[m.id]
	return true


## 菜在不在菜单上：工序用到的机器都开了、要买的原料箱买了、口味开了；后厨菜还要有人在后厨。
func dish_open(dish_id: String, needs_kitchen_hand := true) -> bool:
	var dish := shop.dish(dish_id)
	for s in dish.steps:
		var st := shop.station(s.station)
		if st == null: continue
		if st.block == "pickup": continue
		if not station_unlocked(s.station) and st.companion_of.is_empty(): return false
		if not st.companion_of.is_empty() and not station_unlocked(st.companion_of): return false
		for item in s.consumes:
			if not _box_ready(item): return false
		if st.block == "supply":
			for item in s.produces:
				if not _box_ready(item): return false
	if not flavor_open(dish): return false
	if shop.fulfillment.handoff == "handoff" and needs_kitchen_hand and not dish.front and kitchen_staff() <= 0: return false
	return true


func menu() -> Array[String]:
	var out: Array[String] = []
	for id in dish_ids:
		if dish_open(id, false): out.append(id)
	return out


func is_open() -> bool:
	return station_unlocked(shop.goals.opening_station)


func current_stage() -> SpecStage:
	return shop.stages[stage_index]


# ---------- 时间推进 ----------

func step(dt: float) -> void:
	if paused or dt <= 0 or not is_finite(dt): return
	_accumulator += dt
	while _accumulator + 0.000001 >= STEP:
		_accumulator -= STEP
		_tick()


func run(seconds: float) -> void:
	var t := 0.0
	while t < seconds - 0.000001:
		step(STEP)
		t += STEP


func _tick() -> void:
	clock += STEP
	events.clock = clock
	for e in mods.tick(STEP): events.emit("modifier_ended", e)
	# 整秒 / 整分钟广播：按时间触发的奇遇听这两个
	if int(round(clock * 10.0)) % 10 == 0: events.emit("tick_second", {"time": clock})
	if int(round(clock * 10.0)) % 600 == 0: events.emit("tick_minute", {"time": clock})
	if shop.fulfillment.handoff == "single": _tick_single()
	else: _tick_handoff()
	_track_bottleneck()
	if completed_at < 0.0 and shop_complete():
		completed_at = clock
		events.emit("completed", {})


# =====================================================================
# 交接方式 handoff：后厨跟单 + 前厅递杯（奶茶店）
# =====================================================================

func _tick_handoff() -> void:
	_drop_stuck_tickets()
	flyer_wait = maxf(0.0, flyer_wait - STEP)
	_flyer_entry_wave()
	_order_clock += STEP
	for order in orders: order.wait += STEP
	if is_open() and _order_clock >= _order_interval():
		_order_clock = 0.0
		if orders.size() < queue_capacity(): _add_order()
	_update_machines()
	_update_belt_items()
	for worker in workers:
		if worker.phase == "idle":
			worker.fatigue = maxf(0, worker.fatigue - STEP * shop.dispatch.fatigue_recover)
		else:
			worker.fatigue = minf(1, worker.fatigue + STEP * shop.dispatch.fatigue_gain)
			_update_worker(worker)
	_allocate()
	_run_belts()
	for index in range(diners.size() - 1, -1, -1):
		diners[index].left -= STEP
		if diners[index].left <= 0.000001: diners.remove_at(index)
	if not shop.fulfillment.takeaway_station.is_empty() and station_unlocked(shop.fulfillment.takeaway_station):
		var free := free_seats()
		for order in orders:
			if order.reserved or order.takeaway or order.seat >= 0: continue
			if free > 0: free -= 1
			else: order.takeaway = true


# ---------- 客流 ----------

func flow_multiplier() -> float:
	var flavors := 0
	for dish in shop.dishes:
		if dish.flavor_station.is_empty() or shop.station(dish.flavor_station).block != "topping": continue
		if dish_open(dish.id): flavors += 1
	var machine_levels := 0
	for st in shop.stations:
		if st.counts_for_flow and station_unlocked(st.id): machine_levels += level(st.id) - 1
	var base := (1.0 + shop.flavor_flow * maxi(0, flavors - 1)) * (1.0 + shop.level_flow * machine_levels)
	return mods.value("flow", base)


func _order_interval() -> float:
	return current_stage().customer_interval / flow_multiplier() * tuned("customer")


func ramp(key: String) -> float:
	var f := shop.fulfillment
	if f.ramp_orders <= 0: return 1.0
	return lerpf(f.ramp_start, 1.0, clampf(float(order_ramp.get(key, 0)) / f.ramp_orders, 0.0, 1.0))


## 本阶段各菜的点单权重。按菜单顺序排（.tres 存字典时会把键排序，抽单顺序不能靠字典顺序）；
## “一组口味”键平分给已开放的口味，排在最后；一个都没开时并进 fallback 菜。
func order_weights() -> Dictionary:
	var result := {}
	var stage := current_stage()
	var weights := stage.order_weights
	for d in shop.dishes:
		if weights.has(d.id) and dish_open(d.id): result[d.id] = weights[d.id] * ramp(d.id)
	if not stage.flavor_group.is_empty() and weights.has(stage.flavor_group):
		var share: float = weights[stage.flavor_group]
		var open: Array = []
		for d in shop.dishes:
			if d.flavor_station == "" or d.topping_count <= 0: continue
			if flavor_open(d): open.append(d.id)
		if open.is_empty(): result[stage.flavor_fallback] = float(result.get(stage.flavor_fallback, 0.0)) + share
		for id in open: result[id] = share / open.size()
	return result


func queue_capacity() -> int:
	if shop.fulfillment.handoff == "single": return current_stage().queue_capacity + current_stage().wait_seats
	return current_stage().queue_capacity + seated_orders()


## 排队人数（站位 + 等位）
func queue_size() -> int:
	return queue.size() if shop.fulfillment.handoff == "single" else orders.size()


## 开张以来进店的人数
func arrivals() -> int:
	return (_next_customer_id if shop.fulfillment.handoff == "single" else _next_order) - 1


func _pick_dish(weights: Dictionary) -> String:
	var total := 0.0
	for dish in weights: total += weights[dish]
	var sample := rng.randf() * total
	var selected: String = weights.keys()[0] if not weights.is_empty() else ""
	for dish in weights:
		sample -= weights[dish]
		if sample <= 0:
			selected = dish
			break
	return selected


func _add_order() -> void:
	if not is_open(): return
	var weights := order_weights()
	var total := 0.0
	for dish in weights: total += weights[dish]
	if total <= 0: return
	var selected := _pick_dish(weights)
	var seat := -1
	var takeaway := false
	var takeaway_open: bool = not shop.fulfillment.takeaway_station.is_empty() and station_unlocked(shop.fulfillment.takeaway_station)
	if shop.fulfillment.dine_rule == "seat_first":
		var spare := _spare_seats()
		seat = _first_open_seat() if spare > 0 else -1
		takeaway = takeaway_open and spare <= 0
	for dish in weights: order_ramp[dish] = mini(int(order_ramp.get(dish, 0)) + 1, shop.fulfillment.ramp_orders)
	if takeaway_open: order_ramp.takeaway = mini(int(order_ramp.get("takeaway", 0)) + 1, shop.fulfillment.ramp_orders)
	orders.append({"id": _next_order, "wait": 0.0, "reserved": false, "dish": selected, "takeaway": takeaway, "seat": seat})
	_next_order += 1
	events.emit("arrived", {"dish": selected})


func _flyer_entry_wave() -> void:
	if flyer_wave > 0.0: flyer_wave = maxf(0.0, flyer_wave - STEP)
	if flyer_pending <= 0: return
	flyer_clock += STEP
	if flyer_clock < shop.flyer.wave_seconds / maxf(1.0, float(flyer_customers())): return
	if orders.size() >= queue_capacity(): return
	flyer_clock = 0.0
	flyer_pending -= 1
	_add_order()


# ---------- 座位 ----------

func dine_group() -> SpecSeatGroup:
	for g in shop.seat_groups:
		if g.purpose == "dine": return g
	return null


func seat_total() -> int:
	var g := dine_group()
	return int(seats.get(g.id, 0)) if g != null else 0


func seat_seconds() -> float:
	var s := current_stage().seat_seconds
	var g := dine_group()
	return (s if s > 0 else (g.seconds if g != null else 0.0)) * tuned("seat")


func seated_orders() -> int:
	var count := 0
	for order in orders:
		if int(order.get("seat", -1)) >= 0: count += 1
	return count


func free_seats() -> int:
	var promised := 0
	for worker in workers:
		if worker.job.is_empty() or worker.job.kind != "serve" or _to_go(worker.job): continue
		if int(_order_by_id(worker.job.order_id).get("seat", -1)) < 0: promised += 1
	return seat_total() - diners.size() - promised - seated_orders()


func _spare_seats() -> int:
	var waiting := 0
	for order in orders:
		if int(order.get("seat", -1)) < 0 and not order.get("takeaway", false) and not order.reserved: waiting += 1
	return free_seats() - waiting


func _first_open_seat() -> int:
	var taken: Array = diners.map(func(diner: Dictionary) -> int: return diner.seat)
	for order in orders:
		if int(order.get("seat", -1)) >= 0: taken.append(int(order.seat))
	var seat := 0
	while seat in taken: seat += 1
	return seat


func _order_by_id(id: int) -> Dictionary:
	for order in orders:
		if order.id == id: return order
	return {}


func _to_go(job: Dictionary) -> bool:
	if job.src in [pickup_id, RACK]: return true
	for order in orders:
		if order.id == job.order_id: return order.get("takeaway", false)
	return false


func order_mood(order: Dictionary) -> int:
	var f := shop.fulfillment
	if f.mood_seconds.size() < 2: return 0
	var patience := mods.value("patience", 1.0)
	var wait: float = order.wait * (f.seated_patience if int(order.get("seat", -1)) >= 0 else 1.0) / patience
	return 2 if wait >= f.mood_seconds[1] else (1 if wait >= f.mood_seconds[0] else 0)


# ---------- 员工 ----------

func _kind(kind_id: String) -> SpecStaffKind:
	for k in shop.staff.kinds:
		if k.id == kind_id: return k
	return shop.staff.kinds[0]


func _new_worker(kind_id: String, id := -1) -> Dictionary:
	var kind := _kind(kind_id)
	var worker_id := id if id > 0 else _next_staff
	_next_staff = maxi(_next_staff, worker_id + 1)
	return {"id": worker_id, "kind": kind_id, "name": kind.display_name, "stats": kind.stats.duplicate(),
		"pos": nav.point(shop.layout.spawn_point), "walking": false, "phase": "idle", "task_label": "idle",
		"carry_item": "", "carry_count": 0, "fatigue": 0.0, "completed": 0, "job": {}, "ticket": {},
		"post": "", "path": PackedVector2Array(), "path_index": 0, "action_left": 0.0, "deployed": false, "source": "",
		# single 模式
		"target": "", "timer": 0.0, "order": -1, "steps": [], "step": 0, "chore": ""}


func _seat_at(worker: Dictionary, post: String) -> void:
	worker.post = post
	worker.pos = nav.post(post)


func side_of(worker: Dictionary) -> String:
	if shop.staff.zones.is_empty(): return ""
	return "front" if worker.post == counter_id else "kitchen"


func stat(worker: Dictionary, name: String) -> float:
	var base: float = float(worker.stats.get(name, 1.0))
	var side := side_of(worker)
	var seated := 1.0
	if name in ["walk", "work"] and worker.post in seatables: seated = shop.station(worker.post).seated_bonus
	var value := mods.value(name, base, side, "", "", "staff:%d" % worker.id)
	if name == "walk": return value * seated * tuned("walk")
	if name == "work": return value * seated * tuned("work")
	return value


func walk_speed(worker: Dictionary) -> float:
	return stat(worker, "walk")


func skill(worker: Dictionary) -> float:
	return stat(worker, "work")


func carry(worker: Dictionary) -> int:
	if worker.get("courier", false): return 1
	return int(stat(worker, "carry"))


func front_slots() -> int:
	return int(mods.value("staff_slot", float(shop.staff.front_base_slots), "front"))


func kitchen_slots() -> int:
	return int(current_stage().staff_slots.get("kitchen", 0))


func staff_slots() -> int:
	if shop.staff.zones.is_empty():
		return int(current_stage().staff_slots.get("", 1)) if is_open() else 1
	return front_slots() + kitchen_slots()


func kitchen_staff() -> int:
	var count := 0
	for worker in workers:
		if worker.post != counter_id: count += 1
	return count


func post_owner(post: String, exclude_id := -1) -> int:
	if post.is_empty(): return -1
	if post == counter_id:
		var owners: Array = workers.filter(func(w: Dictionary) -> bool: return w.id != exclude_id and w.post == counter_id)
		return owners[0].id if owners.size() >= front_slots() else -1
	for worker in workers:
		if worker.id != exclude_id and worker.post == post: return worker.id
	return -1


func worker_by_id(id: int) -> Dictionary:
	for worker in roster:
		if worker.id == id: return worker
	return {}


func hire_cost() -> int:
	var rules := shop.staff
	if not rules.hire_costs.is_empty():
		var n := roster.size() - 1
		return rules.hire_costs[n] if n < rules.hire_costs.size() else -1
	return rules.hire_cost_base + maxi(0, roster.size() - 1) * rules.hire_cost_step


func next_hire_kind() -> String:
	var rules := shop.staff
	if rules.hire_rule == "cycle":
		return rules.hire_order[(roster.size() - 1) % rules.hire_order.size()]
	var best: String = hire_pool[0]
	var fewest := -1
	for kind in hire_pool:
		var count := 0
		for worker in roster: count += 1 if worker.kind == kind else 0
		if fewest < 0 or count < fewest:
			best = kind
			fewest = count
	return best


func hire_error() -> String:
	var cost := hire_cost()
	if cost < 0: return "没有可招的人了"
	if shop.staff.zones.is_empty() and workers.size() >= staff_slots(): return "人手已满"
	if gold < cost: return "金币不足，需要 %d" % cost
	return ""


## 招人：分区的店招进名册（再派岗），不分区的店直接上岗。
func hire() -> String:
	var error := hire_error()
	if not error.is_empty(): return error
	gold -= hire_cost()
	var kind := next_hire_kind()
	var worker := _new_worker(kind, _hire_id(kind))
	worker.source = "招募"
	roster.append(worker)
	if shop.staff.zones.is_empty():
		worker.deployed = true
		worker.pos = nav.point(shop.staff.home_anchor)
		workers.append(worker)
	events.emit("hired", {"id": worker.id, "kind": kind})
	return ""


## 名册 id：分区的店按种类顺序给（同种第二位往后排），不分区的店按招人顺序。
func _hire_id(kind: String) -> int:
	if shop.staff.hire_rule == "cycle": return _next_staff
	var id := hire_pool.find(kind) + 1
	var next_id := hire_pool.size()
	for owned in roster:
		next_id = maxi(next_id, owned.id + 1)
		if owned.id == id: id = -1
	return id if id > 0 else next_id


func role_room(post: String, exclude_id := -1) -> String:
	var front := post == counter_id
	var count := 0
	for worker in workers:
		if worker.id != exclude_id and (worker.post == counter_id) == front: count += 1
	if front:
		return "前台最多 %d 位" % front_slots() if count >= front_slots() else ""
	if count >= kitchen_slots(): return "后厨最多 %d 位员工" % kitchen_slots()
	return ""


func deploy_worker(id: int, post := "") -> String:
	var worker := worker_by_id(id)
	if worker.is_empty(): return "未拥有这位员工"
	if worker.deployed: return ""
	if post.is_empty() and not role_room("").is_empty() and role_room(counter_id).is_empty(): post = counter_id
	if not post.is_empty() and post != counter_id:
		if not post in seatables: return "这里不能坐班"
		if post_owner(post, id) != -1: return "这里已经有人了"
	var error := role_room(post, id)
	if not error.is_empty(): return error
	worker.deployed = true
	workers.append(worker)
	if not post.is_empty(): _seat_at(worker, post)
	events.emit("deployed", {"id": id})
	return ""


## 拖人（§3.5）：post 空 = 去 point 那块空地流动；post = 坐班机器或柜台。只检查、不改状态。
func placement_error(id: int, post: String, point := Vector2.INF) -> String:
	if not shop.staff.can_drag: return "这家店不能调岗"
	var worker := worker_by_id(id)
	if worker.is_empty(): return "未拥有这位员工"
	if not post.is_empty():
		if post != counter_id and not post in seatables: return "无效岗位"
		if not station_unlocked(post): return "请先解锁设备"
		if post != counter_id and post_owner(post, id) != -1: return "岗位已有员工"
	var front := post == counter_id
	if not worker.deployed or front != (worker.post == counter_id):
		var room := role_room(post, id)
		if not room.is_empty(): return room
	if front and post_owner(counter_id, id) != -1: return "岗位已有员工"
	var target: Vector2 = nav.post(post) if not post.is_empty() else (worker.pos if point == Vector2.INF else point)
	if not nav.walkable(target, nav.point(counter_id)): return "无法放置在这里"
	return ""


## 派到某处：没上岗的先上岗，再换到这个岗位 / 这块空地。
func place_worker(id: int, post: String, point := Vector2.INF) -> String:
	var error := placement_error(id, post, point)
	if not error.is_empty(): return error
	var worker := worker_by_id(id)
	if not worker.deployed:
		worker.deployed = true
		workers.append(worker)
		events.emit("deployed", {"id": id})
	_cancel_job(worker)
	worker.post = post
	worker.pos = nav.post(post) if not post.is_empty() else (worker.pos if point == Vector2.INF else point)
	events.emit("placed", {"id": id, "post": post})
	return ""


## 收回名册：手上的活放下，东西留在原处。
func recall_worker(id: int) -> String:
	var worker := worker_by_id(id)
	if worker.is_empty(): return "未拥有这位员工"
	if not worker.deployed: return "员工已在待派遣名册"
	_cancel_job(worker)
	worker.post = ""
	worker.deployed = false
	workers.erase(worker)
	events.emit("recalled", {"id": id})
	return ""


## 后厨有人、但都坐在机器上：没人在机器之间搬东西。
func no_kitchen_carrier() -> bool:
	if shop.staff.zones.is_empty(): return false
	var kitchen: Array = workers.filter(func(w: Dictionary) -> bool: return w.post != counter_id)
	return not kitchen.is_empty() and kitchen.all(func(w: Dictionary) -> bool: return not String(w.post).is_empty())


## 放下手上的活：预留全部释放，拿在手上的东西放回原处，跟的单留给别人接（§3.6 预留与回收）。
func _cancel_job(worker: Dictionary) -> void:
	var job: Dictionary = worker.job
	if not job.is_empty():
		if worker.carry_count > 0:
			if job.src == supply_id: generated -= worker.carry_count
			elif job.src == SHELF:
				shelf_count += worker.carry_count
				shelf_stock[job.item] = int(shelf_stock.get(job.item, 0)) + worker.carry_count
			else:
				var stock: Dictionary = stations[job.src].input if job.kind in ["work", "pot_start"] else stations[job.src].output
				stock[job.item] = int(stock.get(job.item, 0)) + worker.carry_count
		elif not job.kind in ["pot_take", "stir"]:
			if job.src == SHELF: shelf_reserved_out -= job.count
			elif job.src != supply_id: stations[job.src].reserved_out[job.item] = int(stations[job.src].reserved_out.get(job.item, 0)) - job.count
		if _is_operation(job):
			stations[job.src].work_reserved = false
			if shop.station(job.src).block == "topping": stations[job.src].processing_item = ""
		elif job.dst == SHELF: shelf_reserved_in -= job.count
		elif job.dst != counter_id and stations.has(job.dst): stations[job.dst].reserved_in -= job.count
		if job.kind == "serve":
			for order in orders:
				if order.id == job.order_id: order.reserved = false
		if stations.has(job.src): _refresh_after_pickup(stations[job.src])
	worker.job = {}
	worker.ticket = {}
	worker.carry_count = 0
	worker.carry_item = ""
	worker.phase = "idle"
	worker.task_label = "idle"
	worker.walking = false
	worker.path = PackedVector2Array()
	worker.path_index = 0
	worker.action_left = 0.0


## 预览：把某条升级轨临时加一级，算完 fn 再还原（面板“当前 → 下一级”用）。
func preview(key: String, fn: Callable) -> Variant:
	if track_of(key) == null: return fn.call()
	levels[key] = int(levels[key]) + 1
	_refresh_key(key)
	var result: Variant = fn.call()
	levels[key] = int(levels[key]) - 1
	_refresh_key(key)
	return result


func _refresh_key(key: String) -> void:
	var t := track_of(key)
	if key.begins_with("staff/"): _refresh_track(null, t, key, int(levels[key]) + 1, key.get_slice("/", 1))
	elif key == "flyer": _refresh_track(null, t, key, levels[key], "")
	else:
		var st := shop.station(key.get_slice("/", 0))
		_refresh_track(st, t, key, levels[key], st.id)


# ---------- 机器 ----------

func pot_seconds(id: String) -> float:
	var st := shop.station(id)
	var seconds := float(st.params.get("cook_seconds", 0.0))
	return seconds * duration_mult(id) / speed(id) * tuned(id)


func machine_seconds(id: String) -> float:
	var st := shop.station(id)
	match st.block:
		"batch_pot": return pot_seconds(id)
		"combine": return float(st.params.get("seconds", 0.0)) * duration_mult(id) / speed(id) * tuned(id)
		"pickup":
			return float(st.params.get("process_seconds", 0.0)) / speed(id) / process_slots(id) * tuned(id)
	return 0.0


func _stock(station: Dictionary) -> int:
	var count: int = station.processing
	for value in station.input.values(): count += value
	for value in station.output.values(): count += value
	return count


func _pause_for_stir(id: String, station: Dictionary, before: float) -> bool:
	for point in shop.station(id).params.get("stir_points", []):
		if before < point and station.progress >= point:
			station.progress = point
			station.remaining = station.duration * (1.0 - point)
			station.phase = "stir"
			return true
	return false


func _update_machines() -> void:
	for st in shop.stations:
		if not st.block in ["batch_pot", "pickup"] and not st.id in autos: continue
		if st.block == "pickup" and st.id != pickup_id: continue
		var key := st.id
		if not station_unlocked(key): continue
		var station: Dictionary = stations[key]
		if station.processing > 0 and not station.phase in ["awaiting_take", "stir"]:
			var before: float = station.progress
			station.remaining = maxf(0, station.remaining - STEP)
			station.progress = 1.0 - station.remaining / station.duration
			if st.block == "batch_pot" and _pause_for_stir(key, station, before): continue
			if station.remaining <= 0.000001:
				if st.block == "batch_pot": station.phase = "awaiting_take"
				else:
					station.output[station.processing_item] += station.processing
					station.processing = 0
					station.processing_item = ""
					station.phase = "ready"
				station.progress = 1.0
		if station.processing == 0 and st.block != "batch_pot":
			var input_item := ""
			for item in station.input:
				if station.input[item] > 0:
					input_item = item
					break
			if not input_item.is_empty():
				# 自动组合台一次做完全部；出餐口加工环节一次一杯
				station.processing = 1 if st.block == "pickup" else station.input[input_item]
				station.input[input_item] -= station.processing
				station.processing_item = input_item if st.block == "pickup" else _auto_output(key)
				station.duration = machine_seconds(key)
				station.remaining = station.duration
				station.progress = 0.0
				station.phase = "working"
			elif _stock(station) == 0:
				station.phase = "idle"
				station.progress = 0.0


func _auto_output(id: String) -> String:
	for key in station_output:
		if key.begins_with(id + "|"): return station_output[key]
	return ""


# ---------- 搬运与预留 ----------

## 放到出餐口 / 加工位 / 外带架上的杯子按菜名记（锅里的中间品直接出餐时换成菜名）。
func _cup(item: String) -> String:
	if item in dish_ids: return item
	for dish in shop.dishes:
		var chain: Array = chains[dish.id]
		if chain.size() == 1 and station_output.get(chain[0] + "|" + dish.id, "") == item: return dish.id
	return item


func _return_slots(source: String) -> int:
	var count := 0
	for worker in workers:
		if not worker.job.is_empty() and worker.job.src == source: count += worker.carry_count
	return count


func dish_cap() -> int:
	var cap: int = int(shop.station(pickup_id).params.get("zones", {}).get("dine", 0)) if not pickup_id.is_empty() else 0
	if bool(shop.station(pickup_id).params.get("dine_at_least_queue", false)) if not pickup_id.is_empty() else false:
		cap = maxi(cap, queue_capacity())
	return cap


func shelf_capacity() -> int:
	var flavors := 0
	for id in kitchen_dishes:
		if dish_open(id): flavors += 1
	return dish_cap() * maxi(1, flavors)


func _shelf_item_free(item: String) -> int:
	var committed: int = shelf_stock.get(item, 0)
	for worker in workers:
		if worker.job.is_empty() or _cup(worker.job.item) != item: continue
		if worker.job.dst == SHELF: committed += worker.job.count
		if worker.job.src == SHELF: committed += worker.carry_count
	for shipment in belt_items:
		if shipment.dst == SHELF and shipment.item == item: committed += shipment.count
	return dish_cap() - committed


func _free(destination: String) -> int:
	if destination == COUNTER or destination == counter_id: return 3
	if destination == SHELF: return shelf_capacity() - shelf_count - shelf_reserved_in - _return_slots(destination)
	var station: Dictionary = stations[destination]
	return station.capacity - _stock(station) - station.reserved_in - _return_slots(destination)


func _input_item(station: String, item: String) -> bool:
	return station_input.get(station, "") == item and shop.station(station).block in ["batch_pot", "topping"]


func _available(source: String, item: String) -> int:
	if source == supply_id or source == SUPPLY: return UNLIMITED
	if source == SHELF:
		var reserved := 0
		for worker in workers:
			if not worker.job.is_empty() and worker.job.src == SHELF and worker.job.item == item and worker.carry_count == 0: reserved += worker.job.count
		return int(shelf_stock.get(item, 0)) - reserved
	var station: Dictionary = stations[source]
	var stock: Dictionary = station.input if _input_item(source, item) else station.output
	return int(stock.get(item, 0)) - int(station.reserved_out.get(item, 0))


func _candidate(kind: String, source: String, destination: String, item: String, worker: Dictionary, priority: float, belt := "") -> Dictionary:
	var count: int = mini(carry(worker), mini(_available(source, item), _free(destination)))
	if count <= 0: return {}
	var job := {"kind": kind, "src": source, "dst": destination, "item": item, "count": count, "priority": priority, "belt": belt, "order_id": -1}
	if destination == SHELF:
		job.count = mini(job.count, _shelf_item_free(_cup(item)))
		if job.count <= 0: return {}
	return job


func _is_operation(job: Dictionary) -> bool:
	return job.kind in ["work", "pot_start", "pot_take", "stir"]


func _source_point(job: Dictionary) -> Vector2:
	if job.get("pour", "") != "": return nav.point(job.pour)
	if job.src == RACK: return nav.point(SHELF)
	if _is_operation(job): return nav.post(job.src)
	return nav.point(job.src)


func _destination_point(job: Dictionary) -> Vector2:
	if _is_operation(job): return _source_point(job)
	if job.dst == RACK: return nav.point(SHELF)
	return nav.point(job.dst)


func _reserve(worker: Dictionary, job: Dictionary) -> void:
	var ticket: Dictionary = job.get("ticket", {})
	job.erase("ticket")
	if job.kind == "work" and shop.station(job.src).block == "topping":
		var flavor: String = ticket.get("dish", worker.ticket.get("dish", ""))
		stations[job.src].processing_item = flavor if not flavor.is_empty() else _seated_flavor(job.src)
	if job.kind in ["pot_take", "stir"]:
		pass
	elif job.src == SHELF:
		shelf_reserved_out += job.count
	elif job.src != supply_id:
		var station: Dictionary = stations[job.src]
		station.reserved_out[job.item] = int(station.reserved_out.get(job.item, 0)) + job.count
	if _is_operation(job):
		stations[job.src].work_reserved = true
	elif job.dst == SHELF:
		shelf_reserved_in += job.count
	elif job.dst != counter_id:
		stations[job.dst].reserved_in += job.count
	if job.kind == "serve":
		for order in orders:
			if order.id == job.order_id: order.reserved = true
	worker.job = job
	worker.task_label = job.kind
	_walk(worker, _source_point(job), "walk_pickup")
	if not ticket.is_empty(): worker.ticket = ticket


func _walk(worker: Dictionary, destination: Vector2, phase: String) -> void:
	worker.path = nav.path(worker.pos, destination)
	worker.path_index = 1 if worker.path.size() > 1 else 0
	worker.phase = phase
	worker.walking = true


func _take(job: Dictionary) -> void:
	if job.src == SHELF:
		shelf_stock[job.item] -= job.count
	if job.src == supply_id:
		generated += job.count
	elif job.src == SHELF:
		shelf_count -= job.count
		shelf_reserved_out -= job.count
	else:
		var station: Dictionary = stations[job.src]
		var stock: Dictionary = station.input if job.kind in ["work", "pot_start"] else station.output
		stock[job.item] -= job.count
		station.reserved_out[job.item] -= job.count
		_refresh_after_pickup(station)


func _refresh_after_pickup(station: Dictionary) -> void:
	if station.processing > 0 or (station.work_reserved and station.phase == "working"): return
	var ready := false
	for count in station.output.values(): ready = ready or count > 0
	station.phase = "ready" if ready else "idle"
	station.progress = 1.0 if ready else 0.0


func _deliver(destination: String, item: String, count: int) -> void:
	if destination == RACK:
		stations[RACK].output[item] += count
		stations[RACK].reserved_in -= count
		return
	if destination == SHELF:
		shelf_stock[_cup(item)] += count
		shelf_count += count
		shelf_reserved_in -= count
		return
	var cup := _cup(item) if destination == pickup_id else item
	stations[destination].input[cup] += count
	stations[destination].reserved_in -= count


func _action_duration(job: Dictionary, worker: Dictionary) -> float:
	var hop := shop.dispatch.hop_seconds
	if job.get("pour", "") != "":
		var total := 0.0
		for s in shop.dish(job.item).steps:
			var st := shop.station(s.station)
			total += st.params.get("seconds", s.seconds) / speed(s.station) * tuned(s.station)
		return total / skill(worker)
	match job.kind:
		"work":
			var st := shop.station(job.src)
			return float(st.params.get("seconds", 0.0)) * job.count / skill(worker) / speed(job.src) * tuned(job.src)
		"stir": return float(shop.station(job.src).params.get("stir_seconds", 1.0)) / skill(worker)
		"load": return hop / skill(worker) / speed(supply_id)
	return hop / skill(worker)


func _update_worker(worker: Dictionary) -> void:
	var job: Dictionary = worker.job
	if worker.walking:
		var distance: float = walk_speed(worker) * STEP
		while distance > 0 and worker.path_index < worker.path.size():
			var target: Vector2 = worker.path[worker.path_index]
			var gap: float = worker.pos.distance_to(target)
			if gap <= distance + 0.00001:
				worker.pos = target
				distance -= gap
				worker.path_index += 1
			else:
				worker.pos = worker.pos.move_toward(target, distance)
				distance = 0
		if worker.path_index < worker.path.size(): return
		worker.walking = false
		if worker.phase == "walk_pickup":
			worker.phase = "work" if _is_operation(job) else "pickup"
			worker.action_left = _action_duration(job, worker)
			if job.kind == "work":
				stations[job.src].phase = "working"
				stations[job.src].duration = worker.action_left
		else:
			worker.phase = "dropoff"
			worker.action_left = shop.dispatch.hop_seconds / skill(worker)
		return
	worker.action_left = maxf(0, worker.action_left - STEP)
	if worker.phase == "work" and job.kind == "work":
		stations[job.src].progress = 1.0 - worker.action_left / stations[job.src].duration
	if worker.action_left > 0.000001: return
	match worker.phase:
		"pickup":
			_take(job)
			worker.carry_item = job.item
			worker.carry_count = job.count
			_walk(worker, _destination_point(job), "walk_dropoff")
		"work":
			var station: Dictionary = stations[job.src]
			match job.kind:
				"pot_start":
					_take(job)
					station.processing = job.count
					station.duration = pot_seconds(job.src)
					station.remaining = station.duration
					station.progress = 0.0
					station.phase = "heating"
				"stir":
					station.phase = "heating"
				"pot_take":
					var out: String = station.output.keys()[0]
					station.output[out] += station.processing
					station.processing = 0
					station.phase = "ready"
					station.progress = 1.0
				_:
					_take(job)
					_complete_topping(job.src, station, job)
					station.phase = "ready"
					station.progress = 1.0
			station.work_reserved = false
			_finish(worker)
		"dropoff":
			if job.kind == "serve":
				_record_sale(job)
				for index in orders.size():
					if orders[index].id == job.order_id:
						orders.remove_at(index)
						break
			else:
				_deliver(job.dst, job.item, job.count)
			_finish(worker)


func _complete_topping(id: String, station: Dictionary, job: Dictionary) -> void:
	if not station.processing_item.is_empty():
		station.output[station.processing_item] += job.count
		station.processing_item = ""
		return
	station.input[job.item] += job.count


func _finish(worker: Dictionary) -> void:
	var job: Dictionary = worker.job
	if not worker.ticket.is_empty() and not job.is_empty():
		var ticket: Dictionary = worker.ticket
		var chain: Array = chains[ticket.dish]
		var at: String = chain[ticket.at]
		var done := false
		if ticket.phase == "carry":
			if job.src == at and not _is_operation(job):
				if ticket.at >= chain.size() - 1: done = true
				else:
					ticket.at += 1
					ticket.phase = "work" if _manual(chain[ticket.at]) else "carry"
		else:
			if job.kind == "work": ticket.phase = "carry"
			elif job.src == at: done = true
		ticket.wait = 0.0
		if done: worker.ticket = {}
	worker.completed += 1
	worker.carry_count = 0
	worker.carry_item = ""
	worker.job = {}
	worker.phase = "idle"
	worker.task_label = "idle"
	worker.walking = false


func _manual(id: String) -> bool:
	return shop.station(id).block == "topping"


func _record_sale(job: Dictionary) -> void:
	if not _to_go(job):
		var seat := int(_order_by_id(job.order_id).get("seat", -1))
		if seat < 0: seat = _first_open_seat()
		diners.append({"seat": seat, "dish": job.item, "left": seat_seconds()})
	sold += job.count
	sold_by_dish[job.item] += job.count
	var earned: float = dish_price(job.item) * job.count + _sale_carry
	var income: int = floori(earned + 0.0001)
	_sale_carry = maxf(0.0, earned - income)
	gold += income
	revenue += income
	events.emit("sale", {"dish": job.item, "count": job.count, "income": income})


# ---------- 调度（§3.6） ----------

func _score(name: String) -> float:
	return float(shop.dispatch.base_scores.get(name, 0.0))


func _allocate() -> void:
	var d := shop.dispatch
	for unused in workers.size():
		var best_worker: Dictionary = {}
		var best_job: Dictionary = {}
		var best_score := -INF
		for worker in workers:
			if worker.phase != "idle": continue
			for job in _jobs(worker):
				if job.is_empty(): continue
				var to_source := nav.path(worker.pos, _source_point(job))
				var to_target := nav.path(_source_point(job), _destination_point(job))
				if to_source.is_empty() or to_target.is_empty(): continue
				var travel: float = (RuleNav.length(to_source) + RuleNav.length(to_target)) / walk_speed(worker)
				var work_time: float = _action_duration(job, worker) if job.kind == "work" else 2.0 * d.hop_seconds / skill(worker)
				var throughput: float = float(job.count) / maxf(0.1, travel + work_time)
				var score: float = (job.priority + throughput * d.throughput_weight - travel * d.travel_penalty) * (1.0 - worker.fatigue * d.fatigue_weight)
				if score > best_score:
					best_score = score
					best_worker = worker
					best_job = job
		if best_job.is_empty(): break
		_reserve(best_worker, best_job)


func _jobs(worker: Dictionary) -> Array:
	var result: Array = []
	for post in seatables:
		if not station_unlocked(post) or (not worker.post.is_empty() and worker.post != post): continue
		if post_owner(post, worker.id) != -1: continue
		var station: Dictionary = stations[post]
		if station.work_reserved: continue
		var st := shop.station(post)
		var kind := ""
		var item: String = station_input.get(post, "")
		var count := 0
		var priority := _score("chore")
		if st.block == "topping" and _available(post, item) > 0:
			kind = "work"
			count = mini(carry(worker), _available(post, item))
			priority = _score("topping")
		elif st.block == "batch_pot" and station.processing == 0 and _available(post, item) >= pot_batch(post):
			kind = "pot_start"
			count = pot_batch(post)
		elif st.block == "batch_pot" and station.phase == "stir":
			kind = "stir"
			count = station.processing
			item = station.output.keys()[0]
			priority = _score("stir")
		elif st.block == "batch_pot" and station.phase == "awaiting_take" and station.processing > 0:
			kind = "pot_take"
			count = station.processing
			item = station.output.keys()[0]
		if not kind.is_empty() and count > 0:
			result.append({"kind": kind, "src": post, "dst": post, "item": item, "count": count, "priority": priority, "belt": "", "order_id": -1})
	if worker.post in seatables: return _follow_seated(worker, result)
	if not worker.post.is_empty() and worker.post != counter_id: return result
	if worker.post.is_empty(): return _follow_jobs(worker, result)
	# 前厅：只递杯
	var seats_left := free_seats()
	for order in orders:
		if order.reserved: continue
		var source: String = RACK if order.takeaway else SHELF
		var pour := ""
		if order.dish in front_dishes:
			source = RACK if order.takeaway and _available(RACK, order.dish) > 0 else supply_id
			if source == supply_id: pour = shop.dish(order.dish).steps[0].station
		var standing_dine_in: bool = not order.takeaway and int(order.seat) < 0
		if standing_dine_in and seats_left <= 0: continue
		var serve := _candidate("serve", source, counter_id, order.dish, worker, _score("serve"))
		if serve.is_empty(): continue
		if standing_dine_in: seats_left -= 1
		serve.count = 1
		serve.order_id = order.id
		serve.pour = pour
		serve.priority += minf(shop.dispatch.wait_bonus_cap, order.wait * shop.dispatch.wait_bonus_per_second)
		result.append(serve)
	return result


func _follow_seated(worker: Dictionary, result: Array) -> Array:
	if shop.station(worker.post).block == "batch_pot": return _pot_jobs(worker, result, worker.post)
	var jobs := result.filter(func(job: Dictionary) -> bool: return not job.is_empty() and job.kind == "work" and not _seated_flavor(worker.post).is_empty())
	for job in jobs: job.count = 1
	return jobs


func _seated_flavor(post: String) -> String:
	var made := {}
	for worker in workers:
		if worker.ticket.is_empty() or chains[worker.ticket.dish][worker.ticket.at] != post or worker.ticket.phase != "work": continue
		if not worker.job.is_empty() and worker.job.src == post: continue
		var dish: String = worker.ticket.dish
		if not made.has(dish): made[dish] = int(stations[post].output.get(dish, 0)) - int(stations[post].reserved_out.get(dish, 0))
		made[dish] -= worker.ticket.count
		if made[dish] < 0: return dish
	return ""


func _first_pot() -> String:
	return pots[0] if not pots.is_empty() else ""


func _follow_jobs(worker: Dictionary, result: Array) -> Array:
	var pot := _first_pot()
	if pot.is_empty() or not station_unlocked(pot):
		var packs: Array = []
		_append_pack_jobs(worker, packs)
		return packs
	var pot_jobs: Array = _pot_jobs(worker, result, pot) if post_owner(pot) == -1 else []
	if not worker.ticket.is_empty():
		var job := _ticket_job(worker, worker.ticket)
		if not job.is_empty(): return [job]
		return pot_jobs if worker.ticket.at == 0 and worker.ticket.phase == "carry" else []
	var jobs: Array = pot_jobs
	_append_pack_jobs(worker, jobs)
	jobs.append(_new_ticket_job(worker, pot_jobs))
	return jobs


func _pot_short(pot: String) -> bool:
	var need := 0
	for worker in workers:
		if not worker.ticket.is_empty() and worker.ticket.at == 0 and worker.ticket.phase == "carry" and chains[worker.ticket.dish][0] == pot: need += worker.ticket.count
	for order in open_orders():
		var start := _start_stage(order.dish, 1)
		if start.at == 0 and start.phase == "carry" and chains[order.dish][0] == pot: need += 1
	var station: Dictionary = stations[pot]
	var out: String = station.output.keys()[0]
	return int(station.output[out]) - int(station.reserved_out.get(out, 0)) + station.processing < need


func _pot_jobs(worker: Dictionary, result: Array, pot: String) -> Array:
	var short := _pot_short(pot)
	var jobs: Array = []
	for job in result:
		if job.is_empty() or not job.kind in ["pot_start", "stir", "pot_take"] or job.src != pot: continue
		if short: job.priority += _score("pot_short_bonus")
		jobs.append(job)
	var input: String = station_input.get(pot, "")
	if not input.is_empty() and _box_ready(input):
		jobs.append(_candidate("load", supply_id, pot, input, worker, _score("load_short") if short else _score("load")))
	return jobs


## 外带：从出餐口取杯送去加工（封口），加工好的送到外带架。
func _append_pack_jobs(worker: Dictionary, result: Array) -> void:
	if pickup_id.is_empty() or not station_unlocked(pickup_id): return
	if _courier or not _belted(pickup_id, RACK):
		for dish in dish_ids:
			result.append(_candidate("carry_to_rack", pickup_id, RACK, dish, worker, _score("to_rack")))
	if _courier: return
	for dish in kitchen_dishes:
		var need := _pack_need(dish)
		if need <= 0: continue
		var job := _candidate("carry_to_process", SHELF, pickup_id, dish, worker, _score("to_process"))
		if job.is_empty(): continue
		job.count = mini(job.count, need)
		result.append(job)


func _pack_need(dish: String) -> int:
	var need := 0
	for order in orders:
		if order.takeaway and not order.reserved and order.dish == dish: need += 1
	return need - _sealed_supply(dish)


func _sealed_supply(dish: String) -> int:
	var seal: Dictionary = stations[pickup_id]
	var rack: Dictionary = stations[RACK]
	var count: int = int(seal.input[dish]) + int(seal.output[dish]) - int(seal.reserved_out.get(dish, 0))
	count += int(rack.output[dish]) - int(rack.reserved_out.get(dish, 0))
	if seal.processing_item == dish: count += seal.processing
	count += _riding_to_rack(dish)
	for other in workers:
		if other.job.is_empty() or _cup(other.job.item) != dish: continue
		if other.job.kind in ["carry_to_process", "carry_to_rack"]: count += other.job.count
	return count


func _riding_to_rack(dish: String) -> int:
	var count := 0
	for shipment in belt_items:
		if shipment.dst == RACK and shipment.item == dish: count += shipment.count
	return count


func _kitchen_supply() -> Dictionary:
	var supply := {}
	for dish in dish_ids:
		supply[dish] = 0
		if not dish in kitchen_dishes: continue
		if not pickup_id.is_empty():
			var seal: Dictionary = stations[pickup_id]
			var rack: Dictionary = stations[RACK]
			supply[dish] += maxi(0, _available(SHELF, dish)) + int(seal.input[dish]) + int(seal.output[dish]) - int(seal.reserved_out.get(dish, 0))
			supply[dish] += int(rack.output[dish]) - int(rack.reserved_out.get(dish, 0))
			if seal.processing_item == dish: supply[dish] += seal.processing
			supply[dish] += _riding_to_rack(dish)
		else:
			supply[dish] += maxi(0, _available(SHELF, dish))
	for worker in workers:
		if not worker.ticket.is_empty(): supply[worker.ticket.dish] += worker.ticket.count
		elif not worker.job.is_empty() and worker.job.kind == "carry_to_process" and worker.job.src == SHELF: supply[worker.job.item] += worker.job.count
		elif not worker.job.is_empty() and worker.job.kind == "carry_to_rack": supply[worker.job.item] += worker.job.count
	return supply


func open_orders() -> Array:
	var supply := _kitchen_supply()
	var result: Array = []
	for order in orders:
		if order.reserved or not order.dish in kitchen_dishes: continue
		if supply[order.dish] > 0: supply[order.dish] -= 1
		else: result.append(order)
	return result


## 一站上没人跟着的现成物品（被收回的单留下的）。
func _loose(station_id: String, dish := "", output := false) -> int:
	var station: Dictionary = stations[station_id]
	var st := shop.station(station_id)
	var count := 0
	var waiting := 0
	if st.block != "topping":
		var input: String = station_input.get(station_id, "")
		var out := _auto_output(station_id)
		count = int(station.input.get(input, 0)) + int(station.output.get(out, 0)) - int(station.reserved_out.get(out, 0)) + station.processing
		for worker in workers:
			if worker.ticket.is_empty() or chains[worker.ticket.dish][worker.ticket.at] != station_id or worker.ticket.phase != "carry": continue
			if worker.job.is_empty() or worker.job.src != station_id: waiting += worker.ticket.count
	elif not output:
		var input: String = station_input.get(station_id, "")
		count = int(station.input.get(input, 0)) - int(station.reserved_out.get(input, 0))
		for worker in workers:
			if worker.ticket.is_empty() or chains[worker.ticket.dish][worker.ticket.at] != station_id or worker.ticket.phase != "work": continue
			if worker.job.is_empty(): waiting += worker.ticket.count
	else:
		count = int(station.output.get(dish, 0)) - int(station.reserved_out.get(dish, 0))
		for worker in workers:
			if worker.ticket.is_empty() or worker.ticket.dish != dish or chains[worker.ticket.dish][worker.ticket.at] != station_id: continue
			if worker.job.is_empty() or worker.job.kind == "work": waiting += worker.ticket.count
	return count - waiting


## 从工序链上最靠后的现成物品那一步接着做（§3.6）。
func _start_stage(dish: String, count: int) -> Dictionary:
	var chain: Array = chains[dish]
	if shop.dispatch.resume_from_stock:
		for i in range(chain.size() - 1, 0, -1):
			var id: String = chain[i]
			if _manual(id):
				if _loose(id, dish, true) >= count: return {"at": i, "phase": "carry"}
				if _loose(id) >= count: return {"at": i, "phase": "work"}
			elif _loose(id) >= count: return {"at": i, "phase": "carry"}
	return {"at": 0, "phase": "carry"}


func _exact(job: Dictionary, count: int) -> Dictionary:
	if job.is_empty() or job.count < count: return {}
	job.count = count
	return job


func _final_job(source: String, item: String, dish: String, count: int, worker: Dictionary) -> Dictionary:
	if not pickup_id.is_empty() and station_unlocked(pickup_id) and _pack_need(dish) >= count:
		var job := _exact(_candidate("carry_to_process", source, pickup_id, item, worker, _score("follow_step")), count)
		if not job.is_empty(): return job
	return _exact(_candidate("carry_to_shelf", source, SHELF, item, worker, _score("follow_step")), count)


func _ticket_job(worker: Dictionary, ticket: Dictionary) -> Dictionary:
	var dish: String = ticket.dish
	var count: int = ticket.count
	var chain: Array = chains[dish]
	var at: String = chain[ticket.at]
	var item: String = station_output.get(at + "|" + dish, "")
	if ticket.phase == "carry":
		if ticket.at >= chain.size() - 1: return _final_job(at, item, dish, count, worker)
		return _exact(_candidate("transfer", at, chain[ticket.at + 1], item, worker, _score("follow_step")), count)
	# 手工台：有人坐班就等他做好再搬走；没人就自己做
	if post_owner(at) != -1: return _final_job(at, dish, dish, count, worker)
	var input: String = station_input.get(at, "")
	if stations[at].work_reserved or _available(at, input) < count: return {}
	return {"kind": "work", "src": at, "dst": at, "item": input, "count": count, "priority": _score("follow_step"), "belt": "", "order_id": -1}


func _new_ticket_job(worker: Dictionary, pot_jobs: Array) -> Dictionary:
	var open := open_orders()
	if open.is_empty(): return {}
	var dish: String = open[0].dish
	var count := 0
	for order in open:
		if order.dish != dish or count >= carry(worker): break
		count += 1
	var start := _start_stage(dish, count)
	var ticket := {"dish": dish, "count": count, "at": start.at, "phase": start.phase, "wait": 0.0}
	var job := _ticket_job(worker, ticket)
	if job.is_empty() and start.at == 0 and start.phase == "carry":
		for option in pot_jobs:
			if not option.is_empty() and (job.is_empty() or option.priority > job.priority): job = option.duplicate()
	if job.is_empty(): return {}
	job.priority = _score("follow") + minf(shop.dispatch.wait_bonus_cap, open[0].wait * shop.dispatch.wait_bonus_per_second)
	job["ticket"] = ticket
	return job


func _drop_stuck_tickets() -> void:
	for worker in workers:
		if worker.ticket.is_empty() or not worker.job.is_empty() or (worker.ticket.at == 0 and worker.ticket.phase == "carry"): continue
		worker.ticket.wait += STEP
		if worker.ticket.wait >= shop.dispatch.ticket_give_up: worker.ticket = {}


# ---------- 连接（传送带） ----------

func _connection(id: String) -> SpecConnection:
	for c in shop.connections:
		if c.id == id: return c
	return null


func _belted(source: String, destination: String) -> bool:
	for id in belts:
		var c := _connection(id)
		if c.from == source and c.to == destination: return true
	return false


func _update_belt_items() -> void:
	for index in range(belt_items.size() - 1, -1, -1):
		var shipment: Dictionary = belt_items[index]
		shipment.progress = minf(1, shipment.progress + STEP / shipment.duration)
		if shipment.progress >= 1:
			_deliver(shipment.dst, shipment.item, shipment.count)
			belt_items.remove_at(index)


func _run_belts() -> void:
	for id in belts:
		belt_clock[id] = maxf(0.0, belt_clock[id] - STEP)
		if belt_clock[id] > 0.0: continue
		var c := _connection(id)
		var courier := {"id": -1, "post": "", "courier": true, "job": {}, "ticket": {}}
		_courier = true
		var options: Array = []
		_append_pack_jobs(courier, options)
		_courier = false
		var best: Dictionary = {}
		for job in options:
			if job.is_empty() or job.src != c.from or job.dst != c.to: continue
			if best.is_empty() or job.priority > best.priority: best = job
		if best.is_empty(): continue
		if best.src == SHELF: shelf_reserved_out += best.count
		elif best.src != supply_id: stations[best.src].reserved_out[best.item] = int(stations[best.src].reserved_out.get(best.item, 0)) + best.count
		if best.dst == SHELF: shelf_reserved_in += best.count
		else: stations[best.dst].reserved_in += best.count
		_take(best)
		belt_items.append({"route": id, "item": best.item, "count": best.count, "progress": 0.0, "duration": c.seconds, "dst": best.dst})
		belt_clock[id] = c.interval


# =====================================================================
# 交接方式 single：一人从收钱跟到递餐（煎饼摊）
# =====================================================================

var customers: Array = []
var queue: Array = []
var _next_customer_id := 1


func _tick_single() -> void:
	if is_open(): _arrivals_single()
	_customers_single()
	for st in shop.stations:
		if st.block != "batch_pot" or not station_unlocked(st.id): continue
		var pot: Dictionary = stations[st.id]
		if pot.phase == "cook":
			pot.remaining -= STEP
			if pot.remaining <= 0.0: pot.phase = "done"
	for worker in workers: _staff_tick(worker)


func _arrivals_single() -> void:
	_next_customer -= STEP
	if flyer_left > 0:
		flyer_timer -= STEP
		if flyer_timer <= 0.0:
			flyer_left -= 1
			flyer_timer = shop.flyer.gap
			_spawn_single()
	if _next_customer <= 0.0:
		var interval := current_stage().customer_interval / mods.value("flow", 1.0) * tuned("customer")
		_next_customer = -log(1.0 - rng.randf() * 0.999) * interval
		_spawn_single()


func _spawn_single() -> void:
	if queue.size() >= queue_capacity():
		lost += 1
		events.emit("lost", {})
		return
	var kind := _pick_dish(order_weights())
	var f := shop.fulfillment
	var addon: bool = kind == f.addon_dish or (not f.addon_dish.is_empty() and rng.randf() < f.addon_chance)
	var c := {"id": _next_customer_id, "kind": kind, "addon": addon, "state": "queue", "wait": 0.0, "claimed": false, "paid": 0}
	_next_customer_id += 1
	customers.append(c)
	queue.append(c.id)
	events.emit("arrived", {"dish": kind})


func _customers_single() -> void:
	var patience := shop.fulfillment.leave_after * mods.value("patience", 1.0)
	for c in customers.duplicate():
		if c.state == "queue":
			c.wait += STEP
			if patience > 0.0 and c.wait > patience and not c.claimed:
				c.state = "leaving"
				queue.erase(c.id)
				lost += 1
				events.emit("lost", {})
		if c.state == "leaving": customers.erase(c)


func customer(id: int) -> Dictionary:
	for c in customers:
		if c.id == id: return c
	return {}


func _order_steps(c: Dictionary) -> Array:
	var take := shop.station(counter_id).params
	var steps := [{"point": counter_id, "action": "take", "seconds": float(take.get("take_seconds", 0.0)), "label": "收钱", "station": counter_id}]
	var f := shop.fulfillment
	var dishes: Array = []
	if c.addon and c.kind != f.addon_dish and f.addon_first: dishes.append(f.addon_dish)
	dishes.append(c.kind)
	if c.addon and c.kind != f.addon_dish and not f.addon_first: dishes.append(f.addon_dish)
	for id in dishes:
		for s in shop.dish(id).steps:
			# 站位：布局里有“机器.动作”就站那儿（比如从锅里拿成品站在成品筐前），否则站机器前
			var point: String = s.station + "." + s.action
			if not shop.layout.aliases.has(point): point = s.station
			steps.append({"point": point, "action": s.action, "seconds": s.seconds * s.repeat, "label": s.label, "station": s.station})
	steps.append({"point": counter_id, "action": "hand", "seconds": float(take.get("hand_seconds", 0.0)), "label": "递餐", "station": counter_id})
	return steps


func _staff_tick(s: Dictionary) -> void:
	if s.walking:
		if s.target == shop.staff.home_anchor and s.order < 0 and s.chore.is_empty() and _find_job_single(s): return
		_walk_single(s)
		return
	if s.phase == "work":
		s.timer -= STEP
		if s.timer > 0.0: return
		_finish_work_single(s)
	_decide_single(s)


func _walk_single(s: Dictionary) -> void:
	var goal := nav.point(s.target)
	var to: Vector2 = goal - s.pos
	var move: float = walk_speed(s) * STEP
	if to.length() <= move:
		s.pos = goal
		s.walking = false
		_arrived_single(s)
	else:
		s.pos += to.normalized() * move


func _go(s: Dictionary, point: String, label: String) -> void:
	s.target = point
	s.task_label = label
	if s.pos.distance_to(nav.point(point)) < 1.0:
		s.walking = false
		_arrived_single(s)
	else:
		s.walking = true
		s.phase = "walk"


func _work_single(s: Dictionary, seconds: float) -> void:
	s.phase = "work"
	s.timer = seconds


func _decide_single(s: Dictionary) -> void:
	if s.phase == "work" or s.walking: return
	if not s.chore.is_empty(): return
	if s.order >= 0:
		_go(s, s.steps[s.step].point, s.steps[s.step].label)
		return
	if _find_job_single(s): return
	var home := shop.staff.home_anchor
	if s.target != home and _crowded(s): _go(s, home, "待命")
	s.phase = "walk" if s.walking else "idle"
	s.task_label = "待命"


func _crowded(s: Dictionary) -> bool:
	for o in workers:
		if o.id != s.id and Vector2(o.pos).distance_to(s.pos) < 60.0: return true
	return false


func _find_job_single(s: Dictionary) -> bool:
	if shop.dispatch.chores_first and _try_pot_chore(s, false): return true
	if queue.is_empty(): return false
	var c := customer(queue[0])
	if c.claimed: return false
	c.claimed = true
	s.order = c.id
	s.steps = _order_steps(c)
	s.step = 0
	s.walking = false
	_go(s, s.steps[0].point, s.steps[0].label)
	return true


func _try_pot_chore(s: Dictionary, blocked: bool) -> bool:
	for id in pots:
		if not station_unlocked(id): continue
		var pot: Dictionary = stations[id]
		if pot.user != -1: continue
		var rule: SpecStockRule = shop.station(id).stock[0] if not shop.station(id).stock.is_empty() else null
		if pot.phase == "done":
			pot.user = s.id
			s.chore = "unload:" + id
			_go(s, id, String(shop.station(id).params.get("unload_label", "出锅")))
			return true
		if pot.phase == "idle" and rule != null and (pot.stock < rule.low or blocked) and pot.stock < rule.cap:
			pot.user = s.id
			s.chore = "load:" + id
			_go(s, id, String(shop.station(id).params.get("load_label", "下锅")))
			return true
	return false


func _arrived_single(s: Dictionary) -> void:
	if not s.chore.is_empty():
		var parts: PackedStringArray = s.chore.split(":")
		var params: Dictionary = shop.station(parts[1]).params
		_work_single(s, float(params.get("load_seconds" if parts[0] == "load" else "unload_seconds", 0.0)))
		return
	if s.order < 0:
		s.phase = "idle"
		s.task_label = "待命"
		return
	var st: Dictionary = s.steps[s.step]
	var station := shop.station(st.station)
	if station.block == "hand" and int(station.params.get("users", 0)) > 0:
		var busy: Dictionary = stations[st.station]
		if busy.user != -1 and busy.user != s.id:
			s.phase = "wait"
			s.task_label = "等" + station.display_name
			return
		busy.user = s.id
		_work_single(s, st.seconds * duration_mult(st.station) / speed(st.station) / skill(s))
	elif station.block == "batch_pot":
		var pot: Dictionary = stations[st.station]
		if pot.stock < 1:
			s.phase = "wait"
			s.task_label = "等" + (_item_name(station.stock[0].item) if not station.stock.is_empty() else station.display_name)
			_try_pot_chore(s, true)
			return
		pot.stock -= 1
		_work_single(s, st.seconds / skill(s))
	else:
		_work_single(s, st.seconds / skill(s))
	s.task_label = st.label


func _finish_work_single(s: Dictionary) -> void:
	s.phase = "idle"
	if not s.chore.is_empty():
		var parts: PackedStringArray = s.chore.split(":")
		var pot: Dictionary = stations[parts[1]]
		var st := shop.station(parts[1])
		if parts[0] == "load":
			pot.phase = "cook"
			pot.remaining = pot_seconds(parts[1])
		else:
			pot.stock = mini(st.stock[0].cap, pot.stock + pot_batch(parts[1]))
			pot.phase = "idle"
		pot.user = -1
		s.chore = ""
		return
	var c := customer(s.order)
	var st: Dictionary = s.steps[s.step]
	match st.action:
		"take":
			queue.erase(c.id)
			var paid := order_price_single(c)
			gold += paid
			revenue += paid
			c.paid = paid
			c.state = "paid"
		"hand":
			c.state = "leaving"
			sold_by_dish[c.kind] = int(sold_by_dish[c.kind]) + 1
			sold += 1
			var f := shop.fulfillment
			if c.addon and c.kind != f.addon_dish:
				sold_by_dish[f.addon_dish] = int(sold_by_dish[f.addon_dish]) + 1
				sold += 1
			events.emit("sale", {"dish": c.kind, "income": c.paid})
			s.order = -1
			s.steps = []
			return
		_:
			var station := shop.station(st.station)
			if station.block == "hand" and int(station.params.get("users", 0)) > 0: stations[st.station].user = -1
	s.step += 1


func _item_name(id: String) -> String:
	for item in shop.items:
		if item.id == id: return item.display_name
	return id


func order_price_single(c: Dictionary) -> int:
	var f := shop.fulfillment
	var total := 0.0
	if c.kind != f.addon_dish: total += raw_price(c.kind)
	if c.addon: total += raw_price(f.addon_dish)
	return int(round(total))


# =====================================================================
# 命令（§3.11）：界面只发这些；每个都返回不能做的原因，空 = 成功
# =====================================================================

func next_stage_cost() -> int:
	if stage_index >= shop.stages.size() - 1: return -1
	return shop.stages[stage_index + 1].cost


func unlock_error(id: String) -> String:
	var st := shop.station(id)
	if st == null: return "未知设备"
	if station_unlocked(id): return "设备已经解锁"
	var stage := shop.stage_of(id)
	if stage < 0: return "这台设备不能单独解锁"
	if stage > 0 and not is_open(): return "请先开张"
	var target := stage if stage > 0 else 0
	if stage > 0 and stage > stage_index + 1: return "请先解锁" + shop.stages[stage - 1].display_name
	if stage == 0 and is_open(): return "设备已经解锁"
	var cost := shop.stages[target].cost
	if gold < cost: return "金币不足，需要 %d" % cost
	return ""


func unlock(id: String) -> String:
	var error := unlock_error(id)
	if not error.is_empty(): return error
	var stage := shop.stage_of(id)
	gold -= shop.stages[stage].cost
	for key in shop.stages[stage].stations:
		unlocked[key] = true
		for st in shop.stations:
			if st.companion_of == key: unlocked[st.id] = true
		for rule in shop.station(key).stock:
			stations[key].stock = rule.start
	stage_index = maxi(stage_index, stage)
	if shop.fulfillment.handoff == "single":
		if id == shop.goals.opening_station: _next_customer = shop.fulfillment.first_customer_delay
	elif orders.is_empty():
		for unused in shop.fulfillment.opening_customers: _add_order()
	events.emit("unlocked", {"station": id, "stage": stage})
	return ""


func next_unlock() -> String:
	if not is_open(): return shop.goals.opening_station
	if stage_index + 1 < shop.stages.size(): return shop.stages[stage_index + 1].stations[0]
	return ""


func box_error(material: String) -> String:
	var st := shop.station(supply_id)
	var m := st.material(material) if st != null else null
	if m == null or not boxes.has(material): return "未知原料箱"
	if boxes[material]: return "原料箱已经解锁"
	if not station_unlocked(m.box_station): return "请先解锁" + shop.station(m.box_station).display_name
	if gold < m.box_cost: return "金币不足，需要 %d" % m.box_cost
	return ""


func unlock_box(material: String) -> String:
	var error := box_error(material)
	if not error.is_empty(): return error
	gold -= shop.station(supply_id).material(material).box_cost
	boxes[material] = true
	events.emit("box", {"material": material})
	return ""


func pending_box() -> String:
	var st := shop.station(supply_id)
	if st == null: return ""
	for m in st.materials:
		if boxes.has(m.id) and not boxes[m.id] and station_unlocked(m.box_station): return m.id
	return ""


## key：机器 id（主轨）、"机器/物料"、"staff/front"、"flyer"
func upgrade_cost(key: String) -> int:
	var t := track_of(key)
	if t == null: return -1
	var lv := level(key) if not key.begins_with("staff/") else int(levels[key]) + 1
	return t.cost(lv)


func upgrade_error(key: String) -> String:
	var t := track_of(key)
	if t == null or t.levels.is_empty(): return "无需升级"
	var parts := key.split("/")
	if not key.begins_with("staff/") and key != "flyer":
		if not station_unlocked(parts[0]) and shop.station(parts[0]).companion_of.is_empty(): return "请先解锁设备"
		if parts.size() > 1:
			if boxes.has(parts[1]) and not boxes[parts[1]]: return "请先解锁原料箱"
			if level(parts[0]) < t.requires_level: return "设备需升到 Lv%d" % t.requires_level
	if key == "flyer" and not is_open(): return "请先开张"
	var cost := upgrade_cost(key)
	if cost < 0: return "已满级"
	if gold < cost: return "金币不足，需要 %d" % cost
	return ""


func upgrade(key: String) -> String:
	var error := upgrade_error(key)
	if not error.is_empty(): return error
	gold -= upgrade_cost(key)
	levels[key] = int(levels[key]) + 1
	_refresh_key(key)
	events.emit("upgraded", {"key": key, "level": levels[key]})
	return ""


func seat_cost() -> int:
	var g := dine_group()
	if g == null: return -1
	var index := (seat_total() - g.start) / maxi(1, g.step)
	return g.costs[index] if index >= 0 and index < g.costs.size() else -1


func seat_error() -> String:
	if not is_open(): return "请先开张"
	if seat_cost() < 0: return "座位已满"
	if gold < seat_cost(): return "金币不足，需要 %d" % seat_cost()
	return ""


func buy_seat() -> String:
	var error := seat_error()
	if not error.is_empty(): return error
	gold -= seat_cost()
	var g := dine_group()
	seats[g.id] = seat_total() + g.step
	events.emit("seat", {})
	return ""


func flyer_customers() -> int:
	return int(mods.value("flyer_customers", 0.0))


func flyer_cooldown() -> float:
	return mods.value("flyer_cooldown", 0.0)


func flyer_error() -> String:
	if not is_open(): return "请先开张"
	if shop.fulfillment.handoff == "single":
		if flyer_ready_at - clock > 0.0: return "传单还要等 %d 秒才能再发" % ceili(flyer_ready_at - clock)
		return ""
	if flyer_wave > 0.0: return "传单正在起效，还有 %d 秒" % ceili(flyer_wave)
	if flyer_wait > 0.0: return "传单还要等 %d 秒才能再发" % ceili(flyer_wait)
	return ""


func send_flyers() -> String:
	var error := flyer_error()
	if not error.is_empty(): return error
	if shop.fulfillment.handoff == "single":
		flyer_left += flyer_customers()
		flyer_timer = 0.0
		flyer_ready_at = clock + flyer_cooldown()
	else:
		flyer_wave = shop.flyer.wave_seconds
		flyer_wait = flyer_cooldown()
		flyer_pending += flyer_customers()
		flyer_clock = 0.0
	events.emit("flyer", {})
	return ""


## 来一波客人（一次性效果 customer_wave）：按传单的入场方式进店。
func customer_wave(count: int) -> void:
	if shop.fulfillment.handoff == "single":
		flyer_left += count
	else:
		flyer_pending += count
		if flyer_wave <= 0.0: flyer_wave = shop.flyer.wave_seconds
	events.emit("wave", {"count": count})


## 执行一条效果（奇遇、培养、永久加成、回访）：一次性效果当场生效，持续类放进加成栈。
func apply_effect(source: String, source_id: String, effect: SpecEffect, seconds := -1.0) -> void:
	match effect.kind:
		"grant_gold":
			gold += effect.value
			events.emit("gold_granted", {"source": source_id, "amount": effect.value})
		"customer_wave": customer_wave(int(effect.value))
		"unlock_staff_kind":
			if not effect.target in hire_pool: hire_pool.append(effect.target)
			events.emit("staff_kind", {"kind": effect.target})
		"unlock_recipe", "shop_news":
			events.emit(effect.kind, {"target": effect.target})
		_:
			mods.add_effect(source, source_id, effect, seconds)
			events.emit("modifier_started", {"source": source, "id": source_id, "kind": effect.kind, "seconds": seconds})


# ---------- 瓶颈提示（§3.10）：只读统计，不影响经营 ----------

## 队伍连续满了多少秒；各批量锅忙碌程度、前厅 / 后厨员工空闲程度（平滑值，0–1）
var full_seconds := 0.0
var pot_busy: Dictionary = {}
var side_idle: Dictionary = {}
const HINT_SMOOTH := 0.1 / 20.0


func _track_bottleneck() -> void:
	var standing := queue_size() - (seated_orders() if shop.fulfillment.handoff != "single" else 0)
	full_seconds = full_seconds + STEP if is_open() and standing >= current_stage().queue_capacity else 0.0
	for id in pots:
		var pot: Dictionary = stations[id]
		var busy := 0.0
		if shop.fulfillment.handoff == "single": busy = 1.0 if pot.phase == "cook" else 0.0
		elif int(pot.processing) > 0 and pot.phase != "awaiting_take": busy = 1.0
		pot_busy[id] = lerpf(float(pot_busy.get(id, 0.0)), busy, HINT_SMOOTH)
	var idle := {}
	for worker in workers:
		var side := side_of(worker)
		if not idle.has(side): idle[side] = [0, 0]
		idle[side][1] += 1
		if worker.job.is_empty() and worker.phase in ["idle", "wait"] and int(worker.get("order", -1)) < 0: idle[side][0] += 1
	for side in idle: side_idle[side] = lerpf(float(side_idle.get(side, 0.0)), float(idle[side][0]) / idle[side][1], HINT_SMOOTH)


# ---------- 奇遇（§3.13） ----------

## 挂上一个奇遇：听它的触发广播。关卡表 / 城市的奇遇也从这里加（不必写在店铺数据里）。
func add_event(ev: SpecEvent) -> void:
	event_defs.append(ev)


## 所有广播都过这里，按奇遇的 trigger 分发（用方法而不是闭包监听，免得互相引用释放不掉）。
func _on_broadcast(message: Dictionary) -> void:
	for ev in event_defs:
		if ev.trigger == message.name: _roll_event(ev, message.data)


## 全店员工的幸运值合计（属性表 luck，经加成栈；没有这项属性 = 0）。
func total_luck() -> float:
	var total := 0.0
	for worker in workers:
		total += mods.value("luck", float(worker.stats.get("luck", 0.0)), side_of(worker), "", "", "staff:%d" % worker.id)
	return total


## 奇遇实际触发概率 = 基础概率 × 加成栈 event_chance × (1 + 幸运值合计)，最高 1。
func event_chance(ev: SpecEvent) -> float:
	return clampf(ev.chance * mods.value("event_chance", 1.0) * (1.0 + total_luck()), 0.0, 1.0)


func _event_conditions_met(ev: SpecEvent, data: Dictionary) -> bool:
	for key in ev.condition:
		var want: Variant = ev.condition[key]
		match key:
			"min_stage": if stage_index < int(want): return false
			"open": if is_open() != bool(want): return false
			_: if data.get(key) != want: return false
	return true


func _roll_event(ev: SpecEvent, data: Dictionary) -> void:
	if ev.once and ev.id in events_seen: return
	if clock < float(event_ready_at.get(ev.id, 0.0)): return
	if not _event_conditions_met(ev, data): return
	if event_rng.randf() >= event_chance(ev): return
	trigger_event(ev)


## 奇遇发生：没有选项就直接生效，有选项就排进卡片队列等玩家选。
func trigger_event(ev: SpecEvent) -> void:
	event_ready_at[ev.id] = clock + ev.cooldown
	if ev.once and not ev.id in events_seen: events_seen.append(ev.id)
	events.emit("event_started", {"id": ev.id, "speaker": ev.speaker})
	if ev.choices.is_empty(): _apply_event(ev)
	else: pending_events.append(ev)


## 玩家在卡片上选了第 choice 个选项。选项 {"label", "cost", "accept": true/false}；accept 为 false = 拒绝。
func answer_event(choice: int) -> String:
	if pending_events.is_empty(): return "现在没有卡片"
	var ev: SpecEvent = pending_events[0]
	if choice < 0 or choice >= ev.choices.size(): return "没有这一项"
	var option: Dictionary = ev.choices[choice]
	var cost := int(option.get("cost", 0))
	if gold < cost: return "金币不足，需要 %d" % cost
	pending_events.pop_front()
	gold -= cost
	if bool(option.get("accept", true)): _apply_event(ev)
	events.emit("event_answered", {"id": ev.id, "choice": choice})
	return ""


func _apply_event(ev: SpecEvent) -> void:
	for effect in ev.effects:
		apply_effect("event", ev.id, effect, -1.0 if effect.one_shot() or ev.duration <= 0.0 else ev.duration)


# ---------- 任务与完店 ----------

func task_rows() -> Array:
	var rows: Array = []
	for stage in shop.stages:
		for t in stage.tasks:
			var current := 0.0
			match t.condition:
				"sell_count": current = float(sold_by_dish.get(t.target, 0))
				"track_level": current = float(level(t.target))
				"flavor_open":
					var dish := shop.dish(t.target)
					current = 1.0 if dish != null and flavor_open(dish) else 0.0
				"revenue": current = revenue
			rows.append({"id": t.id, "name": t.display_name, "current": current, "target": t.amount, "complete": current >= t.amount})
	return rows


func shop_complete() -> bool:
	for rule in shop.goals.complete_when:
		match rule:
			"all_stages":
				if stage_index < shop.stages.size() - 1 or not is_open(): return false
			"all_flavors":
				for dish in shop.dishes:
					if not dish.flavor_station.is_empty() and shop.station(dish.flavor_station).block == "topping" and not flavor_open(dish): return false
			"all_tasks":
				for row in task_rows():
					if not row.complete: return false
	return true


func total_sold() -> int:
	return sold
