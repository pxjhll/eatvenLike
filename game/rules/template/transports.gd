extends RefCounted
## Autonomous carriers use ordinary inventory bundles. Only route cooldowns
## and in-flight time live here; production nodes retain the bundle reference.
const Inventory := preload("res://game/rules/template/inventory.gd")
var _definition: Dictionary
var _state := {"version":1,"cooldowns":{},"flights":[]}

func _init(definition: Dictionary) -> void:
	_definition = definition
	for route in definition: _state.cooldowns[route] = 0.0

static func compile(raw: Dictionary, places: Dictionary) -> Dictionary:
	for id in raw:
		var route: Variant = raw[id]
		if not id is String or id.is_empty() or not Inventory._shape(route,{"from":"","to":"","connection":"","seconds":0.0,"interval":0.0,"capacity":0}): return _error("invalid transport route")
		if not places.has(route.from) or not places.has(route.to) or route.from==route.to or Inventory.is_hand_place(route.from) or Inventory.is_hand_place(route.to) or route.connection.is_empty() or not is_finite(route.seconds) or route.seconds<=0.0 or not is_finite(route.interval) or route.interval<=0.0 or route.capacity<1: return _error("invalid transport ports, timing or capacity")
	return {"error":"","definition":raw.duplicate(true)}

func validate_context(owner: RefCounted) -> String:
	for route in _definition.values():
		var found := false
		for connection in owner.shop.connections:
			if connection.id==route.connection and connection.enabled: found = true
		if not found: return "transport references an unknown enabled connection"
	return ""

func enabled(route: String, owner: RefCounted) -> bool:
	return _definition.has(route) and owner.belts.has(_definition[route].connection)

func start(route: String, stock: RefCounted, entry: Dictionary) -> Dictionary:
	if float(_state.cooldowns[route])>0.00000001: return _error("transport interval")
	var definition: Dictionary = _definition[route]
	var actor := "conveyor:"+str(stock.snapshot().next_bundle)
	var group: Dictionary = stock.reserve_bundle(actor,[entry],definition.capacity)
	if not group.error.is_empty(): return group
	var error: String = stock.pickup_bundle(group.id)
	if not error.is_empty(): stock.cancel_bundle(group.id); return _error(error)
	_state.flights.append({"route":route,"bundle":int(group.id),"duration":float(definition.seconds),"left":float(definition.seconds)})
	_state.cooldowns[route] = float(definition.interval)
	return group

func advance(dt: float, stock: RefCounted) -> String:
	for route in _state.cooldowns: _state.cooldowns[route] = maxf(0.0,float(_state.cooldowns[route])-dt)
	for flight in _state.flights.duplicate():
		flight.left = maxf(0.0,float(flight.left)-dt)
		if flight.left>0.00000001: continue
		var error: String = stock.drop_bundle(flight.bundle)
		if not error.is_empty(): return error
		_state.flights.erase(flight)
	return ""

func cancel(bundle: int, stock: RefCounted) -> String:
	var group: Dictionary = stock.bundle(bundle)
	if group.is_empty() or not String(group.actor).begins_with("conveyor:"): return "not an autonomous carrier"
	var error: String = stock.cancel_bundle(bundle)
	if not error.is_empty(): return error
	_state.flights = _state.flights.filter(func(flight: Dictionary) -> bool: return flight.bundle!=bundle)
	return ""

func frame(stock: RefCounted) -> Array:
	var result: Array = []
	for flight in _state.flights:
		var row: Dictionary = flight.duplicate(true)
		row.progress = 1.0-float(flight.left)/float(flight.duration)
		row.items = []
		for id in stock.bundle(flight.bundle).claims:
			var claim: Dictionary = stock.claim(id)
			row.items.append({"item":claim.item,"count":int(claim.count)})
		result.append(row)
	return result

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func validate(data: Dictionary, units: Array, stock: RefCounted, recipes: Dictionary) -> String:
	if not Inventory._shape(data,{"version":0,"cooldowns":{},"flights":[]}) or data.version!=1 or data.cooldowns.size()!=_definition.size(): return "invalid transport state"
	for route in _definition:
		var left: Variant = data.cooldowns.get(route)
		if not (left is float or left is int) or not is_finite(float(left)) or left<0.0 or left>_definition[route].interval: return "invalid transport cooldown"
	var bindings := {}
	for unit in units:
		for id in unit.running:
			if not recipes[unit.recipe].nodes.has(id): continue
			var node: Dictionary = recipes[unit.recipe].nodes[id]
			if node.capability!="transfer": continue
			var group: Dictionary = stock.bundle(unit.running[id])
			if not String(group.get("actor","")).begins_with("conveyor:"): continue
			if not node.has("transport") or bindings.has(group.id) or group.actor!="conveyor:"+str(group.id) or group.claims.size()!=1: return "invalid transport graph ownership"
			bindings[group.id] = node.transport
	var active := {}
	for flight in data.flights:
		if not Inventory._shape(flight,{"route":"","bundle":0,"duration":0.0,"left":0.0}) or not _definition.has(flight.route) or not bindings.has(flight.bundle) or bindings[flight.bundle]!=flight.route or active.has(flight.bundle): return "invalid transport flight linkage"
		if not is_finite(flight.duration) or not is_finite(flight.left) or flight.duration!=_definition[flight.route].seconds or flight.left<=0.0 or flight.left>flight.duration: return "invalid transport remaining clock"
		var group: Dictionary = stock.bundle(flight.bundle)
		for id in group.claims:
			var claim: Dictionary = stock.claim(id)
			if claim.state!="held" or claim.from!=_definition[flight.route].from or claim.to!=_definition[flight.route].to: return "transport flight differs from real stock"
		active[flight.bundle] = true
	for group in stock.snapshot().bundles:
		if not String(group.actor).begins_with("conveyor:"): continue
		if not bindings.has(group.id):
			if group.actor!="conveyor:"+str(group.id): return "invalid historical carrier identity"
			for id in group.claims:
				if stock.claim(id).state!="cancelled": return "orphan autonomous carrier"
			continue
		for id in group.claims:
			if stock.claim(id).state in Inventory.ACTIVE and not active.has(group.id): return "active carrier has no flight clock"
	return ""

func restore_validated(data: Dictionary) -> void:
	_state = data.duplicate(true)

static func _error(message: String) -> Dictionary:
	return {"error":message,"definition":{}}
