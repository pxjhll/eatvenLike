class_name ShopRules
extends RefCounted
const LegacyQueries := preload("res://game/rules/legacy/content_queries.gd")
const FulfillmentPlan := preload("res://game/rules/fulfillment_plan.gd")
const Numbers := preload("res://game/rules/rule_numbers.gd")
const Sampling := preload("res://game/rules/rule_sampling.gd")
const Upgrades := preload("res://game/rules/upgrade_modifiers.gd")
const QueryContext := preload("res://game/rules/rule_query_context.gd")
const CommandResult := preload("res://game/rules/rule_command_result.gd")
const CommandText := preload("res://content/ui/rule_command_text.gd")
const StateValidator := preload("res://game/rules/shop_state_validator.gd")
const Inventory := preload("res://game/rules/rule_inventory.gd")
const InventoryAudit := preload("res://game/rules/inventory_audit.gd")
const WorkerState := preload("res://game/rules/worker_state.gd")
const Sales := preload("res://game/rules/rule_sales.gd")
const OrderState := preload("res://game/rules/rule_orders.gd")
const Movement := preload("res://game/rules/rule_movement.gd")
var movement: Dictionary = {}
var runtime: RefCounted
var runtime_error := ""
var _runtime_template: Resource
## 通用店铺规则（规格 §3）。所有店跑这一份代码，店铺之间只有 SpecShop 数据不同。
## 这里不出现任何店铺、机器、菜品的名字：机器按工序积木类型（block）认，菜按工序链认。
## 两种交接方式（§3.2 handoff）：
##   handoff = 后厨跟单员把一单从锅一路搬到出餐口，前厅员工取杯递给顾客（每一段是一次“搬运”）
##   single  = 一名员工从收钱跟到递餐，每一步走到机器前做完（煎饼摊）
## 纯逻辑，不依赖场景；界面只读快照、只发命令（§3.11）。

const STEP := 0.1
const SUPPLY := "supply"
## 规则层自己的两个交接位置：出餐口的堂食区（货架）和外带区（外带架）。店铺数据里的传送带用这两个名字指它们，
## 所以机器 id 不能叫这两个名字（test_shop_specs 查）
const SHELF := Inventory.SHELF
const RACK := Inventory.RACK
const PLACES := [SHELF, RACK]
const COUNTER := "counter"
const UNLIMITED := 999

var shop: SpecShop
var nav: RuleNav
var mods := RuleModifiers.new()
var events := RuleEvents.new()
var rng := RandomNumberGenerator.new()

# ---------- 店铺状态 ----------
var clock := 0.0
var _sales := Sales.new()
var _orders_state := OrderState.new()
var gold: float:
	get: return _sales.gold
	set(value): _sales.gold = value
var revenue: float:
	get: return _sales.revenue
	set(value): _sales.revenue = value
var sold: int:
	get: return _sales.sold
	set(value): _sales.sold = value
var sold_by_dish: Dictionary:
	get: return _sales.sold_by_dish
	set(value): _sales.sold_by_dish = value
var lost: int:
	get: return int(runtime.service.orders.active_snapshot().lost) if runtime!=null and runtime.service!=null else _orders_state.lost
	set(value): _orders_state.lost = value
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
var _inventory := Inventory.new()
var stations: Dictionary:
	get: return _inventory.stations
	set(value): _inventory.stations = value
var shelf_stock: Dictionary:
	get: return _inventory.shelf_stock
	set(value): _inventory.shelf_stock = value
var shelf_count: int:
	get: return _inventory.shelf_count
	set(value): _inventory.shelf_count = value
var shelf_reserved_in: int:
	get: return _inventory.shelf_reserved_in
	set(value): _inventory.shelf_reserved_in = value
var shelf_reserved_out: int:
	get: return _inventory.shelf_reserved_out
	set(value): _inventory.shelf_reserved_out = value
var generated: int:
	get: return _inventory.generated
	set(value): _inventory.generated = value
var orders: Array:
	get: return _orders_state.orders
	set(value): _orders_state.orders = value
var diners: Array:
	get: return _orders_state.diners
	set(value): _orders_state.diners = value
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
var order_ramp: Dictionary:
	get: return _orders_state.order_ramp
	set(value): _orders_state.order_ramp = value
var flyer_wave := 0.0
var flyer_wait := 0.0
var flyer_clock := 0.0
var flyer_pending := 0
var flyer_ready_at := 0.0
var flyer_left := 0
var flyer_timer := 0.0
var seats: Dictionary = {}
## 交接方式 serve 的全部运行状态（顾客、订单明细、每份餐、实物、员工手上的活），见 serve_flow.gd
var serve: Dictionary = {}
var _accumulator := 0.0
var _order_clock: float:
	get: return _orders_state.order_clock
	set(value): _orders_state.order_clock = value
var _next_order: int:
	get: return _orders_state.next_order
	set(value): _orders_state.next_order = value
var _next_staff := 1
var _sale_carry: float:
	get: return _sales.sale_carry
	set(value): _sales.sale_carry = value
var _next_customer: float:
	get: return _orders_state.next_customer
	set(value): _orders_state.next_customer = value
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


# ---------- 存档（§3.12）：整店运行状态按名字存，读回来逐帧接着跑 ----------

## 要存的状态。新加的运行时变量写进这里（存读档测试会把没存全的情况查出来）。
const STATE_KEYS := ["clock", "gold", "revenue", "sold", "sold_by_dish", "lost", "stage_index", "unlocked", "levels", "boxes",
	"completed_at", "paused", "tune", "stations", "shelf_stock", "shelf_count", "shelf_reserved_in", "shelf_reserved_out",
	"generated", "orders", "diners", "roster", "hire_pool", "event_ready_at", "events_seen", "belts", "belt_clock",
	"belt_items", "order_ramp", "flyer_wave", "flyer_wait", "flyer_clock", "flyer_pending", "flyer_ready_at", "flyer_left",
	"flyer_timer", "seats", "_accumulator", "_order_clock", "_next_order", "_next_staff", "_sale_carry", "_next_customer",
	"_courier", "customers", "queue", "_next_customer_id", "full_seconds", "pot_busy", "side_idle", "serve"]


## 这些状态按店铺数据里的 id（机器、原料、菜、座位组）存：读档时只认数据里现在有的 id，缺的补开局默认值（§3.12）
const BY_DATA_ID := ["sold_by_dish", "unlocked", "levels", "boxes", "stations", "shelf_stock", "order_ramp", "seats"]


func to_dict() -> Dictionary:
	if runtime!=null: return load("res://game/rules/template/session_state.gd").save(self)
	return _legacy_dict()

func _legacy_dict() -> Dictionary:
	var out := {"shop": shop.id}
	for key in STATE_KEYS:
		var v: Variant = get(key)
		out[key] = _plain(v)
	# 上岗员工就是名册里的同一份：按 id 存，读回来指回名册
	out.workers = workers.map(func(w: Dictionary) -> int: return w.id)
	out.rng = [rng.seed, rng.state]
	out.event_rng = [event_rng.seed, event_rng.state]
	out.mods = _plain(mods.entries)
	out.log = _plain(events.log)
	# 奇遇按 id 存：店铺数据里的奇遇，加上等玩家选的卡片
	out.pending_events = pending_events.map(func(ev: SpecEvent) -> String: return ev.id)
	if movement_enabled(): out.movement = _plain(movement)
	return out


## 深拷贝成只含普通数组 / 字典的值（带类型的数组存档里不收）
static func _plain(v: Variant) -> Variant:
	if v is Array:
		var out: Array = []
		for x in v: out.append(_plain(x))
		return out
	if v is Dictionary:
		var out := {}
		for k in v: out[k] = _plain(v[k])
		return out
	return v


## Validate and fully restore off to the side before replacing any live object.
func load_dict(data: Dictionary, refresh_content: bool = false) -> String:
	if data.has("version") or data.has("runtime"):
		return load("res://game/rules/template/session_state.gd").restore(self,data,refresh_content)
	if _runtime_template!=null:
		return load("res://game/rules/template/legacy_adoption.gd").new().adopt(self,data,refresh_content)
	return _load_legacy_dict(data,refresh_content)

func _load_legacy_dict(data: Dictionary, refresh_content: bool = false) -> String:
	return load("res://game/rules/legacy/state_decoder.gd").restore(self,data,refresh_content)

func _restore_validated(data: Dictionary) -> void:
	for key in STATE_KEYS:
		var v: Variant = data[key]
		var current: Variant = get(key)
		if current is Array and current.is_typed():
			current.assign(v)
		elif key in BY_DATA_ID:
			# 按店铺数据的 id 存的状态：数据里新加的机器 / 菜用开局默认值，数据里已经删掉的丢掉
			var merged: Dictionary = current
			for id in v:
				if merged.has(id): merged[id] = v[id].duplicate(true) if v[id] is Array or v[id] is Dictionary else v[id]
		else:
			set(key, v.duplicate(true) if v is Array or v is Dictionary else v)
	_migrate_retired_staff()
	nav.set_open(unlocked)
	workers = []
	for id in data.get("workers", []):
		for w in roster:
			if w.id == id: workers.append(w)
	rng.seed = int(data.rng[0])
	rng.state = int(data.rng[1])
	event_rng.seed = int(data.event_rng[0])
	event_rng.state = int(data.event_rng[1])
	mods.entries = data.mods.duplicate(true)
	# Older single-order saves did not capture the active pot's duration.
	for id in pots:
		var pot: Dictionary = stations[id]
		if pot.phase == "cook" and float(pot.get("duration", 0.0)) <= 0.0:
			pot.duration = maxf(float(pot.remaining), pot_seconds(id))
	events.log = data.log.duplicate(true)
	events.clock = clock
	pending_events = []
	for id in data.pending_events:
		for ev in event_defs:
			if ev.id == id: pending_events.append(ev)


## Keep worker IDs, assignments and all business state; only replace retired identities.
func _migrate_retired_staff() -> void:
	var replacements := shop.staff.retired_kinds
	if replacements.is_empty(): return
	for worker in roster:
		if not replacements.has(worker.kind): continue
		worker.kind = replacements[worker.kind]
		var kind := _kind(worker.kind)
		worker.name = kind.display_name
		worker.stats = kind.stats.duplicate(true)
	var available: Array[String] = []
	for id in hire_pool:
		var replacement: String = replacements.get(id, id)
		if replacement not in available: available.append(replacement)
	hire_pool = available


## Refresh only definition caches. Jobs, timers, stock and event effects stay recorded.
func _refresh_content_values() -> void:
	var previous := mods.entries.duplicate(true)
	mods.entries = []
	_refresh_all_modifiers()
	var fresh := mods.entries
	var groups := {}
	for entry in fresh:
		if not groups.has(entry.source_id): groups[entry.source_id] = []
		groups[entry.source_id].append(entry)
	var old_sources := {}
	for entry in previous:
		if entry.source == "upgrade": old_sources[entry.source_id] = true
	var rebuilt: Array = []
	# A formerly empty source has no old position: put it before all retained events.
	for entry in fresh:
		if not old_sources.has(entry.source_id): rebuilt.append(entry)
	var inserted := {}
	for entry in previous:
		if entry.source != "upgrade":
			rebuilt.append(entry)
		elif not inserted.has(entry.source_id):
			inserted[entry.source_id] = true
			rebuilt.append_array(groups.get(entry.source_id, []))
	mods.entries = rebuilt
	for worker in roster: worker.stats = _kind(worker.kind).stats.duplicate(true)
	# Newly available default kinds must also appear in older saved recruitment pools.
	for kind in shop.staff.hire_pool:
		if kind not in hire_pool: hire_pool.append(kind)
	var defaults := ShopRules.new(shop)
	for id in stations:
		stations[id].capacity = defaults.stations[id].capacity


func _derive_roles() -> void:
	var plan: Dictionary = FulfillmentPlan.derive(shop)
	counter_id = plan.counter_id
	supply_id = plan.supply_id
	pickup_id = plan.pickup_id
	pots.assign(plan.pots)
	autos.assign(plan.autos)
	seatables.assign(plan.seatables)
	dish_ids.assign(plan.dish_ids)
	front_dishes.assign(plan.front_dishes)
	kitchen_dishes.assign(plan.kitchen_dishes)
	chains = plan.chains
	station_output = plan.station_output
	station_input = plan.station_input


func reset(seed := -1) -> void:
	runtime = null
	runtime_error = ""
	movement = {}
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
	events.clear_history()
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
	nav.set_open(unlocked)
	for st in shop.stations:
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
	serve = {"guests":[],"orders":[],"units":[],"goods":[],"jobs":{},"next_id":1,"served":0,"orders_done":0,"items_sold":0}
	for index in shop.staff.starting.size():
		var worker := _new_worker(shop.staff.starting[index])
		worker.deployed = true
		worker.source = "初始"
		roster.append(worker)
		workers.append(worker)
		# 每位开局员工可以有自己的岗位（starting_posts，空 = 流动），没写就都用 starting_post
		var post: String = shop.staff.starting_posts[index] if index < shop.staff.starting_posts.size() else shop.staff.starting_post
		if not post.is_empty(): _seat_at(worker, post)
	var template: Resource = shop.runtime_template if shop.runtime_template!=null else _runtime_template
	if movement_enabled(): movement = {"version":1,"customers":{}}
	if template!=null: runtime_error = enable_runtime(template)

func enable_runtime(template: Resource, open_service := true) -> String:
	var candidate: RefCounted = load("res://game/rules/template/runtime.gd").new(self,template)
	if not candidate.last_error.is_empty(): return candidate.last_error
	runtime = candidate
	runtime.runner.release_owner()
	_runtime_template = template
	return runtime.set_service_open(is_open()) if open_service else ""


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
	Upgrades.refresh_track(mods, st, t, key, level, default_target)


func track_of(key: String) -> SpecUpgradeTrack:
	return Upgrades.track_of(shop, key)


func tuned(key: String) -> float:
	return Numbers.tuned(tune, key)


# ---------- 查询 ----------

func station_unlocked(id: String) -> bool:
	return unlocked.get(id, false)


func level(id: String) -> int:
	return int(levels.get(id, 1))


func speed(id: String) -> float:
	return Numbers.speed(mods, id)


func duration_mult(id: String) -> float:
	return Numbers.duration_mult(mods, id)


func pot_batch(id: String) -> int:
	return Numbers.pot_batch(shop, mods, id)


func process_slots(id: String) -> int:
	return Numbers.process_slots(shop, mods, id)


func stars(id: String) -> int:
	var t := track_of(id)
	return t.stars(level(id)) if t != null else 0


## 一道菜现在的售价（保留 1 位小数前的原值）：每部分价格 × 作用在这部分上的所有加成。
func raw_price(dish_id: String) -> float:
	return Numbers.raw_price(shop, mods, tune, dish_id)


func dish_price(dish_id: String) -> float:
	return Numbers.dish_price(shop, mods, tune, dish_id)


## Calculated dish amount and settlement policy. Solo payment excludes options/addons.
func dish_quote(dish_id: String) -> Dictionary:
	return Numbers.dish_quote(shop, mods, tune, dish_id)


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
	if runtime!=null: return runtime.service.menu_weights().has(dish_id)
	return LegacyQueries.dish_open(self,dish_id,needs_kitchen_hand)

func menu() -> Array[String]:
	var out: Array[String] = []
	for id in dish_ids:
		if dish_open(id, false): out.append(id)
	return out


func is_open() -> bool:
	return station_unlocked(shop.goals.opening_station)


## 交接方式 serve：前厅接单分座、后厨按配方合流、送餐到座（§10）
func _serving() -> bool:
	return LegacyQueries.serving(self)

## 顾客先排队、再被员工接走的店（一人跟单、送桌）：客流按“下一位多久到”计时，传单逐个放人
func _queued_arrivals() -> bool:
	return LegacyQueries.queued(self)

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
	var bus := events
	bus.begin_batch()
	_tick_runtime()
	bus.end_batch()

func _tick_runtime() -> void:
	if runtime!=null:
		var advancing := runtime
		for entry in mods.tick(STEP): events.emit("modifier_ended",entry)
		runtime_error = runtime.set_service_open(is_open())
		if not runtime_error.is_empty(): return
		runtime_error = runtime.step(STEP)
		if runtime!=advancing: return
		clock = runtime._clock
		events.clock = clock
		if not runtime_error.is_empty(): return
		_track_bottleneck()
		if int(round(clock*10.0))%10==0: events.emit("tick_second",{"time":clock})
		if int(round(clock*10.0))%600==0: events.emit("tick_minute",{"time":clock})
		if completed_at<0.0 and shop_complete():
			completed_at = clock
			events.emit("completed",{})
		return
	runtime_error = "ShopRules requires an explicit shared runtime template"

# =====================================================================
# 交接方式 handoff：后厨跟单 + 前厅递杯（奶茶店）
# =====================================================================

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
	return Numbers.flow_interval(current_stage().customer_interval, flow_multiplier(), tune)


## 现在平均几秒来一位客人（一人跟单的店不算机器等级带来的客流）
func customer_interval() -> float:
	if runtime!=null and runtime.service!=null:
		var policy: Dictionary = runtime._definition.service
		var interval: float = policy.selection.stages[stage_index].interval if policy.has("selection") else policy.arrivals.interval
		return Numbers.flow_interval(interval,runtime.service.flow_multiplier(),tune)
	if shop.fulfillment.handoff != "single": return _order_interval()
	return Numbers.flow_interval(current_stage().customer_interval, mods.value("flow", 1.0), tune)


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
			if dish_open(d.id): open.append(d.id)
		if open.is_empty() and dish_open(stage.flavor_fallback): result[stage.flavor_fallback] = float(result.get(stage.flavor_fallback, 0.0)) + share
		for id in open: result[id] = share / open.size()
	return result


func queue_capacity() -> int:
	if runtime!=null: return runtime.service.queue_capacity()
	if shop.fulfillment.handoff == "single": return current_stage().queue_capacity + wait_seats()
	if _serving(): return current_stage().queue_capacity
	return current_stage().queue_capacity + seated_orders()


## 排队人数（站位 + 等位）
func queue_size() -> int:
	return runtime.service.orders.queue().size() if runtime!=null else 0

## 开张以来进店的人数
func arrivals() -> int:
	if runtime!=null: return int(runtime.service.orders.active_snapshot().next_guest)-1
	return (_next_customer_id if _queued_arrivals() else _next_order) - 1


func _pick_dish(weights: Dictionary) -> String:
	return Sampling.choose(weights, rng)


# ---------- 座位 ----------

func dine_group() -> SpecSeatGroup:
	for g in shop.seat_groups:
		if g.purpose == "dine": return g
	return null


func seat_total() -> int:
	var g := dine_group()
	return int(seats.get(g.id, 0)) if g != null else 0


## 能花钱买的那组座位（写了 costs 的第一组）：奶茶店是堂食座，煎饼摊是等位坐垫
func buy_group() -> SpecSeatGroup:
	for g in shop.seat_groups:
		if not g.costs.is_empty(): return g
	return null


## 一人跟单店的等位座：有能买的等位组就按买了几个算，否则阶段直接给
func wait_seats() -> int:
	var g := buy_group()
	if g != null and g.purpose == "wait": return int(seats.get(g.id, 0))
	return current_stage().wait_seats


## 这组座位现在最多摆几个：等位组受当前阶段的 wait_seats 限制（下一阶段开放更多），堂食组不限
func seat_cap(g: SpecSeatGroup) -> int:
	var full := g.start + (_sum(g.steps) if not g.steps.is_empty() else g.step * g.costs.size())
	if g.purpose == "wait": return mini(full, current_stage().wait_seats)
	return full


func _seat_step(g: SpecSeatGroup) -> int:
	if g.steps.is_empty(): return maxi(1, g.step)
	var index := _seat_buys(g)
	return g.steps[index] if index < g.steps.size() else 0


func _seat_buys(g: SpecSeatGroup) -> int:
	var have := int(seats.get(g.id, 0)) - g.start
	if g.steps.is_empty(): return have / maxi(1, g.step)
	var bought := 0
	for n in g.steps:
		if have < n: break
		have -= n
		bought += 1
	return bought


static func _sum(values: Array) -> int:
	var total := 0
	for v in values: total += int(v)
	return total


func seat_seconds() -> float:
	var s := current_stage().seat_seconds
	var g := dine_group()
	return (s if s > 0 else (g.seconds if g != null else 0.0)) * tuned("seat")


func seated_orders() -> int:
	return runtime.service.orders.active_snapshot().guests.filter(func(guest: Dictionary) -> bool: return guest.queued and not guest.seat.is_empty()).size() if runtime!=null else 0


func free_seats() -> int:
	return maxi(0,seat_total()-seats_used())


func _order_by_id(id: int) -> Dictionary:
	return _orders_state.handoff_order(id)


func order_mood(order: Dictionary) -> int:
	var f := shop.fulfillment
	if f.mood_seconds.size() < 2: return 0
	var patience := mods.value("patience", 1.0)
	var seat: Variant = order.get("seat",-1)
	var seated: bool = not seat.is_empty() if seat is String else int(seat)>=0
	var wait: float = order.wait * (f.seated_patience if seated else 1.0) / patience
	return 2 if wait >= f.mood_seconds[1] else (1 if wait >= f.mood_seconds[0] else 0)


# ---------- 通用查询（记录器、提示、界面都问这几个，不翻各交接方式的内部字段） ----------

## 还在等餐的客人：一人跟单的店是排着队的客人，跟单+递杯的店是订单
func waiting_customers() -> Array:
	return runtime.service.orders.active_snapshot().guests.filter(func(guest: Dictionary) -> bool: return guest.state in ["queue","waiting"]) if runtime!=null else []

## 等急了（心情最差）的客人有几个
func angry_count() -> int:
	var count := 0
	for c in waiting_customers():
		if order_mood(c) >= 2: count += 1
	return count


## 这个员工现在手上没活（没跟单、没杂活、没在搬东西）
func worker_idle(worker: Dictionary) -> bool:
	if runtime!=null: return runtime.runner.idle(worker.id)
	return worker.job.is_empty() and worker.phase in ["idle", "wait"] and int(worker.get("order", -1)) < 0


## 这台机器正在自己做东西（锅在煮、自动机器在转；做好等人拿不算）
func machine_working(id: String) -> bool:
	if runtime!=null: return bool(runtime.runner.machines.status(id).get("working",false))
	if not station_unlocked(id): return false
	var station: Dictionary = stations[id]
	if _queued_arrivals(): return station.phase == "cook"
	return int(station.processing) > 0 and station.phase != "awaiting_take"


## 能买的那组座位现在有几个能坐：堂食组 = 堂食座，等位组 = 等位坐垫
func seat_count() -> int:
	var g := buy_group()
	if g == null: return 0
	return wait_seats() if g.purpose == "wait" else int(seats.get(g.id, 0))


## 那组座位现在坐了几个人：堂食 = 在吃的 + 坐着等的，等位 = 点完单在坐垫上等的
func seats_used() -> int:
	return load("res://game/rules/template/scene_frame.gd").seats_used(runtime,buy_group()) if runtime!=null else 0

# ---------- 员工 ----------

func _kind(kind_id: String) -> SpecStaffKind:
	for k in shop.staff.kinds:
		if k.id == kind_id: return k
	return shop.staff.kinds[0]


func _new_worker(kind_id: String, id := -1) -> Dictionary:
	kind_id = shop.staff.retired_kinds.get(kind_id, kind_id)
	var kind := _kind(kind_id)
	var worker_id := id if id > 0 else _next_staff
	_next_staff = maxi(_next_staff, worker_id + 1)
	return WorkerState.create(worker_id, kind_id, kind.display_name, kind.stats,
		nav.point(shop.layout.spawn_point))


func _seat_at(worker: Dictionary, post: String) -> void:
	WorkerState.place(worker, post, nav.post(post))


func side_of(worker: Dictionary) -> String:
	return Numbers.side_of(shop, worker)


func stat(worker: Dictionary, name: String) -> float:
	return Numbers.stat(shop, mods, tune, worker, name)


func walk_speed(worker: Dictionary) -> float:
	return Numbers.walk_speed(shop, mods, tune, worker) * (shop.layout.motion_units if movement_enabled() else 1.0)


func movement_enabled() -> bool:
	return shop.layout != null and shop.layout.motion_version == 1


func begin_move(worker: Dictionary, goal: Vector2, phase: String) -> void:
	var side := side_of(worker)
	var profile := side if shop.layout.actor_areas.has(side) else "staff"
	Movement.request(worker,nav,goal,profile)
	worker.phase = phase

func advance_move(worker: Dictionary, dt: float) -> bool:
	if not movement_enabled(): return WorkerState.advance_walk(worker,walk_speed(worker)*dt)
	if not worker.has("motion"):
		_rebuild_move(worker)
	return Movement.tick(worker,nav,walk_speed(worker)*dt)


func _rebuild_move(worker: Dictionary) -> void:
	var goal: Vector2 = worker.path[-1] if not worker.path.is_empty() else nav.point(worker.target)
	begin_move(worker,goal,worker.phase)

func skill(worker: Dictionary) -> float:
	return Numbers.skill(shop, mods, tune, worker)


func carry(worker: Dictionary) -> int:
	return Numbers.carry(shop, mods, tune, worker)


func effective_worker_stats(worker: Dictionary) -> Dictionary:
	return Numbers.effective_worker_stats(shop, mods, tune, worker)


## Normalize bars against this worker's region at full cultivation, with current tuning/buffs.
func worker_stat_limits(worker: Dictionary) -> Dictionary:
	var current := effective_worker_stats(worker)
	var key := "staff/" + side_of(worker)
	var track := track_of(key)
	if track == null: return current
	var limit: Dictionary = query_context({key: track.levels.size()}).effective_worker_stats(worker)
	for stat_name in current: limit[stat_name] = maxf(float(current[stat_name]), float(limit[stat_name]))
	return limit


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
		var n := _hires()
		return rules.hire_costs[n] if n < rules.hire_costs.size() else -1
	return rules.hire_cost_base + maxi(0, _hires()) * rules.hire_cost_step


## 已经招了几位（名册里减去开局员工）：第 n 次招人按 hire_costs[n] 收钱
func _hires() -> int:
	return roster.size() - shop.staff.starting.size()


func next_hire_kind() -> String:
	var rules := shop.staff
	if rules.hire_rule == "cycle":
		return rules.hire_order[_hires() % rules.hire_order.size()]
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
	return CommandText.format(command_status("hire", {}), shop)


## 招人：分区的店招进名册（再派岗），不分区的店直接上岗。
func hire() -> String:
	return CommandText.format(execute_command("hire", {}), shop)


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
	return CommandText.format(_role_room_status(post, exclude_id), shop)


func deploy_worker(id: int, post := "") -> String:
	return CommandText.format(execute_command("deploy_worker", {"id": id, "post": post}), shop)


## 拖人（§3.5）：post 空 = 去 point 那块空地流动；post = 坐班机器或柜台。只检查、不改状态。
func placement_error(id: int, post: String, point := Vector2.INF) -> String:
	return CommandText.format(command_status("place_worker", {"id": id, "post": post, "point": point}), shop)


## 派到某处：没上岗的先上岗，再换到这个岗位 / 这块空地。
func place_worker(id: int, post: String, point := Vector2.INF) -> String:
	return CommandText.format(execute_command("place_worker", {"id": id, "post": post, "point": point}), shop)


## 收回名册：手上的活放下，东西留在原处。
func recall_worker(id: int) -> String:
	return CommandText.format(execute_command("recall_worker", {"id": id}), shop)


## 后厨有人、但都坐在机器上：没人在机器之间搬东西。
func no_kitchen_carrier() -> bool:
	if shop.staff.zones.is_empty(): return false
	var kitchen: Array = workers.filter(func(w: Dictionary) -> bool: return w.post != counter_id)
	return not kitchen.is_empty() and kitchen.all(func(w: Dictionary) -> bool: return not String(w.post).is_empty())


## 放下手上的活：预留全部释放，拿在手上的东西放回原处，跟的单留给别人接（§3.6 预留与回收）。
func _cancel_job(worker: Dictionary) -> void:
	if runtime!=null: runtime_error = runtime.cancel_worker(worker.id)

## Evaluate a next-level snapshot without borrowing any live mutable data.
func preview(key: String, evaluator: Callable) -> Variant:
	var overrides := {}
	if track_of(key) != null: overrides[key] = int(levels[key]) + 1
	return evaluator.call(query_context(overrides))


func query_context(level_overrides: Dictionary = {}) -> RefCounted:
	return QueryContext.new(shop, levels, mods, tune, level_overrides)


func _refresh_key(key: String) -> void:
	Upgrades.refresh_key(shop, levels, mods, key)


# ---------- 机器 ----------

## Worker omitted means operation skill 1. Fixed ignores machine upgrades only.
## A pot's manual pickup never inherits its automatic cooking upgrades.
func manual_operation_seconds(id: String, base_seconds: float, worker: Dictionary = {}, fixed := false) -> float:
	return Numbers.manual_operation_seconds(shop, mods, tune, id, base_seconds, worker, fixed)


## Baseline operation, not a complete order; automatic machines retain batch semantics.
func station_timing(id: String) -> Dictionary:
	return Numbers.station_timing(shop, mods, tune, id)


func pot_seconds(id: String) -> float:
	return Numbers.pot_seconds(shop, mods, tune, id)


func machine_seconds(id: String) -> float:
	return Numbers.machine_seconds(shop, mods, tune, id)


func _stock(station: Dictionary) -> int:
	return Inventory.stock(station)


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


func _is_operation(job: Dictionary) -> bool:
	return Inventory.is_operation(job)


func _source_point(job: Dictionary) -> Vector2:
	if job.get("pour", "") != "": return nav.point(job.pour)
	if job.src == RACK: return nav.point(SHELF)
	if _is_operation(job): return nav.post(job.src)
	return nav.point(job.src)


func _destination_point(job: Dictionary) -> Vector2:
	if _is_operation(job): return _source_point(job)
	if job.dst == RACK: return nav.point(SHELF)
	return nav.point(job.dst)


func inventory_diagnostics() -> Array:
	return runtime.runner.inventory.audit() if runtime!=null else []

# ---------- 调度（§3.6） ----------

## 外带：从出餐口取杯送去加工（封口），加工好的送到外带架。
## 一站上没人跟着的现成物品（被收回的单留下的）。
## 从工序链上最靠后的现成物品那一步接着做（§3.6）。
# ---------- 连接（传送带） ----------

func _connection(id: String) -> SpecConnection:
	for c in shop.connections:
		if c.id == id: return c
	return null


## 能买的连接（界面画虚线框用）：{id, name, from, to, cost, owned, error, available}
func connection_rows() -> Array:
	var rows: Array = []
	for c in shop.connections:
		if not c.enabled: continue
		var status := command_status("buy_connection", {"id": c.id})
		rows.append({"id": c.id, "name": c.display_name, "from": c.from, "to": c.to, "cost": c.cost, "owned": belts.has(c.id),
			"status": status, "error": CommandText.format(status, shop), "available": is_open() and stage_index >= c.stage})
	return rows


func connection_error(id: String) -> String:
	return CommandText.format(command_status("buy_connection", {"id": id}), shop)


func buy_connection(id: String) -> String:
	return CommandText.format(execute_command("buy_connection", {"id": id}), shop)


func _belted(source: String, destination: String) -> bool:
	for id in belts:
		var c := _connection(id)
		if c.from == source and c.to == destination: return true
	return false


# =====================================================================
# 交接方式 single：一人从收钱跟到递餐（煎饼摊）
# =====================================================================

var customers: Array:
	get: return _orders_state.customers
	set(value): _orders_state.customers = value
var queue: Array:
	get: return _orders_state.queue
	set(value): _orders_state.queue = value
var _next_customer_id: int:
	get: return _orders_state.next_customer_id
	set(value): _orders_state.next_customer_id = value


## 订单附加选项（§3.2）：机器开了的选项按比例抽；没有开着的选项就不动随机数（不改变别的店的节奏）
func _roll_options() -> Array:
	var out: Array = []
	for option in shop.order_options:
		if not station_unlocked(option.station): continue
		if rng.randf() < option.share: out.append(option.id)
	return out


func customer(id: int) -> Dictionary:
	return _orders_state.single_customer(id)


func _order_steps(c: Dictionary) -> Array:
	return FulfillmentPlan.single_steps(shop, counter_id, c)


## 沿寻路路线走（格子寻路的店绕开桌子，直线走的店路线就是起点到终点）
func _item_name(id: String) -> String:
	for item in shop.items:
		if item.id == id: return item.display_name
	return id


func order_price_single(c: Dictionary) -> int:
	return Numbers.order_price_single(shop, mods, tune, c)


# =====================================================================
# 命令（§3.11）：界面只发这些；每个都返回不能做的原因，空 = 成功
# =====================================================================

func next_stage_cost() -> int:
	if stage_index >= shop.stages.size() - 1: return -1
	return shop.stages[stage_index + 1].cost


func unlock_error(id: String) -> String:
	return CommandText.format(command_status("unlock", {"id": id}), shop)


func unlock(id: String) -> String:
	return CommandText.format(execute_command("unlock", {"id": id}), shop)


func next_unlock() -> String:
	if not is_open(): return shop.goals.opening_station
	if stage_index + 1 < shop.stages.size(): return shop.sold_at(stage_index + 1)
	return ""


func box_error(material: String) -> String:
	return CommandText.format(command_status("unlock_box", {"material": material}), shop)


func unlock_box(material: String) -> String:
	return CommandText.format(execute_command("unlock_box", {"material": material}), shop)


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
	return CommandText.format(command_status("upgrade", {"key": key}), shop)


func upgrade(key: String) -> String:
	return CommandText.format(execute_command("upgrade", {"key": key}), shop)


## 下一次买座位的价格；-1 = 全部买完
func seat_cost() -> int:
	var g := buy_group()
	if g == null: return -1
	var index := _seat_buys(g)
	return g.costs[index] if index >= 0 and index < g.costs.size() else -1


func seat_error() -> String:
	return CommandText.format(command_status("buy_seat", {}), shop)


func buy_seat() -> String:
	return CommandText.format(execute_command("buy_seat", {}), shop)


func flyer_customers() -> int:
	return Numbers.flyer_customers(mods)


func flyer_cooldown() -> float:
	return Numbers.flyer_cooldown(mods)


func flyer_error() -> String:
	return CommandText.format(command_status("send_flyers", {}), shop)


func send_flyers() -> String:
	return CommandText.format(execute_command("send_flyers", {}), shop)


## 来一波客人（一次性效果 customer_wave）：按传单的入场方式进店。
func customer_wave(count: int) -> void:
	if runtime!=null and count>0: runtime_error = runtime.enqueue_wave(count)

## 执行一条效果（奇遇、培养、永久加成、回访）：一次性效果当场生效，持续类放进加成栈。
func apply_effect(source: String, source_id: String, effect: SpecEffect, seconds := -1.0) -> void:
	match effect.kind:
		"grant_gold":
			gold += effect.value
			events.emit("gold_granted", {"source": source_id, "amount": effect.value})
		"customer_wave": customer_wave(int(effect.value))
		"unlock_staff_kind":
			if shop.staff.retired_kinds.has(effect.target): return
			if not shop.staff.kinds.any(func(kind: SpecStaffKind) -> bool: return kind.id == effect.target): return
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
	var standing := queue_size() if runtime!=null else queue_size() - (seated_orders() if not _queued_arrivals() else 0)
	full_seconds = full_seconds + STEP if is_open() and standing >= (queue_capacity() if runtime!=null else current_stage().queue_capacity) else 0.0
	for id in pots:
		var pot: Dictionary = stations[id]
		var busy := 0.0
		if runtime!=null: busy = 1.0 if machine_working(id) else 0.0
		elif _queued_arrivals(): busy = 1.0 if pot.phase == "cook" else 0.0
		elif int(pot.processing) > 0 and pot.phase != "awaiting_take": busy = 1.0
		pot_busy[id] = lerpf(float(pot_busy.get(id, 0.0)), busy, HINT_SMOOTH)
	var idle := {}
	for worker in workers:
		var side := side_of(worker)
		if not idle.has(side): idle[side] = [0, 0]
		idle[side][1] += 1
		if worker_idle(worker): idle[side][0] += 1
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
	var bus := events
	bus.begin_batch()
	event_ready_at[ev.id] = clock + ev.cooldown
	if ev.once and not ev.id in events_seen: events_seen.append(ev.id)
	events.emit("event_started", {"id": ev.id, "speaker": ev.speaker})
	if ev.choices.is_empty(): _apply_event(ev)
	else: pending_events.append(ev)
	bus.end_batch()


## 玩家在卡片上选了第 choice 个选项。选项 {"label", "cost", "accept": true/false}；accept 为 false = 拒绝。
func answer_event(choice: int) -> String:
	return CommandText.format(execute_command("answer_event", {"choice": choice}), shop)


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


## Read-only command validation. Only the stable code determines validity.
func command_status(command: String, arguments: Dictionary = {}) -> Dictionary:
	var validation := CommandResult.validate(command, arguments)
	if not CommandResult.is_ok(validation): return validation
	var params := arguments.duplicate(true)
	params.command = command
	var code := CommandResult.OK
	match command:
		"set_paused":
			params.previous = paused
			params.value = arguments.paused
			params.changed = paused != arguments.paused
		"set_tuning":
			if arguments.key not in ["seat", "customer", "walk", "work", "price"] and shop.station(arguments.key) == null:
				return CommandResult.failure(CommandResult.INVALID_ARGUMENT, {"command": command, "argument": "key"})
			params.previous = tuned(arguments.key)
			params.value = Numbers.normalize_tuning(float(arguments.value), arguments.get("snap", false))
			params.changed = not is_equal_approx(params.previous, params.value)
		"unlock":
			var id: String = arguments.id
			var st := shop.station(id)
			var recipe := _recipe_stage(id)
			if st == null: code = CommandResult.UNKNOWN_STATION
			elif station_unlocked(id) and recipe < 0: code = CommandResult.STATION_ALREADY_UNLOCKED
			else:
				var stage := recipe if recipe >= 0 else shop.stage_of(id)
				if stage < 0: code = CommandResult.STATION_NOT_UNLOCKABLE
				elif stage > 0 and not is_open(): code = CommandResult.SHOP_NOT_OPEN
				elif stage > 0 and stage > stage_index + 1:
					code = CommandResult.STAGE_REQUIRED
					params.stage = stage - 1
				elif stage == 0 and is_open(): code = CommandResult.STATION_ALREADY_UNLOCKED
				elif gold < shop.stages[maxi(stage, 0)].cost:
					code = CommandResult.INSUFFICIENT_GOLD
					params.required = shop.stages[maxi(stage, 0)].cost
		"unlock_box":
			var st := shop.station(supply_id)
			var material: SpecMaterial = st.material(arguments.material) if st != null else null
			if material == null or not boxes.has(arguments.material): code = CommandResult.UNKNOWN_BOX
			elif boxes[arguments.material]: code = CommandResult.BOX_ALREADY_UNLOCKED
			elif not station_unlocked(material.box_station):
				code = CommandResult.STATION_REQUIRED
				params.station = material.box_station
			elif gold < material.box_cost:
				code = CommandResult.INSUFFICIENT_GOLD
				params.required = material.box_cost
		"upgrade":
			var key: String = arguments.key
			var track := track_of(key)
			if track == null or track.levels.is_empty() or not levels.has(key): code = CommandResult.NO_UPGRADE
			else:
				var parts := key.split("/")
				if not key.begins_with("staff/") and key != "flyer":
					if not station_unlocked(parts[0]) and shop.station(parts[0]).companion_of.is_empty():
						code = CommandResult.STATION_REQUIRED
						params.station = parts[0]
					elif parts.size() > 1:
						if boxes.has(parts[1]) and not boxes[parts[1]]:
							code = CommandResult.BOX_REQUIRED
							params.material = parts[1]
						elif level(parts[0]) < track.requires_level:
							code = CommandResult.STATION_LEVEL_REQUIRED
							params.station = parts[0]
							params.required_level = track.requires_level
				if code == CommandResult.OK:
					if key == "flyer" and not is_open(): code = CommandResult.SHOP_NOT_OPEN
					else:
						var cost := upgrade_cost(key)
						if cost < 0: code = CommandResult.MAX_LEVEL
						elif gold < cost:
							code = CommandResult.INSUFFICIENT_GOLD
							params.required = cost
		"buy_seat":
			if not is_open(): code = CommandResult.SHOP_NOT_OPEN
			elif seat_cost() < 0: code = CommandResult.SEATS_FULL
			else:
				var group := buy_group()
				if int(seats.get(group.id, 0)) + _seat_step(group) > seat_cap(group): code = CommandResult.SEAT_STAGE_REQUIRED
				elif gold < seat_cost():
					code = CommandResult.INSUFFICIENT_GOLD
					params.required = seat_cost()
		"send_flyers":
			if not is_open(): code = CommandResult.SHOP_NOT_OPEN
			elif runtime!=null:
				var current: Dictionary = runtime.service.flyers.snapshot()
				if current.wave_left>0.0:
					code = CommandResult.FLYER_ACTIVE; params.seconds = ceili(current.wave_left)
				elif current.cooldown>0.0:
					code = CommandResult.FLYER_COOLDOWN; params.seconds = ceili(current.cooldown)
			elif _queued_arrivals():
				if flyer_ready_at - clock > 0.0:
					code = CommandResult.FLYER_COOLDOWN
					params.seconds = ceili(flyer_ready_at - clock)
			elif flyer_wave > 0.0:
				code = CommandResult.FLYER_ACTIVE
				params.seconds = ceili(flyer_wave)
			elif flyer_wait > 0.0:
				code = CommandResult.FLYER_COOLDOWN
				params.seconds = ceili(flyer_wait)
		"hire":
			var cost := hire_cost()
			if cost < 0: code = CommandResult.HIRE_EXHAUSTED
			elif shop.staff.zones.is_empty() and workers.size() >= staff_slots():
				code = CommandResult.STAFF_FULL
				params.count = staff_slots()
			elif gold < cost:
				code = CommandResult.INSUFFICIENT_GOLD
				params.required = cost
		"deploy_worker":
			var worker := worker_by_id(arguments.id)
			var post: String = arguments.get("post", "")
			params.post = post
			if worker.is_empty(): code = CommandResult.UNKNOWN_WORKER
			elif not worker.deployed:
				if post.is_empty() and not CommandResult.is_ok(_role_room_status("")) and CommandResult.is_ok(_role_room_status(counter_id)):
					post = counter_id
					params.post = post
				if not post.is_empty() and post != counter_id:
					if not post in seatables: code = CommandResult.NOT_SEATABLE
					elif post_owner(post, arguments.id) != -1: code = CommandResult.POST_OCCUPIED
				if code == CommandResult.OK:
					var room := _role_room_status(post, arguments.id)
					code = room.code
					params.merge(room.params)
		"place_worker":
			return _placement_status(arguments.id, arguments.post, arguments.get("point", Vector2.INF))
		"recall_worker":
			var worker := worker_by_id(arguments.id)
			if worker.is_empty(): code = CommandResult.UNKNOWN_WORKER
			elif not worker.deployed: code = CommandResult.WORKER_ALREADY_WAITING
		"buy_connection":
			var connection := _connection(arguments.id)
			if connection == null or not connection.enabled: code = CommandResult.UNKNOWN_CONNECTION
			elif belts.has(arguments.id): code = CommandResult.CONNECTION_ALREADY_BUILT
			elif not is_open() or stage_index < connection.stage:
				code = CommandResult.STAGE_REQUIRED
				params.stage = connection.stage
			elif gold < connection.cost:
				code = CommandResult.INSUFFICIENT_GOLD
				params.required = connection.cost
		"answer_event":
			if pending_events.is_empty(): code = CommandResult.EVENT_MISSING
			else:
				var event: SpecEvent = pending_events[0]
				if arguments.choice < 0 or arguments.choice >= event.choices.size(): code = CommandResult.INVALID_EVENT_CHOICE
				else:
					var cost := int(event.choices[arguments.choice].get("cost", 0))
					if gold < cost:
						code = CommandResult.INSUFFICIENT_GOLD
						params.required = cost
	return CommandResult.failure(code, params)


func _role_room_status(post: String, exclude_id := -1) -> Dictionary:
	var front := post == counter_id
	var count := 0
	for worker in workers:
		if worker.id != exclude_id and (worker.post == counter_id) == front: count += 1
	if front and count >= front_slots(): return CommandResult.failure(CommandResult.FRONT_FULL, {"count": front_slots()})
	if not front and count >= kitchen_slots(): return CommandResult.failure(CommandResult.KITCHEN_FULL, {"count": kitchen_slots()})
	return CommandResult.success()


func _placement_status(id: int, post: String, point: Vector2) -> Dictionary:
	var params := {"command": "place_worker", "id": id, "post": post}
	if not shop.staff.can_drag: return CommandResult.failure(CommandResult.REASSIGNMENT_DISABLED, params)
	var worker := worker_by_id(id)
	if worker.is_empty(): return CommandResult.failure(CommandResult.UNKNOWN_WORKER, params)
	if not post.is_empty():
		if post != counter_id and not post in seatables: return CommandResult.failure(CommandResult.INVALID_POST, params)
		if not station_unlocked(post):
			params.station = post
			return CommandResult.failure(CommandResult.STATION_REQUIRED, params)
		if post != counter_id and post_owner(post, id) != -1: return CommandResult.failure(CommandResult.POST_OCCUPIED, params)
	var front := post == counter_id
	if not worker.deployed or front != (worker.post == counter_id):
		var room := _role_room_status(post, id)
		if not CommandResult.is_ok(room):
			params.merge(room.params)
			return CommandResult.failure(room.code, params)
	if front and post_owner(counter_id, id) != -1: return CommandResult.failure(CommandResult.POST_OCCUPIED, params)
	var target: Vector2 = nav.post(post) if not post.is_empty() else (worker.pos if point == Vector2.INF else point)
	if not nav.walkable(target, nav.point(counter_id)): return CommandResult.failure(CommandResult.POSITION_UNREACHABLE, params)
	return CommandResult.success(params)


## A successful check is committed once; no String adapter participates.
func execute_command(command: String, arguments: Dictionary = {}) -> Dictionary:
	var status := command_status(command, arguments)
	if not CommandResult.is_ok(status): return status
	var bus := events
	bus.begin_batch()
	match command:
		"set_paused": paused = status.params.value
		"set_tuning": tune[arguments.key] = status.params.value
		"unlock": _commit_unlock(arguments.id)
		"unlock_box": _commit_unlock_box(arguments.material)
		"upgrade": _commit_upgrade(arguments.key)
		"buy_seat": _commit_buy_seat()
		"send_flyers": _commit_send_flyers()
		"hire": _commit_hire()
		"deploy_worker":
			var worker := worker_by_id(arguments.id)
			if not worker.deployed:
				worker.deployed = true
				workers.append(worker)
				if not String(status.params.post).is_empty(): _seat_at(worker, status.params.post)
				events.emit("deployed", {"id": arguments.id})
		"place_worker": _commit_place_worker(arguments.id, arguments.post, arguments.get("point", Vector2.INF))
		"recall_worker":
			var worker := worker_by_id(arguments.id)
			_cancel_job(worker)
			worker.post = ""
			worker.deployed = false
			workers.erase(worker)
			events.emit("recalled", {"id": arguments.id})
		"buy_connection": _commit_buy_connection(arguments.id)
		"answer_event":
			var event: SpecEvent = pending_events.pop_front()
			var option: Dictionary = event.choices[arguments.choice]
			gold -= int(option.get("cost", 0))
			if bool(option.get("accept", true)): _apply_event(event)
			events.emit("event_answered", {"id": event.id, "choice": arguments.choice})
	bus.end_batch()
	return status


# Canonical commits are reached only after command_status succeeds.

## 已开的机器上卖的下一个配方阶段（没有返回 -1）：只有紧接着的下一阶段能买，再往后的报“先开上一阶段”
func _recipe_stage(id: String) -> int:
	if not station_unlocked(id): return -1
	for index in shop.recipe_stages(id):
		if index > stage_index: return index
	return -1


func _commit_unlock(id: String) -> void:
	var recipe := _recipe_stage(id)
	var stage := recipe if recipe>=0 else shop.stage_of(id)
	gold -= shop.stages[stage].cost
	for key in shop.stages[stage].stations:
		unlocked[key] = true
		for st in shop.stations:
			if st.companion_of==key: unlocked[st.id] = true
	stage_index = maxi(stage_index,stage)
	nav.set_open(unlocked)
	if runtime!=null: runtime_error = runtime.set_service_open(is_open())
	var message := {"station":id,"stage":stage}
	if recipe>=0: message.dish = shop.stages[stage].dish
	events.emit("unlocked",message)

func _commit_unlock_box(material: String) -> void:
	gold -= shop.station(supply_id).material(material).box_cost
	boxes[material] = true
	events.emit("box", {"material": material})


func _commit_upgrade(key: String) -> void:
	gold -= upgrade_cost(key)
	levels[key] = int(levels[key]) + 1
	_refresh_key(key)
	events.emit("upgraded", {"key": key, "level": levels[key]})


func _commit_buy_seat() -> void:
	gold -= seat_cost()
	var g := buy_group()
	seats[g.id] = int(seats.get(g.id, 0)) + _seat_step(g)
	events.emit("seat", {})


func _commit_send_flyers() -> void:
	if runtime!=null: runtime_error = runtime.send_flyers()

func _commit_hire() -> void:
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


func _commit_place_worker(id: int, post: String, point := Vector2.INF) -> void:
	var worker := worker_by_id(id)
	if not worker.deployed:
		worker.deployed = true
		workers.append(worker)
		events.emit("deployed", {"id": id})
	_cancel_job(worker)
	WorkerState.place(worker, post, nav.post(post) if not post.is_empty() else (worker.pos if point == Vector2.INF else point))
	events.emit("placed", {"id": id, "post": post})


func _commit_buy_connection(id: String) -> void:
	var c := _connection(id)
	gold -= c.cost
	belts[id] = true
	belt_clock[id] = 0.0
	events.emit("connection", {"id": id})
