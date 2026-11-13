extends RefCounted
## Common runtime over compiled production and service capabilities. Shop IDs
## and legacy business modes never select an executor.
const Compiler := preload("res://game/rules/template/compiler.gd")
const Runner := preload("res://game/rules/template/capability_runner.gd")
const Inventory := preload("res://game/rules/template/inventory.gd")
const Restock := preload("res://game/rules/template/restock.gd")
const Numbers := preload("res://game/rules/rule_numbers.gd")
const Service := preload("res://game/rules/template/service.gd")
const Dispatch := preload("res://game/rules/template/dispatch.gd")
const SourceDemand := preload("res://game/rules/template/source_demand.gd")
const Limits := preload("res://game/rules/template/numeric_limits.gd")
const Clock := preload("res://game/rules/template/production_clock.gd")
const TransportBatch := preload("res://game/rules/template/transport_batch.gd")
const Transports := preload("res://game/rules/template/transports.gd")

var runner: RefCounted
var last_error := ""
var _definition: Dictionary = {}
var _units: Array = []
var _next_unit := 1
var _clock := 0.0
var _diagnostics: Array = []
var _restocks: RefCounted
var service: RefCounted
var _transports: RefCounted

func _init(owner: RefCounted, template: Resource) -> void:
	runner = Runner.new(owner)
	var compiled := Compiler.compile(template,Compiler.ports_from_layout(owner.nav.layout))
	if not compiled.errors.is_empty():
		last_error = String(compiled.errors[0].path) + ": " + String(compiled.errors[0].message)
		return
	_definition = compiled.definition
	_transports = Transports.new(_definition.get("transports",{}))
	last_error = _transports.validate_context(owner)
	if not last_error.is_empty(): return
	for id in _definition.places:
		var place: Dictionary = _definition.places[id]
		last_error = runner.define_place(id, place.port, place.capacity, place.infinite)
		if not last_error.is_empty(): return
		for item in place.initial:
			var seeded: Dictionary = runner.inventory.seed(id, item, place.initial[item])
			if not String(seeded.error).is_empty(): last_error = seeded.error; return
	for id in _definition.machines:
		var machine: Dictionary = _definition.machines[id]
		last_error = runner.machines.configure(id, machine.input, machine.output, machine.profile,machine.get("work_port",""),machine.get("stage_ports",{}),machine.get("stage_timing",{}))
		if not last_error.is_empty(): return
		if machine.has("slot_ceiling"):
			last_error = runner.machines.track_slots(id,machine.slot_ceiling)
			if not last_error.is_empty(): return
	_restocks = Restock.new(_definition.restocks, runner)
	last_error = _restocks.validate_context()
	if not last_error.is_empty(): return
	last_error = Clock.validate(_definition,runner.owner)
	if not last_error.is_empty(): return
	last_error = Limits.sync(_definition,runner)
	if not last_error.is_empty(): return
	runner.dispatcher = Dispatch.new(_definition.dispatch, runner, self)
	last_error = runner.dispatcher.last_error
	if not last_error.is_empty(): return
	if not _definition.service.is_empty():
		service = Service.new(self, _definition.service)
		last_error = service.last_error

func arrive(request: Array, selected_options: Variant = null) -> Dictionary:
	if not last_error.is_empty(): return {"error":last_error, "id":-1}
	if service == null: return {"error":"template has no customer service capability", "id":-1}
	return service.arrive(request,selected_options)

func set_service_open(value: bool) -> String:
	if not last_error.is_empty(): return last_error
	if service == null: return "template has no customer service capability"
	return service.set_open(value)

func send_flyers() -> String:
	if not last_error.is_empty(): return last_error
	if service == null: return "template has no customer service capability"
	var error: String = service.send_flyers()
	if not error.is_empty(): return error
	# Observers may save/restore or try a second command; commit precedes emit.
	runner.owner.events.clock = _clock
	runner.owner.events.emit("flyer",{})
	return ""

func request_production(recipe: String) -> Dictionary:
	if not last_error.is_empty(): return {"error":last_error, "id":-1}
	if not _definition.recipes.has(recipe): return {"error":"unknown production recipe", "id":-1}
	var unit := {"id":_next_unit, "recipe":recipe, "done":[], "running":{}}
	_next_unit += 1
	_units.append(unit)
	return {"error":"", "id":unit.id}

func step(dt: float, paused := false) -> String:
	if not last_error.is_empty(): return last_error
	if not is_finite(dt) or dt < 0.0: return "invalid production time"
	if paused or dt == 0.0: return ""
	var dispatch_error: String = runner.dispatcher.validate_context()
	if not dispatch_error.is_empty(): last_error = dispatch_error; return dispatch_error
	var transport_error: String = _transports.validate_context(runner.owner)
	if not transport_error.is_empty(): last_error = transport_error; return transport_error
	if service != null:
		var service_error: String = service.validate_context()
		if not service_error.is_empty(): last_error = service_error; return service_error
	var error: String = Clock.validate(_definition,runner.owner)
	if not error.is_empty(): last_error = error; return error
	error = Limits.sync(_definition,runner)
	if not error.is_empty(): last_error = error; return error
	_clock += dt
	error = runner.step(dt)
	if not error.is_empty(): last_error = error; return error
	error = _transports.advance(dt,runner.inventory)
	if not error.is_empty(): last_error = error; return error
	_reconcile()
	if service != null:
		error = service.advance(dt)
		if not error.is_empty(): last_error = error; return error
	error = _restocks.advance(_stock_demand())
	if not error.is_empty(): last_error = error; return error
	_start_ready_nodes()
	if not last_error.is_empty(): return last_error
	_start_transports()
	error = runner.dispatcher.reconcile()
	if not error.is_empty(): last_error = error; return error
	_allocate()
	return ""

func ready(id: int) -> bool:
	var unit := _find_unit(id)
	if unit.is_empty(): return false
	var recipe: Dictionary = _definition.recipes[unit.recipe]
	var output: Dictionary = recipe.output
	var producer: Dictionary = recipe.nodes[output.node]
	if producer.capability != "source" and output.node not in unit.done: return false
	return runner.inventory.quantity(producer.place, output.item, -1 if producer.capability == "source" else id, true) >= int(output.count)

func source_demand() -> Dictionary:
	if not _definition.has("recipes"): return {}
	return SourceDemand.build(_definition, _units, runner.inventory, runner.machines)

func _stock_demand() -> Dictionary:
	return source_demand() if _restocks.uses_demand else {}

func unit(id: int) -> Dictionary:
	return _find_unit(id).duplicate(true)

func production_output(id: int) -> Dictionary:
	var unit := _find_unit(id)
	if unit.is_empty(): return {}
	var recipe: Dictionary = _definition.recipes[unit.recipe]
	var output: Dictionary = recipe.output
	var producer: Dictionary = recipe.nodes[output.node]
	return {"place":String(producer.place), "item":String(output.item), "count":int(output.count),
		"owner":-1 if producer.capability == "source" else id, "complete":producer.capability == "source" or output.node in unit.done,
		"pickup_seconds":_pickup_seconds(producer)}

func _pickup_seconds(producer: Dictionary) -> float:
	if producer.capability != "source": return float(_definition.hop_seconds)
	if String(producer.timing_target).is_empty(): return float(producer.seconds)
	return Numbers.capability_seconds(runner.owner.mods, runner.owner.tune, producer.timing_target, producer.seconds, producer.fixed)

func frame(displays: Array = []) -> Dictionary:
	var bindings: Array = []
	for machine in _definition.get("machines",{}).values():
		if machine.has("processing_display"): bindings.append(machine.processing_display)
	bindings.append_array(displays)
	var out: Dictionary = runner.frame(bindings)
	out.clock = _clock
	out.units = _units.duplicate(true)
	out.diagnostics = _diagnostics.duplicate(true)
	if _definition.has("transports"): out.transports = _transports.frame(runner.inventory)
	if Limits.enabled(_definition): out.limits = Limits.frame(_definition,runner)
	if service != null:
		var service_frame: Dictionary = service.frame()
		for key in service_frame: out[key] = service_frame[key]
	return out

func snapshot() -> Dictionary:
	var result := {"version":1, "signature":_definition.get("signature", ""), "clock":_clock,
		"next_unit":_next_unit, "units":_units.duplicate(true), "runner":runner.snapshot(),
		"restocks":_restocks.snapshot() if _restocks != null else {"version":1, "runs":{}},
		"service":service.snapshot() if service != null else {}, "dispatch":runner.dispatcher.snapshot() if runner.dispatcher != null else {}}
	if _definition.has("transports"): result.transports = _transports.snapshot()
	return result

func cancel_transport(bundle: int) -> String:
	return _transports.cancel(bundle,runner.inventory)

func restore(data: Dictionary) -> String:
	if not last_error.is_empty(): return last_error
	var dispatch_error: String = runner.dispatcher.validate_context()
	if not dispatch_error.is_empty(): return dispatch_error
	var transport_error: String = _transports.validate_context(runner.owner)
	if not transport_error.is_empty(): return transport_error
	var shape := {"version":0, "signature":"", "clock":0.0, "next_unit":0, "units":[], "runner":{}, "restocks":{}, "service":{}, "dispatch":{}}
	if _definition.has("transports"): shape.transports = {}
	if not Inventory._shape(data,shape): return "invalid production state shape"
	if (service == null) != data.service.is_empty(): return "service state differs from declared capabilities"
	if data.version != 1 or data.signature != _definition.signature: return "production template signature differs"
	if not is_finite(data.clock) or data.clock < 0.0 or data.next_unit < 1: return "invalid production sequence or clock"
	if service != null:
		var service_error: String = service.validate_context()
		if not service_error.is_empty(): return service_error
	var clock_error := Clock.validate(_definition,runner.owner)
	if not clock_error.is_empty(): return clock_error
	var limit_values := Limits.plan(_definition,runner.owner.mods)
	if not limit_values.error.is_empty(): return limit_values.error
	var limit_overrides := Limits.restore_overrides(_definition,data.runner)
	if not limit_overrides.error.is_empty(): return limit_overrides.error
	var restored_service: RefCounted
	var dynamic: Dictionary = {}
	var service_stock := Inventory.new()
	if service != null:
		if not data.runner.get("inventory") is Dictionary: return "missing service inventory"
		var stock_error := service_stock.restore(data.runner.inventory)
		if not stock_error.is_empty(): return stock_error
		restored_service = Service.new(self, _definition.service)
		if not restored_service.last_error.is_empty(): return restored_service.last_error
		var service_error: String = restored_service.prepare_restore(data.service, service_stock)
		if not service_error.is_empty(): return service_error
		dynamic = restored_service.dynamic_places()
	var error: String = runner.validate_snapshot(data.runner, dynamic, limit_overrides.definition)
	if not error.is_empty(): return error
	error = _restocks.validate_snapshot(data.restocks, data.runner.machines, data.runner.inventory)
	if not error.is_empty(): return error
	var units := {}
	var runs := {}
	var claims := {}
	var assigned_runs := {}
	var assigned_bundles := {}
	var assigned_transfer_claims := {}
	var bundles := {}
	for bundle in data.runner.inventory.bundles: bundles[bundle.id] = bundle
	for run in data.runner.machines.runs: runs[run.id] = run
	for claim in data.runner.inventory.claims: claims[claim.id] = claim
	for unit in data.units:
		if not Inventory._shape(unit, {"id":0, "recipe":"", "done":[], "running":{}}): return "invalid production unit shape"
		if unit.id < 1 or unit.id >= data.next_unit or units.has(unit.id) or not _definition.recipes.has(unit.recipe): return "invalid production unit identity"
		units[unit.id] = unit
		var recipe: Dictionary = _definition.recipes[unit.recipe]
		var done := {}
		for id in unit.done:
			if not id is String or done.has(id) or not recipe.nodes.has(id) or recipe.nodes[id].capability == "source" or not unit.running.has(id): return "completed node has no production run"
			done[id] = true
		for id in unit.running:
			if not id is String or not recipe.nodes.has(id) or recipe.nodes[id].capability == "source" or not unit.running[id] is int: return "production node has no operation"
			var node: Dictionary = recipe.nodes[id]
			if node.capability == "transfer":
				var bundle_id: int = unit.running[id]
				if not bundles.has(bundle_id): return "production transfer has no bundle"
				var group: Dictionary = bundles[bundle_id]
				var conveyor: bool = String(group.actor).begins_with("conveyor:") and node.has("transport")
				if (not String(group.actor).begins_with("staff:") and not conveyor) or (group.claims.size()!=1 and not _definition.dispatch.get("batch_transfers",false)): return "production transfer has an invalid carrier or shape"
				var item: String = node.consumes.keys()[0]
				var source: Dictionary = recipe.nodes[node.inputs[item]]
				var source_owner: int = -1 if source.capability == "source" else int(unit.id)
				var claim := {}
				for child in group.claims:
					var current: Dictionary = claims[child]
					if current.from==source.place and current.to==node.place and current.item==item and current.count==node.consumes[item] and current.owner==source_owner and current.allocate_owner==unit.id:
						if not claim.is_empty() or assigned_transfer_claims.has(child): return "production transfer has no unique child claim"
						claim = current
				if claim.is_empty(): return "bundle differs from production transfer"
				assigned_transfer_claims[claim.id] = true
				assigned_bundles[bundle_id] = true
				if (claim.state == "dropped") != done.has(id): return "transfer completion differs from committed drop"
				if not _dependencies_complete(recipe,node,unit): return "production transfer precedes its dependencies"
				continue
			if not runs.has(unit.running[id]): return "production node has no machine run"
			var run: Dictionary = runs[unit.running[id]]
			if assigned_runs.has(run.id): return "machine commit is assigned to more than one production node"
			assigned_runs[run.id] = true
			var claim: Dictionary = claims[run.claim]
			if run.machine != node.machine or claim.owner != unit.id or claim.consumes != node.consumes or claim.produces != node.produces: return "machine run differs from production node"
			if (run.phase == "completed") != done.has(id): return "node completion differs from committed machine state"
			if not _dependencies_complete(recipe, node, unit): return "production run precedes its dependencies"
	for bundle_id in assigned_bundles:
		for child in bundles[bundle_id].claims:
			if not assigned_transfer_claims.has(child): return "production bundle contains an unbound child claim"
	var restored_transports := Transports.new(_definition.get("transports",{}))
	var transport_stock := Inventory.new()
	error = transport_stock.restore(data.runner.inventory)
	if not error.is_empty(): return error
	var transport_state: Dictionary = data.get("transports",{"version":1,"cooldowns":{},"flights":[]})
	error = restored_transports.validate(transport_state,data.units,transport_stock,_definition.recipes)
	if not error.is_empty(): return error
	for lot in data.runner.inventory.lots:
		if lot.owner >= 0 and not units.has(lot.owner): return "inventory has an unknown production owner"
	if restored_service != null:
		error = restored_service.validate_links(data.units, data.runner, service_stock)
		if not error.is_empty(): return error
	var restored_dispatch := Dispatch.new(_definition.dispatch, runner, self)
	error = restored_dispatch.prepare_restore(data.dispatch, dispatch_facts(data.units, data.service), data.runner)
	if not error.is_empty(): return error
	# Only the final adoption writes actor state. Failed graph checks leave all
	# live services and actors intact.
	error = runner.restore(data.runner, dynamic, limit_overrides.definition)
	if not error.is_empty(): return error
	error = Limits.apply_plan(limit_values.definition,runner)
	if not error.is_empty(): return error
	_units = data.units.duplicate(true)
	_next_unit = data.next_unit
	_clock = data.clock
	_restocks.restore_validated(data.restocks)
	restored_transports.restore_validated(transport_state)
	_transports = restored_transports
	service = restored_service
	runner.dispatcher = restored_dispatch
	_diagnostics = []
	return ""

func dispatch_facts(unit_data: Variant = null, service_data: Variant = null) -> Dictionary:
	var units: Array = _units if unit_data == null else unit_data
	var state: Dictionary = ({"orders":service.orders.snapshot()} if service != null else {}) if service_data == null else service_data
	var facts := {"units":{}, "open":{}}
	for unit in units:
		var token := "unit:" + str(unit.id)
		facts.units[unit.id] = token
		var recipe: Dictionary = _definition.recipes[unit.recipe]
		if recipe.nodes[recipe.output.node].capability != "source" and recipe.output.node not in unit.done: facts.open[token] = true
	if not state.is_empty():
		for order in state.orders.orders:
			var token := "order:" + str(order.id)
			for line in order.lines:
				for binding in line.units:
					facts.units[binding.unit] = token
					facts.open.erase("unit:" + str(binding.unit))
			if order.state == "accepted": facts.open[token] = true
		for guest in state.orders.guests:
			if guest.state == "queue": facts.open["guest:" + str(guest.id)] = true
	return facts

func _reconcile() -> void:
	for unit in _units:
		for node in unit.running.keys():
			if _definition.recipes[unit.recipe].nodes[node].capability == "transfer":
				var group: Dictionary = runner.inventory.bundle(unit.running[node])
				var state: String = runner.inventory.claim(group.claims[0]).state
				if state == "dropped" and node not in unit.done: unit.done.append(node)
				elif state == "cancelled": unit.running.erase(node)
				continue
			var run: Dictionary = runner.machines.run(unit.running[node])
			if run.get("phase", "") == "completed" and node not in unit.done: unit.done.append(node)
			elif run.get("phase", "") == "cancelled": unit.running.erase(node)

func _start_ready_nodes() -> void:
	_diagnostics = []
	for unit in _units:
		var recipe: Dictionary = _definition.recipes[unit.recipe]
		for id in recipe.order:
			var node: Dictionary = recipe.nodes[id]
			if node.capability != "process" or id in unit.done or unit.running.has(id): continue
			if not _dependencies_complete(recipe, node, unit): continue
			var machine: Dictionary = _definition.machines[node.machine]
			var supplied := true
			for item in node.consumes:
				if item in _definition.places[machine.input].infinite: continue
				if runner.inventory.quantity(machine.input, item, unit.id, true) < int(node.consumes[item]): supplied = false; break
			if not supplied: continue
			var timing := Clock.evaluate(node,runner.owner)
			if not timing.error.is_empty(): last_error = timing.error; return
			var seconds: float = timing.seconds
			var started: Dictionary = runner.machines.start(node.machine, node.consumes, node.produces, seconds, unit.id)
			if not String(started.error).is_empty():
				_diagnostics.append({"unit":unit.id, "node":id, "reason":started.error})
				continue
			unit.running[id] = started.id

func _start_transports() -> void:
	if not _definition.has("transports"): return
	for unit in _units:
		var recipe: Dictionary = _definition.recipes[unit.recipe]
		for node in recipe.nodes.values():
			if not node.has("transport") or node.id in unit.done or unit.running.has(node.id) or not _transports.enabled(node.transport,runner.owner) or not _dependencies_complete(recipe,node,unit): continue
			var item: String = node.consumes.keys()[0]
			var source: Dictionary = recipe.nodes[node.inputs[item]]
			var result: Dictionary = _transports.start(node.transport,runner.inventory,{"from":source.place,"to":node.place,"item":item,"count":int(node.consumes[item]),"owner":-1 if source.capability=="source" else int(unit.id),"allocate_owner":int(unit.id)})
			if result.error.is_empty(): unit.running[node.id] = int(result.id)

func _allocate() -> void:
	for worker in runner.owner.workers:
		if not runner.idle(worker.id): continue
		for candidate in candidates_for(worker.id):
			var error := ""
			match String(candidate.kind):
				"operate": error = runner.operate(worker.id, candidate.run, candidate.from)
				"transfer": error = runner.transfer(worker.id, candidate.from, candidate.to, candidate.item,
					candidate.count, _definition.hop_seconds, candidate.owner, candidate.unit, candidate.seconds)
				"bundle": error = runner.transfer_bundle(worker.id, candidate.entries, candidate.get("seconds",_definition.hop_seconds))
				"interact": error = runner.interact(worker.id, candidate.from, candidate.seconds, "admit", candidate.guest)
			if not error.is_empty(): continue
			if candidate.has("node"):
				_find_unit(candidate.unit).running[candidate.node] = int(runner.tasks[worker.id].bundle)
			for binding in candidate.get("nodes",[]):
				_find_unit(binding.unit).running[binding.node] = int(runner.tasks[worker.id].bundle)
			if service != null and candidate.category in ["admit", "deliver", "stage"]:
				error = service.claimed(worker.id, candidate)
				if not error.is_empty(): last_error = error; runner.cancel(worker.id)
			break

func candidates_for(worker_id: int) -> Array:
	var worker: Dictionary = runner.owner.worker_by_id(worker_id)
	if worker.is_empty() or not runner._available_worker(worker_id).is_empty(): return []
	return TransportBatch.compose(self,worker,runner.dispatcher.rank(worker, dispatch_candidates(worker)))

func dispatch_candidates(worker: Dictionary) -> Array:
	var pool := _candidates()
	if service != null: pool.append_array(service.candidates(worker))
	for candidate in pool:
		if not candidate.has("unit"): candidate.unit = -1
		var unit := _find_unit(candidate.unit)
		candidate.progress = 0 if unit.is_empty() else unit.done.size()
	return pool

func _candidates() -> Array:
	var work: Array = []
	var transfers: Array = []
	for candidate in _restocks.candidates(_stock_demand()):
		candidate.category = "restock_operate" if candidate.kind == "operate" else "restock_transfer"
		if candidate.kind == "operate":
			candidate.from = candidate.port
			candidate.to = candidate.port
			work.append(candidate)
		else: transfers.append(candidate)
	for unit in _units:
		var recipe: Dictionary = _definition.recipes[unit.recipe]
		for id in recipe.order:
			var node: Dictionary = recipe.nodes[id]
			if id in unit.done: continue
			if node.capability == "transfer":
				if node.has("transport") and _transports.enabled(node.transport,runner.owner): continue
				if unit.running.has(id) or not _dependencies_complete(recipe,node,unit): continue
				var item: String = node.consumes.keys()[0]
				var source: Dictionary = recipe.nodes[node.inputs[item]]
				var seconds: float = node.seconds if String(node.timing_target).is_empty() else Numbers.capability_seconds(runner.owner.mods,runner.owner.tune,node.timing_target,node.seconds,node.fixed)
				transfers.append({"kind":"bundle","category":"transfer","node":id,"unit":int(unit.id),
					"from":source.place,"to":node.place,"seconds":seconds,
					"entries":[{"from":source.place,"to":node.place,"item":item,"count":int(node.consumes[item]),
						"owner":-1 if source.capability == "source" else int(unit.id),"allocate_owner":int(unit.id),"pickup_seconds":_pickup_seconds(source)}]})
				continue
			if node.capability != "process": continue
			var machine: Dictionary = _definition.machines[node.machine]
			if unit.running.has(id):
				var run: Dictionary = runner.machines.run(unit.running[id])
				if String(run.get("phase", "")).begins_with("await_"):
					var port: String = runner.machines.stage_port(run.id)
					work.append({"kind":"operate", "category":"operate", "run":run.id, "from":port, "to":port, "unit":int(unit.id)})
				continue
			if not _dependencies_complete(recipe, node, unit): continue
			for item in node.consumes:
				if item in _definition.places[machine.input].infinite: continue
				var need := int(node.consumes[item]) - int(runner.inventory.quantity(machine.input, item, unit.id)) - int(runner.inventory.incoming(machine.input, item, unit.id))
				if need <= 0: continue
				var producer: Dictionary = recipe.nodes[node.inputs[item]]
				var source_owner := -1 if producer.capability == "source" else int(unit.id)
				var infinite: bool = item in _definition.places[producer.place].infinite
				if not infinite and runner.inventory.quantity(producer.place, item, source_owner, true) <= 0: continue
				transfers.append({"kind":"transfer", "category":"transfer", "from":producer.place, "to":machine.input, "item":item,
					"count":need, "seconds":_pickup_seconds(producer),
					"owner":source_owner, "unit":unit.id})
	work.append_array(transfers)
	return work

func _dependencies_complete(recipe: Dictionary, node: Dictionary, unit: Dictionary) -> bool:
	for id in node.dependencies:
		var dependency: Dictionary = recipe.nodes[id]
		if dependency.capability == "source":
			if not _dependencies_complete(recipe, dependency, unit): return false
		elif id not in unit.done: return false
	return true

func _find_unit(id: int) -> Dictionary:
	for unit in _units:
		if unit.id == id: return unit
	return {}
