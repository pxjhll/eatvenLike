extends RefCounted
const Orders := preload("res://game/rules/template/orders.gd")
const Arrivals := preload("res://game/rules/template/arrivals.gd")
const Customization := preload("res://game/rules/template/customization.gd")
const Selection := preload("res://game/rules/template/menu_selection.gd")
const Waiting := preload("res://game/rules/template/waiting.gd")
const Flyers := preload("res://game/rules/template/flyers.gd")

const DEFAULTS := {"menu":{}, "admission":"automatic", "admission_port":"", "admission_seconds":0.6,
	"admission_roles":[], "delivery":"counter", "delivery_roles":[], "handoff_port":"", "pickup":"",
	"customer_capacity":2, "seats":{}, "eat_seconds":3.0, "orders":{}, "arrivals":{}}

static func compile(raw: Dictionary, places: Dictionary, recipes: Dictionary) -> Dictionary:
	if raw.is_empty(): return {"definition":{}, "error":""}
	var result := DEFAULTS.duplicate(true)
	for key in raw:
		if key in ["customization","selection","delivery_ready","waiting","flyers"]: continue
		if not result.has(key): return _error("unsupported service parameter: " + str(key))
		result[key] = raw[key]
	for key in ["admission", "delivery", "admission_port", "handoff_port", "pickup"]:
		if not result[key] is String: return _error("invalid service policy")
	if result.admission not in ["automatic", "employee"] or result.delivery not in ["counter", "self_pickup", "table"]: return _error("unsupported public service policy")
	var readiness: Variant = raw.get("delivery_ready","")
	if not readiness is String or readiness not in ["","whole_order"]: return _error("invalid delivery readiness policy")
	if not readiness.is_empty():
		if result.delivery == "self_pickup": return _error("self pickup already requires the whole order")
		result.delivery_ready = readiness
	for key in ["admission_seconds", "eat_seconds"]:
		if not (result[key] is int or result[key] is float) or not is_finite(float(result[key])) or result[key] < 0.0: return _error("invalid service duration")
		result[key] = float(result[key])
	for key in ["admission_roles", "delivery_roles"]:
		if not result[key] is Array: return _error("invalid service role list")
		var seen := {}
		for role in result[key]:
			if not role is String or role.is_empty() or seen.has(role): return _error("invalid service role")
			seen[role] = true
	if not result.customer_capacity is int or result.customer_capacity < 1: return _error("invalid customer carry capacity")
	if not result.menu is Dictionary or result.menu.is_empty(): return _error("missing service menu")
	for dish in result.menu:
		var recipe: Variant = result.menu[dish]
		if not dish is String or dish.is_empty() or not recipe is String or not recipes.has(recipe): return _error("invalid menu recipe binding")
		if recipes[recipe].output.count != 1: return _error("service menu requires one product per recipe unit")
	if not result.orders is Dictionary: return _error("invalid order policy")
	var orders := Orders.new(result.orders)
	if not orders.last_error.is_empty(): return _error(orders.last_error)
	result.orders = orders._policy.duplicate(true)
	var customization := Customization.compile(raw.get("customization",{}),result.menu,recipes,result.orders.rounding)
	if not customization.error.is_empty(): return customization
	if not customization.definition.is_empty(): result.customization = customization.definition
	var selection := Selection.compile(raw.get("selection",{}),result.menu)
	if not selection.error.is_empty(): return selection
	if not selection.definition.is_empty(): result.selection = selection.definition
	var waiting := Waiting.compile(raw.get("waiting",{}))
	if not waiting.error.is_empty(): return waiting
	if not waiting.definition.is_empty():
		if result.orders.queue_release != "after_take" or (waiting.definition.retain_after_take and result.delivery != "counter"): return _error("waiting retention requires after-take queue release and counter delivery")
		result.waiting = waiting.definition
	if result.has("selection") and result.delivery == "self_pickup" and not result.selection.addon.is_empty() and result.selection.addon.share>0.0 and result.customer_capacity<2: return _error("selected addon exceeds whole pickup capacity")
	for key in ["admission_port", "handoff_port", "pickup"]:
		var required: bool = (key == "admission_port" and result.admission == "employee") or (key == "handoff_port" and result.delivery == "counter") or (key == "pickup" and result.delivery == "self_pickup")
		if required and not places.has(result[key]): return _error("missing service port: " + key)
		if not required and not result[key].is_empty(): return _error("unused service port: " + key)
	if not result.seats is Dictionary or (result.delivery == "table" and result.seats.is_empty()) or (result.delivery == "counter" and not result.seats.is_empty()): return _error("invalid service seats")
	var seat_ports := {}
	for seat in result.seats:
		if not seat is String or not seat.begins_with("seat:") or seat.length() <= 5 or not result.seats[seat] is String or not places.has(result.seats[seat]) or seat_ports.has(result.seats[seat]): return _error("invalid or reused table port")
		seat_ports[result.seats[seat]] = true
	for place in places:
		if String(place).begins_with("guest:"): return _error("guest containers are managed by service")
	if not result.arrivals is Dictionary: return _error("invalid arrival definition")
	var arrivals := Arrivals.compile(result.arrivals, result.menu, int(result.customer_capacity) if result.delivery == "self_pickup" else -1,result.has("selection"))
	if not String(arrivals.error).is_empty(): return arrivals
	result.arrivals = arrivals.definition
	var flyers := Flyers.compile(raw.get("flyers",{}))
	if not flyers.error.is_empty(): return flyers
	if not flyers.definition.is_empty():
		if result.arrivals.is_empty(): return _error("flyers require the common automatic request selection capability")
		result.flyers = flyers.definition
	return {"definition":result, "error":""}

static func _error(message: String) -> Dictionary:
	return {"definition":{}, "error":message}
