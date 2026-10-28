extends RefCounted
## Session-only prototype. Inventory is conserved from raw pickup through service.
## Reservations include walking workers and belt shipments until actual delivery.
const Layout := preload("res://content/tea/art_playtest_layout.gd")
const STEP := 0.1
const SHELF_CAPACITY := 3
const SALE_PRICE := 12
const ITEMS := {"boil": "tea", "mix": "milk_tea", "topping": "topped", "seal": "sealed"}
const INPUTS := {"boil": "raw", "mix": "tea", "topping": "milk_tea", "seal": "topped"}

var workers: Array = []
var stations: Dictionary = {}
var belt_items: Array = []
var shelf_count := 0
var orders: Array = []
var gold := 60
var sold := 0
var elapsed := 0.0
var use_belts := true
var paused := false
var events: Array = []
var _accumulator := 0.0
var _generated := 0
var _shelf_reserved_in := 0
var _shelf_reserved_out := 0
var _next_order := 1
var _order_clock := 0.0

func _init() -> void:
	for key in ["boil", "mix", "topping", "seal"]:
		stations[key] = {"input": {INPUTS[key]: 0}, "output": {ITEMS[key]: 0},
			"phase": "idle", "progress": 0.0, "label": key, "capacity": 6,
			"processing": 0, "remaining": 0.0, "duration": 0.0,
			"reserved_in": 0, "reserved_out": {}, "work_reserved": false}
	_add_worker()
	for i in 3: _add_order()

func advance(dt: float) -> void:
	if paused or dt <= 0 or not is_finite(dt): return
	_accumulator += dt
	while _accumulator + 0.000001 >= STEP:
		_accumulator -= STEP
		_tick()

func hire_cost() -> int:
	return 35 + maxi(0, workers.size() - 1) * 25 if workers.size() < 3 else -1

func hire() -> bool:
	var price := hire_cost()
	if price < 0 or gold < price: return false
	gold -= price
	_add_worker()
	_event("hired", "Employee hired")
	return true

func train_cost(worker_id: int) -> int:
	for worker in workers:
		if worker.id == worker_id: return 25 * worker.level
	return -1

func train(worker_id: int) -> bool:
	var price := train_cost(worker_id)
	if price < 0 or gold < price: return false
	for worker in workers:
		if worker.id != worker_id: continue
		gold -= price
		worker.level += 1
		match worker.role:
			"speed": worker.speed += 18.0
			"carry": worker.capacity += 1
			"skill": worker.skill += 0.35
		_event("trained", "%s trained" % worker.name)
		return true
	return false

func set_belts(enabled: bool) -> void:
	if use_belts == enabled: return
	use_belts = enabled
	_event("belts_changed", "Conveyors on" if enabled else "Manual transport")

func _add_worker() -> void:
	var index := workers.size()
	workers.append({"id": index + 1, "name": ["Cat", "Raccoon", "Fox"][index],
		"art": ["cat", "raccoon", "fox"][index], "role": ["speed", "carry", "skill"][index],
		"pos": Layout.POINTS.counter, "walking": false, "phase": "idle", "task_label": "idle",
		"carry_item": "", "carry_count": 0, "speed": [112.0, 88.0, 96.0][index],
		"capacity": [2, 3, 2][index], "skill": [1.0, 1.0, 1.6][index],
		"fatigue": 0.0, "completed": 0, "level": 1, "job": {},
		"path": PackedVector2Array(), "path_index": 0, "action_left": 0.0})

func _add_order() -> void:
	orders.append({"id": _next_order, "wait": 0.0, "reserved": false})
	_next_order += 1

func _tick() -> void:
	elapsed += STEP
	_order_clock += STEP
	for order in orders: order.wait += STEP
	if _order_clock >= 7.0:
		_order_clock = 0.0
		if orders.size() < 3: _add_order()
	_update_machines()
	_update_belts()
	for worker in workers:
		if worker.phase == "idle":
			worker.fatigue = maxf(0, worker.fatigue - STEP * 0.025)
		else:
			worker.fatigue = minf(1, worker.fatigue + STEP * 0.004)
			_update_worker(worker)
	_allocate()

func _update_machines() -> void:
	for key in ["boil", "mix", "seal"]:
		var station: Dictionary = stations[key]
		if station.processing > 0:
			station.remaining = maxf(0, station.remaining - STEP)
			station.progress = 1.0 - station.remaining / station.duration
			if station.remaining <= 0.000001:
				station.output[ITEMS[key]] += station.processing
				station.processing = 0
				station.phase = "ready"
				station.progress = 1.0
				_event("batch_ready", "%s ready" % key)
		if station.processing == 0:
			var available: int = station.input[INPUTS[key]]
			var batch: int = 3 if key == "boil" else available
			if available >= batch and batch > 0:
				station.input[INPUTS[key]] -= batch
				station.processing = batch
				station.duration = {"boil": 7.0, "mix": 4.0, "seal": 3.0}[key]
				station.remaining = station.duration
				station.progress = 0.0
				station.phase = {"boil": "heating", "mix": "mixing", "seal": "sealing"}[key]
				_event("batch_started", "%s started" % key)
			elif _stock(station) == 0:
				station.phase = "idle"
				station.progress = 0.0

func _update_belts() -> void:
	for index in range(belt_items.size() - 1, -1, -1):
		var shipment: Dictionary = belt_items[index]
		shipment.progress = minf(1, shipment.progress + STEP / shipment.duration)
		if shipment.progress >= 1:
			_deliver(shipment.dst, shipment.item, shipment.count)
			belt_items.remove_at(index)
			_event("belt_delivered", "Conveyor delivered %d cups" % shipment.count)

func _stock(station: Dictionary) -> int:
	var count: int = station.processing
	for value in station.input.values(): count += value
	for value in station.output.values(): count += value
	return count

func _free(destination: String) -> int:
	if destination == "counter": return 3
	if destination == "shelf": return SHELF_CAPACITY - shelf_count - _shelf_reserved_in
	var station: Dictionary = stations[destination]
	return station.capacity - _stock(station) - station.reserved_in

func _available(source: String, item: String) -> int:
	if source == "supply": return 999
	if source == "shelf": return shelf_count - _shelf_reserved_out
	var station: Dictionary = stations[source]
	var stock: Dictionary = station.input if source == "topping" and item == "milk_tea" else station.output
	return int(stock.get(item, 0)) - int(station.reserved_out.get(item, 0))

func _candidate(kind: String, source: String, destination: String, item: String, worker: Dictionary, priority: float, belt: String = "") -> Dictionary:
	var count: int = mini(worker.capacity, mini(_available(source, item), _free(destination)))
	if count <= 0: return {}
	return {"kind": kind, "src": source, "dst": destination, "item": item,
		"count": count, "priority": priority, "belt": belt, "order_id": -1}

func _jobs(worker: Dictionary) -> Array:
	var result: Array = []
	var serve := _candidate("serve", "shelf", "counter", "sealed", worker, 110)
	if not serve.is_empty():
		for order in orders:
			if not order.reserved:
				serve.count = 1
				serve.order_id = order.id
				serve.priority += minf(20, order.wait * 0.1)
				result.append(serve)
				break
	result.append(_candidate("load_boil", "supply", "boil", "raw", worker, 26))
	result.append(_candidate("unload_boil", "boil", "mix", "tea", worker, 47))
	result.append(_candidate("transfer_to_topping", "mix", "topping", "milk_tea", worker, 62))
	var topping: Dictionary = stations.topping
	if not topping.work_reserved and _available("topping", "milk_tea") > 0:
		result.append({"kind": "topping", "src": "topping", "dst": "topping", "item": "milk_tea",
			"count": mini(worker.capacity, _available("topping", "milk_tea")), "priority": 72.0, "belt": "", "order_id": -1})
	result.append(_candidate("load_seal_belt" if use_belts else "carry_to_seal", "topping", "seal", "topped", worker, 84,
		"topping_to_seal" if use_belts else ""))
	result.append(_candidate("load_shelf_belt" if use_belts else "carry_to_shelf", "seal", "shelf", "sealed", worker, 96,
		"seal_to_shelf" if use_belts else ""))
	return result

func _destination_point(job: Dictionary) -> Vector2:
	if job.belt == "topping_to_seal": return Layout.POINTS.belt_in
	if job.belt == "seal_to_shelf": return Layout.POINTS.seal_belt
	return Layout.POINTS[job.dst]

func _path_length(points: PackedVector2Array) -> float:
	var length := 0.0
	for index in range(1, points.size()): length += points[index - 1].distance_to(points[index])
	return length

func _allocate() -> void:
	# Joint matching is recomputed after every assignment, so all reservations are visible.
	for unused in workers.size():
		var best_worker: Dictionary = {}
		var best_job: Dictionary = {}
		var best_score := -INF
		for worker in workers:
			if worker.phase != "idle": continue
			for job in _jobs(worker):
				if job.is_empty(): continue
				var to_source := Layout.path(worker.pos, Layout.POINTS[job.src])
				var to_target := Layout.path(Layout.POINTS[job.src], _destination_point(job))
				if to_source.is_empty() or to_target.is_empty(): continue
				var travel: float = (_path_length(to_source) + _path_length(to_target)) / worker.speed
				var work_time: float = (2.0 * job.count if job.kind == "topping" else 1.2) / worker.skill
				var throughput: float = float(job.count) / maxf(0.1, travel + work_time)
				var score: float = (job.priority + throughput * 18.0 - travel * 1.2) * (1.0 - worker.fatigue * 0.18)
				if score > best_score:
					best_score = score
					best_worker = worker
					best_job = job
		if best_job.is_empty(): break
		_reserve(best_worker, best_job)

func _reserve(worker: Dictionary, job: Dictionary) -> void:
	if job.src == "shelf":
		_shelf_reserved_out += job.count
	elif job.src != "supply":
		var station: Dictionary = stations[job.src]
		station.reserved_out[job.item] = int(station.reserved_out.get(job.item, 0)) + job.count
	if job.kind == "topping":
		stations.topping.work_reserved = true
	elif job.dst == "shelf":
		_shelf_reserved_in += job.count
	elif job.dst != "counter":
		stations[job.dst].reserved_in += job.count
	if job.kind == "serve":
		for order in orders:
			if order.id == job.order_id: order.reserved = true
	worker.job = job
	worker.task_label = job.kind
	_walk(worker, Layout.POINTS[job.src], "walk_pickup")

func _walk(worker: Dictionary, destination: Vector2, phase: String) -> void:
	worker.path = Layout.path(worker.pos, destination)
	worker.path_index = 1 if worker.path.size() > 1 else 0
	worker.phase = phase
	worker.walking = true

func _update_worker(worker: Dictionary) -> void:
	var job: Dictionary = worker.job
	if worker.walking:
		var distance: float = worker.speed * STEP
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
			worker.phase = "work" if job.kind == "topping" else "pickup"
			worker.action_left = (2.0 * job.count if job.kind == "topping" else 0.6) / worker.skill
			if job.kind == "topping":
				stations.topping.phase = "working"
				stations.topping.duration = worker.action_left
		else:
			worker.phase = "dropoff"
			worker.action_left = 0.6 / worker.skill
		return
	worker.action_left = maxf(0, worker.action_left - STEP)
	if worker.phase == "work":
		stations.topping.progress = 1.0 - worker.action_left / stations.topping.duration
	if worker.action_left > 0.000001: return
	match worker.phase:
		"pickup":
			_take(job)
			worker.carry_item = job.item
			worker.carry_count = job.count
			_walk(worker, _destination_point(job), "walk_dropoff")
		"work":
			_take(job)
			stations.topping.output.topped += job.count
			stations.topping.work_reserved = false
			stations.topping.phase = "ready"
			stations.topping.progress = 1.0
			_finish(worker)
		"dropoff":
			if job.kind == "serve":
				for index in orders.size():
					if orders[index].id == job.order_id:
						orders.remove_at(index)
						break
				sold += job.count
				gold += SALE_PRICE * job.count
				_event("sale", "Served pearl milk tea +12")
			elif not job.belt.is_empty():
				var duration: float = maxf(1, _path_length(Layout.belt_path(job.belt)) / 60.0)
				belt_items.append({"route": job.belt, "item": job.item, "count": job.count,
					"progress": 0.0, "duration": duration, "dst": job.dst})
				_event("belt_loaded", "Loaded %d cups on conveyor" % job.count)
			else:
				_deliver(job.dst, job.item, job.count)
			_finish(worker)

func _take(job: Dictionary) -> void:
	if job.src == "supply":
		_generated += job.count
	elif job.src == "shelf":
		shelf_count -= job.count
		_shelf_reserved_out -= job.count
	else:
		var station: Dictionary = stations[job.src]
		var stock: Dictionary = station.input if job.kind == "topping" else station.output
		stock[job.item] -= job.count
		station.reserved_out[job.item] -= job.count
		_refresh_after_pickup(station)

func _refresh_after_pickup(station: Dictionary) -> void:
	# A different worker may collect output while this station is still working.
	if station.processing > 0 or (station.work_reserved and station.phase == "working"):
		return
	var ready := false
	for count in station.output.values():
		ready = ready or count > 0
	station.phase = "ready" if ready else "idle"
	station.progress = 1.0 if ready else 0.0

func _deliver(destination: String, item: String, count: int) -> void:
	if destination == "shelf":
		shelf_count += count
		_shelf_reserved_in -= count
	else:
		stations[destination].input[item] += count
		stations[destination].reserved_in -= count

func _finish(worker: Dictionary) -> void:
	worker.completed += 1
	worker.carry_count = 0
	worker.carry_item = ""
	worker.job = {}
	worker.phase = "idle"
	worker.task_label = "idle"
	worker.walking = false

func _event(kind: String, text: String) -> void:
	events.append({"kind": kind, "text": text})
	if events.size() > 24: events.pop_front()

func audit() -> Dictionary:
	var errors: Array = []
	var stock := shelf_count
	var carried := 0
	var belts := 0
	var expected_in := {"boil": 0, "mix": 0, "topping": 0, "seal": 0, "shelf": 0}
	var expected_out := {}
	var reserved_orders: Array = []
	for key in stations:
		var station: Dictionary = stations[key]
		var count := _stock(station)
		stock += count
		if count + station.reserved_in > station.capacity or station.reserved_in < 0:
			errors.append("capacity: " + key)
		for value in station.input.values():
			if value < 0: errors.append("negative input: " + key)
		for value in station.output.values():
			if value < 0: errors.append("negative output: " + key)
	for worker in workers:
		carried += worker.carry_count
		if worker.carry_count < 0 or worker.carry_count > worker.capacity: errors.append("worker capacity")
		if worker.job.is_empty(): continue
		var job: Dictionary = worker.job
		if job.kind == "serve": reserved_orders.append(job.order_id)
		if job.kind != "topping" and expected_in.has(job.dst): expected_in[job.dst] += job.count
		if worker.phase in ["walk_pickup", "pickup", "work"] and job.src != "supply":
			var key: String = job.src + ":" + job.item
			expected_out[key] = int(expected_out.get(key, 0)) + job.count
	for shipment in belt_items:
		belts += shipment.count
		expected_in[shipment.dst] += shipment.count
	for key in stations:
		if stations[key].reserved_in != expected_in[key]: errors.append("incoming reservation: " + key)
		for item in stations[key].reserved_out:
			if stations[key].reserved_out[item] != expected_out.get(key + ":" + item, 0): errors.append("source reservation: " + key)
	if _shelf_reserved_in != expected_in.shelf or _shelf_reserved_out != expected_out.get("shelf:sealed", 0):
		errors.append("shelf reservation")
	if shelf_count < 0 or shelf_count + _shelf_reserved_in > SHELF_CAPACITY: errors.append("shelf capacity")
	for order in orders:
		if order.reserved != reserved_orders.has(order.id): errors.append("order reservation")
	var total := stock + carried + belts + sold
	if total != _generated: errors.append("conservation")
	return {"valid": errors.is_empty(), "errors": errors, "generated": _generated,
		"stock": stock, "carried": carried, "belts": belts, "sold": sold, "accounted": total,
		"reserved_in": expected_in, "reserved_out": expected_out}
