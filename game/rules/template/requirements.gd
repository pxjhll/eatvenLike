extends RefCounted
## Pure eligibility over outer command-owned facts; no copied unlock state.

static func compile(raw: Variant) -> Dictionary:
	if not raw is Dictionary: return _error("invalid requirements")
	var result := {"stations":[],"boxes":[],"levels":{},"stage":0}
	for key in raw:
		if not result.has(key): return _error("unsupported requirement: "+str(key))
		result[key] = raw[key]
	for key in ["stations","boxes"]:
		if not result[key] is Array: return _error("invalid requirement identifiers")
		var seen := {}
		for id in result[key]:
			if not id is String or id.is_empty() or seen.has(id): return _error("invalid or repeated requirement identifier")
			seen[id] = true
	if not result.stage is int or result.stage < 0 or not result.levels is Dictionary: return _error("invalid requirement stage or levels")
	for key in result.levels:
		if not key is String or key.is_empty() or not result.levels[key] is int or result.levels[key] < 1: return _error("invalid requirement upgrade level")
	return {"definition":result.duplicate(true),"error":""}

static func reference_error(definition: Dictionary, owner: RefCounted) -> String:
	for id in definition.stations:
		if owner.shop.station(id) == null: return "requirement references unknown station: "+id
	for id in definition.boxes:
		if not owner.boxes.has(id): return "requirement references unknown material box: "+id
	for key in definition.levels:
		if owner.track_of(key) == null: return "requirement references unknown upgrade track: "+key
	return ""

static func met(definition: Dictionary, owner: RefCounted) -> bool:
	if owner.stage_index < int(definition.stage): return false
	for id in definition.stations:
		if not owner.station_unlocked(id): return false
	for id in definition.boxes:
		if not owner.boxes.get(id,false): return false
	for key in definition.levels:
		if owner.level(key) < int(definition.levels[key]): return false
	return true

static func _error(message: String) -> Dictionary:
	return {"definition":{},"error":message}
