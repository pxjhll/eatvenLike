extends "res://game/rules/action_context.gd"
## Explicit adapter for existing serve jobs. Inventory and claims stay in
## ServeFlow; the action lease contains only stable references to that owner.
var rules: ShopRules
var flow: Script
const Customers := preload("res://game/rules/customer_movement.gd")
const Worker := preload("res://game/rules/worker_state.gd")

func _init(rules_: ShopRules, flow_: Script) -> void:
	rules = rules_
	flow = flow_

static func step(kind: String, target: String, label := "", seconds := 0.0, data: Dictionary = {}) -> Dictionary:
	return {"kind":kind,"target":target,"seconds":seconds,"label":label,"data":data.duplicate(true)}

static func plan(job: Dictionary) -> Array:
	if job.kind=="home": return [step("move",job.to,"回岗")]
	var out := [step("move",job.from)]
	if job.kind in ["take","work"]: out.append(step("operate",job.from))
	else:
		out.append(step("pickup",job.from))
		out.append(step("transport",job.to))
		out.append(step("drop",job.to))
	return out

static func binding(worker: Dictionary, job: Dictionary) -> Dictionary:
	var lease := {"scope":"serve","owner":int(worker.id)}
	for key in ["kind","unit","step","item","from","to","guest"]: lease[key] = job[key]
	return lease

func reserve(worker: Dictionary, _steps: Array) -> Dictionary:
	var job: Dictionary = flow.job_of(rules,worker)
	if job.is_empty(): return {"error":"missing assignment","lease":{}}
	return {"error":"","lease":binding(worker,job)}

func ready(worker: Dictionary, action: Dictionary) -> String:
	var job: Dictionary = flow.job_of(rules,worker)
	if job.is_empty(): return "missing assignment"
	if worker.action.lease!=binding(worker,job): return "assignment changed"
	if job.kind=="take" and not Customers.ready(rules,"guest:%d"%int(job.guest)): return "customer not at queue"
	if action.kind=="move": return ""
	if action.kind in ["transport","drop"]:
		var good: Dictionary = flow._good(rules,int(job.good))
		if good.is_empty() or good.at!="hand:"+str(worker.id) or int(good.res)!=int(worker.id) or worker.carry_count!=1: return "carried good unavailable"
		if action.kind=="transport": return ""
	if action.kind=="wait":
		var condition := String(action.data.get("condition",""))
		if condition=="": return ""
		if condition=="station_unlocked": return "" if rules.station_unlocked(action.target) else "station unavailable"
		return "unsupported wait condition"
	var goal: Vector2 = flow._point(rules,action.target)
	if worker.walking or not Vector2(worker.pos).is_equal_approx(goal): return "not at action port"
	if action.kind=="pickup" and int(job.good)!=-1:
		var good: Dictionary = flow._good(rules,int(job.good))
		if good.is_empty() or good.at!=job.from or int(good.res)!=int(worker.id): return "reserved good unavailable"
	elif action.kind=="operate" and job.kind=="work":
		var unit: Dictionary = flow.unit(rules,int(job.unit))
		var recipe: SpecStep = rules.shop.dish(String(unit.dish)).steps[int(job.step)]
		if int(rules.stations[recipe.station].user)!=int(worker.id): return "workstation unavailable"
		for item in recipe.consumes:
			if flow.goods_at(rules,recipe.station,item,int(unit.id)).size()<int(recipe.consumes[item]): return "inputs unavailable"
	return ""

func enter(worker: Dictionary, action: Dictionary) -> void:
	var job: Dictionary = flow.job_of(rules,worker)
	match String(action.kind):
		"move":
			if job.kind=="home":
				job.stage = "home"
				worker.target = worker.post
				rules.begin_move(worker,rules.nav.post(worker.post),"walk")
			else: flow._go(rules,worker,action.target,"go_from")
		"transport": flow._go(rules,worker,action.target,"go_to")
		"pickup","operate","drop": flow._arrived(rules,worker)
		"wait":
			worker.phase = "wait"
			worker.walking = false
			worker.action_left = action.seconds
	if not action.label.is_empty(): worker.task_label = action.label

func advance(worker: Dictionary, action: Dictionary, dt: float) -> bool:
	if action.kind in ["move","transport"]:
		var arrived := rules.advance_move(worker,dt)
		if not arrived and worker.path.is_empty():
			worker.action.status = "blocked"
			worker.action.reason = "route unavailable"
		return arrived
	return Worker.tick_handoff_action(worker,dt)

func commit(worker: Dictionary, action: Dictionary) -> void:
	var job: Dictionary = flow.job_of(rules,worker)
	match String(action.kind):
		"move":
			if job.kind=="home": flow._end(rules,worker)
		"pickup": flow._pick_good(rules,worker,job)
		"operate": flow._worked(rules,worker,job)
		"drop": flow._dropped(rules,worker,job)

func cancel(worker: Dictionary, lease: Dictionary) -> void:
	var job: Dictionary = flow.job_of(rules,worker)
	if not job.is_empty() and lease==binding(worker,job): flow._cancel_assignment(rules,worker)

func restore(worker: Dictionary) -> void:
	var job: Dictionary = flow.job_of(rules,worker)
	var stages := {"go_from":0,"pick":1,"go_to":2,"drop":3,"work":1,"home":0}
	worker.action = {"version":1,"steps":plan(job),"index":int(stages[job.stage]),"status":"running","reason":"","started":true,"lease":binding(worker,job)}
