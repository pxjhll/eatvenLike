extends RefCounted
## Waiting-place identities only. Orders own queue state; outer commands own
## purchased capacity; Customers owns all paths and arrival facts.
const Inventory := preload("res://game/rules/template/inventory.gd")
var _definition: Dictionary
var _state := {"version":1,"leases":[]}

func _init(definition: Dictionary) -> void:
	_definition = definition.duplicate(true)

static func compile(raw: Variant) -> Dictionary:
	if not raw is Dictionary: return _error("invalid waiting policy")
	if raw.is_empty(): return {"definition":{},"error":""}
	for key in raw:
		if key not in ["group","ports","line","stages","retain_after_take","call_during_final_work"]: return _error("unsupported waiting parameter: "+str(key))
	if not raw.get("group") is String or raw.group.is_empty() or not raw.get("ports") is Array or not raw.get("line") is Array or raw.line.is_empty() or not raw.get("stages") is Array or raw.stages.is_empty() or not raw.get("retain_after_take",false) is bool: return _error("invalid waiting definition")
	if not raw.get("call_during_final_work",false) is bool or (raw.get("call_during_final_work",false) and not raw.get("retain_after_take",false)): return _error("early pickup call requires retained waiting")
	var seen := {}
	for port in raw.ports:
		if not port is String or not port.begins_with("wait:"+raw.group+"/") or seen.has(port): return _error("invalid or repeated waiting seat port")
		seen[port] = true
	seen = {}
	for point in raw.line:
		if not point is Vector2 or not point.is_finite() or seen.has(point): return _error("invalid or repeated waiting line point")
		seen[point] = true
	for stage in raw.stages:
		if not Inventory._shape(stage,{"standing":0,"seats":0}) or stage.standing<1 or stage.standing>raw.line.size() or stage.seats<0 or stage.seats>raw.ports.size(): return _error("invalid waiting stage limits")
	var result: Dictionary = raw.duplicate(true)
	result.retain_after_take = raw.get("retain_after_take",false)
	return {"definition":result,"error":""}

func ports() -> Dictionary:
	var result := {}
	for index in _definition.line.size(): result["waiting_line:"+str(index)] = _definition.line[index]
	return result

func validate(owner: RefCounted, customers: RefCounted) -> String:
	if owner.stage_index<0 or owner.stage_index>=_definition.stages.size(): return "outer stage is outside waiting declaration"
	var group: SpecSeatGroup
	for candidate in owner.shop.seat_groups:
		if candidate.id == _definition.group: group = candidate; break
	if group == null or group.purpose != "wait": return "waiting policy references an unknown waiting purchase group"
	var count: Variant = owner.seats.get(_definition.group,0)
	if not count is int or count<0 or count>_definition.ports.size(): return "owned waiting seats exceed declared ports"
	for port in _definition.ports:
		var target: Dictionary = customers._target(port)
		if not target.error.is_empty(): return target.error
	return ""

func seat_limit(owner: RefCounted) -> int:
	return mini(int(owner.seats.get(_definition.group,0)),int(_definition.stages[owner.stage_index].seats))

func capacity(owner: RefCounted, orders: Dictionary) -> int:
	var seats := seat_limit(owner)
	var retained := 0
	for row in _state.leases:
		if _definition.ports.find(row.port)>=seats: retained += 1
	var accepted := 0
	if _definition.retain_after_take:
		for guest in orders.guests:
			if guest.state == "waiting": accepted += 1
	return maxi(0,mini(int(_definition.stages[owner.stage_index].standing)+seats,_definition.line.size()+seats+retained-accepted))

func _eligible(guest: Dictionary) -> bool:
	return guest.state == "queue" or (_definition.retain_after_take and guest.state == "waiting")

func _ordered(orders: Dictionary) -> Array:
	var result: Array = []
	if _definition.retain_after_take:
		for guest in orders.guests:
			if guest.state == "waiting": result.append(guest)
	for guest in orders.guests:
		if guest.state == "queue": result.append(guest)
	return result

func sync(owner: RefCounted, orders: Dictionary, called: Dictionary, automatic: bool) -> Dictionary:
	var guests := {}
	for guest in orders.guests: guests[guest.id] = guest
	var leases: Array = _state.leases.filter(func(row: Dictionary) -> bool: return guests.has(row.guest) and _eligible(guests[row.guest]))
	var occupied := {}
	var assigned := {}
	for row in leases: occupied[row.port] = true; assigned[row.guest] = true
	var queued := 0
	var standing: int = _definition.stages[owner.stage_index].standing
	for guest in _ordered(orders):
		var needs_seat: bool = guest.state == "waiting" or queued>=standing
		if guest.state == "queue": queued += 1
		if assigned.has(guest.id) or not needs_seat: continue
		for index in seat_limit(owner):
			var port: String = _definition.ports[index]
			if occupied.has(port): continue
			leases.append({"guest":int(guest.id),"port":port})
			occupied[port] = true
			break
	var projected := _project(orders,called,automatic,leases)
	if projected.error.is_empty(): _state.leases = leases
	return projected

func targets(orders: Dictionary, called: Dictionary, automatic: bool) -> Dictionary:
	return _project(orders,called,automatic,_state.leases)

func _project(orders: Dictionary, called: Dictionary, automatic: bool, leases: Array) -> Dictionary:
	var seats := {}
	for row in leases: seats[row.guest] = row.port
	var targets := {}
	var line := 0
	var queued := 0
	for guest in _ordered(orders):
		var target: String = seats.get(guest.id,"")
		if target.is_empty():
			if line>=_definition.line.size(): return {"error":"waiting line has no declared physical port","targets":{}}
			target = "waiting_line:"+str(line)
			line += 1
		if guest.state == "queue":
			if guest.claimed>0 and queued!=0: return {"error":"only queue head may hold an admission claim","targets":{}}
			if guest.claimed>0 or (automatic and queued==0): target = "queue:0"
			queued += 1
		elif called.has(guest.id): target = "pickup"
		targets[guest.id] = target
	return {"error":"","targets":targets}

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func restore(data: Variant, orders: Dictionary, called: Dictionary, automatic: bool) -> String:
	if not Inventory._shape(data,{"version":0,"leases":[]}) or data.version!=1: return "invalid waiting lease state"
	var guests := {}
	for guest in orders.guests: guests[guest.id] = guest
	var seen_guests := {}
	var seen_ports := {}
	for row in data.leases:
		if not Inventory._shape(row,{"guest":0,"port":""}) or not guests.has(row.guest) or not _eligible(guests[row.guest]) or row.port not in _definition.ports or seen_guests.has(row.guest) or seen_ports.has(row.port): return "invalid, duplicate or orphan waiting lease"
		seen_guests[row.guest] = true
		seen_ports[row.port] = true
	var projected := _project(orders,called,automatic,data.leases)
	if not projected.error.is_empty(): return projected.error
	_state = data.duplicate(true)
	return ""

static func _error(message: String) -> Dictionary:
	return {"definition":{},"error":message}
