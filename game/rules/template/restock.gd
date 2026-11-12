extends RefCounted
## Shared replenishment produces ordinary capability requests. It never moves
## an actor or edits stock outside the public transaction/machine services.
const Inventory := preload("res://game/rules/template/inventory.gd")
const Numbers := preload("res://game/rules/rule_numbers.gd")
var _definition: Dictionary
var _runner: RefCounted
var _runs: Dictionary = {}

func _init(definition: Dictionary, runner: RefCounted) -> void:
	_definition = definition
	_runner = runner
	for id in definition: _runs[id] = -1

func advance() -> void:
	for id in _definition:
		var rule: Dictionary = _definition[id]
		if int(_runs[id]) >= 0:
			var run: Dictionary = _runner.machines.run(_runs[id])
			if run.get("phase", "") not in ["completed", "cancelled"]: continue
			_runs[id] = -1
		if not _can_fill(rule): continue
		var device: Dictionary = _runner.machines.snapshot().definitions[rule.machine]
		var ready := true
		for item in rule.consumes:
			if item in _runner.inventory.snapshot().places[device.input].infinite: continue
			if _runner.inventory.quantity(device.input, item, -1, true) < int(rule.consumes[item]): ready = false; break
		if not ready: continue
		var seconds := Numbers.capability_seconds(_runner.owner.mods, _runner.owner.tune, rule.machine, rule.seconds)
		var started: Dictionary = _runner.machines.start(rule.machine, rule.consumes, rule.produces, seconds)
		if String(started.error).is_empty(): _runs[id] = started.id

func candidates() -> Array:
	var out: Array = []
	for id in _definition:
		var rule: Dictionary = _definition[id]
		var device: Dictionary = _runner.machines.snapshot().definitions[rule.machine]
		if int(_runs[id]) >= 0:
			var run: Dictionary = _runner.machines.run(_runs[id])
			if String(run.get("phase", "")).begins_with("await_"):
				out.append({"kind":"operate", "run":run.id, "port":device.output if run.phase == "await_unload" else device.input})
			continue
		if not _can_fill(rule): continue
		for item in rule.consumes:
			if not rule.sources.has(item): continue
			var need := int(rule.consumes[item]) - int(_runner.inventory.quantity(device.input, item, -1)) - int(_runner.inventory.incoming(device.input, item, -1))
			if need <= 0: continue
			var source: String = rule.sources[item]
			if item not in _runner.inventory.snapshot().places[source].infinite and _runner.inventory.quantity(source, item, -1, true) <= 0: continue
			out.append({"kind":"transfer", "from":source, "to":device.input, "item":item,
				"count":need, "seconds":rule.fetch_seconds, "owner":-1, "unit":-1})
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
		if run.machine != rule.machine or claim.owner != -1 or claim.consumes != rule.consumes or claim.produces != rule.produces: return "replenishment differs from its declared recipe"
	return ""

func restore_validated(data: Dictionary) -> void:
	_runs = data.runs.duplicate()

func _can_fill(rule: Dictionary) -> bool:
	var device: Dictionary = _runner.machines.snapshot().definitions[rule.machine]
	var projected := 0
	for item in rule.produces: projected += int(_runner.inventory.quantity(device.output, item, -1))
	for claim in _runner.inventory.snapshot().claims:
		if claim.kind != "operation" or claim.state != "reserved" or claim.to != device.output or claim.owner != -1: continue
		for item in rule.produces: projected += int(claim.produces.get(item, 0))
	var batch := Inventory._total(rule.produces)
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
			if key not in ["machine", "consumes", "produces", "sources", "seconds", "fetch_seconds", "stock_limit"]: valid = false
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
		var capacity: int = places[device.output].capacity
		if capacity >= 0 and (int(rule.stock_limit) > capacity or Inventory._total(rule.produces) > capacity): valid = false
		if not valid:
			errors.append({"code":"invalid_restock", "path":path, "message":"replenishment source or output capacity is invalid"})
			continue
		result[id] = {"machine":rule.machine, "consumes":consumes.duplicate(), "produces":rule.produces.duplicate(),
			"sources":sources.duplicate(), "seconds":float(rule.get("seconds", 0.0)),
			"fetch_seconds":float(rule.get("fetch_seconds", 0.6)), "stock_limit":int(rule.stock_limit)}
	return {"definition":result, "errors":errors}
