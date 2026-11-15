extends RefCounted
## Keep the transaction proofs reachable from a live save. IDs and cumulative
## sales and stock counters stay monotonic when their old records are removed.
const Inventory := preload("res://game/rules/template/inventory.gd")
const Machines := preload("res://game/rules/template/machines.gd")

static func compact(runtime: Dictionary, recipes: Dictionary) -> void:
	var service: Dictionary = runtime.service
	if service.is_empty(): return
	var runner: Dictionary = runtime.runner
	var stock: Dictionary = runner.inventory
	var orders: Dictionary = service.orders
	var dependencies := {}
	var pending: Array[String] = []
	var bound_units := {}

	for guest in orders.guests:
		var key := _key("guest", guest.id)
		if guest.state != "gone": pending.append(key)
		_link(dependencies, key, "order", guest.order)
		for proof in guest.consumption: _link(dependencies, key, "claim", proof)
	for order in orders.orders:
		var key := _key("order", order.id)
		_link(dependencies, key, "guest", order.guest)
		if order.state != "delivered" or not order.paid: pending.append(key)
		for line in order.lines:
			for binding in line.units:
				bound_units[binding.unit] = order.id
				_link(dependencies, key, "unit", binding.unit)
			for proof in line.claims: _link(dependencies, key, "claim", proof)
	var source_outputs := {}
	for unit in runtime.units:
		var key := _key("unit", unit.id)
		if bound_units.has(unit.id):
			_link(dependencies, key, "order", bound_units[unit.id])
		else:
			pending.append(key)
		var recipe: Dictionary = recipes[unit.recipe]
		var output: Dictionary = recipe.nodes[recipe.output.node]
		if output.capability == "source":
			source_outputs[unit.id] = {"place":output.place, "item":recipe.output.item}
		for node in unit.running:
			var kind := "bundle" if recipe.nodes[node].capability == "transfer" else "run"
			_link(dependencies, key, kind, unit.running[node])

	for run in runner.machines.runs:
		var key := _key("run", run.id)
		if run.phase not in Machines.TERMINAL: pending.append(key)
		_link(dependencies, key, "claim", run.claim)
	for group in stock.bundles:
		var key := _key("bundle", group.id)
		for claim in group.claims: _link(dependencies, key, "claim", claim)
	for claim in stock.claims:
		var key := _key("claim", claim.id)
		if claim.state in Inventory.ACTIVE: pending.append(key)
		_link(dependencies, key, "bundle", claim.group)
		_link(dependencies, key, "unit", claim.owner)
		_link(dependencies, key, "unit", claim.allocate_owner)
		for place in [claim.from, claim.to]:
			if place.begins_with("guest:"): _link(dependencies, key, "guest", int(place.trim_prefix("guest:")))
		if claim.actor.begins_with("customer:"):
			_link(dependencies, key, "guest", int(claim.actor.trim_prefix("customer:")))
		# Shared-source demand also counts past withdrawals for retained units.
		var source: Dictionary = source_outputs.get(claim.allocate_owner, {})
		if claim.kind == "transfer" and claim.state != "cancelled" and claim.from == source.get("place") and claim.item == source.get("item"):
			_link(dependencies, _key("unit", claim.allocate_owner), "claim", claim.id)

	for lot in stock.lots:
		if lot.owner > 0: pending.append(_key("unit", lot.owner))
		if lot.place.begins_with("guest:"): pending.append(lot.place)
	for run in runtime.restocks.runs.values():
		if run > 0: pending.append(_key("run", run))
	for lease in runtime.dispatch.machines: pending.append(_key("run", lease.run))
	for lease in runtime.dispatch.scopes: pending.append(lease.scope)
	for actor in service.customers.customers: pending.append(_key("guest", actor.id))
	for lease in service.get("waiting", {}).get("leases", []): pending.append(_key("guest", lease.guest))
	for task in runner.tasks:
		if task.run > 0: pending.append(_key("run", task.run))
		if task.claim > 0: pending.append(_key("claim", task.claim))
		if task.bundle > 0: pending.append(_key("bundle", task.bundle))
		if task.subject > 0: pending.append(_key("guest", task.subject))
		if not task.scope.is_empty(): pending.append(task.scope)
	for event in runner.interactions: pending.append(_key("guest", event.subject))
	for flight in runtime.get("transports", {}).get("flights", []): pending.append(_key("bundle", flight.bundle))
	for delivery in service.deliveries:
		pending.append(_key("order", delivery.order))
		pending.append(_key("bundle", delivery.bundle))

	var retained := {}
	while not pending.is_empty():
		var key: String = pending.pop_back()
		if retained.has(key): continue
		retained[key] = true
		pending.append_array(dependencies.get(key, []))

	orders.guests = _keep(orders.guests, retained, "guest")
	orders.orders = _keep(orders.orders, retained, "order")
	runtime.units = _keep(runtime.units, retained, "unit")
	runner.machines.runs = _keep(runner.machines.runs, retained, "run")
	stock.claims = _keep(stock.claims, retained, "claim")
	stock.bundles = _keep(stock.bundles, retained, "bundle")
	var stocked_places := {}
	for lot in stock.lots: stocked_places[lot.place] = true
	for claim in stock.claims:
		if claim.state in Inventory.ACTIVE and claim.kind == "transfer":
			stocked_places["hand@" + claim.actor] = true
	for port in runner.ports.keys():
		if port.begins_with("guest:") and not retained.has(port):
			runner.ports.erase(port)
			stock.places.erase(port)
	for place in stock.places.keys():
		if stocked_places.has(place): continue
		if place.begins_with("hand@conveyor:") or (place.begins_with("hand@customer:") and not retained.has("guest:" + place.trim_prefix("hand@customer:"))):
			stock.places.erase(place)
	if service.has("dining"):
		service.dining.routes = service.dining.routes.filter(func(route: Dictionary) -> bool:
			return retained.has(_key("guest", route.guest)))

static func _key(kind: String, id: int) -> String:
	return kind + ":" + str(id)

static func _link(dependencies: Dictionary, from: String, kind: String, id: int) -> void:
	if id <= 0: return
	if not dependencies.has(from): dependencies[from] = []
	dependencies[from].append(_key(kind, id))

static func _keep(records: Array, retained: Dictionary, kind: String) -> Array:
	return records.filter(func(record: Dictionary) -> bool: return retained.has(_key(kind, record.id)))
