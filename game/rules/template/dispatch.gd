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
	last_error = validate_context()

func validate_context() -> String:
	var owner: RefCounted = _runner_ref.get_ref().owner
	for binding in _definition.get("station_posts",{}).values():
		if not owner.shop.layout.posts.has(binding.post): return "station binding has no declared post anchor"
		var count := 0
		for worker in owner.workers:
			if worker.deployed and worker.post==binding.post: count += 1
		if count>1: return "station post has multiple deployed occupants"
	return ""

static func compile(raw: Dictionary, places: Dictionary, machines: Dictionary) -> Dictionary:
	for key in raw:
		if key not in ["roles", "posts", "scores", "continuation_bonus", "travel_penalty", "affinity", "affinity_bonus", "hold_machine", "help_while_waiting", "station_posts", "assistance", "batch_transfers", "collect_at_drop_last"]: return _error("unsupported dispatch parameter: " + str(key))
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
	var assistance: Variant = raw.get("assistance",{})
	if not assistance is Dictionary: return _error("invalid assistance policy")
	var helpers := {}
	for key in ["batch_transfers","collect_at_drop_last"]:
		var enabled: Variant = raw.get(key,false)
		if not enabled is bool: return _error("invalid transport dispatch flag: " + key)
		if enabled: result[key] = true
	for scope in assistance:
		if scope not in ["roles","posts"] or not assistance[scope] is Dictionary: return _error("invalid assistance scope")
		if assistance[scope].is_empty(): continue
		helpers[scope] = {}
		for id in assistance[scope]:
			if not result[scope].has(id) or not assistance[scope][id] is Dictionary: return _error("assistance needs a declared native profile")
			var rule := {"transfer_from":[],"transfer_to":[],"wait_for_admission":false}
			for key in assistance[scope][id]:
				var value: Variant = assistance[scope][id][key]
				if key=="wait_for_admission":
					if not value is bool: return _error("invalid assistance admission guard")
				elif key in ["transfer_from","transfer_to"]:
					if not value is Array: return _error("invalid assistance transport permission")
					var seen := {}
					for target in value:
						if not target is String or (target!="*" and not places.has(target)) or seen.has(target): return _error("invalid assistance transport target")
						seen[target] = true
				else: return _error("assistance only grants transport")
				rule[key] = value.duplicate() if value is Array else value
			helpers[scope][id] = rule
	if not helpers.is_empty(): result.assistance = helpers
	var bindings: Variant = raw.get("station_posts",{})
	if not bindings is Dictionary: return _error("invalid station post bindings")
	if not bindings.is_empty():
		result.station_posts = {}
		for machine in bindings:
			var binding: Variant = bindings[machine]
			if not machine is String or not machines.has(machine) or not binding is Dictionary or binding.size()!=2 or not binding.get("post") is String or not result.posts.has(binding.post) or not binding.get("feed") is bool: return _error("invalid machine or station post binding")
			if not _grants(result.posts[binding.post].operate,machine): return _error("station holder has no operating permission")
			if binding.feed:
				for other in machines:
					if other!=machine and machines[other].input==machines[machine].input: return _error("exclusive feed needs an unambiguous machine input")
			result.station_posts[machine] = {"post":binding.post,"feed":binding.feed,"input":machines[machine].input}
	return {"definition":result, "error":""}

func rank(worker: Dictionary, candidates: Array) -> Array:
	var native := _rank(worker,candidates,false)
	if not native.is_empty() or not _help_available(worker): return native
	return _rank(worker,candidates,true)

func _rank(worker: Dictionary, candidates: Array, helping: bool) -> Array:
	var runner: RefCounted = _runner_ref.get_ref()
	var ranked: Array = []
	var facts := _facts()
	for index in candidates.size():
		var candidate: Dictionary = candidates[index]
		var request := request_for(candidate)
		if request.is_empty() or not _station_allows(worker,request): continue
		if not _permission(_native_rule(worker),request) and not (helping and _permission(_helper_rule(worker),request)): continue
		if not _helper_rule(worker).is_empty() and not _claimable(worker,candidate): continue
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
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.score != b.score: return a.score > b.score
		var left := int(a.candidate.get("progress",0))
		var right := int(b.candidate.get("progress",0))
		return left > right if left != right else a.index < b.index)
	var result: Array = []
	for entry in ranked: result.append(entry.candidate)
	return result

func _claimable(worker: Dictionary, candidate: Dictionary) -> bool:
	var runner: RefCounted = _runner_ref.get_ref()
	if candidate.kind=="operate":
		for task in runner.tasks.values():
			if task.kind=="operate" and task.run==candidate.run: return false
		return true
	if candidate.kind=="interact": return true
	# Probe the same transactions offside; candidate queries must never reserve
	# real stock or treat an impossible whole move as available native work.
	var stock := Inventory.new()
	stock._state = runner.inventory.snapshot()
	if candidate.kind=="transfer":
		return String(stock.reserve_transfer(worker.id,candidate.from,candidate.to,candidate.item,candidate.count,runner.owner.carry(worker),candidate.get("owner",-2),candidate.get("unit",-2)).error).is_empty()
	var entries: Array = candidate.entries.duplicate(true)
	for entry in entries: entry.erase("pickup_seconds")
	return String(stock.reserve_bundle("staff:"+str(worker.id),entries,runner.owner.carry(worker)).error).is_empty()

func _facts() -> Dictionary:
	return {"units":{}, "open":{}} if _runtime_ref == null else _runtime_ref.get_ref().dispatch_facts()

func customer_ready(task: Dictionary) -> bool:
	if _runtime_ref == null: return true
	var runtime: RefCounted = _runtime_ref.get_ref()
	if runtime.service == null or (runtime.service.waiting == null and runtime.service.dining == null): return true
	if task.kind == "interact": return runtime.service.customers.ready(task.subject,"queue:0")
	if task.to.begins_with("guest:"):
		var id := int(task.to.trim_prefix("guest:"))
		return runtime.service.customers.ready(id,runtime.service._delivery_target(runtime.service.orders.guest(id)))
	return true

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
	var source: Dictionary = stock.active_snapshot()
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

func allowed(worker: Dictionary, request: Dictionary, check_priority := true) -> bool:
	if not _station_allows(worker,request): return false
	if _permission(_native_rule(worker),request): return true
	if not _permission(_helper_rule(worker),request): return false
	if not check_priority: return true
	if not _help_available(worker): return false
	if _runtime_ref==null: return false
	return _rank(worker,_runtime_ref.get_ref().dispatch_candidates(worker),false).is_empty()

func _native_rule(worker: Dictionary) -> Dictionary:
	var runner: RefCounted = _runner_ref.get_ref()
	if not String(worker.post).is_empty() and _definition.posts.has(worker.post):
		return _definition.posts[worker.post]
	if not String(worker.post).is_empty() and not _definition.posts.is_empty(): return PERMISSIONS
	if not _definition.roles.is_empty(): return _definition.roles.get(runner.access_profile(worker), PERMISSIONS)
	return {"operate":["*"],"interact":["*"],"transfer_from":["*"],"transfer_to":["*"]}

func _helper_rule(worker: Dictionary) -> Dictionary:
	var helpers: Dictionary = _definition.get("assistance",{})
	if not String(worker.post).is_empty(): return helpers.get("posts",{}).get(worker.post,{})
	return helpers.get("roles",{}).get(_runner_ref.get_ref().access_profile(worker),{})

func _help_available(worker: Dictionary) -> bool:
	var rule := _helper_rule(worker)
	if rule.is_empty() or _runtime_ref==null: return false
	var service: RefCounted = _runtime_ref.get_ref().service
	return not (rule.wait_for_admission and service!=null and service.admission_pending(worker))

static func _permission(rule: Dictionary, request: Dictionary) -> bool:
	if rule.is_empty(): return false
	match String(request.kind):
		"operate": return _grants(rule.get("operate",[]), request.machine)
		"interact": return _grants(rule.get("interact",[]), request.port)
		"transfer": return _grants(rule.transfer_from, request.from) and _grants(rule.transfer_to, request.to)
		"bundle":
			if not _grants(rule.transfer_to, request.to): return false
			for source in request.froms:
				if not _grants(rule.transfer_from, source): return false
			return true
	return false

func _station_allows(worker: Dictionary, request: Dictionary) -> bool:
	var runner: RefCounted = _runner_ref.get_ref()
	for machine in _definition.get("station_posts",{}):
		var binding: Dictionary = _definition.station_posts[machine]
		var operation: bool = request.kind=="operate" and request.machine==machine
		var feeding: bool = binding.feed and request.kind in ["transfer","bundle"] and request.to==binding.input
		if not operation and not feeding: continue
		for holder in runner.owner.workers:
			if holder.deployed and holder.post==binding.post and holder.id!=worker.id: return false
	return true

func allowed_task(worker: Dictionary, task: Dictionary, devices: RefCounted, check_leases := true) -> bool:
	if check_leases and not _leases.can_start(worker, task.scope, int(task.run), devices, true).is_empty(): return false
	match String(task.kind):
		"operate":
			var run: Dictionary = devices.run(task.run)
			return not run.is_empty() and allowed(worker, {"kind":"operate", "machine":run.machine},false)
		"interact": return allowed(worker, {"kind":"interact", "port":task.from},false)
		"transfer": return allowed(worker, {"kind":"transfer", "from":task.from, "to":task.to},false)
		"bundle":
			var sources: Array = []
			for pick in task.picks: sources.append(String(pick.from))
			return allowed(worker, {"kind":"bundle", "froms":sources, "to":task.to},false)
	return false

static func _grants(targets: Array, target: String) -> bool:
	return "*" in targets or target in targets

static func _error(message: String) -> Dictionary:
	return {"definition":{}, "error":message}
