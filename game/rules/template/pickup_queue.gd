extends RefCounted
## Derived waiting ranks over existing Orders and delivery phases. This module
## stores configuration only; inventory, seat leases and paths remain shared.
var _ports: Array

func _init(definition: Dictionary) -> void:
	_ports = definition.ports.duplicate()

static func compile(raw: Variant, seats: Dictionary, delivery: String) -> Dictionary:
	if not raw is Dictionary: return _error("invalid pickup queue definition")
	if raw.is_empty(): return {"definition":{},"error":""}
	if delivery!="self_pickup" or seats.is_empty() or raw.size()!=1 or not raw.get("ports") is Array or raw.ports.size()!=seats.size(): return _error("pickup queue requires one ordered point per declared self-pickup seat")
	var seen := {}
	for port in raw.ports:
		if not port is String or not port.begins_with("pickup:") or port.length()<=7 or seen.has(port): return _error("invalid or repeated pickup queue point")
		seen[port] = true
	return {"definition":{"ports":raw.ports.duplicate()},"error":""}

func validate(customers: RefCounted) -> String:
	var points := {}
	for port in _ports:
		var target: Dictionary = customers._target(port)
		if not target.error.is_empty(): return target.error
		if points.has(target.point): return "pickup queue points share a physical location"
		points[target.point] = true
	return ""

func targets(state: Dictionary, deliveries: Array) -> Dictionary:
	var carrying := {}
	for delivery in deliveries:
		if delivery.phase in ["carry","drop"]: carrying[delivery.order] = true
	var targets := {}
	for guest in state.guests:
		if guest.state!="waiting" or carrying.has(guest.order): continue
		if targets.size()>=_ports.size(): return {"targets":{},"error":"waiting customers exceed declared pickup points"}
		targets[guest.id] = _ports[targets.size()]
	return {"targets":targets,"error":""}

static func _error(message: String) -> Dictionary:
	return {"definition":{},"error":message}
