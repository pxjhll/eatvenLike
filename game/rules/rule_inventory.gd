extends RefCounted
## Owns the existing stock maps and handoff transfer ledger only.
## Jobs are read-only transition inputs; employee/order execution stays outside.

const SHELF := "shelf"
const RACK := "rack"

var stations: Dictionary = {}
var shelf_stock: Dictionary = {}
var shelf_count := 0
var shelf_reserved_in := 0
var shelf_reserved_out := 0
var generated := 0


static func is_operation(job: Dictionary) -> bool:
	return job.kind in ["work", "pot_start", "pot_take", "stir"]


static func stock(station: Dictionary) -> int:
	var count: int = station.processing
	for value in station.input.values(): count += value
	for value in station.output.values(): count += value
	return count


static func refresh_after_pickup(station: Dictionary) -> void:
	if station.processing > 0 or (station.work_reserved and station.phase == "working"): return
	var ready := false
	for count in station.output.values(): ready = ready or count > 0
	station.phase = "ready" if ready else "idle"
	station.progress = 1.0 if ready else 0.0


func reserve(job: Dictionary, supply_id: String, counter_id: String) -> void:
	if job.kind in ["pot_take", "stir"]:
		pass
	elif job.src == SHELF:
		shelf_reserved_out += job.count
	elif job.src != supply_id:
		var station: Dictionary = stations[job.src]
		station.reserved_out[job.item] = int(station.reserved_out.get(job.item, 0)) + job.count
	if is_operation(job):
		stations[job.src].work_reserved = true
	elif job.dst == SHELF:
		shelf_reserved_in += job.count
	elif job.dst != counter_id:
		stations[job.dst].reserved_in += job.count


func take(job: Dictionary, supply_id: String) -> void:
	if job.src == SHELF:
		shelf_stock[job.item] -= job.count
	if job.src == supply_id:
		generated += job.count
	elif job.src == SHELF:
		shelf_count -= job.count
		shelf_reserved_out -= job.count
	else:
		var station: Dictionary = stations[job.src]
		var source_stock: Dictionary = station.input if job.kind in ["work", "pot_start"] else station.output
		source_stock[job.item] -= job.count
		station.reserved_out[job.item] -= job.count
		refresh_after_pickup(station)


func deliver(destination: String, item: String, count: int) -> void:
	if destination == RACK:
		stations[RACK].output[item] += count
		stations[RACK].reserved_in -= count
		return
	if destination == SHELF:
		shelf_stock[item] += count
		shelf_count += count
		shelf_reserved_in -= count
		return
	stations[destination].input[item] += count
	stations[destination].reserved_in -= count


func cancel(job: Dictionary, carried: int, supply_id: String, counter_id: String, clear_processing_item: bool = false) -> void:
	if job.is_empty(): return
	if carried > 0:
		if job.src == supply_id: generated -= carried
		elif job.src == SHELF:
			shelf_count += carried
			shelf_stock[job.item] = int(shelf_stock.get(job.item, 0)) + carried
		else:
			var source_stock: Dictionary = stations[job.src].input if job.kind in ["work", "pot_start"] else stations[job.src].output
			source_stock[job.item] = int(source_stock.get(job.item, 0)) + carried
	elif not job.kind in ["pot_take", "stir"]:
		if job.src == SHELF: shelf_reserved_out -= job.count
		elif job.src != supply_id: stations[job.src].reserved_out[job.item] = int(stations[job.src].reserved_out.get(job.item, 0)) - job.count
	if is_operation(job):
		stations[job.src].work_reserved = false
		if clear_processing_item: stations[job.src].processing_item = ""
	elif job.dst == SHELF: shelf_reserved_in -= job.count
	elif job.dst != counter_id and stations.has(job.dst): stations[job.dst].reserved_in -= job.count
	if stations.has(job.src): refresh_after_pickup(stations[job.src])
