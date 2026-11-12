extends RefCounted
## Shared replenishment produces ordinary capability requests. It never moves
## an actor or edits stock outside the public transaction/machine services.
const Inventory := preload("res://game/rules/template/inventory.gd")
const Numbers := preload("res://game/rules/rule_numbers.gd")
const Batch := preload("res://game/rules/template/batch_recipe.gd")
const Limits := preload("res://game/rules/template/numeric_limits.gd")
var _definition: Dictionary
var _runner: RefCounted
var _runs: Dictionary = {}
var uses_demand := false

func _init(definition: Dictionary, runner: RefCounted) -> void:
	_definition = definition
	_runner = runner
	for id in definition:
		_runs[id] = -1
		uses_demand = uses_demand or definition[id].policy.mode == "demand"

func advance(demand: Dictionary = {}) -> String:
	for id in _definition:
		var rule: Dictionary = _definition[id]
		if int(_runs[id]) >= 0:
			var run: Dictionary = _runner.machines.run(_runs[id])
			if run.get("phase", "") not in ["completed", "cancelled"]: continue
			_runs[id] = -1
		var planned := Batch.evaluate(rule, _runner.owner.mods)
		if not planned.error.is_empty(): return "restocks." + id + ": " + planned.error
		rule = planned.definition
		if not _can_fill(rule, demand): continue
		var device: Dictionary = _runner.machines.snapshot().definitions[rule.machine]
		var ready := true
		for item in rule.consumes:
			if item in _runner.inventory.snapshot().places[device.input].infinite: continue
			if _runner.inventory.quantity(device.input, item, -1, true) < int(rule.consumes[item]): ready = false; break
		if not ready: continue
		var seconds := Numbers.capability_seconds(_runner.owner.mods, _runner.owner.tune, rule.machine, rule.seconds)
		var started: Dictionary = _runner.machines.start(rule.machine, rule.consumes, rule.produces, seconds)
		if String(started.error).is_empty(): _runs[id] = started.id
	return ""

func candidates(demand: Dictionary = {}) -> Array:
	var out: Array = []
	for id in _definition:
		var rule: Dictionary = _definition[id]
		var device: Dictionary = _runner.machines.snapshot().definitions[rule.machine]
		if int(_runs[id]) >= 0:
			var run: Dictionary = _runner.machines.run(_runs[id])
			if String(run.get("phase", "")).begins_with("await_"):
				out.append({"kind":"operate", "run":run.id, "port":device.output if run.phase == "await_unload" else device.input})
			continue
		var planned := Batch.evaluate(rule, _runner.owner.mods)
		if not planned.error.is_empty(): continue
		rule = planned.definition
		if not _can_fill(rule, demand): continue
		for item in rule.consumes:
			if not rule.sources.has(item): continue
			var need := int(rule.consumes[item]) - int(_runner.inventory.quantity(device.input, item, -1)) - int(_runner.inventory.incoming(device.input, item, -1))
			if need <= 0: continue
			var source: String = rule.sources[item]
			if item not in _runner.inventory.snapshot().places[source].infinite and _runner.inventory.quantity(source, item, -1, true) <= 0: continue
			var seconds: float = rule.fetch_seconds
			if not String(rule.get("fetch_timing_target", "")).is_empty():
				seconds = Numbers.capability_seconds(_runner.owner.mods, _runner.owner.tune, rule.fetch_timing_target, seconds, bool(rule.get("fetch_fixed",false)))
			out.append({"kind":"transfer", "from":source, "to":device.input, "item":item,
				"count":need, "seconds":seconds, "owner":-1, "unit":-1})
	return out

func snapshot() -> Dictionary:
	return {"version":1, "runs":_runs.duplicate()}

func validate_snapshot(data: Dictionary, machine_state: Dictionary, stock_state: Dictionary) -> String:
	if not Inventory._shape(data, {"version":0, "runs":{}}) or data.version != 1 or data.runs.size() != _definition.size(): return "invalid replenishment state"
	var runs := {}
	var claims := {}
	var assigned := {}
	for run in machine_state.runs: runs[run.id] = run
	for claim in stock_state.claims: claims[claim.id] = claim
	for id in _definition:
		if not data.runs.has(id) or not data.runs[id] is int or data.runs[id] < -1: return "invalid replenishment run"
		if data.runs[id] == -1: continue
		if not runs.has(data.runs[id]) or assigned.has(data.runs[id]): return "replenishment run missing or duplicated"
		assigned[data.runs[id]] = true
		var run: Dictionary = runs[data.runs[id]]
		var claim: Dictionary = claims[run.claim]
		var rule: Dictionary = _definition[id]
		if run.machine != rule.machine or claim.owner != -1 or not Batch.matches(rule,claim): return "replenishment differs from its declared recipe"
	return ""

func restore_validated(data: Dictionary) -> void:
	_runs = data.runs.duplicate()

func _can_fill(rule: Dictionary, demand: Dictionary) -> bool:
	var device: Dictionary = _runner.machines.snapshot().definitions[rule.machine]
	var projected := 0
	for item in rule.produces: projected += int(_runner.inventory.quantity(device.output, item, -1))
	for claim in _runner.inventory.snapshot().claims:
		if claim.kind != "operation" or claim.state != "reserved" or claim.to != device.output or claim.owner != -1: continue
		for item in rule.produces: projected += int(claim.produces.get(item, 0))
	var batch := Inventory._total(rule.produces)
	if rule.policy.mode == "demand":
		var item: String = rule.produces.keys()[0]
		var need: int = int(demand.get(device.output, {}).get(item, 0))
		var limit: int = int(rule.stock_limit)
		var target := mini(limit, int(rule.policy.base))
		var multiplier: int = int(rule.policy.per_waiting)
		if need > 0 and multiplier > 0:
			@warning_ignore("integer_division")
			var saturated: bool = multiplier > limit / need
			target = maxi(target, limit if saturated else need * multiplier)
		if projected >= target and projected >= int(rule.policy.low): return false
	var space := batch
	if device.input == device.output:
		var finite: Dictionary = rule.consumes.duplicate()
		for item in _runner.inventory.snapshot().places[device.input].infinite: finite.erase(item)
		space = maxi(0, space - Inventory._total(finite))
	return (projected == 0 or projected + batch <= int(rule.stock_limit)) and _runner.inventory.remaining_capacity(device.output) >= space

static func compile(raw: Dictionary, places: Dictionary, machines: Dictionary) -> Dictionary:
	var result := {}
	var errors: Array = []
	for id in raw:
		var path := "restocks." + str(id)
		var rule: Variant = raw[id]
		if not id is String or id.is_empty() or not rule is Dictionary:
			errors.append({"code":"invalid_restock", "path":path, "message":"invalid replenishment definition"})
			continue
		var valid := true
		for key in rule:
			if key not in ["machine", "consumes", "produces", "sources", "seconds", "fetch_seconds", "stock_limit", "policy", "batch", "fetch_timing_target", "fetch_fixed"]: valid = false
		if not rule.get("fetch_timing_target", "") is String or not rule.get("fetch_fixed", false) is bool: valid = false
		elif rule.get("fetch_fixed", false) and String(rule.get("fetch_timing_target", "")).is_empty(): valid = false
		if not rule.get("machine") is String or not machines.has(rule.machine) or not rule.get("consumes", {}) is Dictionary or not rule.get("produces") is Dictionary or not rule.get("sources", {}) is Dictionary: valid = false
		for key in ["seconds", "fetch_seconds"]:
			var value: Variant = rule.get(key, 0.6 if key == "fetch_seconds" else 0.0)
			if not (value is float or value is int) or not is_finite(float(value)) or value < 0.0: valid = false
		if not rule.get("stock_limit") is int or int(rule.stock_limit) < 1: valid = false
		if not valid:
			errors.append({"code":"invalid_restock", "path":path, "message":"unsupported replenishment capability or parameter"})
			continue
		if not Inventory._counts_valid(rule.get("consumes", {})) or not Inventory._counts_valid(rule.produces) or rule.produces.is_empty():
			errors.append({"code":"invalid_restock", "path":path, "message":"invalid replenishment quantities"})
			continue
		var policy := _policy(rule.get("policy", {}))
		if not policy.error.is_empty() or (policy.definition.get("mode", "") == "demand" and rule.produces.size() != 1):
			errors.append({"code":"invalid_stock_policy", "path":path + ".policy", "message":policy.error if not policy.error.is_empty() else "demand policy requires one stock item"})
			continue
		if policy.definition.mode == "demand" and Inventory._total(rule.produces) > int(rule.stock_limit):
			errors.append({"code":"invalid_stock_limit", "path":path + ".stock_limit", "message":"a demand batch must fit its stock limit"})
			continue
		var device: Dictionary = machines[rule.machine]
		var consumes: Dictionary = rule.get("consumes", {})
		var sources: Dictionary = rule.get("sources", {})
		for item in consumes:
			if item in places[device.input].infinite: continue
			if not sources.get(item) is String or not places.has(sources[item]) or sources[item] == device.input: valid = false
		for item in sources:
			if not consumes.has(item) or item in places[device.input].infinite: valid = false
		for item in rule.produces:
			if item in places[device.output].infinite: valid = false
		var capacity: int = Limits.storage_ceiling(places[device.output]).capacity
		var batch := Batch.compile(rule.get("batch",{}),consumes,rule.produces,Limits.storage_ceiling(places[device.input]),Limits.storage_ceiling(places[device.output]),int(rule.stock_limit))
		if not batch.error.is_empty():
			errors.append({"code":"invalid_batch_binding","path":path + ".batch","message":batch.error})
			continue
		if capacity >= 0 and (int(rule.stock_limit) > capacity or Inventory._total(rule.produces) > capacity): valid = false
		if not valid:
			errors.append({"code":"invalid_restock", "path":path, "message":"replenishment source or output capacity is invalid"})
			continue
		result[id] = {"machine":rule.machine, "consumes":consumes.duplicate(), "produces":rule.produces.duplicate(),
			"sources":sources.duplicate(), "seconds":float(rule.get("seconds", 0.0)),
			"fetch_seconds":float(rule.get("fetch_seconds", 0.6)), "stock_limit":int(rule.stock_limit), "policy":policy.definition}
		if not batch.definition.is_empty(): result[id].batch = batch.definition
		if not String(rule.get("fetch_timing_target", "")).is_empty():
			result[id].fetch_timing_target = rule.fetch_timing_target
			result[id].fetch_fixed = bool(rule.get("fetch_fixed",false))
	return {"definition":result, "errors":errors}

static func _policy(raw: Variant) -> Dictionary:
	var invalid := {"definition":{}, "error":"invalid or unsupported stock policy"}
	if not raw is Dictionary: return invalid
	for key in raw:
		if key not in ["mode", "base", "per_waiting", "low"]: return invalid
	var mode: Variant = raw.get("mode", "fill")
	if mode not in ["fill", "demand"]: return invalid
	var result := {"mode":mode}
	for key in ["base", "per_waiting", "low"]:
		var value: Variant = raw.get(key, 0)
		if not value is int or value < 0 or (mode == "fill" and value != 0): return invalid
		result[key] = value
	return {"definition":result, "error":""}
