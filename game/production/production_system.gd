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
			StationDef.Mode.TOPPING:
				_advance_topping(st, def, dt, events)
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


func validate_material_upgrade(slot_id: String, material_id: String) -> String:
	if not has_slot(slot_id):
		return "没有这个工位"
	var m := station_def(slot_id).material(material_id)
	if m == null:
		return "这台机器没有这个物料槽"
	return _by_slot[slot_id].mat_upgrade_problem(m)


func material_upgrade_cost(slot_id: String, material_id: String) -> int:
	return _by_slot[slot_id].mat_upgrade_cost(station_def(slot_id).material(material_id))


func commit_material_upgrade(slot_id: String, material_id: String) -> int:
	var st: StationState = _by_slot[slot_id]
	assert(st.mat_upgrade_problem(station_def(slot_id).material(material_id)) == "")
	st.mat_levels[material_id] = st.mat_level(material_id) + 1
	return st.mat_level(material_id)


## 这种成品的售价倍率：加料机上对应配料槽的等级（首店：配料槽升级 = 这个口味涨价）
func price_bonus(item: String) -> float:
	for st in stations:
		var def := _def(st)
		if def.mode != StationDef.Mode.TOPPING or st.status != StationState.Status.ACTIVE:
			continue
		for m in def.materials:
			if m.item_id == item:
				return m.bonus(st.mat_level(m.id))
	return 1.0


## 现在能上货架的成品：有启用的机器正往货架送，或者货架上还有没被订走的
func available_items() -> Dictionary:
	var out := {}
	for seg in segments:
		if seg.to_slot != SHELF or not _seg_routable(seg) or not _by_slot.has(seg.from_slot):
			continue
		var st: StationState = _by_slot[seg.from_slot]
		if st.status != StationState.Status.ACTIVE:
			continue
		for item in _output_kinds(st, _def(st)):
			out[item] = true
	for item in shelf:
		if free_stock(item) > 0:
			out[item] = true
	return out


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
	if not def.materials.is_empty():
		_advance_cabinet(st, def, dt, events)
		return
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


## 原料柜：每个原料槽自己计时、自己出货，出口按每种原料分别计容量，
## 所以一种料的下游堵住了也不挡另一种（布局基线⑮「轮流、满了跳过」）
func _advance_cabinet(st: StationState, def: StationDef, dt: float, events: Array) -> void:
	for m in def.materials:
		if not st.mat_open(m):
			continue
		var interval := def.supply_interval / (st.speed(def) * m.bonus(st.mat_level(m.id)))
		var t := float(st.mat_timers.get(m.item_id, 0.0)) + dt
		if t >= interval - EPS:
			if int(st.outputs.get(m.item_id, 0)) + def.supply_batch > def.output_capacity:
				t = interval
			else:
				t -= interval
				SaveUtil.add_counts(st.outputs, {m.item_id: def.supply_batch})
				events.append({"type": "produced", "slot": st.slot_id, "item": m.item_id, "count": def.supply_batch})
		st.mat_timers[m.item_id] = t


## 加料机：和自动机器一样计进度，只是每杯开工前挑口味——在已开放的配料槽之间轮流，
## 某口味在货架上（含在途）已经够 flavor_cap 杯就跳过；全都够了就停着
func _advance_topping(st: StationState, def: StationDef, dt: float, events: Array) -> void:
	var carry := 0.0
	if st.phase == StationState.Phase.PROCESSING:
		st.progress += dt * st.speed(def) / def.cycle_seconds
		if st.progress >= 1.0 - EPS:
			carry = maxf(0.0, st.progress - 1.0)
			SaveUtil.add_counts(st.outputs, {st.making: 1})
			events.append({"type": "produced", "slot": st.slot_id, "item": st.making, "count": 1})
			st.making = ""
			st.phase = StationState.Phase.IDLE
			st.progress = 0.0
	if st.phase != StationState.Phase.IDLE or SaveUtil.total(st.outputs) + 1 > def.output_capacity:
		return
	for item in def.recipe.inputs:
		if int(st.inputs.get(item, 0)) < def.recipe.inputs[item]:
			return
	var flavor := _next_flavor(st, def)
	if flavor == "":
		return
	_consume(st, def, events)
	st.making = flavor
	st.phase = StationState.Phase.PROCESSING
	st.progress = carry


func _next_flavor(st: StationState, def: StationDef) -> String:
	var n := def.materials.size()
	for k in n:
		var idx := (st.flavor_index + k) % n
		var m := def.materials[idx]
		if st.mat_open(m) and _in_flight(m.item_id) < def.flavor_cap:
			st.flavor_index = (idx + 1) % n
			return m.item_id
	return ""


## 这种成品在货架上、传送带上、机器出口和机器里一共有几杯
func _in_flight(item: String) -> int:
	var count := int(shelf.get(item, 0))
	for seg in segments:
		count += int(seg.item_counts().get(item, 0))
	for st in stations:
		count += int(st.outputs.get(item, 0))
		if st.making == item:
			count += 1
	return count


## 这台机器会出哪些成品
func _output_kinds(st: StationState, def: StationDef) -> Array:
	var out := []
	if def.mode == StationDef.Mode.TOPPING or (def.mode == StationDef.Mode.SUPPLY and not def.materials.is_empty()):
		for m in def.materials:
			if st.mat_open(m):
				out.append(m.item_id)
	elif def.recipe != null:
		out.append_array(def.recipe.outputs.keys())
	return out


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
		if seg.from_slot == st.slot_id and _seg_routable(seg):
			outs.append(seg)
	if outs.is_empty():
		return
	while SaveUtil.total(st.outputs) > 0:
		var pushed := false
		for k in outs.size():
			var idx := (st.rr_index + k) % outs.size()
			var seg := outs[idx]
			if seg.items.is_empty() or seg.items[-1].pos >= ITEM_SPACING - EPS:
				# 一个出口出几种料（原料柜）时，每条带只拿下游要的那种
				var item := _item_for(st, seg.to_slot)
				if item == "":
					continue
				SaveUtil.remove_counts(st.outputs, {item: 1})
				seg.items.append({"item": item, "pos": 0.0})
				st.rr_index = (idx + 1) % outs.size()
				pushed = true
				break
		if not pushed:
			return


func _seg_routable(seg: BeltSegmentState) -> bool:
	if not seg.connected or not _routable(seg.to_slot):
		return false
	return seg.until_active == "" or not _by_slot.has(seg.until_active) or _by_slot[seg.until_active].status != StationState.Status.ACTIVE


## 出口里第一件下游收的料；货架什么都收
func _item_for(st: StationState, to_slot: String) -> String:
	for item in st.outputs:
		if int(st.outputs[item]) <= 0:
			continue
		if to_slot == SHELF:
			return item
		var def := _def(_by_slot[to_slot])
		if def.recipe != null and def.recipe.inputs.has(item):
			return item
	return ""


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
