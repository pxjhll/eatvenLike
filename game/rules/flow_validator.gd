extends RefCounted
const Production := preload("res://game/rules/production_plan.gd")
const Actions := preload("res://game/rules/rule_actions.gd")
const Bundle := preload("res://game/rules/bundle_delivery.gd")
const Context := preload("res://game/rules/bundle_action_context.gd")

static func units(data: Dictionary, shop: SpecShop) -> String:
	var signatures := {}
	for unit: Dictionary in data.serve.units:
		if not unit.has("flow_version") and not unit.has("recipe_signature"): continue
		if shop.fulfillment.flow_version!=1 or unit.get("flow_version")!=1 or not unit.get("flow_version") is int: return "unit flow version unsupported"
		if not unit.get("recipe_signature") is String: return "unit recipe signature missing"
		if not signatures.has(unit.dish): signatures[unit.dish] = Production.compile(shop,unit.dish).signature
		if unit.recipe_signature!=signatures[unit.dish]: return "unit recipe identity changed"
		var completed := {}
		var manual := Production.work_steps(shop,unit.dish)
		for index in unit.done:
			if index not in manual or completed.has(index) or Production.blocked_inputs(shop,unit.dish,index,unit.done): return "unit completed dependencies invalid"
			completed[index] = true
	return ""

static func _find(rows: Array, id: int) -> Dictionary:
	for row: Dictionary in rows:
		if row.id==id: return row
	return {}

static func bundle(data: Dictionary, shop: SpecShop, worker: Dictionary, job: Dictionary) -> String:
	if not Bundle.enabled(shop) or shop.dispatch.action_version!=1: return "bundle delivery is not enabled"
	if not job.get("bundle_version") is int or job.bundle_version!=1: return "bundle version unsupported"
	if not job.get("order") is int or not job.get("capacity") is int or not job.get("goods") is Array: return "bundle fields invalid"
	if not worker.deployed or job.goods.is_empty() or job.capacity<job.goods.size(): return "bundle capacity invalid"
	var order := _find(data.serve.orders,int(job.order))
	if order.is_empty() or order.paid or job.guest!=order.guest or job.to!="seat:"+str(order.seat): return "bundle order invalid"
	var remaining := 0
	for line: Dictionary in order.lines: remaining += int(line.qty)-int(line.delivered)
	if job.goods.size()!=remaining: return "bundle does not cover all outstanding lines"
	var error := Actions.validate(worker.get("action"))
	if not error.is_empty(): return error
	var program: Dictionary = worker.action
	if program.status not in Actions.ACTIVE or program.lease!=Bundle.binding(worker,job): return "bundle lease invalid"
	var ids := {}
	var owners := {}
	var held: Array = []
	for entry in job.goods:
		if not entry is Dictionary or not entry.get("id") is int or not entry.get("from") is String: return "bundle good reference invalid"
		if ids.has(entry.id): return "bundle duplicates an item"
		ids[entry.id] = true
		var good := _find(data.serve.goods,int(entry.id))
		if good.is_empty() or good.res!=worker.id: return "bundle good lease invalid"
		var unit := _find(data.serve.units,int(good.owner))
		if unit.is_empty() or unit.order!=order.id or owners.has(unit.id): return "bundle unit invalid"
		owners[unit.id] = true
		if shop.dish(unit.dish).item!=good.item or entry.from!=Bundle.source_port(shop,unit.dish): return "bundle collection port invalid"
		if good.at=="hand:"+str(worker.id): held.append(int(good.id))
		elif good.at!=entry.from: return "bundle good is not at source or in hand"
	if job.good!=job.goods[0].id or job.from!=job.goods[0].from or job.item!=_find(data.serve.goods,int(job.good)).item: return "bundle first member invalid"
	var expected: Array = Context.plan(job)
	if program.steps.size()!=expected.size(): return "bundle plan length invalid"
	for index in expected.size():
		for key in ["kind","target","data"]:
			if program.steps[index][key]!=expected[index][key]: return "bundle plan differs from its reserved goods"
	var picked: Array = []
	for index in program.index:
		if program.steps[index].kind=="pickup": picked.append(int(program.steps[index].data.good))
	if worker.carry_count!=picked.size(): return "bundle cursor differs from carrying count"
	if picked.is_empty():
		if not worker.carry_item.is_empty(): return "empty bundle hands have an item"
	elif worker.carry_item!=_find(data.serve.goods,int(picked[0])).item: return "bundle displayed item invalid"
	picked.sort()
	held.sort()
	if held!=picked: return "bundle cursor differs from actual held identities"
	if program.started:
		var step: Dictionary = program.steps[program.index]
		if step.kind in ["move","transport"]:
			var stage := "deliver" if step.target.begins_with("seat:") else "collect"
			if job.stage!=stage or worker.phase!="walk" or not worker.walking: return "bundle movement phase invalid"
		elif worker.walking or worker.phase!="work" or job.stage!=("pick" if step.kind=="pickup" else "drop"): return "bundle hand action phase invalid"
	return ""

static func protected_file_error(state: Dictionary, shop: SpecShop) -> String:
	if not state.get("serve") is Dictionary: return ""
	var serve: Dictionary = state.serve
	if serve.get("units") is Array:
		var signatures := {}
		for unit in serve.units:
			if not unit is Dictionary: continue
			if unit.has("flow_version") or unit.has("recipe_signature"):
				var version: Variant = unit.get("flow_version")
				if shop.fulfillment.flow_version!=1 or ((version is int or version is float) and version>1): return "flow version is newer than configuration"
				if unit.get("dish") is String and unit.get("recipe_signature") is String and shop.dish(unit.dish)!=null:
					if not signatures.has(unit.dish): signatures[unit.dish] = Production.compile(shop,unit.dish).signature
					if unit.recipe_signature!=signatures[unit.dish]: return "active recipe identity changed"
	if serve.get("jobs") is Dictionary:
		for job in serve.jobs.values():
			if not job is Dictionary or not job.has("bundle_version"): continue
			var version: Variant = job.bundle_version
			if not Bundle.enabled(shop) or ((version is int or version is float) and version>1): return "bundle version is newer than configuration"
	return ""

static func needs_adoption(state: Dictionary, shop: SpecShop) -> bool:
	if shop.fulfillment.flow_version!=1 or not state.get("serve") is Dictionary or not state.serve.get("units") is Array: return false
	for unit in state.serve.units:
		if unit is Dictionary and not unit.has("flow_version") and not unit.has("recipe_signature"): return true
	return false
