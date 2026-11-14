extends "res://game/rules/action_context.gd"
const Bundle := preload("res://game/rules/bundle_delivery.gd")
const Customers := preload("res://game/rules/customer_movement.gd")
const Worker := preload("res://game/rules/worker_state.gd")
var rules: ShopRules
var flow: Script

func _init(rules_: ShopRules, flow_: Script) -> void:
	rules = rules_
	flow = flow_

static func _step(kind: String, target: String, data: Dictionary = {}) -> Dictionary:
	return {"kind":kind,"target":target,"seconds":0.0,"label":"送餐","data":data.duplicate(true)}

static func plan(job: Dictionary) -> Array:
	var steps: Array = []
	for i in job.goods.size():
		var entry: Dictionary = job.goods[i]
		steps.append(_step("move" if i==0 else "transport",entry.from))
		steps.append(_step("pickup",entry.from,{"good":int(entry.id)}))
	steps.append(_step("transport",job.to))
	steps.append(_step("drop",job.to))
	return steps

func reserve(worker: Dictionary, _steps: Array) -> Dictionary:
	return Bundle.reserve(rules,worker,flow.job_of(rules,worker),flow)

func ready(worker: Dictionary, step: Dictionary) -> String:
	var job: Dictionary = flow.job_of(rules,worker)
	if job.is_empty() or worker.action.lease!=Bundle.binding(worker,job): return "bundle assignment changed"
	var error := Bundle.check_goods(rules,worker,job,flow,true)
	if not error.is_empty(): return error
	if step.kind=="drop":
		var guest: Dictionary = flow.guest(rules,int(job.guest))
		if guest.get("state","")!="seated" or not Customers.ready(rules,"guest:%d"%int(job.guest)): return "customer not seated"
		if worker.carry_count!=job.goods.size(): return "bundle not collected"
	if step.kind in ["move","transport"]: return ""
	if worker.walking or not Vector2(worker.pos).is_equal_approx(flow._point(rules,step.target)): return "not at bundle port"
	if step.kind=="pickup":
		var good: Dictionary = flow._good(rules,int(step.data.good))
		if good.at!=step.target: return "good already picked"
	return ""

func enter(worker: Dictionary, step: Dictionary) -> void:
	var job: Dictionary = flow.job_of(rules,worker)
	worker.target = "" if step.target.begins_with("seat:") else step.target
	worker.task_label = step.label
	if step.kind in ["move","transport"]:
		job.stage = "deliver" if step.target.begins_with("seat:") else "collect"
		rules.begin_move(worker,flow._point(rules,step.target),"walk")
	else:
		job.stage = "pick" if step.kind=="pickup" else "drop"
		worker.phase = "work"
		worker.walking = false
		var seconds := float(rules.shop.station(rules.counter_id).params.get("hand_seconds",0.0)) if step.kind=="drop" else rules.shop.dispatch.hop_seconds
		worker.action_left = seconds/rules.skill(worker)

func advance(worker: Dictionary, step: Dictionary, dt: float) -> bool:
	if step.kind in ["move","transport"]:
		var arrived := rules.advance_move(worker,dt)
		if not arrived and worker.path.is_empty():
			worker.action.status = "blocked"
			worker.action.reason = "route unavailable"
		return arrived
	return Worker.tick_handoff_action(worker,dt)

func commit(worker: Dictionary, step: Dictionary) -> void:
	var job: Dictionary = flow.job_of(rules,worker)
	if step.kind=="pickup":
		var good: Dictionary = flow._good(rules,int(step.data.good))
		good.at = "hand:"+str(worker.id)
		if worker.carry_count==0: worker.carry_item = good.item
		worker.carry_count += 1
	elif step.kind=="drop": Bundle.complete(rules,worker,job,flow)

func cancel(worker: Dictionary, lease: Dictionary) -> void:
	var job: Dictionary = flow.job_of(rules,worker)
	if not job.is_empty() and lease==Bundle.binding(worker,job): Bundle.cancel(rules,worker,job,flow)
