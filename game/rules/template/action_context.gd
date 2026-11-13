extends "res://game/rules/action_context.gd"
## One action adapter for public capabilities; business templates never provide
## their own pickup/drop/operation inventory side effects.
const Movement := preload("res://game/rules/rule_movement.gd")
var runner: RefCounted

func _init(runtime: RefCounted) -> void:
	runner = runtime

static func _step(kind: String, target: String) -> Dictionary:
	return {"kind":kind, "target":target, "seconds":0.0, "label":"", "data":{}}

static func plan(task: Dictionary) -> Array:
	if task.kind in ["operate", "interact"]: return [_step("move", task.from), _step("operate", task.from)]
	if task.kind == "bundle":
		var steps: Array = []
		for pick in task.picks:
			steps.append(_step("move", pick.from))
			var pickup := _step("pickup", pick.from)
			pickup.data.claim = int(pick.claim)
			pickup.seconds = float(pick.seconds)
			steps.append(pickup)
		steps.append(_step("transport", task.to))
		steps.append(_step("drop", task.to))
		return steps
	return [_step("move", task.from), _step("pickup", task.from), _step("transport", task.to), _step("drop", task.to)]

func reserve(worker: Dictionary, _steps: Array) -> Dictionary:
	var task: Dictionary = runner.tasks.get(worker.id, {})
	return {"error":"missing capability request" if task.is_empty() else "", "lease":_binding(task)}

func ready(worker: Dictionary, action: Dictionary) -> String:
	var task: Dictionary = runner.tasks.get(worker.id, {})
	if task.is_empty() or worker.action.lease != _binding(task): return "capability assignment changed"
	if action.kind in ["move", "transport"]: return ""
	if not runner.ports.has(action.target) or worker.walking or not Vector2(worker.pos).is_equal_approx(runner.ports[action.target]): return "not at capability port"
	if action.kind == "operate":
		if task.kind == "interact": return "" if runner.dispatcher == null or runner.dispatcher.customer_ready(task) else "customer not at admission port"
		if worker.action.started: return ""
		var run: Dictionary = runner.machines.run(task.run)
		return "" if run.get("phase", "") == "await_" + task.stage else "machine stage changed"
	if task.kind == "bundle" and action.kind == "drop":
		if runner.dispatcher != null and not runner.dispatcher.customer_ready(task): return "customer not at delivery port"
		for pick in task.picks:
			if runner.inventory.claim(pick.claim).get("state", "") != "held": return "bundle stock unavailable"
		return ""
	var claim: Dictionary = runner.inventory.claim(action.data.claim if task.kind == "bundle" else task.claim)
	var expected := "reserved" if action.kind == "pickup" else "held"
	return "" if claim.get("state", "") == expected else "capability stock unavailable"

func enter(worker: Dictionary, action: Dictionary) -> void:
	var task: Dictionary = runner.tasks[worker.id]
	if action.kind in ["move", "transport"]:
		Movement.request(worker, runner.owner.nav, runner.ports[action.target], task.profile)
		worker.phase = "walk"
		worker.target = action.target
		return
	worker.walking = false
	worker.phase = "work" if action.kind == "operate" else ("pickup" if action.kind == "pickup" else "dropoff")
	worker.task_label = action.kind
	worker.action_left = task.drop_seconds if action.kind == "drop" else task.seconds
	if task.kind == "bundle" and action.kind == "pickup": worker.action_left = float(action.seconds)
	if action.kind == "operate" and task.kind == "operate":
		var timing: Dictionary = runner.machines.stage_seconds(task.run,runner.owner.mods,runner.owner.tune)
		runner.last_error = timing.error
		if runner.last_error.is_empty(): runner.last_error = runner.machines.engage(task.run, worker.id, float(runner.owner.skill(worker)),timing.seconds)

func advance(worker: Dictionary, action: Dictionary, dt: float) -> bool:
	if action.kind in ["move", "transport"]:
		var arrived := Movement.tick(worker, runner.owner.nav, float(runner.owner.walk_speed(worker)) * dt)
		if not arrived and worker.path.is_empty():
			worker.action.status = "blocked"
			worker.action.reason = "route unavailable"
		return arrived
	if action.kind == "operate" and runner.tasks[worker.id].kind == "operate":
		var task: Dictionary = runner.tasks[worker.id]
		var run: Dictionary = runner.machines.run(task.run)
		worker.action_left = float(run.stage_left) / float(run.operator_rate)
		worker.duration = float(run.stage_total) / float(run.operator_rate)
		return run.phase != task.stage
	worker.action_left = maxf(0.0, float(worker.action_left) - dt)
	return worker.action_left <= 0.000001

func commit(worker: Dictionary, action: Dictionary) -> void:
	var task: Dictionary = runner.tasks[worker.id]
	match String(action.kind):
		"pickup":
			runner.last_error = runner.inventory.pickup_bundle_part(task.bundle, action.data.claim) if task.kind == "bundle" else runner.inventory.pickup(task.claim)
			runner._sync_hand(worker)
		"drop":
			runner.last_error = runner.inventory.drop_bundle(task.bundle) if task.kind == "bundle" else runner.inventory.drop(task.claim)
			if runner.last_error.is_empty(): runner._finish(worker)
		"operate": runner._finish(worker)

	if runner.trace!=null and runner.last_error.is_empty():
		runner.trace.record("action."+String(action.kind),{"worker":int(worker.id),"target":String(action.target),"pos":worker.pos,"port":runner.ports[action.target],"task":task.duplicate(true)})

func cancel(worker: Dictionary, _lease: Dictionary) -> void:
	runner._cancel_effect(worker)

static func _binding(task: Dictionary) -> Dictionary:
	return {} if task.is_empty() else {"scope":"template", "task":int(task.id), "worker":int(task.worker)}
