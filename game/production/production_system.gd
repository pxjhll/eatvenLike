class_name ProductionSystem
extends RefCounted
## 后厨：工位（含外购箱、未解锁机位、并联槽）、连接与传送带、备料架库存与预留。
## 不管金币、员工是谁、前厅工位。不持有其他系统的引用，只经 GameSim 往来。

## 备料架作为连接终点时的 id
const SHELF := "shelf"
## 传送带上相邻两件物料的最小间距（格）
const ITEM_SPACING := 1.0
const EPS := 0.000001

var _config: ShopConfig
var _slot_defs := {}        # slot_id -> SlotDef（只读）
var _by_slot := {}          # slot_id -> StationState

var stations: Array[StationState] = []
var segments: Array[BeltSegmentState] = []
## 备料架 item_id -> 数量（含已预留）
var shelf := {}
## order_id -> {"item": String, "count": int}
var reservations := {}
var requests: Array[WorkRequest] = []


func setup(config: ShopConfig) -> void:
	_config = config
	for slot in config.slots:
		if slot.station.owner != StationDef.OwnerSystem.PRODUCTION:
			continue
		_slot_defs[slot.id] = slot
		stations.append(StationState.create(slot))
	for conn in config.connections:
		segments.append(BeltSegmentState.create(conn))
	_reindex()


# ---------------------------------------------------------------- tick

## tick 第 2 步：物流。先交付到达终点的物料，再移动，最后把出口缓冲推上传送带。
## 本 tick 刚推上传送带的物料不会在同一 tick 内移动。
func advance_logistics(dt: float, closed_zone: String = "") -> Array:
	for seg in segments:
		if not seg.connected or in_zone(seg.from_slot, closed_zone) or in_zone(seg.to_slot, closed_zone):
			continue
		if not seg.items.is_empty() and seg.items[0].pos >= seg.length - EPS:
			if _try_accept(seg.to_slot, seg.items[0].item):
				seg.items.pop_front()
		var step := _config.belt_speed * dt
		for i in seg.items.size():
			var it: Dictionary = seg.items[i]
			var limit: float = seg.length if i == 0 else seg.items[i - 1].pos - ITEM_SPACING
			it.pos = maxf(it.pos, minf(it.pos + step, limit))
	for st in stations:
		if st.status == StationState.Status.ACTIVE and not in_zone(st.slot_id, closed_zone):
			_push_outputs(st)
	return []


## tick 第 4 步：工位加工、外购到货，按需提出人工请求。
func advance_stations(dt: float, new_id: Callable, closed_zone: String = "") -> Array:
	var events := []
	for st in stations:
		if st.status != StationState.Status.ACTIVE or in_zone(st.slot_id, closed_zone):
			continue
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
	var st: StationState = _by_slot[req.slot_id]
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


func validate_parallel(slot_id: String) -> String:
	if not has_slot(slot_id) or _slot_defs[slot_id].parallel_of == "":
		return "这不是并联槽"
	if _by_slot[slot_id].status != StationState.Status.EMPTY_PARALLEL:
		return "并联槽已启用"
	if not has_slot(_slot_defs[slot_id].parallel_of):
		return "并联槽不属于固定机位"
	return ""


func commit_parallel(slot_id: String) -> void:
	assert(validate_parallel(slot_id) == "")
	_by_slot[slot_id].status = StationState.Status.ACTIVE


func validate_unlock(slot_id: String) -> String:
	if not has_slot(slot_id):
		return "没有这个工位"
	if _by_slot[slot_id].status != StationState.Status.LOCKED:
		return "机位不是未解锁状态"
	return ""


func commit_unlock(slot_id: String) -> void:
	assert(validate_unlock(slot_id) == "")
	_by_slot[slot_id].status = StationState.Status.ACTIVE


func validate_connection(from_slot: String, to_slot: String) -> String:
	return "" if _segment_between(from_slot, to_slot) != null else "ShopConfig 不允许这条连接"


## 线上已有物料不转移、不复制，留在原处（断开的传送带不再移动），玩家可用 ClearItems 清理
func commit_connection(from_slot: String, to_slot: String, connected: bool) -> void:
	_segment_between(from_slot, to_slot).connected = connected


func has_segment(segment_id: String) -> bool:
	return _segment(segment_id) != null


## 这段传送带两端的机位
func segment_slots(segment_id: String) -> Array[String]:
	var seg := _segment(segment_id)
	return [seg.from_slot, seg.to_slot]


func in_zone(slot_id: String, zone: String) -> bool:
	return zone != "" and _slot_defs.has(slot_id) and station_def(slot_id).zone == zone


func clear_segment(segment_id: String) -> Array:
	var seg := _segment(segment_id)
	var events := []
	var counts := seg.item_counts()
	for item in counts:
		events.append({"type": "cleared", "item": item, "count": counts[item]})
	seg.items.clear()
	return events


## 当前场上（传送带、工位缓冲、备料架）每种物料的数量。加工中的投入不计。
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


## 存档之后店里新加的机位和传送带（新菜）不在存档里，保持开店时的初始状态
func from_dict(d: Dictionary) -> void:
	var saved := {}
	for sd in d.stations:
		saved[String(sd.slot)] = sd
	stations.clear()
	for slot in _config.slots:
		if not _slot_defs.has(slot.id):
			continue
		stations.append(StationState.from_dict(saved[slot.id]) if saved.has(slot.id) else StationState.create(slot))
	var seg_data := {}
	for sd in d.segments:
		seg_data[String(sd.id)] = sd
	for seg in segments:
		if seg_data.has(seg.id):
			seg.load_dict(seg_data[seg.id])
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
	_by_slot.clear()
	for st in stations:
		_by_slot[st.slot_id] = st


func _def(st: StationState) -> StationDef:
	return _slot_defs[st.slot_id].station


func _advance_supply(st: StationState, def: StationDef, dt: float, events: Array) -> void:
	var interval := def.supply_interval / st.speed(def)
	st.supply_timer += dt
	if st.supply_timer < interval - EPS:
		return
	if SaveUtil.total(st.outputs) + SaveUtil.total(def.recipe.outputs) * def.supply_batch > def.output_capacity:
		st.supply_timer = interval
		return
	st.supply_timer -= interval
	for i in def.supply_batch:
		_produce(st, def, events)


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


func _post_request(st: StationState, kind: int, seconds: float, zone: String, new_id: Callable) -> void:
	var r := WorkRequest.create(new_id.call(), kind, zone, seconds)
	r.slot_id = st.slot_id
	requests.append(r)
	st.request_id = r.id


## 一个出口连多条线时轮流送，跳过堵住的一路
func _push_outputs(st: StationState) -> void:
	var outs: Array[BeltSegmentState] = []
	for seg in segments:
		if seg.from_slot == st.slot_id and seg.connected and _routable(seg.to_slot):
			outs.append(seg)
	if outs.is_empty():
		return
	while SaveUtil.total(st.outputs) > 0:
		var pushed := false
		for k in outs.size():
			var idx := (st.rr_index + k) % outs.size()
			var seg := outs[idx]
			if seg.items.is_empty() or seg.items[-1].pos >= ITEM_SPACING - EPS:
				var item: String = st.outputs.keys()[0]
				SaveUtil.remove_counts(st.outputs, {item: 1})
				seg.items.append({"item": item, "pos": 0.0})
				st.rr_index = (idx + 1) % outs.size()
				pushed = true
				break
		if not pushed:
			return


func _routable(slot_id: String) -> bool:
	return slot_id == SHELF or (_by_slot.has(slot_id) and _by_slot[slot_id].status == StationState.Status.ACTIVE)


func _try_accept(slot_id: String, item: String) -> bool:
	if slot_id == SHELF:
		if int(shelf.get(item, 0)) >= _config.shelf_capacity:
			return false
		shelf[item] = int(shelf.get(item, 0)) + 1
		return true
	if not _routable(slot_id):
		return false
	var st: StationState = _by_slot[slot_id]
	var def := _def(st)
	if def.recipe == null or not def.recipe.inputs.has(item):
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


func _segment(segment_id: String) -> BeltSegmentState:
	for seg in segments:
		if seg.id == segment_id:
			return seg
	return null


func _segment_between(from_slot: String, to_slot: String) -> BeltSegmentState:
	for seg in segments:
		if seg.from_slot == from_slot and seg.to_slot == to_slot:
			return seg
	return null
