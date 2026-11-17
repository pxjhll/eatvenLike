extends RefCounted
## Read-only advisory projection. Never changes dispatch, money or staffing.
const SourceDemand := preload("res://game/rules/template/source_demand.gd")
const CommandResult := preload("res://game/rules/rule_command_result.gd")

static func candidates(runtime: RefCounted) -> Array:
	if runtime == null or runtime.service == null: return []
	var owner: RefCounted = runtime.runner.owner
	if not owner.is_open(): return []
	var bindings: Dictionary = runtime._definition.dispatch.get("station_posts", {})
	if bindings.is_empty(): return []
	# Only accepted, unfulfilled customer work establishes demand. Idle reserve
	# production alone must never produce a staffing recommendation.
	var needed := {}
	for order in runtime.service.orders.active_snapshot().orders:
		if order.state != "accepted": continue
		for line in order.lines:
			for unit in line.units:
				if unit.delivered < unit.qty: needed[unit.unit] = true
	if needed.is_empty(): return []
	var stock: RefCounted = runtime.runner.inventory
	var demand := {}
	var demand_built := false
	var machines: Dictionary = runtime.runner.machines.active_snapshot()
	var out: Array = []
	for machine in bindings:
		var post: String = bindings[machine].post
		var occupied := false
		var mobile := 0
		for worker in owner.workers:
			if not worker.deployed: continue
			if worker.post == post: occupied = true
			if not String(worker.post).is_empty(): continue
			var permission: Dictionary = runtime.runner.dispatcher._native_rule(worker)
			if permission.get("transfer_from", []).is_empty() or permission.get("transfer_to", []).is_empty(): continue
			if not runtime.runner.dispatcher.allowed(worker, {"kind":"operate", "machine":machine}, false): continue
			if CommandResult.is_ok(owner.command_status("place_worker", {"id":int(worker.id), "post":post})): mobile += 1
		# Do not move the sole eligible mobile worker into a fixed position.
		if occupied or mobile < 2: continue
		var busy := false
		for run in machines.runs:
			if run.machine == machine and not String(run.phase).begins_with("await_"): busy = true
		if busy: continue
		for run in machines.runs:
			if run.machine != machine or not String(run.phase).begins_with("await_"): continue
			var claim: Dictionary = stock.claim(run.claim)
			var blocked: bool = needed.has(claim.owner)
			if claim.owner == -1:
				if not demand_built:
					var units: Array = runtime._units.filter(func(unit: Dictionary) -> bool: return needed.has(unit.id))
					demand = SourceDemand.build(runtime._definition, units, stock, runtime.runner.machines)
					demand_built = true
				for item in claim.produces:
					if int(demand.get(claim.to, {}).get(item, 0)) > 0 and stock.quantity(claim.to, item, -1, true) == 0: blocked = true
			if blocked:
				out.append({"target":String(machine), "post":post, "run":int(run.id), "phase":String(run.phase), "stir_index":int(run.stir_index)})
	return out
