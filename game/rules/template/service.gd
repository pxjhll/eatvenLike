extends RefCounted
## Compose order facts, movement and inventory capabilities. Service policies
## choose ports and public actions; no shop supplies its own execution code.
const Orders := preload("res://game/rules/template/orders.gd")
const Customers := preload("res://game/rules/template/customers.gd")
const Inventory := preload("res://game/rules/template/inventory.gd")
const Arrivals := preload("res://game/rules/template/arrivals.gd")
const Numbers := preload("res://game/rules/rule_numbers.gd")
const Customization := preload("res://game/rules/template/customization.gd")
const Selection := preload("res://game/rules/template/menu_selection.gd")
const Waiting := preload("res://game/rules/template/waiting.gd")
const Flyers := preload("res://game/rules/template/flyers.gd")
const Ramp := preload("res://game/rules/template/menu_ramp.gd")
const Dining := preload("res://game/rules/template/dining.gd")
const Seating := preload("res://game/rules/template/seating.gd")
const PickupQueue := preload("res://game/rules/template/pickup_queue.gd")

var orders: RefCounted
var customers: RefCounted
var arrivals: RefCounted
var waiting: RefCounted
var flyers: RefCounted
var ramp: RefCounted
var dining: RefCounted
var seating: RefCounted
var pickup_queue: RefCounted
var last_error := ""
var _runtime_ref: WeakRef
var _runtime: RefCounted:
	get: return _runtime_ref.get_ref()
var _policy: Dictionary
var _deliveries: Array = []

func _init(runtime: RefCounted, policy: Dictionary) -> void:
	_runtime_ref = weakref(runtime)
	_policy = policy.duplicate(true)
	orders = Orders.new(policy.orders)
	if policy.has("dining"): dining = Dining.new(policy.dining)
	if policy.has("seating"): seating = Seating.new(policy.seating)
	if policy.has("pickup_queue"): pickup_queue = PickupQueue.new(policy.pickup_queue)
	if policy.has("waiting"): waiting = Waiting.new(policy.waiting)
	customers = Customers.new(runtime.runner.owner.nav,waiting.ports() if waiting != null else {})
	last_error = orders.last_error if not orders.last_error.is_empty() else customers.last_error
	if not last_error.is_empty(): return
	for target in ["entrance", "exit", "pickup", "queue:0"] + (dining.declared_seats() if dining!=null else policy.seats.keys()):
		var resolved: Dictionary = customers._target(target)
		if not String(resolved.error).is_empty(): last_error = resolved.error; return
	for dish in policy.menu:
		var found := false
		for definition in runtime.runner.owner.shop.dishes:
			if definition.id == dish: found = true; break
		if not found: last_error = "service menu has no shared dish quote"; return
	for role in policy.admission_roles + policy.delivery_roles:
		if not runtime.runner.owner.shop.layout.actor_areas.has(role): last_error = "service role has no declared access profile"; return
	for option in policy.get("customization",{}).get("options",[]):
		if runtime.runner.owner.shop.station(option.unlock) == null: last_error = "option unlock has no declared station"; return
	if not policy.arrivals.is_empty(): arrivals = Arrivals.new(policy.arrivals)
	if policy.has("flyers"): flyers = Flyers.new(policy.flyers)
	if policy.get("selection",{}).has("ramp"): ramp = Ramp.new(policy.selection.ramp,policy.selection.order)
	if policy.has("selection"): last_error = Selection.validate(policy.selection,runtime.runner.owner)
	if last_error.is_empty() and waiting != null: last_error = waiting.validate(runtime.runner.owner,customers)
	if last_error.is_empty() and flyers != null: last_error = flyers.values(runtime.runner.owner.mods).error
	if last_error.is_empty() and dining != null: last_error = dining.validate(runtime.runner.owner)
	if last_error.is_empty() and seating != null: last_error = seating.validate(runtime.runner.owner)
	if last_error.is_empty() and pickup_queue != null: last_error = pickup_queue.validate(customers)

func set_open(value: bool) -> String:
	if arrivals == null: return "template has no automatic arrival capability"
	var context_error := validate_context()
	if not context_error.is_empty(): return context_error
	for index in arrivals.set_open(value):
		var result := _automatic_arrival()
		if result not in ["", "queue full"]: return result
	return ""

func _automatic_arrival() -> String:
	if orders.queue().size() >= queue_capacity(): return String(_reject_arrival().error)
	if _deferred(): return String(arrive([]).error)
	var request: Array = Selection.request(_policy.selection,_runtime.runner.owner,ramp.counts() if ramp!=null else {}) if _policy.has("selection") else arrivals.request(_runtime.runner.owner.rng)
	if request.is_empty(): return ""
	var result: Dictionary = arrive(request)
	return result.error

func _advance_arrivals(dt: float) -> String:
	if arrivals == null: return ""
	if flyers != null:
		var flyer_error: String = flyers.advance(dt,arrivals.snapshot().open)
		if not flyer_error.is_empty(): return flyer_error
		if arrivals.snapshot().open and flyers.due(_runtime.runner.owner.mods):
			var menu_open: bool = _deferred() or not _policy.has("selection") or not menu_weights().is_empty()
			var full: bool = orders.queue().size()>=queue_capacity()
			if menu_open and (not full or not flyers.waits_outside()):
				flyers.consume()
				flyer_error = _automatic_arrival()
				if flyer_error not in ["","queue full"]: return flyer_error
	var error: String = arrivals.advance(dt)
	if not error.is_empty(): return error
	var count := 0
	while arrivals.due():
		count += 1
		if count > 10000: return "arrival schedule exceeds supported events per step"
		var owner: RefCounted = _runtime.runner.owner
		var interval: float = _policy.selection.stages[owner.stage_index].interval if _policy.has("selection") else _policy.arrivals.interval
		var mean := Numbers.flow_interval(interval, flow_multiplier(), owner.tune)
		error = arrivals.schedule_next(mean, owner.rng)
		if not error.is_empty(): return error
		error = _automatic_arrival()
		if error not in ["", "queue full"]: return error
	return ""

func arrive(request: Array, selected_options: Variant = null) -> Dictionary:
	if not last_error.is_empty(): return {"error":last_error, "id":-1}
	var context_error := validate_context()
	if not context_error.is_empty(): return {"error":context_error,"id":-1}
	if _deferred():
		if not request.is_empty() or selected_options!=null: return {"error":"food and options are selected at admission","id":-1}
		return _enqueue([])
	var rows: Array = []
	var total := 0
	for row in request:
		if not row is Dictionary or row.size() != 2 or not row.get("dish") is String or not row.get("qty") is int or row.qty < 1 or not _policy.menu.has(row.dish): return {"error":"invalid service order request", "id":-1}
		if _policy.has("selection") and not Selection.eligible(_policy.selection,row.dish,_runtime.runner.owner): return {"error":"service dish requirements are not met","id":-1}
		var recipe: String = _policy.menu[row.dish]
		var output: Dictionary = _runtime._definition.recipes[recipe].output
		rows.append({"dish":String(row.dish), "recipe":recipe, "item":String(output.item), "qty":int(row.qty)})
		total += int(row.qty)
	if rows.is_empty() or (_policy.delivery == "self_pickup" and total > int(_policy.customer_capacity)): return {"error":"order exceeds whole pickup capacity", "id":-1}
	if not _policy.has("customization") and selected_options != null and (not selected_options is Array or not selected_options.is_empty()): return {"error":"template has no order option capability","id":-1}
	var choice: Dictionary = {}
	if _policy.has("customization") and selected_options != null:
		choice = Customization.select(_policy.customization,rows[0].dish,rows[0].recipe,selected_options,_runtime.runner.owner)
		if not choice.error.is_empty(): return {"error":choice.error,"id":-1}
	if orders.queue().size() >= queue_capacity(): return _reject_arrival()
	if _policy.has("customization"):
		if choice.is_empty(): choice = Customization.select(_policy.customization,rows[0].dish,rows[0].recipe,selected_options,_runtime.runner.owner)
		if not choice.error.is_empty(): return {"error":choice.error,"id":-1}
		rows[0].options = choice.ids
		rows[0].recipe = choice.recipe
		rows[0].item = String(_runtime._definition.recipes[choice.recipe].output.item)
	return _enqueue(rows)

func _reject_arrival() -> Dictionary:
	var result: Dictionary = orders.reject_arrival()
	_runtime.runner.owner.events.emit("lost",{})
	return result

func _deferred() -> bool:
	return _policy.get("selection",{}).get("at")=="admission"

func _menu_ready() -> bool:
	return not _deferred() or not menu_weights().is_empty()

func _enqueue(rows: Array) -> Dictionary:
	var admitted: Dictionary = orders.arrive(rows, queue_capacity())
	if not String(admitted.error).is_empty(): return admitted
	if ramp != null and not _deferred(): ramp.admitted(menu_weights())
	last_error = customers.spawn(admitted.id)
	if last_error.is_empty() and dining != null: last_error = _admit()
	if last_error.is_empty(): last_error = _sync_queue()
	if last_error.is_empty(): _runtime.runner.owner.events.emit("arrived",{"guest":int(admitted.id)})
	return admitted if last_error.is_empty() else {"error":last_error, "id":-1}

func validate_context() -> String:
	var error: String = Selection.validate(_policy.selection,_runtime.runner.owner) if _policy.has("selection") else ""
	if error.is_empty() and waiting != null: error = waiting.validate(_runtime.runner.owner,customers)
	if error.is_empty() and flyers != null: error = flyers.values(_runtime.runner.owner.mods).error
	if error.is_empty() and dining != null: error = dining.validate(_runtime.runner.owner,orders.active_snapshot())
	if error.is_empty() and seating != null: error = seating.validate(_runtime.runner.owner,orders.active_snapshot())
	if error.is_empty() and pickup_queue != null:
		error = pickup_queue.validate(customers)
		if error.is_empty(): error = pickup_queue.targets(orders.active_snapshot(),_deliveries).error
	return error

func send_flyers() -> String:
	if flyers == null: return "template has no flyer capability"
	var error := validate_context()
	if not error.is_empty(): return error
	return flyers.send(arrivals.snapshot().open,_runtime.runner.owner.mods)

func queue_capacity() -> int:
	if dining != null: return dining.capacity(_runtime.runner.owner,orders.active_snapshot())
	if seating != null: return seating.capacity(_runtime.runner.owner)
	return waiting.capacity(_runtime.runner.owner,orders.active_snapshot()) if waiting != null else _runtime.runner.owner.nav.layout.customer_queue.size()

func menu_weights() -> Dictionary:
	return Selection.weights(_policy.selection,_runtime.runner.owner,ramp.counts() if ramp!=null else {}) if _policy.has("selection") else {}

func flow_multiplier() -> float:
	return Selection.flow_multiplier(_policy.selection,_runtime.runner.owner) if _policy.has("selection") else float(_runtime.runner.owner.mods.value("flow",1.0))

func advance(dt: float) -> String:
	if not last_error.is_empty(): return last_error
	if _policy.has("selection"):
		var selection_error := validate_context()
		if not selection_error.is_empty(): return selection_error
	var error := _advance_arrivals(dt)
	if not error.is_empty(): return error
	error = customers.advance(dt)
	if not error.is_empty(): return error
	var loss_before: int = orders.active_snapshot().lost
	error = orders.advance(dt)
	if not error.is_empty(): return error
	for unused in int(orders.active_snapshot().lost)-loss_before: _runtime.runner.owner.events.emit("lost",{})
	for event in _runtime.runner.take_interactions():
		var guest: Dictionary = orders.guest(event.subject)
		if guest.is_empty() or guest.claimed != event.worker or event.purpose != "admit": return "interaction has no admission claim"
		if event.result == "completed": error = _accept(guest.id, event.worker)
		else: error = orders.cancel_admission(guest.id, event.worker)
		if not error.is_empty(): return error
	error = _reconcile_deliveries(dt)
	if not error.is_empty(): return error
	error = orders.advance_meals(dt, _runtime.runner.inventory)
	if not error.is_empty(): return error
	for guest in orders.active_snapshot().guests:
		if guest.state == "leaving":
			error = customers.request(guest.id, "exit")
			if error.is_empty() and customers.ready(guest.id, "exit"):
				error = customers.remove(guest.id)
				if error.is_empty(): error = orders.finish_departure(guest.id)
		elif guest.state == "served":
			var target := _destination(guest)
			error = customers.request(guest.id,target)
			if error.is_empty() and customers.ready(guest.id, target): error = orders.begin_meal(guest.id,float(guest.meal_left) if guest.meal_left>0.0 else _meal_seconds(guest), _runtime.runner.inventory)
		elif guest.state == "waiting" and not _customer_carrying(guest.order):
			if dining == null and (waiting == null or not _policy.waiting.retain_after_take):
				error = customers.request(guest.id, _pickup_target(guest) if _policy.delivery == "self_pickup" else _destination(guest))
		if not error.is_empty(): return error
	error = _sync_queue()
	if not error.is_empty(): return error
	error = _admit()
	if not error.is_empty(): return error
	if pickup_queue != null:
		error = _sync_pickups()
		if not error.is_empty(): return error
	return _fulfill()

func frame(active_only := false) -> Dictionary:
	var state: Dictionary = orders.active_snapshot() if active_only else orders.snapshot()
	var result := {"guests":state.guests, "orders":state.orders, "queue":orders.queue(), "lost":state.lost,
		"customers":customers.snapshot().customers, "arrivals":arrivals.snapshot() if arrivals != null else {}}
	if waiting != null: result.waiting = waiting.snapshot(); result.queue_capacity = queue_capacity()
	if flyers != null: result.flyers = flyers.snapshot()
	if ramp != null: result.ramp = ramp.snapshot()
	if dining != null: result.dining = dining.snapshot(); result.queue_capacity = queue_capacity()
	if seating != null: result.queue_capacity = queue_capacity()
	if pickup_queue != null: result.pickup_targets = pickup_queue.targets(state,_deliveries).targets
	return result

func snapshot() -> Dictionary:
	var result := {"version":1, "orders":orders.snapshot(), "customers":customers.snapshot(), "deliveries":_deliveries.duplicate(true),
		"arrivals":arrivals.snapshot() if arrivals != null else {}}
	if waiting != null: result.waiting = waiting.snapshot()
	if flyers != null: result.flyers = flyers.snapshot()
	if ramp != null: result.ramp = ramp.snapshot()
	if dining != null: result.dining = dining.snapshot()
	return result

func adopt_saved_history(saved: Dictionary) -> void:
	orders.adopt_saved_history(saved.orders)
	if dining != null: dining.adopt_saved_history(saved.dining)

func prepare_restore(data: Dictionary, stock: RefCounted, refresh_numeric := false, dispatch_data: Dictionary = {}, production: Array = []) -> String:
	var shape := {"version":0, "orders":{}, "customers":{}, "deliveries":[], "arrivals":{}}
	if waiting != null: shape.waiting = {}
	if flyers != null: shape.flyers = {}
	if ramp != null: shape.ramp = {}
	if dining != null: shape.dining = {}
	if not Inventory._shape(data,shape) or data.version != 1: return "invalid customer service state"
	if (arrivals == null) != data.arrivals.is_empty(): return "arrival state differs from declared capabilities"
	if arrivals != null:
		var arrival_error: String = arrivals.restore(data.arrivals)
		if not arrival_error.is_empty(): return arrival_error
	if flyers != null:
		var flyer_error: String = flyers.restore(data.flyers,refresh_numeric)
		if not flyer_error.is_empty(): return flyer_error
	var error: String = orders.restore(data.orders, stock)
	if not error.is_empty(): return error
	if dining != null:
		error = dining.restore(data.dining,data.orders,_runtime.runner.owner)
		if not error.is_empty(): return error
	if seating != null:
		error = seating.validate(_runtime.runner.owner,data.orders)
		if not error.is_empty(): return error
	if ramp != null:
		error = ramp.restore(data.ramp,int(data.orders.next_order)-1 if _deferred() else int(data.orders.next_guest)-1,refresh_numeric)
		if not error.is_empty(): return error
	error = customers.restore(data.customers)
	if not error.is_empty(): return error
	var bundles := {}
	for delivery in data.deliveries:
		if not Inventory._shape(delivery, {"order":0, "bundle":0, "phase":"", "left":0.0}): return "invalid fulfillment state"
		if bundles.has(delivery.bundle) or delivery.phase not in ["staff", "collect", "carry", "drop"] or not is_finite(delivery.left) or delivery.left < 0.0: return "invalid or duplicate fulfillment bundle"
		if (delivery.phase == "staff") != (_policy.delivery != "self_pickup"): return "fulfillment actor differs from service policy"
		bundles[delivery.bundle] = true
	_deliveries = data.deliveries.duplicate(true)
	if pickup_queue != null:
		var pickup_plan: Dictionary = pickup_queue.targets(orders.snapshot(),_deliveries)
		if not pickup_plan.error.is_empty(): return pickup_plan.error
	var waiting_targets := {}
	var previous_targets := {}
	if dining != null:
		previous_targets = dining.targets(orders.snapshot(),_called_guests([]))
		waiting_targets = dining.targets(orders.snapshot(),_called_guests(dispatch_data.get("scopes",[])))
	if waiting != null:
		var called := _called_guests(null,production)
		var automatic: bool = _policy.admission=="automatic"
		error = waiting.restore(data.waiting,orders.snapshot(),called,automatic)
		if not error.is_empty(): return error
		var projected: Dictionary = waiting.targets(orders.snapshot(),called,automatic)
		if not projected.error.is_empty(): return projected.error
		waiting_targets = projected.targets
		# Production starts after queue sync. The previous waiting target is
		# also valid in that tick and in saves from before early pickup calls.
		if _calls_during_final_work():
			previous_targets = waiting.targets(orders.snapshot(),_called_guests(null,[]),automatic).targets
	var seats := {}
	var actors := {}
	var queue: Array = orders.queue()
	var maximum: int = _policy.waiting.line.size()+_policy.waiting.ports.size() if waiting != null else _runtime.runner.owner.nav.layout.customer_queue.size()+(dining.declared_seats().size() if dining!=null else 0)
	if queue.size() > maximum: return "customer queue exceeds declared ports"
	for guest in orders.snapshot().guests:
		for index in guest.request.size():
			var row: Dictionary = guest.request[index]
			if not _policy.menu.has(row.dish): return "customer request differs from service menu"
			var recipe: String = _policy.menu[row.dish]
			if dining != null and guest.order>0: recipe = dining.recipe(row.dish,recipe,dining.route(guest.id).takeaway)
			if index == 0 and _policy.has("customization"):
				if not row.has("options"): return "customized request has no frozen selection"
				var canonical := Customization.canonical(_policy.customization,row.options)
				if not canonical.error.is_empty() or canonical.ids != row.options: return "invalid frozen option selection"
				var resolved := Customization.resolve(_policy.customization,row.dish,recipe,row.options)
				if not resolved.error.is_empty(): return resolved.error
				recipe = resolved.recipe
			elif row.has("options"): return "unrelated request option selection"
			if recipe != row.recipe or _runtime._definition.recipes[recipe].output.item != row.item: return "customer request differs from service menu"
		if not guest.seat.is_empty() and (guest.seat not in (dining.declared_seats() if dining!=null else _policy.seats.keys()) or guest.order < 1): return "customer seat differs from template"
		if dining == null and guest.order > 0 and guest.seat.is_empty() != _policy.seats.is_empty(): return "accepted customer has an inconsistent seat lease"
		if guest.state != "gone" and not ((dining!=null or seating!=null) and guest.state=="leaving") and not guest.seat.is_empty():
			if seats.has(guest.seat): return "seat is leased by two customers"
			seats[guest.seat] = guest.id
		var actor: Dictionary = customers.record(guest.id)
		if guest.state == "gone":
			if not actor.is_empty(): return "departed customer still has a motion actor"
			continue
		if actor.is_empty(): return "customer has no motion actor"
		actors[guest.id] = true
		var target := "queue:" + str(queue.find(guest.id)) if guest.state == "queue" else _destination(guest)
		if waiting_targets.has(guest.id): target = waiting_targets[guest.id]
		if guest.state == "leaving": target = "exit"
		elif guest.state == "waiting" and _policy.delivery == "self_pickup":
			target = _pickup_target(guest)
			for delivery in _deliveries:
				if delivery.order == guest.order and delivery.phase in ["carry", "drop"]: target = _destination(guest)
		# A customer may still have the previous waiting target until queue sync.
		var previous_wait: bool = guest.state=="waiting" and previous_targets.has(guest.id) and actor.target==previous_targets[guest.id]
		if actor.target != target and not previous_wait: return "customer movement target differs from service facts"
		if guest.state=="eating" and not customers.ready(guest.id, target): return "meal started before actual seating or handoff arrival"
	if actors.size() != data.customers.customers.size(): return "orphan customer motion actor"
	return ""

func dynamic_places() -> Dictionary:
	var places := {}
	for guest in orders.snapshot().guests:
		if guest.order < 1: continue
		var place := _guest_place(guest)
		places["guest:" + str(guest.id)] = {"port":_runtime._definition.places[place].port, "capacity":-1, "infinite":[]}
	return places

func validate_links(units: Array, runner_data: Dictionary, stock: RefCounted) -> String:
	var by_unit := {}
	for unit in units: by_unit[unit.id] = unit
	var bound := {}
	for order in orders.snapshot().orders:
		for line in order.lines:
			var total := 0
			for binding in line.units:
				if not by_unit.has(binding.unit) or by_unit[binding.unit].recipe != line.recipe: return "order binding differs from production unit"
				total += int(binding.qty)
				bound[binding.unit] = {"order":int(order.id), "line":line, "guest":int(order.guest)}
			if total != line.qty: return "accepted order is missing production bindings"
	var admissions := {}
	for task in runner_data.tasks:
		if task.kind != "interact": continue
		if task.from != _policy.admission_port or _policy.admission != "employee": return "admission program differs from service policy"
		if admissions.has(task.subject): return "duplicate admission program"
		admissions[task.subject] = task.worker
	for event in runner_data.interactions:
		if admissions.has(event.subject): return "duplicate admission result"
		admissions[event.subject] = event.worker
	for guest in orders.snapshot().guests:
		if guest.claimed == -1:
			if admissions.has(guest.id): return "admission program has no customer claim"
		elif admissions.get(guest.id, -1) != guest.claimed: return "customer admission claim has no employee program"
		admissions.erase(guest.id)
	if not admissions.is_empty(): return "admission references an unknown customer"
	var groups := {}
	var customer_orders := {}
	for delivery in _deliveries:
		var order: Dictionary = orders.order(delivery.order)
		var group: Dictionary = stock.bundle(delivery.bundle)
		if order.is_empty() or order.state != "accepted" or group.is_empty(): return "fulfillment has no active order or bundle"
		groups[group.id] = true
		if delivery.phase == "staff":
			if not group.actor.begins_with("staff:") or delivery.left != 0.0: return "staff delivery has an invalid carrier or clock"
		else:
			if group.actor != "customer:" + str(order.guest) or customer_orders.has(order.id) or group.capacity != _policy.customer_capacity: return "customer bundle has an invalid carrier or capacity"
			customer_orders[order.id] = true
		var total := 0
		for id in group.claims:
			var claim: Dictionary = stock.claim(id)
			var unit := Orders._claim_owner(claim)
			if not bound.has(unit) or bound[unit].order != order.id or claim.to != "guest:" + str(order.guest) or claim.item != bound[unit].line.item: return "fulfillment item differs from its bound order"
			if id in bound[unit].line.claims: return "fulfillment proof was already reconciled"
			var descriptor := _unit_output(by_unit[unit])
			if not descriptor.complete: return "fulfillment precedes production completion"
			if delivery.phase == "staff":
				if claim.from != descriptor.place or claim.owner != descriptor.owner: return "staff collected from an unrelated production output"
			else:
				var source_owner: int = descriptor.owner if descriptor.place == _policy.pickup else unit
				if claim.from != _policy.pickup or claim.owner != source_owner: return "customer picked from an unrelated stock container"
				var expected := "reserved" if delivery.phase == "collect" else "held"
				if claim.state != expected: return "customer carry progress differs from physical claim"
				if delivery.left > float(_runtime._definition.hop_seconds): return "customer pickup or drop clock exceeds declared duration"
			total += int(claim.count)
		if delivery.phase != "staff":
			var expected := 0
			for line in order.lines: expected += int(line.qty)
			if total != expected: return "self-pickup bundle is not the whole order"
	for claim in stock.snapshot().claims:
		if claim.kind != "transfer" or claim.state not in Inventory.ACTIVE: continue
		if (claim.actor.begins_with("customer:") or claim.to.begins_with("guest:")) and not groups.has(claim.group): return "orphan active customer or delivery transfer"
	return ""

func _unit_output(unit: Dictionary) -> Dictionary:
	var recipe: Dictionary = _runtime._definition.recipes[unit.recipe]
	var node: Dictionary = recipe.nodes[recipe.output.node]
	return {"place":String(node.place), "owner":-1 if node.capability == "source" else int(unit.id),
		"complete":node.capability == "source" or node.id in unit.done}

func _sync_queue() -> String:
	if dining != null:
		var targets: Dictionary = dining.targets(orders.active_snapshot(),_called_guests())
		for id in targets:
			var error: String = customers.request(id,targets[id])
			if not error.is_empty(): return error
		return ""
	if waiting != null:
		var plan: Dictionary = waiting.sync(_runtime.runner.owner,orders.active_snapshot(),_called_guests(),_policy.admission=="automatic")
		if not plan.error.is_empty(): return plan.error
		for guest in plan.targets:
			var error: String = customers.request(guest,plan.targets[guest])
			if not error.is_empty(): return error
		return ""
	var queue: Array = orders.queue()
	for index in queue.size():
		var guest: Dictionary = orders.guest(queue[index])
		if guest.state != "queue": continue
		var error: String = customers.request(guest.id, "queue:" + str(index))
		if not error.is_empty(): return error
	return ""

func _called_guests(scope_rows: Variant = null, production: Variant = null) -> Dictionary:
	var called := {}
	for delivery in _deliveries:
		var order: Dictionary = orders.order(delivery.order)
		if not order.is_empty(): called[order.guest] = true
	var active_orders: Array = orders.active_snapshot().orders
	for order in active_orders:
		for line in order.lines:
			if line.delivered>0: called[order.guest] = true
	# A committed order follower starts the customer's counter approach while
	# preparing, so staff and guest travel concurrently. No extra call ledger.
	if dining!=null and _policy.delivery=="counter":
		var rows: Variant = _runtime.runner.dispatcher.snapshot().scopes if scope_rows==null else scope_rows
		if rows is Array:
			for row in rows:
				if not row is Dictionary or not row.get("scope") is String or not row.scope.begins_with("order:"): continue
				var order: Dictionary = orders.order(int(row.scope.trim_prefix("order:")))
				if order.get("state","")=="accepted": called[order.guest] = true
	if _calls_during_final_work():
		var recorded_units: Variant = null
		if production is Array:
			recorded_units = {}
			# Restore checks the production links after rebuilding service.
			for unit in production:
				if unit is Dictionary and unit.get("id") is int: recorded_units[unit.id] = unit
		for order in active_orders:
			if order.state=="accepted" and not called.has(order.guest) and _order_finishing(order,recorded_units):
				called[order.guest] = true
	return called

func _calls_during_final_work() -> bool:
	return waiting!=null and _policy.delivery=="counter" and _policy.waiting.get("call_during_final_work",false)

func _order_finishing(order: Dictionary, recorded_units: Variant) -> bool:
	for line in order.lines:
		if line.units.is_empty(): return false
		for binding in line.units:
			if binding.delivered>=binding.qty: continue
			var unit: Dictionary = _runtime._find_unit(binding.unit) if recorded_units==null else recorded_units.get(binding.unit,{})
			if not unit.get("recipe") is String or not unit.get("running") is Dictionary: return false
			var recipe: Dictionary = _runtime._definition.recipes.get(unit.recipe,{})
			if recipe.is_empty(): return false
			var final: Dictionary = recipe.nodes[recipe.output.node]
			if final.capability=="source" or unit.running.has(final.id): continue
			if final.capability!="transfer" or not unit.running.has(final.inputs.values()[0]): return false
	return true

func _free_seat() -> String:
	var available: Array = dining.seats(_runtime.runner.owner) if dining!=null else _policy.seats.keys()
	if seating != null: available = seating.seats(_runtime.runner.owner)
	for seat in available:
		var free := true
		for guest in orders.active_snapshot().guests:
			if guest.seat == seat and guest.state != "gone" and not ((dining!=null or seating!=null) and guest.state=="leaving"): free = false; break
		if free: return seat
	return ""

func _admit() -> String:
	var queue: Array = orders.queue()
	if dining != null:
		for id in queue:
			if orders.guest(id).state!="queue": continue
			if _free_seat().is_empty() and not dining.takeaway_open(_runtime.runner.owner): break
			var error := _accept(id)
			if not error.is_empty(): return error
		return ""
	if queue.is_empty() or not _menu_ready(): return ""
	var guest: Dictionary = orders.guest(queue[0])
	if guest.state != "queue" or guest.claimed != -1 or not customers.ready(guest.id, "queue:0"): return ""
	if not _policy.seats.is_empty() and _free_seat().is_empty(): return ""
	if _policy.admission == "automatic": return _accept(guest.id)
	return ""

func _accept(id: int, employee: int = -1) -> String:
	if dining == null and not customers.ready(id, "queue:0"): return "customer moved before admission"
	var seat := _free_seat()
	if dining!=null:
		if seat.is_empty() and not dining.takeaway_open(_runtime.runner.owner): return "admission lost its dining or takeaway route"
	elif not _policy.seats.is_empty() and seat.is_empty(): return "admission lost its seat"
	var quotes := {}
	var request: Array = orders.guest(id).request
	var rng_before: int = _runtime.runner.owner.rng.state
	if _deferred():
		if not _menu_ready():
			var error: String = orders.cancel_admission(id,employee)
			if employee>0: _runtime.runner.dispatcher.release_worker(employee)
			return error
		var selected := Selection.request(_policy.selection,_runtime.runner.owner,ramp.counts() if ramp!=null else {})
		for row in selected:
			var recipe: String = _policy.menu[row.dish]
			request.append({"dish":String(row.dish),"recipe":recipe,"item":String(_runtime._definition.recipes[recipe].output.item),"qty":int(row.qty)})
		if _policy.has("customization"):
			var choice := Customization.select(_policy.customization,request[0].dish,request[0].recipe,null,_runtime.runner.owner)
			if not choice.error.is_empty(): _runtime.runner.owner.rng.state = rng_before; return choice.error
			request[0].options = choice.ids
			request[0].recipe = choice.recipe
			request[0].item = String(_runtime._definition.recipes[choice.recipe].output.item)
	if dining != null:
		for row in request:
			row.recipe = dining.recipe(row.dish,_policy.menu[row.dish],seat.is_empty())
			row.item = String(_runtime._definition.recipes[row.recipe].output.item)
		var resolution: String = orders.resolve_request(id,request)
		if not resolution.is_empty(): return resolution
	for index in request.size():
		var row: Dictionary = request[index]
		if _policy.has("customization"):
			quotes[index] = Customization.quote(_policy.customization,_runtime.runner.owner,row.dish,row.get("options",[]))
		else: quotes[row.dish] = float(_runtime.runner.owner.dish_price(row.dish))
	var admitted: Dictionary = orders.admit_selected(id,request,quotes,employee) if _deferred() else orders.admit(id, quotes, employee)
	if not String(admitted.error).is_empty():
		if _deferred(): _runtime.runner.owner.rng.state = rng_before
		return admitted.error
	if _deferred() and ramp!=null: ramp.admitted(menu_weights())
	if dining != null: dining.record(id,seat.is_empty())
	if not seat.is_empty():
		var error: String = orders.assign_seat(id, seat)
		if not error.is_empty(): return error
	var guest: Dictionary = orders.guest(id)
	var port: Vector2 = _runtime.runner.ports[_guest_place(guest)]
	var error: String = _runtime.runner.define_dynamic_place("guest:" + str(id), port)
	if not error.is_empty(): return error
	var lines: Array = orders.order(admitted.id).lines
	if _policy.get("selection",{}).get("addon",{}).get("first",false) and lines.size()>1:
		lines = lines.slice(1)+[lines[0]]
	for line in lines:
		for index in int(line.qty):
			var unit: Dictionary = _runtime.production_for_service(line.recipe)
			if not String(unit.error).is_empty(): return unit.error
			error = orders.bind_unit(admitted.id, line.id, unit.id)
			if not error.is_empty(): return error
	_runtime.runner.dispatcher.promote(id, admitted.id, employee)
	if _policy.orders.pay_at == "on_take":
		var receipt: Dictionary = orders.settle(admitted.id, _runtime.runner.owner._sales)
		if not String(receipt.error).is_empty(): return receipt.error
	if dining == null and (waiting == null or not _policy.waiting.retain_after_take):
		error = customers.request(guest.id, _pickup_target(guest) if _policy.delivery == "self_pickup" else _destination(guest))
		if not error.is_empty(): return error
	error = _sync_queue() if waiting != null or dining != null else ""
	if error.is_empty(): _runtime.runner.owner.events.emit("order_taken",{"guest":int(id),"order":int(admitted.id),"seat":guest.seat})
	return error

func _guest_place(guest: Dictionary) -> String:
	if dining != null: return String(_policy.handoff_port)
	return String(_policy.seats[guest.seat]) if not guest.seat.is_empty() else String(_policy.pickup if _policy.delivery=="self_pickup" else _policy.handoff_port)

func _meal_seconds(guest: Dictionary) -> float:
	if dining!=null: return float(guest.meal_left)
	if guest.seat.is_empty(): return 0.0
	return seating.seconds(_runtime.runner.owner) if seating!=null else float(_policy.eat_seconds)

func _delivery_target(guest: Dictionary) -> String:
	return "pickup" if dining!=null else _destination(guest)

func _pickup_target(guest: Dictionary) -> String:
	if pickup_queue==null: return "pickup"
	return String(pickup_queue.targets(orders.active_snapshot(),_deliveries).targets.get(guest.id,""))

func _sync_pickups() -> String:
	var plan: Dictionary = pickup_queue.targets(orders.active_snapshot(),_deliveries)
	if not plan.error.is_empty(): return plan.error
	for id in plan.targets:
		var error: String = customers.request(id,plan.targets[id])
		if not error.is_empty(): return error
	return ""

func _destination(guest: Dictionary) -> String:
	if not guest.seat.is_empty(): return guest.seat
	if dining != null: return "exit"
	return "exit" if _policy.delivery == "self_pickup" else "pickup"

func _eligible(worker: Dictionary, roles: Array) -> bool:
	return worker.deployed and _runtime.runner.idle(worker.id) and (roles.is_empty() or _runtime.runner.access_profile(worker) in roles)

func _customer_carrying(order: int) -> bool:
	for delivery in _deliveries:
		if delivery.order == order and delivery.phase in ["collect", "carry", "drop"]: return true
	return false

func _fulfill() -> String:
	if _policy.delivery != "self_pickup": return ""
	for order in orders.active_snapshot().orders:
		if order.state == "delivered": continue
		var guest: Dictionary = orders.guest(order.guest)
		if _customer_carrying(order.id) or not customers.ready(guest.id, _pickup_target(guest)): continue
		var entries := _entries(order, _policy.pickup)
		var total := 0
		for line in order.lines: total += int(line.qty) - int(line.delivered)
		if entries.size() != total: continue
		var group: Dictionary = _runtime.runner.inventory.reserve_bundle("customer:" + str(guest.id), entries, _policy.customer_capacity)
		if String(group.error).is_empty(): _deliveries.append({"order":int(order.id), "bundle":int(group.id), "phase":"collect", "left":float(_runtime._definition.hop_seconds)})
	return ""

func admission_pending(worker: Dictionary) -> bool:
	if _policy.admission!="employee" or not _menu_ready() or not _eligible(worker,_policy.admission_roles): return false
	if not _runtime.runner.dispatcher.allowed(worker,{"kind":"interact","port":_policy.admission_port}): return false
	var queue: Array = orders.queue()
	return not queue.is_empty() and orders.guest(queue[0]).state=="queue" and (_policy.seats.is_empty() or not _free_seat().is_empty())

func candidates(worker: Dictionary) -> Array:
	var out: Array = []
	var queue: Array = orders.queue()
	if _policy.admission == "employee" and not queue.is_empty() and _menu_ready() and _eligible(worker, _policy.admission_roles):
		var guest: Dictionary = orders.guest(queue[0])
		if guest.state == "queue" and guest.claimed == -1 and (waiting != null or customers.ready(guest.id, "queue:0")) and (_policy.seats.is_empty() or not _free_seat().is_empty()):
			out.append({"kind":"interact", "category":"admit", "guest":int(guest.id), "unit":-1,
				"from":String(_policy.admission_port), "to":String(_policy.admission_port), "seconds":float(_policy.admission_seconds)})
	if not _eligible(worker, _policy.delivery_roles): return out
	for order in orders.active_snapshot().orders:
		if order.state == "delivered": continue
		var guest: Dictionary = orders.guest(order.guest)
		if _policy.delivery == "self_pickup":
			if not _customer_carrying(order.id): out.append_array(_stage_candidates(order))
		elif dining != null or (waiting != null and _policy.waiting.retain_after_take) or customers.ready(guest.id, _destination(guest)):
			var entries := _entries(order)
			if entries.is_empty(): continue
			if _policy.get("delivery_ready","") == "whole_order":
				var needed := 0
				for line in order.lines: needed += int(line.qty)-int(line.delivered)
				var available := 0
				for entry in entries: available += int(entry.count)
				if available != needed: continue
			entries.resize(mini(entries.size(), _runtime.runner.owner.carry(worker)))
			out.append({"kind":"bundle", "category":"deliver", "order":int(order.id), "unit":int(entries[0].allocate_owner),
				"from":String(entries[0].from), "to":String(entries[0].to), "entries":entries})
	return out

func claimed(worker_id: int, candidate: Dictionary) -> String:
	if candidate.category == "admit":
		var error: String = orders.claim_admission(candidate.guest, worker_id)
		if not error.is_empty(): return error
		return _sync_queue() if waiting != null else ""
	if candidate.category == "deliver":
		_deliveries.append({"order":int(candidate.order), "bundle":int(_runtime.runner.tasks[worker_id].bundle), "phase":"staff", "left":0.0})
		if waiting != null or dining != null: return _sync_queue()
	return ""

func _entries(order: Dictionary, staged: String = "") -> Array:
	var entries: Array = []
	var selected := {}
	for line in order.lines:
		for binding in line.units:
			if binding.delivered >= binding.qty: continue
			var destination := "guest:" + str(order.guest)
			var assigned: int = _runtime.runner.inventory.quantity(destination, line.item, binding.unit) + _runtime.runner.inventory.incoming(destination, line.item, binding.unit)
			if assigned >= int(binding.qty) - int(binding.delivered): continue
			var output: Dictionary = _runtime.production_output(binding.unit)
			if output.is_empty() or not output.complete: continue
			var place: String = output.place if staged.is_empty() else staged
			var stock_owner: int = output.owner if staged.is_empty() or output.place == staged else int(binding.unit)
			var integrated: bool = line.item in _runtime._definition.places[place].infinite
			var key := [place, String(line.item), stock_owner]
			if not integrated and _runtime.runner.inventory.quantity(place, line.item, stock_owner, true) - int(selected.get(key, 0)) < binding.qty: continue
			selected[key] = int(selected.get(key, 0)) + int(binding.qty)
			var entry := {"from":place, "to":"guest:" + str(order.guest), "item":String(line.item), "count":int(binding.qty), "owner":stock_owner, "allocate_owner":int(binding.unit)}
			if staged.is_empty(): entry.pickup_seconds = float(output.pickup_seconds)
			entries.append(entry)
	return entries

func _stage_candidates(order: Dictionary) -> Array:
	var out: Array = []
	for line in order.lines:
		for binding in line.units:
			var output: Dictionary = _runtime.production_output(binding.unit)
			if output.is_empty() or not output.complete: continue
			if output.place == _policy.pickup: continue
			if _runtime.runner.inventory.quantity(_policy.pickup, line.item, binding.unit) + _runtime.runner.inventory.incoming(_policy.pickup, line.item, binding.unit) >= binding.qty: continue
			out.append({"kind":"transfer", "category":"stage", "order":int(order.id), "unit":int(binding.unit),
				"from":String(output.place), "to":String(_policy.pickup), "item":String(line.item), "count":int(binding.qty),
				"owner":int(output.owner), "seconds":float(output.pickup_seconds)})
	return out

func _reconcile_deliveries(dt: float) -> String:
	return _reconcile_delivery_records(dt)

func reconcile_cancellations() -> String:
	for event in _runtime.runner.take_interactions():
		if event.result!="cancelled": return "unexpected unfinished admission result"
		var error: String = orders.cancel_admission(event.subject,event.worker)
		if not error.is_empty(): return error
	for delivery in _deliveries.duplicate():
		var bundle: Dictionary = _runtime.runner.inventory.bundle(delivery.bundle)
		if _runtime.runner.inventory.claim(bundle.claims[0]).state=="cancelled": _deliveries.erase(delivery)
	return _sync_queue()

func _reconcile_delivery_records(dt: float) -> String:
	for delivery in _deliveries.duplicate():
		var order: Dictionary = orders.order(delivery.order)
		var guest: Dictionary = orders.guest(order.guest)
		var stock: RefCounted = _runtime.runner.inventory
		var group: Dictionary = stock.bundle(delivery.bundle)
		if group.is_empty(): return "delivery bundle missing"
		var first: Dictionary = stock.claim(group.claims[0])
		if first.state == "cancelled": _deliveries.erase(delivery); continue
		if delivery.phase == "collect" or delivery.phase == "drop":
			var target := _pickup_target(guest) if delivery.phase == "collect" else _destination(guest)
			if not customers.ready(guest.id, target): continue
			delivery.left = maxf(0.0, float(delivery.left) - dt)
			if delivery.left > 0.000001: continue
			var error: String = stock.pickup_bundle(group.id) if delivery.phase == "collect" else stock.drop_bundle(group.id)
			if not error.is_empty(): return error
			if delivery.phase == "collect":
				delivery.phase = "carry"
				error = customers.request(guest.id, _destination(guest))
				if not error.is_empty(): return error
		elif delivery.phase == "carry":
			if not customers.ready(guest.id, _destination(guest)): continue
			delivery.phase = "drop"
			delivery.left = float(_runtime._definition.hop_seconds)
		if stock.claim(group.claims[0]).state != "dropped": continue
		for id in group.claims:
			var claim: Dictionary = stock.claim(id)
			var line_id := -1
			for line in order.lines:
				for binding in line.units:
					if binding.unit == Orders._claim_owner(claim) and line.item == claim.item: line_id = line.id; break
			var error: String = orders.record_delivery(order.id, line_id, id, stock, _runtime.runner.owner._sales)
			if not error.is_empty(): return error
		if orders.order(order.id).state == "delivered":
			if _policy.orders.pay_at == "on_deliver":
				var receipt: Dictionary = orders.settle(order.id, _runtime.runner.owner._sales)
				if not String(receipt.error).is_empty(): return receipt.error
			_runtime.runner.owner.events.emit("sale",_sale_event(orders.order(order.id)))
			if dining != null:
				var error: String = orders.prepare_meal(guest.id,0.0 if guest.seat.is_empty() else dining.seconds(_runtime.runner.owner))
				if not error.is_empty(): return error
		_deliveries.erase(delivery)
	return ""

func _sale_event(order: Dictionary) -> Dictionary:
	var items: Array = []; var count := 0
	for line in order.lines:
		items.append({"dish":String(line.dish),"count":int(line.qty)})
		count += int(line.qty)
	return {"order":int(order.id),"guest":int(order.guest),"dish":String(order.lines[0].dish),"count":count,"items":items,"income":int(order.income)}
