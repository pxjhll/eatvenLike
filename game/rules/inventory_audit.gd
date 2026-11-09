extends RefCounted
## Opt-in inspection of live accounting, independent of Rules and save validation.

const Inventory := preload("res://game/rules/rule_inventory.gd")

static func inspect(inventory: RefCounted, workers: Array, belt_items: Array,
		orders: Array, mode: String, supply_id: String, counter_id: String) -> Array:
	var rows: Array = []
	for field in ["generated", "shelf_count", "shelf_reserved_in", "shelf_reserved_out"]:
		_nonnegative(rows, field, inventory.get(field))
	var shelf_total = 0
	for item in inventory.shelf_stock:
		var value = inventory.shelf_stock[item]
		_nonnegative(rows, "shelf_stock." + str(item), value)
		shelf_total += value
	_compare(rows, "shelf_count_mismatch", "shelf_count", shelf_total, inventory.shelf_count)
	for id in inventory.stations:
		var station: Dictionary = inventory.stations[id]
		var path := "stations." + str(id) + "."
		for field in ["input", "output", "reserved_out"]:
			for item in station[field]: _nonnegative(rows, path + field + "." + str(item), station[field][item])
		for field in ["reserved_in", "processing", "stock", "capacity"]:
			_nonnegative(rows, path + field, station[field])
	for index in workers.size(): _nonnegative(rows, "workers[%d].carry_count" % index, workers[index].carry_count)
	for index in belt_items.size(): _nonnegative(rows, "belt_items[%d].count" % index, belt_items[index].count)
	if mode != "handoff": return rows

	# Claims come solely from unfinished work, never from stored reservations.
	# Keep input/output source pools separate even when their item keys coincide.
	var source_claims := {}
	var outgoing := {}
	var incoming := {}
	var work_claims := {}
	var order_claims := {}
	var shelf_out := 0
	var shelf_in := 0
	for worker in workers:
		if not worker.deployed or worker.job.is_empty(): continue
		var job: Dictionary = worker.job
		if worker.carry_count == 0 and job.src != supply_id and not job.kind in ["pot_take", "stir"]:
			if job.src == Inventory.SHELF:
				shelf_out += job.count
				_add_source(source_claims, job.src, "shelf_stock", job.item, job.count)
			else:
				if not outgoing.has(job.src): outgoing[job.src] = {}
				_add(outgoing[job.src], job.item, job.count)
				_add_source(source_claims, job.src, "input" if job.kind in ["work", "pot_start"] else "output", job.item, job.count)
		if Inventory.is_operation(job):
			_add(work_claims, job.src, 1)
		elif job.dst == Inventory.SHELF:
			shelf_in += job.count
		elif job.dst != counter_id:
			_add(incoming, job.dst, job.count)
		if job.kind == "serve": _add(order_claims, job.order_id, 1)
	for shipment in belt_items:
		if shipment.dst == Inventory.SHELF: shelf_in += shipment.count
		elif shipment.dst != counter_id: _add(incoming, shipment.dst, shipment.count)

	_compare(rows, "reservation_mismatch", "shelf_reserved_out", shelf_out, inventory.shelf_reserved_out)
	_compare(rows, "reservation_mismatch", "shelf_reserved_in", shelf_in, inventory.shelf_reserved_in)
	for id in inventory.stations:
		var station: Dictionary = inventory.stations[id]
		var path := "stations." + str(id) + "."
		var expected_out: Dictionary = outgoing.get(id, {})
		var keys: Array = station.reserved_out.keys()
		for item in expected_out:
			if not keys.has(item): keys.append(item)
		for item in keys:
			_compare(rows, "reservation_mismatch", path + "reserved_out." + str(item), expected_out.get(item, 0), station.reserved_out.get(item, 0))
		_compare(rows, "reservation_mismatch", path + "reserved_in", incoming.get(id, 0), station.reserved_in)
		var count: int = work_claims.get(id, 0)
		_compare(rows, "work_reservation_mismatch", path + "work_reserved", count > 0, station.work_reserved)
		if count > 1: _row(rows, "multiple_work_claims", path + "work_reserved", 1, count)
	for index in orders.size():
		var order: Dictionary = orders[index]
		_compare(rows, "order_reservation_mismatch", "orders[%d].reserved" % index, order_claims.get(order.id, 0) > 0, order.reserved)
	for source in source_claims:
		for pool in source_claims[source]:
			for item in source_claims[source][pool]:
				var claimed = source_claims[source][pool][item]
				var available = inventory.shelf_stock.get(item, 0) if source == Inventory.SHELF else inventory.stations[source][pool].get(item, 0)
				if claimed > available:
					var path := "shelf_stock." + str(item) if source == Inventory.SHELF else "stations." + str(source) + "." + str(pool) + "." + str(item)
					_row(rows, "source_over_reserved", path, available, claimed)
	return rows

static func _add(counts: Dictionary, key: Variant, count: int) -> void:
	counts[key] = counts.get(key, 0) + count

static func _add_source(claims: Dictionary, source: String, pool: String, item: String, count: int) -> void:
	if not claims.has(source): claims[source] = {}
	if not claims[source].has(pool): claims[source][pool] = {}
	_add(claims[source][pool], item, count)

static func _nonnegative(rows: Array, path: String, actual: Variant) -> void:
	if actual < 0: _row(rows, "negative_inventory", path, 0, actual)

static func _compare(rows: Array, code: String, path: String, expected: Variant, actual: Variant) -> void:
	if expected != actual: _row(rows, code, path, expected, actual)

static func _row(rows: Array, code: String, path: String, expected: Variant, actual: Variant) -> void:
	rows.append({"code": code, "path": path, "expected": expected, "actual": actual})
