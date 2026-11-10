extends RefCounted
## Local machine clocks and phase effects; Rules selects output and duration.

const Inventory := preload("res://game/rules/rule_inventory.gd")


static func pause_for_stir(station: Dictionary, before: float, points: Array) -> bool:
	for point in points:
		if before < point and station.progress >= point:
			station.progress = point
			station.remaining = station.duration * (1.0 - point)
			station.phase = "stir"
			return true
	return false


static func advance_handoff(station: Dictionary, block: String, delta: float, stir_points: Array) -> String:
	if station.processing > 0 and not station.phase in ["awaiting_take", "stir"]:
		var before: float = station.progress
		station.remaining = maxf(0, station.remaining - delta)
		station.progress = 1.0 - station.remaining / station.duration
		if block == "batch_pot" and pause_for_stir(station, before, stir_points): return ""
		if station.remaining <= 0.000001:
			if block == "batch_pot": station.phase = "awaiting_take"
			else:
				station.output[station.processing_item] += station.processing
				station.processing = 0
				station.processing_item = ""
				station.phase = "ready"
			station.progress = 1.0
	if station.processing == 0 and block != "batch_pot":
		for item in station.input:
			if station.input[item] > 0:
				station.processing = 1 if block == "pickup" else station.input[item]
				station.input[item] -= station.processing
				return item
		if Inventory.stock(station) == 0:
			station.phase = "idle"
			station.progress = 0.0
	return ""


static func begin_automatic(station: Dictionary, seconds: float) -> void:
	station.duration = seconds
	station.remaining = station.duration
	station.progress = 0.0
	station.phase = "working"


static func advance_single(station: Dictionary, delta: float) -> void:
	if station.phase == "cook":
		station.remaining -= delta
		if station.remaining <= 0.0: station.phase = "done"
