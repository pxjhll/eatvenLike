extends RefCounted
## Optional purchased seat availability and stage queue/meal values. Orders
## alone owns leases, Customers owns paths; no second seat runtime is stored.
const Inventory := preload("res://game/rules/template/inventory.gd")
const Numbers := preload("res://game/rules/rule_numbers.gd")
var _definition: Dictionary

func _init(definition: Dictionary) -> void:
	_definition = definition.duplicate(true)

static func compile(raw: Variant, seats: Dictionary) -> Dictionary:
	if not raw is Dictionary: return _error("invalid seating declaration")
	if raw.is_empty(): return {"definition":{},"error":""}
	if raw.size()!=3 or not raw.get("group") is String or raw.group.is_empty() or not raw.get("order") is Array or raw.order.is_empty() or raw.order.size()!=seats.size() or not raw.get("stages") is Array or raw.stages.is_empty(): return _error("seating needs purchase group, all ordered seats and stages")
	for index in raw.order.size():
		if not raw.order[index] is String or raw.order[index]!="seat:"+raw.group+"/"+str(index) or not seats.has(raw.order[index]): return _error("invalid purchased seat order")
	for stage in raw.stages:
		if not stage is Dictionary or stage.size()!=2 or not stage.get("standing") is int or stage.standing<1 or not (stage.get("seconds") is float or stage.get("seconds") is int) or not is_finite(float(stage.seconds)) or stage.seconds<0.0: return _error("invalid seating stage")
	return {"definition":raw.duplicate(true),"error":""}

func validate(owner: RefCounted, orders: Dictionary = {}) -> String:
	if owner.stage_index<0 or owner.stage_index>=_definition.stages.size(): return "outer stage outside seating declaration"
	var found := false
	for group in owner.shop.seat_groups:
		if group.id!=_definition.group or group.purpose!="dine": continue
		var full: int = group.start+group.step*group.costs.size()
		if not group.steps.is_empty():
			full = group.start
			for step in group.steps: full += int(step)
		if full!=_definition.order.size(): return "seating declaration differs from purchase group capacity"
		found = true
	if not found: return "unknown dining seat purchase group"
	var count: Variant = owner.seats.get(_definition.group,0)
	if not count is int or count<0 or count>_definition.order.size(): return "owned seats exceed declared seating ports"
	for stage in _definition.stages:
		if stage.standing>owner.nav.layout.customer_queue.size(): return "seating queue exceeds physical ports"
	if not is_finite(seconds(owner)): return "invalid effective seating meal duration"
	for guest in orders.get("guests",[]):
		if guest.state not in ["leaving","gone"] and not guest.seat.is_empty() and guest.seat not in seats(owner): return "customer leases an unowned seat"
	return ""

func seats(owner: RefCounted) -> Array:
	return _definition.order.slice(0,int(owner.seats.get(_definition.group,0)))

func capacity(owner: RefCounted) -> int:
	return int(_definition.stages[owner.stage_index].standing)

func seconds(owner: RefCounted) -> float:
	return float(_definition.stages[owner.stage_index].seconds)*Numbers.tuned(owner.tune,"seat")

static func _error(message: String) -> Dictionary:
	return {"definition":{},"error":message}
