class_name FrontHallSystem
extends RefCounted
## 前厅：顾客生成、排队、订单、前厅固定位点的解锁状态与等级、前厅服务步骤。
## 不直接加金币、不直接动库存（库存事务经 GameSim 交给 Production）。
##
## 所有顾客都在柜台点单。柜台服务员接单后，要么到出品台现打一杯（饮水机式，不囤杯、
## 不限量），要么到货架取一杯（走库存预留）。出品台不配员工。

const EPS := 0.000001

var _config: ShopConfig
var _slot_defs := {}  # id -> StationDef（只读）
var _spot_defs := {}  # id -> FrontSpotDef（只读，前厅固定位点才有）
var _dishes := {}     # dish_id -> DishDef（只读）
var _by_slot := {}

## 前厅工位与位点的运行状态（柜台、出品台、以后的货架位）
var counters: Array[StationState] = []
## 排队中的订单，按到店顺序
var orders: Array[OrderState] = []
var requests: Array[WorkRequest] = []
## 当前菜单 = 已解锁到第几阶段（来客间隔和点单权重取这一阶段的）
var menu_stage := 0
var next_arrival := 0.0
## 当前缺货的菜品 dish_id -> true
var stockout := {}
## 后厨现在能上货架的成品 item_id -> true（GameSim 每 tick 从 Production 抄过来，不存档）。
## 顾客只点出品台现打的、或者这里有的菜；都没有时按阶段权重照点（开店前也有人来）
var available := {}


func setup(config: ShopConfig, rng: RandomNumberGenerator) -> void:
	_config = config
	for dish in config.dishes:
		_dishes[dish.id] = dish
	for slot in config.slots:
		if slot.station.owner != StationDef.OwnerSystem.FRONT_HALL:
			continue
		_slot_defs[slot.id] = slot.station
		counters.append(StationState.create(slot))
	for spot in config.front_spots:
		_slot_defs[spot.id] = spot.station
		_spot_defs[spot.id] = spot
		counters.append(StationState.create_spot(spot))
	_reindex()
	next_arrival = _roll_interval(rng)


## tick 第 4 步：来客与耐心。返回 {"events", "cancelled"}，cancelled 是要由 GameSim 释放预留的订单。
## claimed：Workforce 已认领的请求 id（只读）。
func advance(dt: float, rng: RandomNumberGenerator, new_id: Callable, claimed: Dictionary) -> Dictionary:
	var events := []
	var cancelled := []
	next_arrival -= dt
	while next_arrival <= EPS:
		_spawn(rng, new_id, events)
		next_arrival += _roll_interval(rng)
	# 出品台的饮品不用等库存，柜台有人就能开始服务
	for o in orders:
		if o.state == OrderState.State.WAITING_STOCK and _dispenser_for(o.dish_id) != null:
			_begin_service(o, new_id, false)
	for o in orders.duplicate():
		if o.request_id != -1 and claimed.has(o.request_id):
			continue
		o.wait += dt
		if o.wait >= _config.customer_patience - EPS:
			orders.erase(o)
			if o.request_id != -1:
				requests.erase(_find_request(o.request_id))
			cancelled.append(o.id)
			events.append({"type": "customer_lost", "dish": o.dish_id, "reason": "patience"})
	return {"events": events, "cancelled": cancelled}


## 等料订单的 StockNeed，GameSim 拿去向 Production 预留
func stock_needs() -> Array:
	var out := []
	for o in orders:
		if o.state == OrderState.State.WAITING_STOCK and _dispenser_for(o.dish_id) == null:
			out.append({"order_id": o.id, "item": _dishes[o.dish_id].item_id, "count": 1})
	return out


## 预留成功：发布服务请求
func on_reserved(order_id: int, new_id: Callable) -> void:
	_begin_service(_find_order(order_id), new_id, true)


## 有订单在等货架上的货就算缺货；出品台的饮品不会缺货。状态变化时发事件。
func update_stockout() -> Array:
	var now := {}
	for o in orders:
		if o.state == OrderState.State.WAITING_STOCK and _dispenser_for(o.dish_id) == null:
			now[o.dish_id] = true
	var events := []
	for dish_id in now:
		if not stockout.has(dish_id):
			events.append({"type": "stockout_started", "dish": dish_id})
	for dish_id in stockout:
		if not now.has(dish_id):
			events.append({"type": "stockout_ended", "dish": dish_id})
	stockout = now
	return events


func open_requests() -> Array:
	var out := []
	for r in requests:
		out.append(r.as_open())
	return out


func owns_request(request_id: int) -> bool:
	return _find_request(request_id) != null


## 服务完成：订单离开队列，返回 {"order_id", "dish_id", "price", "from_stock"}；
## from_stock 为真时 GameSim 才去 Production 取预留的那一杯。
func on_work_completed(request_id: int) -> Dictionary:
	var r := _find_request(request_id)
	requests.erase(r)
	var o := _find_order(r.order_id)
	orders.erase(o)
	return {"order_id": o.id, "dish_id": o.dish_id, "price": _dishes[o.dish_id].price, "from_stock": o.from_stock}


func dish_item(dish_id: String) -> String:
	return _dishes[dish_id].item_id


func set_menu_stage(stage_index: int) -> void:
	menu_stage = stage_index


# ---------------------------------------------------------------- 命令用的校验与提交

func has_slot(slot_id: String) -> bool:
	return _by_slot.has(slot_id)


func station_def(slot_id: String) -> StationDef:
	return _slot_defs[slot_id]


func has_spot(spot_id: String) -> bool:
	return _spot_defs.has(spot_id)


func spot_def(spot_id: String) -> FrontSpotDef:
	return _spot_defs[spot_id]


func is_active(slot_id: String) -> bool:
	return has_slot(slot_id) and _by_slot[slot_id].status == StationState.Status.ACTIVE


## 这个工位上最多站几个人（不要员工的位点是 0）
func post_capacity(post: String) -> int:
	if _spot_defs.has(post):
		return _spot_defs[post].posts
	return 1 if has_slot(post) else 0


func validate_upgrade(slot_id: String) -> String:
	if not has_slot(slot_id):
		return "没有这个工位"
	return _by_slot[slot_id].upgrade_problem(station_def(slot_id))


func upgrade_cost(slot_id: String) -> int:
	return _by_slot[slot_id].upgrade_cost(station_def(slot_id))


func commit_upgrade(slot_id: String) -> int:
	var st: StationState = _by_slot[slot_id]
	assert(st.upgrade_problem(station_def(slot_id)) == "")
	st.level += 1
	return st.level


func validate_unlock(slot_id: String) -> String:
	if not has_slot(slot_id):
		return "没有这个工位"
	if _by_slot[slot_id].status != StationState.Status.LOCKED:
		return "机位不是未解锁状态"
	return ""


func commit_unlock(slot_id: String) -> void:
	assert(validate_unlock(slot_id) == "")
	_by_slot[slot_id].status = StationState.Status.ACTIVE


# ---------------------------------------------------------------- 存档

func to_dict() -> Dictionary:
	var cs := []
	for c in counters:
		cs.append(c.to_dict())
	var os := []
	for o in orders:
		os.append(o.to_dict())
	var rs := []
	for r in requests:
		rs.append(r.to_dict())
	return {
		"counters": cs,
		"orders": os,
		"requests": rs,
		"menu_stage": menu_stage,
		"next_arrival": next_arrival,
		"stockout": stockout.keys(),
	}


func from_dict(d: Dictionary) -> void:
	counters.clear()
	for cd in d.counters:
		counters.append(StationState.from_dict(cd))
	orders.clear()
	for od in d.orders:
		orders.append(OrderState.from_dict(od))
	requests.clear()
	for rd in d.requests:
		requests.append(WorkRequest.from_dict(rd))
	menu_stage = int(d.menu_stage)
	next_arrival = float(d.next_arrival)
	stockout.clear()
	for dish_id in d.stockout:
		stockout[String(dish_id)] = true
	_reindex()


# ---------------------------------------------------------------- 内部

func _reindex() -> void:
	_by_slot.clear()
	for c in counters:
		_by_slot[c.slot_id] = c


func _stage() -> ShopStageDef:
	return _config.progression.stages[menu_stage]


func _roll_interval(rng: RandomNumberGenerator) -> float:
	return _stage().customer_interval * (1.0 + _config.arrival_jitter * rng.randf_range(-1.0, 1.0))


func _spawn(rng: RandomNumberGenerator, new_id: Callable, events: Array) -> void:
	var dish_id := _pick_dish(rng)
	if orders.size() >= _config.queue_capacity:
		events.append({"type": "customer_lost", "dish": dish_id, "reason": "queue_full"})
		return
	var o := OrderState.new()
	o.id = new_id.call()
	o.dish_id = dish_id
	orders.append(o)
	events.append({"type": "customer_arrived", "dish": dish_id})


## 发布一张服务请求：柜台接单递杯，出品台的饮品再加上在台前打一杯的时间。
func _begin_service(o: OrderState, new_id: Callable, from_stock: bool) -> void:
	var counter := _counter_for(o.dish_id)
	if counter == null:
		return
	var def: StationDef = _slot_defs[counter.slot_id]
	var seconds := def.cycle_seconds / counter.speed(def)
	var dispenser := _dispenser_for(o.dish_id)
	if dispenser != null:
		var dispenser_def: StationDef = _slot_defs[dispenser.slot_id]
		seconds += dispenser_def.cycle_seconds / dispenser.speed(dispenser_def)
	var r := WorkRequest.create(new_id.call(), WorkRequest.Kind.SERVE, def.zone, seconds)
	r.order_id = o.id
	r.post = counter.slot_id if _spot_defs.has(counter.slot_id) else ""
	r.source = dispenser.slot_id if dispenser != null else ""
	requests.append(r)
	o.state = OrderState.State.WAITING_SERVICE
	o.from_stock = from_stock
	o.request_id = r.id


func _pick_dish(rng: RandomNumberGenerator) -> String:
	var weights := {}
	for dish_id in _stage().order_weights:
		if _dispenser_for(dish_id) != null or available.has(_dishes[dish_id].item_id):
			weights[dish_id] = _stage().order_weights[dish_id]
	if weights.is_empty():
		weights = _stage().order_weights
	var total := 0.0
	for dish_id in weights:
		total += weights[dish_id]
	var roll := rng.randf() * total
	var last := ""
	for dish_id in weights:
		last = dish_id
		roll -= weights[dish_id]
		if roll < 0.0:
			return dish_id
	return last


## 能接这道菜的柜台（要员工的那种）
func _counter_for(dish_id: String) -> StationState:
	for c in counters:
		if c.status != StationState.Status.ACTIVE:
			continue
		var def: StationDef = _slot_defs[c.slot_id]
		if def.mode != StationDef.Mode.DISPENSER and dish_id in def.dishes:
			return c
	return null


## 现打这道饮品的出品台；没有就说明这道菜从货架取
func _dispenser_for(dish_id: String) -> StationState:
	for c in counters:
		if c.status != StationState.Status.ACTIVE:
			continue
		var def: StationDef = _slot_defs[c.slot_id]
		if def.mode == StationDef.Mode.DISPENSER and dish_id in def.dishes:
			return c
	return null


func _find_order(order_id: int) -> OrderState:
	for o in orders:
		if o.id == order_id:
			return o
	return null


func _find_request(request_id: int) -> WorkRequest:
	for r in requests:
		if r.id == request_id:
			return r
	return null
