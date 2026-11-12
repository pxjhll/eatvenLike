extends RefCounted
## One permission gate for both planning and direct capability requests. Posts
## override role permissions explicitly; templates cannot provide task code.
const Inventory := preload("res://game/rules/template/inventory.gd")
const PERMISSIONS := {"operate":[], "transfer_from":[], "transfer_to":[], "interact":[]}
var last_error := ""
var _definition: Dictionary
var _runner_ref: WeakRef

func _init(definition: Dictionary, runner: RefCounted) -> void:
	_definition = definition.duplicate(true)
	_runner_ref = weakref(runner)
	for profile in definition.roles:
		if not runner.owner.shop.layout.actor_areas.has(profile): last_error = "dispatch role has no declared access profile"; return

static func compile(raw: Dictionary, places: Dictionary, machines: Dictionary) -> Dictionary:
	for key in raw:
		if key not in ["roles", "posts"]: return _error("unsupported dispatch parameter: " + str(key))
	var result := {"roles":{}, "posts":{}}
	for scope in result:
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

func allowed_task(worker: Dictionary, task: Dictionary, devices: RefCounted) -> bool:
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
