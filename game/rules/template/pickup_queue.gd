extends RefCounted
## Derived waiting ranks over existing Orders and delivery phases. This module
## stores configuration only; inventory, seat leases and paths remain shared.
var _ports: Array

func _init(definition: Dictionary) -> void:
	_ports = definition.ports.duplicate()

static func compile(raw: Variant, seats: Dictionary, delivery: String) -> Dictionary:
	if not raw is Dictionary: return _error("invalid pickup queue definition")
	if raw.is_empty(): return {"definition":{},"error":""}
	if delivery!="self_pickup" or seats.is_empty() or not raw.get("ports") is Array or raw.ports.size()!=seats.size(): return _error("pickup queue requires one ordered point per declared self-pickup seat")
	if raw.size()!=1+int(raw.has("mixed_line")) or not raw.get("mixed_line",false) is bool:
		return _error("invalid mixed queue option")
	var seen := {}
	for port in raw.ports:
		if not port is String or not port.begins_with("pickup:") or port.length()<=7 or seen.has(port): return _error("invalid or repeated pickup queue point")
		seen[port] = true
	var definition := {"ports":raw.ports.duplicate()}
	if raw.get("mixed_line",false): definition.mixed_line = true
	return {"definition":definition,"error":""}

func validate(customers: RefCounted) -> String:
	var points := {}
	for port in _ports:
		var target: Dictionary = customers._target(port)
		if not target.error.is_empty(): return target.error
		if points.has(target.point): return "pickup queue points share a physical location"
		points[target.point] = true
	return ""

func validate_mixed_line(customers: RefCounted, seats: Dictionary, stages: Array) -> String:
	var standing := 0
	for stage in stages: standing = maxi(standing,int(stage.standing))
	var points := {}
	var head: Dictionary = customers._target(_ports[0])
	for rank in seats.size()+standing:
		var spot: Dictionary = customers._target("queue:"+str(rank))
		if not spot.error.is_empty(): return "mixed line needs a point for every seat and waiting customer"
		if points.has(spot.point) or not customers._nav.can_stand(spot.point,"customer"): return "mixed line points must be distinct and reachable"
		if rank==0 and spot.point!=head.point: return "queue head and pickup must use the same point"
		points[spot.point] = true
	return ""

func targets(state: Dictionary, deliveries: Array, before_order := -1, counter_dishes: Array = [], mixed_line := false) -> Dictionary:
	var carrying := {}
	for delivery in deliveries:
		if delivery.phase in ["carry","drop"]: carrying[delivery.order] = true
	var targets := {}
	for guest in state.guests:
		if guest.state!="waiting" or carrying.has(guest.order): continue
		if not guest.get("regular", false) and before_order>=0 and guest.order>=before_order and (guest.request.is_empty() or guest.request[0].dish not in counter_dishes): continue
		if targets.size()>=_ports.size(): return {"targets":{},"error":"waiting customers exceed declared pickup points"}
		var rank := targets.size()
		targets[guest.id] = "queue:"+str(rank) if mixed_line and rank>0 else _ports[rank]
	return {"targets":targets,"error":""}

static func _error(message: String) -> Dictionary:
	return {"definition":{},"error":message}
