extends RefCounted
## Compose order facts, movement and inventory capabilities. Service policies
## choose ports and public actions; no shop supplies its own execution code.
const Orders := preload("res://game/rules/template/orders.gd")
const Customers := preload("res://game/rules/template/customers.gd")
const Inventory := preload("res://game/rules/template/inventory.gd")

var orders: RefCounted
var customers: RefCounted
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
	customers = Customers.new(runtime.runner.owner.nav)
	last_error = orders.last_error if not orders.last_error.is_empty() else customers.last_error
	if not last_error.is_empty(): return
	for target in ["entrance", "exit", "pickup", "queue:0"] + policy.seats.keys():
		var resolved: Dictionary = customers._target(target)
		if not String(resolved.error).is_empty(): last_error = resolved.error; return
	for dish in policy.menu:
		var found := false
		for definition in runtime.runner.owner.shop.dishes:
			if definition.id == dish: found = true; break
		if not found: last_error = "service menu has no shared dish quote"; return
	for role in policy.admission_roles + policy.delivery_roles:
		if not runtime.runner.owner.shop.layout.actor_areas.has(role): last_error = "service role has no declared access profile"; return

func arrive(request: Array) -> Dictionary:
	if not last_error.is_empty(): return {"error":last_error, "id":-1}
	var rows: Array = []
	var total := 0
	for row in request:
		if not row is Dictionary or row.size() != 2 or not row.get("dish") is String or not row.get("qty") is int or row.qty < 1 or not _policy.menu.has(row.dish): return {"error":"invalid service order request", "id":-1}
		var recipe: String = _policy.menu[row.dish]
		var output: Dictionary = _runtime._definition.recipes[recipe].output
		rows.append({"dish":String(row.dish), "recipe":recipe, "item":String(output.item), "qty":int(row.qty)})
		total += int(row.qty)
	if rows.is_empty() or (_policy.delivery == "self_pickup" and total > int(_policy.customer_capacity)): return {"error":"order exceeds whole pickup capacity", "id":-1}
	var admitted: Dictionary = orders.arrive(rows, _runtime.runner.owner.nav.layout.customer_queue.size())
	if not String(admitted.error).is_empty(): return admitted
	last_error = customers.spawn(admitted.id)
	if last_error.is_empty(): last_error = _sync_queue()
	return admitted if last_error.is_empty() else {"error":last_error, "id":-1}

func advance(dt: float) -> String:
	if not last_error.is_empty(): return last_error
	var error: String = customers.advance(dt)
	if not error.is_empty(): return error
	error = orders.advance(dt)
	if not error.is_empty(): return error
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
	for guest in orders.snapshot().guests:
		if guest.state == "leaving":
			error = customers.request(guest.id, "exit")
			if error.is_empty() and customers.ready(guest.id, "exit"):
				error = customers.remove(guest.id)
				if error.is_empty(): error = orders.finish_departure(guest.id)
		elif guest.state == "served":
			var target := _destination(guest)
			if customers.ready(guest.id, target): error = orders.begin_meal(guest.id, _policy.eat_seconds if not guest.seat.is_empty() else 0.0, _runtime.runner.inventory)
		elif guest.state == "waiting" and not _customer_carrying(guest.order):
			error = customers.request(guest.id, "pickup" if _policy.delivery == "self_pickup" else _destination(guest))
		if not error.is_empty(): return error
	error = _sync_queue()
	if not error.is_empty(): return error
	error = _admit()
	if not error.is_empty(): return error
	return _fulfill()

func frame() -> Dictionary:
	var state: Dictionary = orders.snapshot()
	return {"guests":state.guests, "orders":state.orders, "queue":orders.queue(), "lost":state.lost,
		"customers":customers.snapshot().customers}

func snapshot() -> Dictionary:
	return {"version":1, "orders":orders.snapshot(), "customers":customers.snapshot(), "deliveries":_deliveries.duplicate(true)}

func prepare_restore(data: Dictionary, stock: RefCounted) -> String:
	if not Inventory._shape(data, {"version":0, "orders":{}, "customers":{}, "deliveries":[]}) or data.version != 1: return "invalid customer service state"
	var error: String = orders.restore(data.orders, stock)
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
	var seats := {}
	var actors := {}
	var queue: Array = orders.queue()
	if queue.size() > _runtime.runner.owner.nav.layout.customer_queue.size(): return "customer queue exceeds declared ports"
	for guest in orders.snapshot().guests:
		for row in guest.request:
			if not _policy.menu.has(row.dish) or _policy.menu[row.dish] != row.recipe or _runtime._definition.recipes[row.recipe].output.item != row.item: return "customer request differs from service menu"
		if not guest.seat.is_empty() and (not _policy.seats.has(guest.seat) or guest.order < 1): return "customer seat differs from template"
		if guest.order > 0 and guest.seat.is_empty() != _policy.seats.is_empty(): return "accepted customer has an inconsistent seat lease"
		if guest.state != "gone" and not guest.seat.is_empty():
			if seats.has(guest.seat): return "seat is leased by two customers"
			seats[guest.seat] = guest.id
		var actor: Dictionary = customers.record(guest.id)
		if guest.state == "gone":
			if not actor.is_empty(): return "departed customer still has a motion actor"
			continue
		if actor.is_empty(): return "customer has no motion actor"
		actors[guest.id] = true
		var target := "queue:" + str(queue.find(guest.id)) if guest.state == "queue" else _destination(guest)
		if guest.state == "leaving": target = "exit"
		elif guest.state == "waiting" and _policy.delivery == "self_pickup":
			target = "pickup"
			for delivery in _deliveries:
				if delivery.order == guest.order and delivery.phase in ["carry", "drop"]: target = _destination(guest)
		if actor.target != target: return "customer movement target differs from service facts"
		if guest.state in ["served", "eating"] and not customers.ready(guest.id, target): return "meal started before actual seating or handoff arrival"
	if actors.size() != data.customers.customers.size(): return "orphan customer motion actor"
	return ""

func dynamic_places() -> Dictionary:
	var places := {}
	for guest in orders.snapshot().guests:
		if guest.order < 1: continue
		var place: String = _policy.seats[guest.seat] if not guest.seat.is_empty() else (_policy.pickup if _policy.delivery == "self_pickup" else _policy.handoff_port)
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
	var queue: Array = orders.queue()
	for index in queue.size():
		var guest: Dictionary = orders.guest(queue[index])
		if guest.state != "queue": continue
		var error: String = customers.request(guest.id, "queue:" + str(index))
		if not error.is_empty(): return error
	return ""

func _free_seat() -> String:
	for seat in _policy.seats:
		var free := true
		for guest in orders.snapshot().guests:
			if guest.seat == seat and guest.state != "gone": free = false; break
		if free: return seat
	return ""

func _admit() -> String:
	var queue: Array = orders.queue()
	if queue.is_empty(): return ""
	var guest: Dictionary = orders.guest(queue[0])
	if guest.state != "queue" or guest.claimed != -1 or not customers.ready(guest.id, "queue:0"): return ""
	if not _policy.seats.is_empty() and _free_seat().is_empty(): return ""
	if _policy.admission == "automatic": return _accept(guest.id)
	for worker in _runtime.runner.owner.workers:
		if not _eligible(worker, _policy.admission_roles): continue
		var error: String = _runtime.runner.interact(worker.id, _policy.admission_port, _policy.admission_seconds, "admit", guest.id)
		if not error.is_empty(): continue
		return orders.claim_admission(guest.id, worker.id)
	return ""

func _accept(id: int, employee: int = -1) -> String:
	if not customers.ready(id, "queue:0"): return "customer moved before admission"
	var seat := _free_seat()
	if not _policy.seats.is_empty() and seat.is_empty(): return "admission lost its seat"
	var quotes := {}
	for row in orders.guest(id).request: quotes[row.dish] = float(_runtime.runner.owner.dish_price(row.dish))
	var admitted: Dictionary = orders.admit(id, quotes, employee)
	if not String(admitted.error).is_empty(): return admitted.error
	if not seat.is_empty():
		var error: String = orders.assign_seat(id, seat)
		if not error.is_empty(): return error
	var guest: Dictionary = orders.guest(id)
	var port: Vector2 = _runtime.runner.ports[_policy.seats[seat] if not seat.is_empty() else (_policy.pickup if _policy.delivery == "self_pickup" else _policy.handoff_port)]
	var error: String = _runtime.runner.define_dynamic_place("guest:" + str(id), port)
	if not error.is_empty(): return error
	for line in orders.order(admitted.id).lines:
		for index in int(line.qty):
			var unit: Dictionary = _runtime.request_production(line.recipe)
			if not String(unit.error).is_empty(): return unit.error
			error = orders.bind_unit(admitted.id, line.id, unit.id)
			if not error.is_empty(): return error
	if _policy.orders.pay_at == "on_take":
		var receipt: Dictionary = orders.settle(admitted.id, _runtime.runner.owner._sales)
		if not String(receipt.error).is_empty(): return receipt.error
	return customers.request(guest.id, "pickup" if _policy.delivery == "self_pickup" else _destination(guest))

func _destination(guest: Dictionary) -> String:
	if not guest.seat.is_empty(): return guest.seat
	return "exit" if _policy.delivery == "self_pickup" else "pickup"

func _eligible(worker: Dictionary, roles: Array) -> bool:
	return worker.deployed and _runtime.runner.idle(worker.id) and (roles.is_empty() or _runtime.runner.access_profile(worker) in roles)

func _customer_carrying(order: int) -> bool:
	for delivery in _deliveries:
		if delivery.order == order and delivery.phase in ["collect", "carry", "drop"]: return true
	return false

func _fulfill() -> String:
	for order in orders.snapshot().orders:
		if order.state == "delivered": continue
		var guest: Dictionary = orders.guest(order.guest)
		if _policy.delivery == "self_pickup":
			if _customer_carrying(order.id): continue
			var error := _stage(order)
			if not error.is_empty(): return error
			if not customers.ready(guest.id, "pickup"): continue
			var entries := _entries(order, _policy.pickup)
			var total := 0
			for line in order.lines: total += int(line.qty) - int(line.delivered)
			if entries.size() != total: continue
			var group: Dictionary = _runtime.runner.inventory.reserve_bundle("customer:" + str(guest.id), entries, _policy.customer_capacity)
			if String(group.error).is_empty(): _deliveries.append({"order":int(order.id), "bundle":int(group.id), "phase":"collect", "left":float(_runtime._definition.hop_seconds)})
		else:
			if not customers.ready(guest.id, _destination(guest)): continue
			for worker in _runtime.runner.owner.workers:
				if not _eligible(worker, _policy.delivery_roles): continue
				var entries := _entries(order)
				if entries.is_empty(): break
				entries.resize(mini(entries.size(), _runtime.runner.owner.carry(worker)))
				var error: String = _runtime.runner.transfer_bundle(worker.id, entries, _runtime._definition.hop_seconds)
				if error.is_empty(): _deliveries.append({"order":int(order.id), "bundle":int(_runtime.runner.tasks[worker.id].bundle), "phase":"staff", "left":0.0})
	return ""

func _entries(order: Dictionary, staged: String = "") -> Array:
	var entries: Array = []
	var selected := {}
	for line in order.lines:
		for binding in line.units:
			if binding.delivered >= binding.qty: continue
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

func _stage(order: Dictionary) -> String:
	for line in order.lines:
		for binding in line.units:
			var output: Dictionary = _runtime.production_output(binding.unit)
			if output.is_empty() or not output.complete: continue
			if output.place == _policy.pickup: continue
			if _runtime.runner.inventory.quantity(_policy.pickup, line.item, binding.unit) + _runtime.runner.inventory.incoming(_policy.pickup, line.item, binding.unit) >= binding.qty: continue
			for worker in _runtime.runner.owner.workers:
				if not _eligible(worker, _policy.delivery_roles): continue
				var error: String = _runtime.runner.transfer(worker.id, output.place, _policy.pickup, line.item, binding.qty, _runtime._definition.hop_seconds, output.owner, binding.unit, output.pickup_seconds)
				if error.is_empty(): break
	return ""

func _reconcile_deliveries(dt: float) -> String:
	for delivery in _deliveries.duplicate():
		var order: Dictionary = orders.order(delivery.order)
		var guest: Dictionary = orders.guest(order.guest)
		var stock: RefCounted = _runtime.runner.inventory
		var group: Dictionary = stock.bundle(delivery.bundle)
		if group.is_empty(): return "delivery bundle missing"
		var first: Dictionary = stock.claim(group.claims[0])
		if first.state == "cancelled": _deliveries.erase(delivery); continue
		if delivery.phase == "collect" or delivery.phase == "drop":
			var target := "pickup" if delivery.phase == "collect" else _destination(guest)
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
		if orders.order(order.id).state == "delivered" and _policy.orders.pay_at == "on_deliver":
			var receipt: Dictionary = orders.settle(order.id, _runtime.runner.owner._sales)
			if not String(receipt.error).is_empty(): return receipt.error
		_deliveries.erase(delivery)
	return ""
