extends RefCounted
## Exposure grows once per successful arrival for every currently available
## weight. This is not a sales counter; group shares bypass the multiplier.
const Inventory := preload("res://game/rules/template/inventory.gd")
var _definition: Dictionary
var _counts := {}

func _init(definition: Dictionary, order: Array) -> void:
	_definition = definition.duplicate(true)
	for dish in order: _counts[dish] = 0

static func compile(raw: Variant) -> Dictionary:
	if not raw is Dictionary: return _error("invalid menu ramp")
	if raw.is_empty(): return {"definition":{},"error":""}
	if raw.size()!=2 or not (raw.get("start") is float or raw.get("start") is int) or not raw.get("orders") is int: return _error("menu ramp needs start and integer orders")
	if not is_finite(float(raw.start)) or raw.start<=0.0 or raw.start>1.0 or raw.orders<0: return _error("invalid menu ramp curve")
	return {"definition":{"start":float(raw.start),"orders":int(raw.orders)},"error":""}

static func multiplier(definition: Dictionary, count: int) -> float:
	if definition.orders<=0: return 1.0
	return lerpf(float(definition.start),1.0,clampf(float(count)/float(definition.orders),0.0,1.0))

func admitted(weights: Dictionary) -> void:
	for dish in weights: _counts[dish] = mini(int(_counts[dish])+1,int(_definition.orders))

func counts() -> Dictionary:
	return _counts.duplicate()

func snapshot() -> Dictionary:
	return {"version":1,"counts":counts()}

func restore(data: Dictionary, arrivals: int, refresh_numeric := false) -> String:
	if not Inventory._shape(data,{"version":0,"counts":{}}) or data.version!=1 or data.counts.size()!=_counts.size(): return "invalid menu ramp state"
	for dish in _counts:
		if not data.counts.has(dish) or not data.counts[dish] is int or data.counts[dish]<0 or data.counts[dish]>arrivals: return "invalid or impossible menu exposure"
		if not refresh_numeric and data.counts[dish]>int(_definition.orders): return "invalid or impossible menu exposure"
	_counts = data.counts.duplicate()
	if refresh_numeric:
		for dish in _counts: _counts[dish] = mini(int(_counts[dish]),int(_definition.orders))
	return ""

static func _error(message: String) -> Dictionary:
	return {"definition":{},"error":message}
