extends RefCounted
## Explicit menu identities and station tracks contribute to the shared arrival
## multiplier. Unlocks, levels and effects remain owned by the outer commands.

static func compile(raw: Variant, menu: Dictionary) -> Dictionary:
	if not raw is Dictionary: return _error("invalid menu flow")
	if raw.is_empty(): return {"definition":{},"error":""}
	var result := {"flavors":[],"stations":[],"per_extra_flavor":0.0,"per_level":0.0}
	for key in raw:
		if not result.has(key): return _error("unsupported menu flow parameter")
		result[key] = raw[key]
	for key in ["flavors","stations"]:
		if not result[key] is Array: return _error("invalid menu flow identities")
		var seen := {}
		for id in result[key]:
			if not id is String or id.is_empty() or seen.has(id) or (key=="flavors" and not menu.has(id)): return _error("invalid or repeated menu flow identity")
			seen[id] = true
	for key in ["per_extra_flavor","per_level"]:
		if not (result[key] is float or result[key] is int) or not is_finite(float(result[key])) or result[key]<0.0: return _error("invalid menu flow coefficient")
		result[key] = float(result[key])
	if (result.per_extra_flavor>0.0 and result.flavors.is_empty()) or (result.per_level>0.0 and result.stations.is_empty()): return _error("menu flow coefficient has no contributing identities")
	return {"definition":result.duplicate(true),"error":""}

static func reference_error(definition: Dictionary, owner: RefCounted) -> String:
	for id in definition.stations:
		if owner.shop.station(id)==null or owner.track_of(id)==null: return "menu flow references an unknown station track: "+id
	return ""

static func multiplier(definition: Dictionary, gates: Dictionary, owner: RefCounted) -> float:
	var requirements := preload("res://game/rules/template/requirements.gd")
	var flavors := 0
	for dish in definition.flavors:
		if requirements.met(gates[dish],owner): flavors += 1
	var levels := 0
	for id in definition.stations:
		if owner.station_unlocked(id): levels += maxi(0,owner.level(id)-1)
	var base: float = (1.0+float(definition.per_extra_flavor)*maxi(0,flavors-1))*(1.0+float(definition.per_level)*levels)
	# Do not let a set-effect hide overflow in authored contributions.
	if not is_finite(base) or base<=0.0: return NAN
	return float(owner.mods.value("flow",base))

static func _error(message: String) -> Dictionary:
	return {"definition":{},"error":message}
