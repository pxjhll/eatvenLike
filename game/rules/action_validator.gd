extends RefCounted
## Read-only consistency between action cursors, live serve leases and legacy
## job projections. Missing action records are legacy adoption, never a replay.
const Actions := preload("res://game/rules/rule_actions.gd")
const Context := preload("res://game/rules/serve_action_context.gd")
const FlowValidator := preload("res://game/rules/flow_validator.gd")
const Handoff := preload("res://game/rules/handoff_action_context.gd")
const Single := preload("res://game/rules/single_action_context.gd")

static func validate(data: Dictionary, shop: SpecShop) -> String:
	for worker: Dictionary in data.roster:
		if not worker.has("action"): continue
		if shop.dispatch.action_version!=1: return "action requires an enabled adapter"
		var error := Actions.validate(worker.action)
		if not error.is_empty(): return "roster[%d].%s"%[worker.id,error]
		var program: Dictionary = worker.action
		if program.status not in Actions.ACTIVE: return "action has no active business lease"
		if shop.fulfillment.handoff in ["handoff","single"]:
			error = Handoff.validate(worker) if shop.fulfillment.handoff=="handoff" else Single.validate(worker,shop,data.stations)
			if not error.is_empty(): return error
			continue
		var job: Dictionary = data.serve.jobs.get(str(worker.id),{})
		if job.get("kind","")=="bundle":
			error = FlowValidator.bundle(data,shop,worker,job)
			if not error.is_empty(): return error
			continue
		if job.is_empty() or program.status not in Actions.ACTIVE: return "action has no active business lease"
		if program.lease!=Context.binding(worker,job): return "action lease differs from assignment"
		var actual: Array = []
		for step: Dictionary in program.steps:
			if step.kind=="wait":
				if step.data.get("condition","") not in ["","station_unlocked"]: return "action wait condition unsupported"
				continue
			actual.append([step.kind,step.target])
		var expected: Array = []
		for step: Dictionary in Context.plan(job): expected.append([step.kind,step.target])
		if actual!=expected: return "action effects differ from reserved assignment"
		var carrying := false
		for index in program.index:
			if program.steps[index].kind=="pickup": carrying = true
			elif program.steps[index].kind=="drop": carrying = false
		if (worker.carry_count>0)!=carrying: return "action cursor differs from physical carrying state"
		var step: Dictionary = program.steps[program.index]
		if worker.action_left<0.0: return "action remaining time is negative"
		if not program.started: continue
		if step.kind in ["move","transport"]:
			var stage := "home" if job.kind=="home" else ("go_to" if step.kind=="transport" else "go_from")
			if job.stage!=stage or not worker.walking or worker.phase!="walk": return "action move differs from real phase"
		elif step.kind=="wait":
			if worker.walking or worker.phase!="wait": return "action wait differs from real phase"
		else:
			var stage: String = {"pickup":"pick","operate":"work","drop":"drop"}[step.kind]
			if job.stage!=stage or worker.walking or worker.phase!="work": return "action work differs from real phase"
	return ""
