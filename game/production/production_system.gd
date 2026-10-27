class_name ProductionSystem
extends RefCounted
## 后厨：设备运行状态（加工进度、等级、出入口缓冲）、按 Layout 给出的连接推进物流、
## 传送带上的物品、货架库存与预留。
## 不管设备在哪、金币、员工是谁、前厅工位。不持有其他系统的引用，只经 GameSim 往来。

## 货架作为连接终点时的 id
const SHELF := BeltRouter.SHELF
## 传送带上相邻两件物料的最小间距（格）
const ITEM_SPACING := 1.0
const EPS := 0.000001

var _config: ShopConfig
var _by_id := {}            # device id -> StationState

var stations: Array[StationState] = []
var segments: Array[BeltSegmentState] = []
## 货架 item_id -> 数量（含已预留）
var shelf := {}
## order_id -> {"item": String, "count": int}
var reservations := {}
var requests: Array[WorkRequest] = []


func setup(config: ShopConfig) -> void:
	_config = config


# ---------------------------------------------------------------- 布局

## ConfirmLayout 提交：新设备建 State；搬动过的设备保留进度、缓冲、等级；
## 旧传送带上的物料全部退回各自上游设备的出口缓冲（允许暂时超过出口容量，超出期间不出新货）。
## devices / belts 是 Layout 的生效布局。
func apply_layout(devices: Array, belts: Array) -> void:
	for seg in segments:
		var from: StationState = _by_id.get(seg.from_slot)
		if from != null:
			SaveUtil.add_counts(from.outputs, seg.item_counts())
	segments.clear()
	var kept := {}
	for d in devices:
		kept[d.id] = true
		if not _by_id.has(d.id):
			stations.append(StationState.create(d.id, d.def))
	for st in stations.duplicate():
		assert(kept.has(st.slot_id), "布局里没有删除设备的途径")
	for b in belts:
		segments.append(BeltSegmentState.create(b.id, b.from, b.to, b.item, b.path.size()))
	_reindex()


## 有一条传送带把这种成品送到货架
func delivers(item: String) -> bool:
	for seg in segments:
		if seg.to_slot == SHELF and seg.item == item:
			return true
	return false


# ---------------------------------------------------------------- tick

## tick 第 2 步：物流。先交付到达终点的物料，再移动，最后把出口缓冲推上传送带。
## 本 tick 刚推上传送带的物料不会在同一 tick 内移动。
func advance_logistics(dt: float) -> Array:
	for seg in segments:
		if not seg.items.is_empty() and seg.items[0].pos >= seg.length - EPS:
			if _try_accept(seg.to_slot, seg.items[0].item):
				seg.items.pop_front()
		var step := _config.belt_speed * dt
		for i in seg.items.size():
			var it: Dictionary = seg.items[i]
			var limit: float = seg.length if i == 0 else seg.items[i - 1].pos - ITEM_SPACING
			it.pos = maxf(it.pos, minf(it.pos + step, limit))
	for st in stations:
		_push_outputs(st)
	return []


## tick 第 4 步：设备加工、原料柜出货，按需提出人工请求。
func advance_stations(dt: float, new_id: Callable) -> Array:
	var events := []
	for st in stations:
		var def := _def(st)
		match def.mode:
			StationDef.Mode.SUPPLY:
				_advance_supply(st, def, dt, events)
			StationDef.Mode.AUTO:
				_advance_auto(st, def, dt, events)
			StationDef.Mode.COOP:
				_advance_coop(st, def, dt, new_id)
			StationDef.Mode.MANUAL:
				if st.phase == StationState.Phase.IDLE and _can_start(st, def):
					_post_request(st, WorkRequest.Kind.WORK, def.cycle_seconds / st.speed(def), def.zone, new_id)
					st.phase = StationState.Phase.WAIT_WORK
	return events


func open_requests() -> Array:
	var out := []
	for r in requests:
		out.append(r.as_open())
	return out


func owns_request(request_id: int) -> bool:
	return _find_request(request_id) != null


## overshoot：人工步骤完成后本 tick 剩下的秒数，机器接着用
func on_work_completed(request_id: int, overshoot: float) -> Array:
	var events := []
	var req := _find_request(request_id)
	assert(req != null)
	requests.erase(req)
	var st: StationState = _by_id[req.slot_id]
	var def := _def(st)
	st.request_id = -1
	match st.phase:
		StationState.Phase.WAIT_LOAD:
			_consume(st, def, events)
			st.phase = StationState.Phase.PROCESSING
			st.progress = overshoot * st.speed(def) / def.cycle_seconds
		StationState.Phase.WAIT_UNLOAD:
			_produce(st, def, events)
			st.phase = StationState.Phase.IDLE
		StationState.Phase.WAIT_WORK:
			_consume(st, def, events)
			_produce(st, def, events)
			st.phase = StationState.Phase.IDLE
	return events


# ---------------------------------------------------------------- 库存事务（经 GameSim 由 FrontHall 发起）

func free_stock(item: String) -> int:
	var reserved := 0
	for order_id in reservations:
		if reservations[order_id].item == item:
			reserved += int(reservations[order_id].count)
	return int(shelf.get(item, 0)) - reserved


func reserve(order_id: int, item: String, count: int) -> bool:
	if reservations.has(order_id):
		return true
	if free_stock(item) < count:
		return false
	reservations[order_id] = {"item": item, "count": count}
	return true


func take_reserved(order_id: int) -> Array:
	var r: Dictionary = reservations[order_id]
	reservations.erase(order_id)
	SaveUtil.remove_counts(shelf, {r.item: r.count})
	return [{"type": "taken", "item": r.item, "count": r.count}]


func release(order_id: int) -> void:
	reservations.erase(order_id)


# ---------------------------------------------------------------- 命令用的校验与提交

func has_slot(device_id: String) -> bool:
	return _by_id.has(device_id)


func station_def(device_id: String) -> StationDef:
	return _def(_by_id[device_id])


func validate_upgrade(device_id: String) -> String:
	if not has_slot(device_id):
		return "没有这台设备"
	return _by_id[device_id].upgrade_problem(station_def(device_id))


func upgrade_cost(device_id: String) -> int:
	return _by_id[device_id].upgrade_cost(station_def(device_id))


func commit_upgrade(device_id: String) -> int:
	var st: StationState = _by_id[device_id]
	assert(st.upgrade_problem(station_def(device_id)) == "")
	st.level += 1
	return st.level


## 当前场上（传送带、设备缓冲、货架）每种物料的数量。加工中的投入不计。
func count_items() -> Dictionary:
	var out := {}
	for seg in segments:
		SaveUtil.add_counts(out, seg.item_counts())
	for st in stations:
		SaveUtil.add_counts(out, st.inputs)
		SaveUtil.add_counts(out, st.outputs)
	SaveUtil.add_counts(out, shelf)
	return out


# ---------------------------------------------------------------- 存档

func to_dict() -> Dictionary:
	var sts := []
	for st in stations:
		sts.append(st.to_dict())
	var segs := []
	for seg in segments:
		segs.append(seg.to_dict())
	var res := []
	for order_id in reservations:
		res.append({"order": order_id, "item": reservations[order_id].item, "count": reservations[order_id].count})
	var reqs := []
	for r in requests:
		reqs.append(r.to_dict())
	return {"stations": sts, "segments": segs, "shelf": shelf.duplicate(), "reservations": res, "requests": reqs}


func from_dict(d: Dictionary) -> void:
	stations.clear()
	for sd in d.stations:
		stations.append(StationState.from_dict(sd))
	segments.clear()
	for sd in d.segments:
		segments.append(BeltSegmentState.from_dict(sd))
	shelf = SaveUtil.int_dict(d.shelf)
	reservations.clear()
	for r in d.reservations:
		reservations[int(r.order)] = {"item": String(r.item), "count": int(r.count)}
	requests.clear()
	for rd in d.requests:
		requests.append(WorkRequest.from_dict(rd))
	_reindex()


# ---------------------------------------------------------------- 内部

func _reindex() -> void:
	_by_id.clear()
	for st in stations:
		_by_id[st.slot_id] = st


func _def(st: StationState) -> StationDef:
	return _config.device_def(st.def_id)


## 原料柜：每隔一段时间出一份，几个槽按顺序轮流；某种料下游没空位（或这个槽的出口满了）就跳过它
func _advance_supply(st: StationState, def: StationDef, dt: float, events: Array) -> void:
	var interval := def.supply_interval / st.speed(def)
	st.supply_timer += dt
	if st.supply_timer < interval - EPS:
		return
	var count := def.supply_items.size()
	for k in count:
		var idx := (st.supply_rr + k) % count
		var item: String = def.supply_items[idx]
		if int(st.outputs.get(item, 0)) < def.output_capacity and _has_demand(st.slot_id, item):
			st.supply_timer -= interval
			st.supply_rr = (idx + 1) % count
			st.outputs[item] = int(st.outputs.get(item, 0)) + 1
			events.append({"type": "produced", "slot": st.slot_id, "item": item, "count": 1})
			return
	st.supply_timer = interval


## 这种料的下游里有没有一路还收得下（带上的 + 下游入口里的 < 入口容量）
func _has_demand(device_id: String, item: String) -> bool:
	for seg in segments:
		if seg.from_slot != device_id or seg.item != item:
			continue
		if seg.to_slot == SHELF:
			return true
		var to: StationState = _by_id[seg.to_slot]
		var cap := int(_def(to).input_capacity.get(item, 0))
		if seg.items.size() + int(to.inputs.get(item, 0)) < cap:
			return true
	return false


func _advance_auto(st: StationState, def: StationDef, dt: float, events: Array) -> void:
	# 做完一份后本 tick 剩下的进度直接用在下一份上，保证步长无关
	var carry := 0.0
	if st.phase == StationState.Phase.PROCESSING:
		st.progress += dt * st.speed(def) / def.cycle_seconds
		if st.progress >= 1.0 - EPS:
			carry = maxf(0.0, st.progress - 1.0)
			_produce(st, def, events)
			st.phase = StationState.Phase.IDLE
			st.progress = 0.0
	if st.phase == StationState.Phase.IDLE and _can_start(st, def):
		_consume(st, def, events)
		st.phase = StationState.Phase.PROCESSING
		st.progress = carry


func _advance_coop(st: StationState, def: StationDef, dt: float, new_id: Callable) -> void:
	match st.phase:
		StationState.Phase.IDLE:
			if _can_start(st, def):
				_post_request(st, WorkRequest.Kind.LOAD, def.manual_seconds / st.speed(def), def.zone, new_id)
				st.phase = StationState.Phase.WAIT_LOAD
		StationState.Phase.PROCESSING:
			st.progress += dt * st.speed(def) / def.cycle_seconds
			if st.progress >= 1.0 - EPS:
				st.progress = 1.0
				_post_request(st, WorkRequest.Kind.UNLOAD, def.manual_seconds / st.speed(def), def.zone, new_id)
				st.phase = StationState.Phase.WAIT_UNLOAD


## 配齐一份输入，且出口放得下这份输出（加工中的那份算在内，所以完成时一定放得下）
func _can_start(st: StationState, def: StationDef) -> bool:
	for item in def.recipe.inputs:
		if int(st.inputs.get(item, 0)) < def.recipe.inputs[item]:
			return false
	return SaveUtil.total(st.outputs) + SaveUtil.total(def.recipe.outputs) <= def.output_capacity


func _consume(st: StationState, def: StationDef, events: Array) -> void:
	SaveUtil.remove_counts(st.inputs, def.recipe.inputs)
	for item in def.recipe.inputs:
		events.append({"type": "consumed", "slot": st.slot_id, "item": item, "count": def.recipe.inputs[item]})


func _produce(st: StationState, def: StationDef, events: Array) -> void:
	SaveUtil.add_counts(st.outputs, def.recipe.outputs)
	for item in def.recipe.outputs:
		events.append({"type": "produced", "slot": st.slot_id, "item": item, "count": def.recipe.outputs[item]})


## 人工请求带工位：只有站在这台设备上的员工能做（一人一岗）
func _post_request(st: StationState, kind: int, seconds: float, zone: String, new_id: Callable) -> void:
	var r := WorkRequest.create(new_id.call(), kind, zone, seconds)
	r.slot_id = st.slot_id
	r.post = st.slot_id
	requests.append(r)
	st.request_id = r.id


## 出口里每件物料只走收它的那几路；同一种物料有几路时轮流送，跳过堵住的一路（决定⑥）
func _push_outputs(st: StationState) -> void:
	for item in st.outputs.keys():
		var outs: Array[BeltSegmentState] = []
		for seg in segments:
			if seg.from_slot == st.slot_id and seg.item == item:
				outs.append(seg)
		if outs.is_empty():
			continue
		while int(st.outputs.get(item, 0)) > 0:
			var pushed := false
			for k in outs.size():
				var idx := (st.rr_index + k) % outs.size()
				var seg := outs[idx]
				if seg.items.is_empty() or seg.items[-1].pos >= ITEM_SPACING - EPS:
					SaveUtil.remove_counts(st.outputs, {item: 1})
					seg.items.append({"item": item, "pos": 0.0})
					st.rr_index = (idx + 1) % outs.size()
					pushed = true
					break
			if not pushed:
				break


func _try_accept(to: String, item: String) -> bool:
	if to == SHELF:
		if int(shelf.get(item, 0)) >= _config.shelf_capacity:
			return false
		shelf[item] = int(shelf.get(item, 0)) + 1
		return true
	var st: StationState = _by_id[to]
	var def := _def(st)
	if not def.accepts(item):
		return false
	if int(st.inputs.get(item, 0)) >= int(def.input_capacity.get(item, 0)):
		return false
	st.inputs[item] = int(st.inputs.get(item, 0)) + 1
	return true


func _find_request(request_id: int) -> WorkRequest:
	for r in requests:
		if r.id == request_id:
			return r
	return null
