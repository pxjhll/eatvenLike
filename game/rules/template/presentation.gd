extends RefCounted
## Explicit display declarations. Geometry is supplied by the scene as plain
## data; projections never own stock, movement, meal or transport clocks.
const Inventory := preload("res://game/rules/template/inventory.gd")

static func compile(raw: Dictionary, places: Dictionary, service: Dictionary, transports: Dictionary = {}) -> Dictionary:
	if raw.is_empty(): return {"error":"","definition":{}}
	for key in raw:
		if key not in ["stock","counters","dining","poses","conveyors"]: return _error("unknown presentation parameter: "+str(key))
	var result := {"stock":[],"counters":{},"dining":{},"poses":{},"conveyors":{}}
	for key in result:
		if raw.has(key) and typeof(raw[key])!=typeof(result[key]): return _error("invalid presentation section")
		result[key] = raw.get(key,result[key]).duplicate(true)
	var occupied := {}
	for binding in result.stock:
		if not Inventory._shape(binding,{"places":[],"ports":[],"host":"","height":0.0}) or not _places(binding.places,places) or binding.ports.is_empty() or not _height(binding.height): return _error("invalid stock showcase")
		for port in binding.ports:
			if not port is String or port.is_empty() or occupied.has(port): return _error("duplicate or missing showcase port")
			occupied[port] = true
	for id in result.counters:
		if not id is String or id.is_empty() or not _places(result.counters[id],places): return _error("invalid stock counter")
	var seats: Array = service.get("dining",{}).get("order",service.get("seats",{}).keys()).duplicate()
	seats.append_array(service.get("waiting",{}).get("ports",[]))
	for seat in result.dining:
		var binding: Variant = result.dining[seat]
		if seat not in seats or not String(seat).begins_with("seat:") or not Inventory._shape(binding,{"port":"","offsets":[],"host":"","height":0.0}) or binding.port.is_empty() or binding.offsets.is_empty() or not _height(binding.height): return _error("invalid dining display")
		var seen := {}
		for point in binding.offsets:
			if not point is Vector2 or not point.is_finite() or seen.has(point): return _error("invalid dining offset")
			seen[point] = true
	for seat in result.poses:
		var binding: Variant = result.poses[seat]
		if seat not in seats or not Inventory._shape(binding,{"port":"","offset":Vector2.ZERO,"facing":0}) or binding.port.is_empty() or not binding.offset.is_finite() or binding.facing<0 or binding.facing>7: return _error("invalid seated pose")
	for id in result.conveyors:
		var binding: Variant = result.conveyors[id]
		if not transports.has(id) or not Inventory._shape(binding,{"path":[],"host":"","height":0.0}) or binding.path.size()<2 or not _height(binding.height): return _error("invalid conveyor display")
		for port in binding.path:
			if not port is String or port.is_empty(): return _error("invalid conveyor path")
	return {"error":"","definition":result}

static func port_names(definition: Dictionary) -> Array:
	var result: Array = []
	for binding in definition.get("stock",[]): result.append_array(binding.ports)
	for binding in definition.get("dining",{}).values()+definition.get("poses",{}).values(): result.append(binding.port)
	for binding in definition.get("conveyors",{}).values(): result.append_array(binding.path)
	return result

static func host_names(definition: Dictionary) -> Array:
	var result: Array = []
	for binding in definition.get("stock",[])+definition.get("dining",{}).values()+definition.get("conveyors",{}).values():
		if not binding.host.is_empty(): result.append(binding.host)
	return result

static func resolve(definition: Dictionary, geometry: Dictionary) -> Dictionary:
	if definition.is_empty(): return {"error":"","definition":{}}
	if not geometry.get("ports") is Dictionary or not geometry.get("hosts") is Array: return _error("presentation requires scene geometry")
	for port in port_names(definition):
		if not geometry.ports.get(port) is Vector2 or not geometry.ports[port].is_finite(): return _error("missing display port: "+str(port))
	for host in host_names(definition):
		if host not in geometry.hosts: return _error("missing display host: "+host)
	var result: Dictionary = definition.duplicate(true)
	result.stock = []
	for binding in definition.stock:
		var points: Array = []
		for port in binding.ports: points.append(geometry.ports[port])
		result.stock.append({"capability":"stock_showcase","places":binding.places.duplicate(),"points":points,"host":binding.host,"height":binding.height})
	for binding in result.dining.values():
		binding.points = []
		for offset in binding.offsets: binding.points.append(geometry.ports[binding.port]+offset)
	for binding in result.poses.values(): binding.pos = geometry.ports[binding.port]+binding.offset
	for binding in result.conveyors.values():
		binding.points = []
		for port in binding.path: binding.points.append(geometry.ports[port])
	return {"error":"","definition":result}

static func project(frame: Dictionary, definition: Dictionary) -> void:
	frame.counters = {}
	for id in definition.get("counters",{}):
		var counts := {"count":0,"reserved":0,"available":0}
		for place in definition.counters[id]:
			for field in counts: counts[field] += int(frame.stock[place][field])
		frame.counters[id] = counts
	for row in frame.movement.customers.values():
		if row.seated and definition.get("poses",{}).has(row.seat_key):
			row.render_pos = definition.poses[row.seat_key].pos
			row.facing = definition.poses[row.seat_key].facing
		if not row.seated or row.state!="eating" or not definition.get("dining",{}).has(row.seat_key): continue
		var binding: Dictionary = definition.dining[row.seat_key]
		var stock: Dictionary = frame.stock.get("guest:"+str(row.id),{"items":{}})
		var index := 0
		for item in stock.items:
			for unused in mini(stock.items[item].count,binding.points.size()-index):
				frame.draws.append({"capability":"dining_item","guest":row.id,"item":item,"pos":binding.points[index],"host":binding.host,"height":binding.height})
				index += 1
	for flight in frame.get("transports",[]):
		if not definition.get("conveyors",{}).has(flight.route): continue
		var binding: Dictionary = definition.conveyors[flight.route]
		var point := along(binding.points,flight.progress)
		for item in flight.items: frame.draws.append({"capability":"transport_item","bundle":flight.bundle,"item":item.item,"pos":point,"host":binding.host,"height":binding.height})

static func along(points: Array, progress: float) -> Vector2:
	var length := 0.0
	for index in range(1,points.size()): length += Vector2(points[index-1]).distance_to(points[index])
	var remaining := length*clampf(progress,0.0,1.0)
	for index in range(1,points.size()):
		var distance := Vector2(points[index-1]).distance_to(points[index])
		if remaining<=distance: return Vector2(points[index-1]).lerp(points[index],remaining/maxf(distance,0.000001))
		remaining -= distance
	return points[-1]

static func _places(ids: Variant, places: Dictionary) -> bool:
	if not ids is Array or ids.is_empty(): return false
	var seen := {}
	for id in ids:
		if not id is String or not places.has(id) or Inventory.is_hand_place(id) or seen.has(id): return false
		seen[id] = true
	return true

static func _height(value: float) -> bool:
	return is_finite(value) and value>0.0

static func _error(message: String) -> Dictionary:
	return {"error":message,"definition":{}}
