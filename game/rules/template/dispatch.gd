extends RefCounted
## One permission gate for both planning and direct capability requests. Posts
## override role permissions explicitly; templates cannot provide task code.
const Inventory := preload("res://game/rules/template/inventory.gd")
const Leases := preload("res://game/rules/template/dispatch_leases.gd")
const Machines := preload("res://game/rules/template/machines.gd")
const PERMISSIONS := {"operate":[], "transfer_from":[], "transfer_to":[], "interact":[]}
const SCORES := {"admit":400.0, "deliver":300.0, "stage":250.0, "operate":200.0,
	"transfer":100.0, "restock_operate":200.0, "restock_transfer":100.0}
var last_error := ""
var _definition: Dictionary
var _runner_ref: WeakRef
var _runtime_ref: WeakRef
var _leases: RefCounted

func _init(definition: Dictionary, runner: RefCounted, runtime: RefCounted = null) -> void:
	_definition = definition.duplicate(true)
	_runner_ref = weakref(runner)
	if runtime != null: _runtime_ref = weakref(runtime)
	_leases = Leases.new(definition, runner)
	for profile in definition.roles:
		if not runner.owner.shop.layout.actor_areas.has(profile): last_error = "dispatch role has no declared access profile"; return

static func compile(raw: Dictionary, places: Dictionary, machines: Dictionary) -> Dictionary:
	for key in raw:
		if key not in ["roles", "posts", "scores", "continuation_bonus", "travel_penalty", "affinity", "affinity_bonus", "hold_machine", "help_while_waiting"]: return _error("unsupported dispatch parameter: " + str(key))
	var result := {"roles":{}, "posts":{}, "scores":SCORES.duplicate(), "continuation_bonus":0.0, "travel_penalty":0.0,
		"affinity":"none", "affinity_bonus":100.0, "hold_machine":false, "help_while_waiting":true}
	for key in ["continuation_bonus", "travel_penalty", "affinity_bonus"]:
		var value: Variant = raw.get(key, result[key])
		if not (value is float or value is int) or not is_finite(float(value)) or value < 0.0: return _error("invalid dispatch cost or bonus")
		result[key] = float(value)
	result.affinity = raw.get("affinity", "none")
	if result.affinity not in ["none", "prefer", "exclusive"]: return _error("unsupported follower policy")
	for key in ["hold_machine", "help_while_waiting"]:
		var value: Variant = raw.get(key, result[key])
		if not value is bool: return _error("invalid dispatch lease flag")
		result[key] = value
	var scores: Variant = raw.get("scores", {})
	if not scores is Dictionary: return _error("invalid dispatch scores")
	for key in scores:
		if not result.scores.has(key) or not (scores[key] is float or scores[key] is int) or not is_finite(float(scores[key])): return _error("unsupported or invalid dispatch score")
		result.scores[key] = float(scores[key])
	for scope in ["roles", "posts"]:
		var entries: Variant = raw.get(scope, {})
		if not entries is Dictionary: return _error("invalid dispatch " + scope)
		for id in entries:
			if not id is String or id.is_empty() or not entries[id] is Dictionary: return _error("invalid dispatch permission definition")
			var permissions := PERMISSIONS.duplicate(true)
			for key in entries[id]:
				if not permissions.has(key) or not entries[id][key] is Array: return _error("unsupported dispatch permission")
				var seen := {}
				for target in entries[id][key]:
					if not target is String or target.is_empty() or seen.has(target): return _error("invalid permission target")
					if target != "*" and not (machines if key == "operate" else places).has(target): return _error("permission references an unknown machine or port")
					seen[target] = true
				permissions[key] = entries[id][key].duplicate()
			result[scope][id] = permissions
	return {"definition":result, "error":""}

func rank(worker: Dictionary, candidates: Array) -> Array:
	var runner: RefCounted = _runner_ref.get_ref()
	var ranked: Array = []
	var facts := _facts()
	for index in candidates.size():
		var candidate: Dictionary = candidates[index]
		var request := request_for(candidate)
		if request.is_empty() or not allowed(worker, request): continue
		var context := context_for_candidate(candidate, facts)
		if not String(context.error).is_empty() or not can_start(worker, context.scope, int(candidate.get("run", -1))).is_empty(): continue
		var path: PackedVector2Array = runner.owner.nav.path(worker.pos, runner.ports[candidate.from], runner.access_profile(worker))
		if path.is_empty(): continue
		var distance := 0.0
		for point in range(1, path.size()): distance += path[point-1].distance_to(path[point])
		var score: float = float(_definition.scores[candidate.category])
		if int(candidate.get("progress", 0)) > 0: score += float(_definition.continuation_bonus)
		var preferred: Dictionary = _leases.record(worker.id)
		if not preferred.is_empty() and preferred.scope == context.scope: score += float(_definition.affinity_bonus)
		score -= distance / float(runner.owner.shop.layout.motion_units) * float(_definition.travel_penalty)
		ranked.append({"score":score, "index":index, "candidate":candidate.duplicate(true)})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score if a.score != b.score else a.index < b.index)
	var result: Array = []
	for entry in ranked: result.append(entry.candidate)
	return result

func _facts() -> Dictionary:
	return {"units":{}, "open":{}} if _runtime_ref == null else _runtime_ref.get_ref().dispatch_facts()

func context_for_candidate(candidate: Dictionary, facts: Dictionary = {}) -> Dictionary:
	if facts.is_empty(): facts = _facts()
	if candidate.kind == "interact":
		var token := "guest:" + str(candidate.guest)
		return {"error":"", "scope":token if facts.open.has(token) else ""}
	if candidate.kind == "bundle":
		var ids: Array = []
		for entry in candidate.entries: ids.append(int(entry.get("allocate_owner", entry.get("owner", -1))))
		return _context_ids(ids, facts)
	return _context_ids([int(candidate.get("unit", -1))], facts)

func context_for_guest(guest: int) -> Dictionary:
	var token := "guest:" + str(guest)
	return {"error":"", "scope":token if _facts().open.has(token) else ""}

func context_for_claims(stock: RefCounted, claims: Array, facts: Dictionary = {}) -> Dictionary:
	var source: Dictionary = stock.snapshot()
	var owners := {}
	for lot in source.lots: owners[lot.id] = lot.owner
	var ids: Array = []
	for claim in claims:
		if claim.kind == "operation": ids.append(int(claim.owner)); continue
		ids.append(int(claim.allocate_owner))
		if claim.minted: ids.append(int(claim.owner))
		elif claim.state == "reserved":
			for part in claim.parts: ids.append(int(owners.get(part.lot, -1)))
		else:
			for held in claim.held: ids.append(int(held.owner))
	return _context_ids(ids, _facts() if facts.is_empty() else facts)

func _context_ids(ids: Array, facts: Dictionary) -> Dictionary:
	var scopes := {}
	for id in ids:
		if id < 0: continue
		if not facts.units.has(id):
			if _definition.affinity != "none": return {"error":"task has an unknown production owner", "scope":""}
			continue
		if facts.open.has(facts.units[id]): scopes[facts.units[id]] = true
	if scopes.size() > 1 and _definition.affinity == "exclusive": return {"error":"exclusive follower cannot combine different orders", "scope":""}
	return {"error":"", "scope":String(scopes.keys()[0]) if scopes.size() == 1 else ""}

func can_start(worker: Dictionary, scope: String, run: int = -1) -> String:
	var runner: RefCounted = _runner_ref.get_ref()
	return _leases.can_start(worker, scope, run, runner.machines)

func started(worker: Dictionary, task: Dictionary) -> void:
	_leases.started(worker, task, String(task.profile))

func release_worker(worker: int) -> void:
	_leases.release_worker(worker)

func promote(guest: int, order: int, worker: int) -> void:
	_leases.promote(guest, order, worker)

func reconcile() -> String:
	return _leases.reconcile(_facts().open)

func snapshot() -> Dictionary:
	return _leases.snapshot()

func prepare_restore(data: Dictionary, facts: Dictionary, runner_data: Dictionary) -> String:
	var stock := Inventory.new()
	var error := stock.restore(runner_data.inventory)
	if not error.is_empty(): return error
	var devices := Machines.new(stock)
	error = devices.restore(runner_data.machines)
	if not error.is_empty(): return error
	error = _leases.restore(data, facts, devices)
	if not error.is_empty(): return error
	var runner: RefCounted = _runner_ref.get_ref()
	for task in runner_data.tasks:
		var context := {"error":"", "scope":""}
		if task.kind == "interact":
			var token := "guest:" + str(task.subject)
			context.scope = token if facts.open.has(token) else ""
		elif task.kind == "operate": context = context_for_claims(stock, [stock.claim(devices.run(task.run).claim)], facts)
		elif task.kind == "transfer": context = context_for_claims(stock, [stock.claim(task.claim)], facts)
		else:
			var claims: Array = []
			for id in stock.bundle(task.bundle).claims: claims.append(stock.claim(id))
			context = context_for_claims(stock, claims, facts)
		if not String(context.error).is_empty() or context.scope != task.scope: return "actor scope differs from real inventory or customer"
		var worker: Dictionary = runner.owner.worker_by_id(task.worker)
		if _definition.affinity != "none" and not task.scope.is_empty() and _leases.record(task.worker).get("scope", "") != task.scope: return "active employee has no matching follower lease"
		if _definition.hold_machine and task.kind == "operate" and _leases.machine_holder(task.run) != task.worker: return "active operator has no matching machine lease"
		error = _leases.can_start(worker, task.scope, task.run, devices, true)
		if not error.is_empty(): return error
	for event in runner_data.interactions:
		if _definition.affinity != "none" and event.result == "completed" and facts.open.has("guest:" + str(event.subject)) and _leases.record(event.worker).get("scope", "") != "guest:" + str(event.subject): return "completed admission lost its follower lease"
	return ""

func request_for(candidate: Dictionary) -> Dictionary:
	var runner: RefCounted = _runner_ref.get_ref()
	match String(candidate.kind):
		"operate":
			var run: Dictionary = runner.machines.run(candidate.run)
			return {} if run.is_empty() else {"kind":"operate", "machine":run.machine}
		"interact": return {"kind":"interact", "port":candidate.from}
		"transfer": return {"kind":"transfer", "from":candidate.from, "to":candidate.to}
		"bundle":
			var sources: Array = []
			for entry in candidate.entries: sources.append(String(entry.from))
			return {"kind":"bundle", "froms":sources, "to":candidate.to}
	return {}

func allowed(worker: Dictionary, request: Dictionary) -> bool:
	var runner: RefCounted = _runner_ref.get_ref()
	var rule: Dictionary
	if not String(worker.post).is_empty() and _definition.posts.has(worker.post):
		rule = _definition.posts[worker.post]
	elif not String(worker.post).is_empty() and not _definition.posts.is_empty(): return false
	elif not _definition.roles.is_empty(): rule = _definition.roles.get(runner.access_profile(worker), PERMISSIONS)
	else: return true
	match String(request.kind):
		"operate": return _grants(rule.operate, request.machine)
		"interact": return _grants(rule.interact, request.port)
		"transfer": return _grants(rule.transfer_from, request.from) and _grants(rule.transfer_to, request.to)
		"bundle":
			if not _grants(rule.transfer_to, request.to): return false
			for source in request.froms:
				if not _grants(rule.transfer_from, source): return false
			return true
	return false

func allowed_task(worker: Dictionary, task: Dictionary, devices: RefCounted, check_leases := true) -> bool:
	if check_leases and not _leases.can_start(worker, task.scope, int(task.run), devices, true).is_empty(): return false
	match String(task.kind):
		"operate":
			var run: Dictionary = devices.run(task.run)
			return not run.is_empty() and allowed(worker, {"kind":"operate", "machine":run.machine})
		"interact": return allowed(worker, {"kind":"interact", "port":task.from})
		"transfer": return allowed(worker, {"kind":"transfer", "from":task.from, "to":task.to})
		"bundle":
			var sources: Array = []
			for pick in task.picks: sources.append(String(pick.from))
			return allowed(worker, {"kind":"bundle", "froms":sources, "to":task.to})
	return false

static func _grants(targets: Array, target: String) -> bool:
	return "*" in targets or target in targets

static func _error(message: String) -> Dictionary:
	return {"definition":{}, "error":message}
