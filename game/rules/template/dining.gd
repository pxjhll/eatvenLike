extends RefCounted
## Counter receipt followed by dining or takeaway. Orders alone holds seat
## leases; this optional policy records only the committed route choice.
const Requirements := preload("res://game/rules/template/requirements.gd")
const Inventory := preload("res://game/rules/template/inventory.gd")
const Numbers := preload("res://game/rules/rule_numbers.gd")
var _definition: Dictionary
var _routes: Array = []

func _init(definition: Dictionary) -> void:
	_definition = definition.duplicate(true)

static func compile(raw: Variant, seats: Dictionary, menu: Dictionary, recipes: Dictionary) -> Dictionary:
	if not raw is Dictionary: return _error("invalid dining policy")
	if raw.is_empty(): return {"definition":{},"error":""}
	for key in raw:
		if key not in ["group","order","stages","takeaway"]: return _error("unsupported dining parameter")
	if not seats.is_empty() or not raw.get("group") is String or raw.group.is_empty() or not raw.get("order") is Array or raw.order.is_empty() or not raw.get("stages") is Array or raw.stages.is_empty(): return _error("counter dining needs purchase group, ordered customer seats and stages, without table service ports")
	var seen := {}
	for index in raw.order.size():
		var id: Variant = raw.order[index]
		if not id is String or id!="seat:"+raw.group+"/"+str(index) or seen.has(id): return _error("invalid dining seat order")
		seen[id] = true
	for stage in raw.stages:
		if not stage is Dictionary or stage.size()!=2 or not stage.get("standing") is int or stage.standing<1 or not (stage.get("seconds") is float or stage.get("seconds") is int) or not is_finite(float(stage.seconds)) or stage.seconds<0.0: return _error("invalid dining stage")
	var takeaway: Variant = raw.get("takeaway",{})
	if not takeaway is Dictionary: return _error("invalid takeaway policy")
	var result: Dictionary = raw.duplicate(true)
	result.takeaway = {}
	if not takeaway.is_empty():
		if takeaway.size()!=2 or not takeaway.get("requires") is Dictionary or takeaway.requires.is_empty() or not takeaway.get("variants") is Dictionary: return _error("takeaway needs explicit gate and recipe variants")
		var requirement := Requirements.compile(takeaway.requires)
		if not requirement.error.is_empty(): return requirement
		for dish in takeaway.variants:
			if not menu.has(dish) or not takeaway.variants[dish] is String or not recipes.has(takeaway.variants[dish]) or recipes[takeaway.variants[dish]].output.count!=1: return _error("invalid takeaway recipe binding")
		result.takeaway = {"requires":requirement.definition,"variants":takeaway.variants.duplicate()}
	return {"definition":result,"error":""}

func validate(owner: RefCounted, state: Dictionary = {}) -> String:
	if owner.stage_index<0 or owner.stage_index>=_definition.stages.size(): return "outer stage outside dining declaration"
	var found := false
	for group in owner.shop.seat_groups:
		if group.id==_definition.group and group.purpose=="dine":
			var total: int = group.start+group.step*group.costs.size()
			if not group.steps.is_empty():
				total = group.start
				for step in group.steps: total += int(step)
			if total!=_definition.order.size(): return "dining declaration does not cover purchased seat capacity"
			found = true
	if not found: return "unknown dining purchase group"
	var count: Variant = owner.seats.get(_definition.group,0)
	if not count is int or count<0 or count>_definition.order.size(): return "owned dining seats exceed declared ports"
	if not is_finite(seconds(owner)): return "invalid effective dining duration"
	for stage in _definition.stages:
		if stage.standing>owner.nav.layout.customer_queue.size(): return "dining standing capacity exceeds physical queue ports"
	if not _definition.takeaway.is_empty():
		var error := Requirements.reference_error(_definition.takeaway.requires,owner)
		if not error.is_empty(): return error
	for guest in state.get("guests",[]):
		if guest.state not in ["leaving","gone"] and not guest.seat.is_empty() and guest.seat not in seats(owner): return "customer leases an unowned dining seat"
		var maximum := 0.0
		for stage in _definition.stages: maximum = maxf(maximum,float(stage.seconds)*Numbers.TUNING_MAX)
		if guest.meal_left>maximum: return "meal clock exceeds all declared stages and tuning limits"
	return ""

func seats(owner: RefCounted) -> Array:
	return _definition.order.slice(0,int(owner.seats.get(_definition.group,0)))

func declared_seats() -> Array:
	return _definition.order.duplicate()

func takeaway_open(owner: RefCounted) -> bool:
	return not _definition.takeaway.is_empty() and Requirements.met(_definition.takeaway.requires,owner)

func recipe(dish: String, base: String, takeaway: bool) -> String:
	return String(_definition.takeaway.variants.get(dish,base)) if takeaway else base

func capacity(owner: RefCounted, state: Dictionary) -> int:
	var seated := 0
	for guest in state.guests:
		if guest.queued and not guest.seat.is_empty(): seated += 1
	return int(_definition.stages[owner.stage_index].standing)+seated

func seconds(owner: RefCounted) -> float:
	return float(_definition.stages[owner.stage_index].seconds)*Numbers.tuned(owner.tune,"seat")

func record(id: int, takeaway: bool) -> void:
	_routes.append({"guest":id,"takeaway":takeaway})

func route(id: int) -> Dictionary:
	for entry in _routes:
		if entry.guest==id: return entry.duplicate()
	return {}

func targets(state: Dictionary, called: Dictionary) -> Dictionary:
	var result := {}
	var line := 0
	for guest in state.guests:
		if guest.state not in ["queue","waiting"]: continue
		var target: String = guest.seat
		if target.is_empty(): target = "queue:"+str(line); line += 1
		if called.has(guest.id): target = "pickup"
		result[guest.id] = target
	return result

func snapshot() -> Dictionary:
	return {"version":1,"routes":_routes.duplicate(true)}

func restore(data: Dictionary, state: Dictionary, owner: RefCounted) -> String:
	if not Inventory._shape(data,{"version":0,"routes":[]}) or data.version!=1: return "invalid dining route state"
	var routes := {}
	for row in data.routes:
		if not Inventory._shape(row,{"guest":0,"takeaway":false}) or row.guest<1 or routes.has(row.guest): return "invalid or repeated dining route"
		routes[row.guest] = row
	var accepted := 0
	for guest in state.guests:
		if guest.order<1:
			if routes.has(guest.id) or not guest.seat.is_empty(): return "pending customer has a committed route or seat"
			continue
		accepted += 1
		if not routes.has(guest.id): return "accepted customer has no dining route"
		if routes[guest.id].takeaway != guest.seat.is_empty() or (routes[guest.id].takeaway and _definition.takeaway.is_empty()): return "customer seat differs from committed route"
	if accepted!=routes.size(): return "orphan dining route"
	var error := validate(owner,state)
	if not error.is_empty(): return error
	_routes = data.routes.duplicate(true)
	return ""

static func _error(message: String) -> Dictionary:
	return {"definition":{},"error":message}
