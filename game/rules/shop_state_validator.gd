extends RefCounted
## Read-only save validation. Defaults describe the current data IDs; historical
## orphan top-level IDs are ignored exactly as in the restore merge.

const BY_DATA_ID := ["sold_by_dish", "unlocked", "levels", "boxes", "stations", "shelf_stock", "order_ramp", "seats"]
var _worker_shape := {"id": 0, "kind": "", "name": "", "stats": {}, "pos": Vector2.ZERO,
	"walking": false, "phase": "", "task_label": "", "carry_item": "", "carry_count": 0,
	"fatigue": 0.0, "completed": 0, "job": {}, "ticket": {}, "post": "", "path": PackedVector2Array(),
	"path_index": 0, "action_left": 0.0, "deployed": false, "source": "", "target": "", "timer": 0.0,
	"order": -1, "steps": [], "step": 0, "chore": ""}

var _shop: SpecShop
var _state: Dictionary
var _defaults: Dictionary
var _chains: Dictionary
var _items := {}
var _staff := {}
var _orders := {}
var _customers := {}
var _routes := {}
var _events: Array = []


func validate(data: Dictionary, defaults: Dictionary, shop: SpecShop, chains: Dictionary, available_events: Array = []) -> String:
	_shop = shop
	_defaults = defaults
	_chains = chains
	_items = {}
	_staff = {}
	_orders = {}
	_customers = {}
	_routes = {}
	_events = available_events if not available_events.is_empty() else shop.events
	var error := _shape(data, defaults, "state")
	if not error.is_empty(): return error
	if data.shop != shop.id: return "不是这家店的存档"
	_state = data.duplicate()
	for key in BY_DATA_ID:
		var merged: Dictionary = defaults[key].duplicate()
		for id in data[key]:
			if merged.has(id): merged[id] = data[key][id]
		_state[key] = merged
	error = _plain_finite(_state, "state")
	if not error.is_empty(): return error
	for key in ["rng", "event_rng"]:
		if data[key].size() != 2 or not data[key][0] is int or not data[key][1] is int: return key + " 必须是两个整数"
	if data.stage_index < 0 or data.stage_index >= shop.stages.size(): return "stage_index out of range"
	for key in ["clock", "gold", "revenue", "sold", "lost", "generated", "shelf_count", "shelf_reserved_in", "shelf_reserved_out", "flyer_pending", "flyer_left", "full_seconds"]:
		if data[key] < 0: return key + " 不能为负"
	# step() consumes a tick within this tolerance; fractional GUI frame deltas
	# can therefore leave a small negative remainder. Preserve it exactly.
	if data._accumulator < -0.000001: return "_accumulator out of range"
	for key in ["_next_order", "_next_staff", "_next_customer_id"]:
		if data[key] < 1: return key + " 必须为正整数"
	for key in ["sold_by_dish", "shelf_stock", "order_ramp", "seats"]:
		error = _map(_state[key], 0, key, true)
		if not error.is_empty(): return error
	for key in ["unlocked", "boxes"]:
		error = _map(_state[key], false, key)
		if not error.is_empty(): return error
	for key in ["tune", "event_ready_at", "belt_clock", "pot_busy", "side_idle"]:
		error = _map(data[key], 0.0, key)
		if not error.is_empty(): return error
	for key in _state.levels:
		var level: Variant = _state.levels[key]
		if not level is int or level < (0 if key.begins_with("staff/") else 1): return "levels." + key + " 等级无效"
		var track := _track(key)
		if track != null and level > track.levels.size() + (0 if key.begins_with("staff/") else 1): return "levels." + key + " 等级out of range"
	for item in shop.items: _items[item.id] = true
	for dish in shop.dishes:
		_items[dish.id] = true
		for step in dish.steps:
			for id in step.consumes: _items[id] = true
			for id in step.produces: _items[id] = true
	for station in shop.stations:
		for material in station.materials: _items[material.id] = true
	for route in shop.connections: _routes[route.id] = route
	for key in ["hire_pool", "events_seen", "pending_events"]:
		for id in data[key]:
			if not id is String: return key + " 必须包含字符串 ID"
	for id in data.hire_pool:
		if not _has_kind(id): return "hire_pool 未知员工种类 " + id
	for id in data.pending_events:
		if not _has_event(id): return "pending_events 未知事件 " + id
	for row in data.orders:
		error = _shape(row, {"id": 0, "wait": 0.0, "reserved": false, "dish": "", "takeaway": false, "seat": 0}, "orders")
		if not error.is_empty(): return error
		if row.id < 1 or _orders.has(row.id) or row.id >= data._next_order: return "orders.id 无效或重复"
		if shop.dish(row.dish) == null or row.wait < 0 or row.seat < -1: return "orders 菜品或座位无效"
		_orders[row.id] = row
	for row in data.customers:
		error = _shape(row, {"id": 0, "kind": "", "addon": false, "state": "", "wait": 0.0, "claimed": false, "paid": 0}, "customers")
		if not error.is_empty(): return error
		if row.id < 1 or _customers.has(row.id) or row.id >= data._next_customer_id: return "customers.id 无效或重复"
		if shop.dish(row.kind) == null or not row.state in ["queue", "paid", "leaving"] or row.wait < 0 or row.paid < 0: return "customers 状态无效"
		if not row.get("options", []) is Array: return "customers.options 类型不对"
		for id in row.get("options", []):
			if not id is String or not _has_option(id): return "customers.options unknown option"
		_customers[row.id] = row
	var queued := {}
	for id in data.queue:
		if not id is int or not _customers.has(id) or queued.has(id): return "queue 引用无效或重复"
		if _customers[id].state != "queue": return "queue 顾客状态无效"
		queued[id] = true
	for row in data.diners:
		error = _shape(row, {"seat": 0, "dish": "", "left": 0.0}, "diners")
		if not error.is_empty(): return error
		if row.seat < 0 or shop.dish(row.dish) == null: return "diners 引用无效"
	for worker in data.roster:
		error = _shape(worker, _worker_shape, "roster")
		if not error.is_empty(): return error
		if worker.id < 1 or worker.id >= data._next_staff or _staff.has(worker.id): return "roster.id 无效或重复"
		_staff[worker.id] = worker
	var deployed := {}
	for id in data.workers:
		if not id is int or not _staff.has(id) or deployed.has(id): return "workers 名册引用无效或重复"
		deployed[id] = true
	for worker in data.roster:
		if worker.deployed != deployed.has(worker.id): return "roster.deployed 与 workers 不一致"
		error = _worker(worker)
		if not error.is_empty(): return "roster[%d].%s" % [worker.id, error]
	for id in _state.stations:
		error = _station(id, _state.stations[id])
		if not error.is_empty(): return "stations." + id + "." + error
	for worker in data.roster:
		error = _job_storage(worker)
		if not error.is_empty(): return "roster[%d].%s" % [worker.id, error]
	for row in data.mods:
		error = _shape(row, {"source": "", "source_id": "", "kind": "", "op": "", "value": 0.0, "target": "", "dishes": [], "part": "", "left": 0.0, "total": 0.0}, "mods")
		if not error.is_empty(): return error
		if not row.op in ["mul", "add", "set"]: return "mods.op 无效"
		for id in row.dishes:
			if not id is String: return "mods.dishes 类型不对"
	for row in data.log:
		error = _shape(row, {"name": "", "time": 0.0, "data": {}}, "log")
		if not error.is_empty(): return error
	for id in data.belts:
		if not _routes.has(id) or not data.belts[id] is bool: return "belts 引用或类型无效"
		if not data.belt_clock.has(id): return "belt_clock 缺少 " + id
	for id in data.belt_clock:
		if not _routes.has(id): return "belt_clock 引用无效"
	for row in data.belt_items:
		error = _shape(row, {"route": "", "item": "", "count": 0, "progress": 0.0, "duration": 0.0, "dst": ""}, "belt_items")
		if not error.is_empty(): return error
		if not _routes.has(row.route) or not _items.has(row.item) or row.count <= 0 or row.duration <= 0 or row.progress < 0 or row.progress > 1: return "belt_items 状态无效"
		if row.dst != _routes[row.route].to or not _destination(row.dst): return "belt_items 目标无效"
		if not _delivery_slot(row.dst, row.item): return "belt_items 缺少目标物品"
	return _serve(data)


## 送桌店（serve）的运行状态：引用都指向现有的顾客 / 订单 / 份 / 实物 / 员工，实物在合法位置，预留和手上的活对得上。
func _serve(data: Dictionary) -> String:
	var s: Variant = data.serve
	var error := _shape(s, {"guests": [], "orders": [], "units": [], "goods": [], "jobs": {}, "next_id": 0, "served": 0, "orders_done": 0, "items_sold": 0}, "serve")
	if not error.is_empty(): return error
	var serving: bool = _shop.fulfillment.handoff == "serve"
	if not serving:
		for key in ["guests", "orders", "units", "goods", "jobs"]:
			if not s[key].is_empty(): return "serve 只属于送桌店"
		return ""
	for key in ["next_id", "served", "orders_done", "items_sold"]:
		if s[key] < 0: return "serve." + key + " 不能为负"
	var ids := {}
	var guests := {}
	var orders := {}
	var units := {}
	var goods := {}
	var seats := {}
	for g in s.guests:
		error = _shape(g, {"id": 0, "state": "", "wait": 0.0, "seat": 0, "order": 0, "claimed": 0, "walk_left": 0.0, "walk_total": 0.0, "eat_left": 0.0}, "serve.guests")
		if not error.is_empty(): return error
		if not g.state in ["queue", "to_seat", "seated", "eating"] or g.wait < 0 or g.walk_left < 0 or g.eat_left < 0: return "serve.guests 状态无效"
		if g.seat >= 0:
			if seats.has(g.seat): return "serve.guests 座位重复"
			seats[g.seat] = true
		elif g.state != "queue": return "serve.guests 缺少座位"
		guests[g.id] = g
		ids[g.id] = true
	for o in s.orders:
		error = _shape(o, {"id": 0, "guest": 0, "seat": 0, "lines": [], "paid": false}, "serve.orders")
		if not error.is_empty(): return error
		if not guests.has(o.guest) or guests[o.guest].order != o.id or o.lines.is_empty(): return "serve.orders 引用无效"
		for line in o.lines:
			error = _shape(line, {"dish": "", "qty": 0, "delivered": 0}, "serve.orders.lines")
			if not error.is_empty(): return error
			if _shop.dish(line.dish) == null or line.qty < 1 or line.delivered < 0 or line.delivered > line.qty: return "serve.orders.lines 无效"
		orders[o.id] = o
		ids[o.id] = true
	for u in s.units:
		error = _shape(u, {"id": 0, "order": 0, "line": 0, "dish": "", "done": [], "wait": 0.0}, "serve.units")
		if not error.is_empty(): return error
		if not orders.has(u.order) or u.line < 0 or u.line >= orders[u.order].lines.size() or orders[u.order].lines[u.line].dish != u.dish: return "serve.units 引用无效"
		for step in u.done:
			if not step is int or step < 0 or step >= _shop.dish(u.dish).steps.size(): return "serve.units.done 无效"
		units[u.id] = u
		ids[u.id] = true
	for g in s.goods:
		error = _shape(g, {"id": 0, "item": "", "at": "", "owner": 0, "res": 0}, "serve.goods")
		if not error.is_empty(): return error
		if not _items.has(g.item) or (g.owner != -1 and not units.has(g.owner)): return "serve.goods 物品或 owner 无效"
		if g.res != -1 and not _staff.has(g.res): return "serve.goods 预留员工无效"
		if g.at.begins_with("hand:"):
			if g.res != int(g.at.substr(5)) or not _staff.has(g.res): return "serve.goods 拿在手上的必须是本人预留"
		elif g.at.begins_with("seat:"):
			if g.owner == -1: return "serve.goods seat goods need an owner"
		elif not _state.stations.has(g.at): return "serve.goods 位置无效"
		goods[g.id] = g
		ids[g.id] = true
	for id in ids:
		if id < 1 or id >= s.next_id: return "serve id out of range"
	if ids.size() != s.guests.size() + s.orders.size() + s.units.size() + s.goods.size(): return "serve id 重复"
	for key in s.jobs:
		if not key is String or not key.is_valid_int() or not _staff.has(int(key)): return "serve.jobs 员工引用无效"
		var job: Variant = s.jobs[key]
		error = _shape(job, {"kind": "", "unit": 0, "step": 0, "item": "", "good": 0, "from": "", "to": "", "guest": 0, "stage": ""}, "serve.jobs")
		if not error.is_empty(): return error
		if not job.kind in ["take", "work", "carry", "pass", "serve", "home"]: return "serve.jobs.kind 无效"
		if job.kind in ["work", "carry", "pass", "serve"] and not units.has(job.unit): return "serve.jobs.unit 无效"
		if job.kind == "take" and not guests.has(job.guest): return "serve.jobs.guest 无效"
		if job.good != -1 and (not goods.has(job.good) or goods[job.good].res != int(key)): return "serve.jobs.good 预留不一致"
	for id in goods:
		var g: Dictionary = goods[id]
		if g.res != -1 and (not s.jobs.has(str(g.res)) or s.jobs[str(g.res)].good != id): return "serve.goods 预留没有对应的活"
	return ""


func _job_storage(worker: Dictionary) -> String:
	if worker.job.is_empty(): return ""
	var job: Dictionary = worker.job
	var source := _shop.station(job.src)
	var operation: bool = job.kind in ["work", "pot_start", "pot_take", "stir"]
	# Supply bypasses stock accounting only for transport. It is never a machine.
	if operation:
		if source == null: return "job.src operation requires machine"
		if job.kind == "work":
			if source.block != "topping": return "job.kind requires topping"
		elif source.block != "batch_pot": return "job.kind requires batch_pot"
		if not worker.phase in ["walk_pickup", "work"]: return "job.phase incompatible with operation"
		var active: Dictionary = _state.stations[job.src]
		if not active.work_reserved: return "job.src missing work reservation"
		if job.kind in ["pot_take", "stir"]:
			var phase := "awaiting_take" if job.kind == "pot_take" else "stir"
			if active.phase != phase or active.processing != job.count or not active.output.has(job.item): return "job.src invalid active pot state"
		elif job.kind == "pot_start" and active.processing != 0: return "job.src pot already processing"
	elif not worker.phase in ["walk_pickup", "pickup", "walk_dropoff", "dropoff"]: return "job.phase incompatible with transport"
	if worker.walking != worker.phase.begins_with("walk_"): return "job.walking incompatible with phase"
	if job.src == "shelf":
		if not _state.shelf_stock.has(job.item): return "job.src 缺少物品"
	elif source == null or source.block != "supply":
		var station: Dictionary = _state.stations[job.src]
		if job.kind == "pot_take":
			if station.output.is_empty(): return "job.src 缺少产出"
		elif job.kind != "stir":
			var stock: Dictionary = station.input if job.kind in ["work", "pot_start"] else station.output
			if not stock.has(job.item) or not station.reserved_out.has(job.item): return "job.src 缺少物品或预留"
		if worker.phase == "work" and job.kind == "work" and station.get("duration", 0.0) <= 0: return "job.duration 无效"
	if operation:
		if job.src != job.dst: return "job.dst 操作目标无效"
	elif job.kind == "serve":
		var destination := _shop.station(job.dst)
		if destination == null or destination.block != "counter": return "job.dst 出餐目标无效"
	elif not _delivery_slot(job.dst, job.item): return "job.dst 缺少目标物品"
	return ""


func _delivery_slot(destination: String, item: String) -> bool:
	if destination == "shelf": return _state.shelf_stock.has(_cup(item))
	if not _state.stations.has(destination): return false
	if destination == "rack": return _state.stations[destination].output.has(item)
	var station := _shop.station(destination)
	var key := _cup(item) if station != null and station.block == "pickup" else item
	return _state.stations[destination].input.has(key)


func _cup(item: String) -> String:
	if _shop.dish(item) != null: return item
	for dish in _shop.dishes:
		var chain: Array = _chains[dish.id]
		if chain.size() != 1: continue
		var output := ""
		for step in dish.steps:
			if step.station == chain[0]:
				for produced in step.produces: output = produced
		if output == item: return dish.id
	return item


func _worker(w: Dictionary) -> String:
	if not _has_kind(w.kind): return "kind 未知员工种类"
	var error := _map(w.stats, 0.0, "stats")
	if not error.is_empty(): return error
	if not w.phase in ["idle", "wait", "walk", "work", "walk_pickup", "walk_dropoff", "pickup", "dropoff"]: return "phase 无效"
	if w.path_index < 0 or w.path_index > w.path.size(): return "path_index out of range"
	if w.carry_count < 0 or w.completed < 0 or w.fatigue < 0 or w.fatigue > 1: return "count/fatigue invalid"
	if not w.carry_item.is_empty() and not _items.has(w.carry_item): return "carry_item 未知物品"
	if not w.post.is_empty() and _shop.station(w.post) == null: return "post 未知站点"
	if not w.target.is_empty() and not _point(w.target): return "target 未知路径目标"
	if w.has("duration") and (not _number(w.duration) or w.duration < 0): return "duration 无效"
	for step in w.steps:
		error = _shape(step, {"point": "", "action": "", "seconds": 0.0, "label": "", "station": ""}, "steps")
		if not error.is_empty(): return error
		if _shop.station(step.station) == null or not _point(step.point) or step.seconds < 0: return "steps 站点、路径或时间无效"
		if not _step_action(step.station, step.action): return "steps.action incompatible with station"
		for key in ["fixed", "into_machine", "put_down"]:
			if step.has(key) and not step[key] is bool: return "steps." + key + " 类型不对"
		if step.has("holds") and (not step.holds is String or (not step.holds.is_empty() and not _items.has(step.holds))): return "steps.holds 无效"
	if not w.steps.is_empty():
		if w.steps[0].action != "take" or w.steps[-1].action != "hand": return "steps missing take/hand boundary"
		for index in w.steps.size():
			if (index > 0 and w.steps[index].action == "take") or (index < w.steps.size() - 1 and w.steps[index].action == "hand"): return "steps misplaced take/hand"
	if w.step < 0 or (not w.steps.is_empty() and w.step >= w.steps.size()): return "step out of range"
	# The final handoff clears steps/order but intentionally leaves the last step index.
	if w.order != -1 and (not _customers.has(w.order) or w.steps.is_empty()): return "order 活动顾客引用无效"
	if not w.chore.is_empty():
		var parts: PackedStringArray = w.chore.split(":")
		if parts.size() != 2 or not parts[0] in ["load", "unload"]: return "chore 无效"
		var station := _shop.station(parts[1])
		if station == null or station.block != "batch_pot": return "chore 引用无效"
	if not w.ticket.is_empty():
		error = _shape(w.ticket, {"dish": "", "count": 0, "at": 0, "phase": "", "wait": 0.0}, "ticket")
		if not error.is_empty(): return error
		var ticket: Dictionary = w.ticket
		if not _chains.has(ticket.dish) or ticket.at < 0 or ticket.at >= _chains[ticket.dish].size() or ticket.count < 1 or not ticket.phase in ["carry", "work"] or ticket.wait < 0: return "ticket 引用或索引无效"
	if not w.job.is_empty():
		error = _shape(w.job, {"kind": "", "src": "", "dst": "", "item": "", "count": 0, "priority": 0.0, "belt": "", "order_id": 0}, "job")
		if not error.is_empty(): return error
		var job: Dictionary = w.job
		if not job.kind in ["work", "pot_start", "pot_take", "stir", "serve", "load", "transfer", "carry_to_process", "carry_to_rack", "carry_to_shelf"]: return "job.kind 无效"
		if not _destination(job.src) or not _destination(job.dst) or not _items.has(job.item) or job.count < 1: return "job 引用或计数无效"
		if job.kind in ["work", "pot_start", "pot_take", "stir"] and _shop.station(job.src) == null: return "job 操作站点无效"
		if job.kind == "serve" and (not _orders.has(job.order_id) or _orders[job.order_id].dish != job.item): return "job.order_id 引用无效"
		if not job.belt.is_empty() and not _routes.has(job.belt): return "job.belt 引用无效"
		if job.has("pour"):
			if not job.pour is String: return "job.pour 类型不对"
			if not job.pour.is_empty() and (not _point(job.pour) or _shop.dish(job.item) == null): return "job.pour 无效"
	elif _shop.fulfillment.handoff == "handoff" and (w.walking or w.phase in ["work", "pickup", "dropoff", "walk_pickup", "walk_dropoff"]): return "job 活动工序缺少任务"
	if _shop.fulfillment.handoff == "single" and w.phase == "work" and w.order == -1 and w.chore.is_empty(): return "work 缺少工序"
	return ""


func _step_action(station: String, action: String) -> bool:
	if action in ["take", "hand"]: return _shop.station(station).block == "counter"
	for dish in _shop.dishes:
		for step in dish.steps:
			if step.station == station and step.action == action: return true
	for option in _shop.order_options:
		if option.step == null: continue
		var source: String = option.station if option.step.station.is_empty() else option.step.station
		if source == station and option.step.action == action: return true
	return false


func _station(id: String, row: Variant) -> String:
	var shape: Dictionary = _defaults.stations[id].duplicate()
	shape.erase("duration") # Legacy single-order pots restore this after validation.
	var error := _shape(row, shape, "state")
	if not error.is_empty(): return error
	for key in ["input", "output", "reserved_out"]:
		error = _map(row[key], 0, key, true)
		if not error.is_empty(): return error
		for item in row[key]:
			if not _items.has(item): return key + " 未知物品"
		for item in shape[key]:
			if not row[key].has(item): return key + " 缺少 " + item
	for key in ["processing", "reserved_in", "capacity", "stock"]:
		if row[key] < 0: return key + " 不能为负"
	if not row.phase in ["idle", "ready", "working", "heating", "stir", "awaiting_take", "cook", "done"]: return "phase 无效"
	if row.progress < 0 or row.progress > 1: return "progress out of range"
	if row.user != -1 and not _staff.has(row.user): return "user 员工引用无效"
	if not row.processing_item.is_empty() and not _items.has(row.processing_item): return "processing_item 未知物品"
	# Manual topping work consumes this output reference too, while processing
	# remains zero. Validate every nonempty reference, not only automatic batches.
	if not row.processing_item.is_empty() and not row.output.has(row.processing_item): return "processing_item 缺少产出槽"
	if row.has("duration") and (not _number(row.duration) or row.duration < 0): return "duration 无效"
	if row.processing > 0 and not row.phase in ["awaiting_take", "stir"] and row.get("duration", 0.0) <= 0: return "duration 活动加工时间无效"
	if row.processing > 0 and _shop.station(id) != null and _shop.station(id).block != "batch_pot" and not row.output.has(row.processing_item): return "processing_item 缺少产出槽"
	return ""


func _shape(value: Variant, shape: Dictionary, path: String) -> String:
	if not value is Dictionary: return path + " 必须是字典"
	for key in shape:
		if not value.has(key): return path + " 缺少 " + key
		if not _same_type(value[key], shape[key]): return path + "." + key + " 类型不对"
	return ""


func _same_type(value: Variant, sample: Variant) -> bool:
	return typeof(value) == typeof(sample) or (sample is float and value is int)


func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _map(value: Dictionary, sample: Variant, path: String, nonnegative := false) -> String:
	for key in value:
		if (not key is String and not key is StringName) or not _same_type(value[key], sample): return path + " 键或值类型不对"
		if nonnegative and value[key] < 0: return path + "." + key + " 不能为负"
	return ""


func _plain_finite(value: Variant, path: String, depth := 0) -> String:
	if depth > 64: return path + " nested too deeply"
	if value is float and not is_finite(value): return path + " 数字必须有限"
	if value is Vector2 and (not is_finite(value.x) or not is_finite(value.y)): return path + " 坐标必须有限"
	if value is Array or value is PackedVector2Array:
		for index in value.size():
			var error := _plain_finite(value[index], "%s[%d]" % [path, index], depth + 1)
			if not error.is_empty(): return error
	elif value is Dictionary:
		for key in value:
			if not key is String and not key is StringName: return path + " 字典键必须是字符串"
			var error := _plain_finite(value[key], path + "." + key, depth + 1)
			if not error.is_empty(): return error
	elif not typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2, TYPE_VECTOR2I]:
		return path + " invalid save value type"
	return ""


func _destination(id: String) -> bool:
	return id == "shelf" or _state.stations.has(id)


func _point(id: String) -> bool:
	return _shop.layout.points.has(id) or _shop.layout.aliases.has(id) or _shop.layout.posts.has(id)


func _has_kind(id: String) -> bool:
	for kind in _shop.staff.kinds:
		if kind.id == id: return true
	return false


func _has_event(id: String) -> bool:
	for event in _events:
		if event.id == id: return true
	return false


func _has_option(id: String) -> bool:
	for option in _shop.order_options:
		if option.id == id: return true
	return false


func _track(key: String) -> SpecUpgradeTrack:
	if key == "flyer": return _shop.flyer.track
	if key.begins_with("staff/"):
		for track in _shop.staff.tracks:
			if track.id == key.substr(6): return track
		return null
	var parts := key.split("/")
	var station := _shop.station(parts[0])
	if station == null: return null
	if parts.size() > 1:
		var material := station.material(parts[1])
		return material.track if material != null else null
	return station.track("level") if not station.tracks.is_empty() else null
