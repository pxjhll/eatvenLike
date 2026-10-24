class_name FrontHallSystem
extends RefCounted
## 前厅：顾客生成、排队、订单、前厅工位的运行状态与等级、前厅服务步骤。
## 不直接加金币、不直接动库存（库存事务经 GameSim 交给 Production）。

const EPS := 0.000001

var _config: ShopConfig
var _slot_defs := {}  # slot_id -> SlotDef（只读）
var _dishes := {}     # dish_id -> DishDef（只读）
var _by_slot := {}

var counters: Array[StationState] = []
## 排队中的订单，按到店顺序
var orders: Array[OrderState] = []
var requests: Array[WorkRequest] = []
## 当前菜单 = 已解锁到第几阶段（来客间隔和点单权重取这一阶段的）
var menu_stage := 0
var next_arrival := 0.0
## 当前缺货的菜品 dish_id -> true
var stockout := {}


func setup(config: ShopConfig, rng: RandomNumberGenerator) -> void:
	_config = config
	for dish in config.dishes:
		_dishes[dish.id] = dish
	for slot in config.slots:
		if slot.station.owner != StationDef.OwnerSystem.FRONT_HALL:
			continue
		_slot_defs[slot.id] = slot
		counters.append(StationState.create(slot))
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
		if o.state == OrderState.State.WAITING_STOCK:
			out.append({"order_id": o.id, "item": _dishes[o.dish_id].item_id, "count": 1})
	return out


## 预留成功：发布服务请求
func on_reserved(order_id: int, new_id: Callable) -> void:
	var o := _find_order(order_id)
	var counter := _counter_for(o.dish_id)
	assert(counter != null, "没有能卖这道菜的前厅工位")
	var def: StationDef = _slot_defs[counter.slot_id].station
	var r := WorkRequest.create(new_id.call(), WorkRequest.Kind.SERVE, def.zone, def.cycle_seconds / counter.speed(def))
	r.order_id = order_id
	requests.append(r)
	o.state = OrderState.State.WAITING_SERVICE
	o.request_id = r.id


## 有订单在等料的菜算缺货，状态变化时发事件
func update_stockout() -> Array:
	var now := {}
	for o in orders:
		if o.state == OrderState.State.WAITING_STOCK:
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


## 服务完成：订单离开队列，返回 {"order_id", "dish_id", "price"} 由 GameSim 取料并结算
func on_work_completed(request_id: int) -> Dictionary:
	var r := _find_request(request_id)
	requests.erase(r)
	var o := _find_order(r.order_id)
	orders.erase(o)
	return {"order_id": o.id, "dish_id": o.dish_id, "price": _dishes[o.dish_id].price}


func set_menu_stage(stage_index: int) -> void:
	menu_stage = stage_index


# ---------------------------------------------------------------- 命令用的校验与提交

func has_slot(slot_id: String) -> bool:
	return _by_slot.has(slot_id)


func station_def(slot_id: String) -> StationDef:
	return _slot_defs[slot_id].station


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


func _pick_dish(rng: RandomNumberGenerator) -> String:
	var weights := _stage().order_weights
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


func _counter_for(dish_id: String) -> StationState:
	for c in counters:
		if c.status == StationState.Status.ACTIVE and dish_id in _slot_defs[c.slot_id].station.dishes:
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
