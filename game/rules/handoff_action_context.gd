extends "res://game/rules/action_context.gd"
## Shared capabilities over the existing handoff inventory transaction.
const Worker := preload("res://game/rules/worker_state.gd")
const Completion := preload("res://game/rules/fulfillment_completion.gd")
const Customers := preload("res://game/rules/customer_movement.gd")
const Step := preload("res://game/rules/serve_action_context.gd")
var rules: ShopRules

func _init(owner: ShopRules) -> void:
	rules = owner

static func plan(job: Dictionary) -> Array:
	var out := [Step.step("move","source")]
	if job.kind in ["pot_start","pot_take","stir","work"]:
		out.append(Step.step("operate","source"))
	else:
		out.append(Step.step("pickup","source"))
		out.append(Step.step("transport","destination"))
		out.append(Step.step("drop","destination"))
	return out

static func binding(worker: Dictionary) -> Dictionary:
	return {"scope":"handoff","owner":int(worker.id),"job":worker.job.duplicate(true)}

func reserve(worker: Dictionary, _steps: Array) -> Dictionary:
	return {"error":"missing assignment" if worker.job.is_empty() else "","lease":binding(worker)}

func ready(worker: Dictionary, action: Dictionary) -> String:
	if worker.job.is_empty() or worker.action.lease!=binding(worker): return "assignment changed"
	if action.kind in ["move","transport"]: return ""
	var goal := rules._destination_point(worker.job) if action.kind=="drop" else rules._source_point(worker.job)
	if worker.walking or not Vector2(worker.pos).is_equal_approx(goal): return "not at action port"
	if action.kind=="drop" and worker.job.kind=="serve" and not Customers.ready(rules,"order:%d"%int(worker.job.order_id)): return "customer not at pickup"
	return ""

func enter(worker: Dictionary, action: Dictionary) -> void:
	match String(action.kind):
		"move": rules.begin_move(worker,rules._source_point(worker.job),"walk_pickup")
		"transport": rules.begin_move(worker,rules._destination_point(worker.job),"walk_dropoff")
		_:
			var phase: String = {"operate":"work","pickup":"pickup","drop":"dropoff"}[action.kind]
			var seconds: float = rules.shop.dispatch.hop_seconds/rules.skill(worker) if action.kind=="drop" else rules._action_duration(worker.job,worker)
			Worker.enter_handoff_action(worker,phase,seconds)
			if action.kind=="operate" and worker.job.kind=="work":
				rules.stations[worker.job.src].phase = "working"
				rules.stations[worker.job.src].duration = seconds

func advance(worker: Dictionary, action: Dictionary, dt: float) -> bool:
	if action.kind in ["move","transport"]:
		var arrived := rules.advance_move(worker,dt)
		if not arrived and worker.path.is_empty():
			worker.action.status = "blocked"
			worker.action.reason = "route unavailable"
		return arrived
	var done := Worker.tick_handoff_action(worker,dt)
	if action.kind=="operate" and worker.job.kind=="work":
		var station: Dictionary = rules.stations[worker.job.src]
		station.progress = 1.0-worker.action_left/station.duration
	return done

func commit(worker: Dictionary, action: Dictionary) -> void:
	var job: Dictionary = worker.job
	match String(action.kind):
		"move": worker.phase = "work" if rules._is_operation(job) else "pickup"
		"transport": worker.phase = "dropoff"
		"pickup":
			rules._take(job)
			worker.carry_item = job.item
			worker.carry_count = job.count
		"operate":
			if Completion.consumes_handoff_source(job): rules._take(job)
			Completion.complete_handoff_work(rules.stations[job.src],job,rules.pot_seconds(job.src) if job.kind=="pot_start" else 0.0)
			worker.erase("action")
			rules._finish(worker)
		"drop":
			if job.kind!="serve": rules._deliver(job.dst,job.item,job.count)
			worker.erase("action")
			rules._finish(worker)
			if job.kind=="serve": rules._record_sale(job)

func cancel(worker: Dictionary, _lease: Dictionary) -> void:
	rules._cancel_handoff_assignment(worker)

func restore(worker: Dictionary) -> void:
	var index: int = {"walk_pickup":0,"pickup":1,"work":1,"walk_dropoff":2,"dropoff":3}[worker.phase]
	worker.action = {"version":1,"steps":plan(worker.job),"index":index,"status":"running","reason":"","started":true,"lease":binding(worker)}

static func validate(worker: Dictionary) -> String:
	var program: Dictionary = worker.action
	if worker.job.is_empty() or program.lease!=binding(worker): return "handoff action lease differs from assignment"
	if program.steps!=plan(worker.job): return "handoff action effects differ from assignment"
	var action: Dictionary = program.steps[program.index]
	var phase: String = {"move":"walk_pickup","transport":"walk_dropoff","pickup":"pickup","operate":"work","drop":"dropoff"}[action.kind]
	if program.started and (worker.phase!=phase or worker.walking!=(action.kind in ["move","transport"])): return "handoff action differs from real phase"
	if (worker.carry_count>0)!=(program.index>=2): return "handoff cursor differs from carrying state"
	return ""
