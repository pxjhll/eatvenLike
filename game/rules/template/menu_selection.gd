extends RefCounted
## Data-defined primary/group/addon sampling; the caller owns queue timing and RNG.
const Requirements := preload("res://game/rules/template/requirements.gd")
const Sampling := preload("res://game/rules/rule_sampling.gd")

static func compile(raw: Variant, menu: Dictionary) -> Dictionary:
	if not raw is Dictionary: return _error("invalid menu selection")
	if raw.is_empty(): return {"definition":{},"error":""}
	for key in raw:
		if key not in ["order","gates","groups","stages","addon"]: return _error("unsupported menu selection parameter: "+str(key))
	if not raw.get("order") is Array or not raw.get("gates") is Dictionary or not raw.get("groups",[]) is Array or not raw.get("stages") is Array or raw.stages.is_empty(): return _error("menu selection needs order, gates and stages")
	var result := {"order":raw.order.duplicate(),"gates":{},"groups":raw.get("groups",[]).duplicate(true),"stages":raw.stages.duplicate(true),"addon":raw.get("addon",{}).duplicate(true) if raw.get("addon",{}) is Dictionary else {}}
	var seen := {}
	for dish in result.order:
		if not dish is String or not menu.has(dish) or seen.has(dish): return _error("invalid or repeated menu order")
		seen[dish] = true
	if seen.size() != menu.size() or raw.gates.size() != menu.size(): return _error("menu selection must cover all menu dishes")
	for dish in raw.gates:
		if not menu.has(dish): return _error("unused menu requirement")
		var gate := Requirements.compile(raw.gates[dish])
		if not gate.error.is_empty(): return gate
		result.gates[dish] = gate.definition
	var groups := {}
	for group in result.groups:
		if not group is Dictionary or group.size()!=3 or not group.get("id") is String or group.id.is_empty() or menu.has(group.id) or groups.has(group.id) or not group.get("dishes") is Array or group.dishes.is_empty() or not menu.has(group.get("fallback")): return _error("invalid menu group")
		var members := {}
		for dish in group.dishes:
			if not dish is String or not menu.has(dish) or members.has(dish): return _error("invalid menu group member")
			members[dish] = true
		groups[group.id] = true
	for stage in result.stages:
		if not stage is Dictionary or stage.size()!=2 or not (stage.get("interval") is float or stage.get("interval") is int) or not is_finite(float(stage.interval)) or stage.interval <= 0.0 or not stage.get("weights") is Dictionary or stage.weights.is_empty(): return _error("invalid menu stage")
		var total := 0.0
		for key in stage.weights:
			var weight: Variant = stage.weights[key]
			if not key is String or (not menu.has(key) and not groups.has(key)) or not (weight is float or weight is int) or not is_finite(float(weight)) or weight <= 0.0: return _error("invalid menu stage weight")
			total += float(weight)
		if not is_finite(total): return _error("invalid menu total weight")
		for group in result.groups:
			if group.id not in stage.weights: continue
			for dish in group.dishes:
				if dish in stage.weights: return _error("menu group overlaps direct dish weight")
	var addon: Variant = raw.get("addon",{})
	if not addon is Dictionary: return _error("invalid menu addon")
	if not addon.is_empty():
		for key in addon:
			if key not in ["dish","share","first"]: return _error("unsupported addon parameter")
		if not menu.has(addon.get("dish")) or not addon.get("first",false) is bool or not (addon.get("share") is int or addon.get("share") is float) or not is_finite(float(addon.share)) or addon.share<0.0 or addon.share>1.0: return _error("invalid menu addon")
	return {"definition":result,"error":""}

static func validate(definition: Dictionary, owner: RefCounted) -> String:
	if owner.stage_index < 0 or owner.stage_index >= definition.stages.size(): return "outer stage is outside declared menu selection"
	for gate in definition.gates.values():
		var error := Requirements.reference_error(gate,owner)
		if not error.is_empty(): return error
	return ""

static func eligible(definition: Dictionary, dish: String, owner: RefCounted) -> bool:
	return definition.gates.has(dish) and Requirements.met(definition.gates[dish],owner)

static func weights(definition: Dictionary, owner: RefCounted) -> Dictionary:
	var configured: Dictionary = definition.stages[owner.stage_index].weights
	var result := {}
	for dish in definition.order:
		if configured.has(dish) and eligible(definition,dish,owner): result[dish] = float(configured[dish])
	for group in definition.groups:
		if not configured.has(group.id): continue
		var opened: Array = []
		for dish in group.dishes:
			if eligible(definition,dish,owner): opened.append(dish)
		var share: float = configured[group.id]
		if opened.is_empty():
			if eligible(definition,group.fallback,owner): result[group.fallback] = float(result.get(group.fallback,0.0))+share
		else:
			for dish in opened: result[dish] = float(result.get(dish,0.0))+share/opened.size()
	return result

static func request(definition: Dictionary, owner: RefCounted) -> Array:
	var available := weights(definition,owner)
	if available.is_empty(): return []
	var dish := Sampling.choose(available,owner.rng)
	var rows := [{"dish":dish,"qty":1}]
	var addon: Dictionary = definition.addon
	if not addon.is_empty() and dish != addon.dish and eligible(definition,addon.dish,owner) and owner.rng.randf()<float(addon.share): rows.append({"dish":String(addon.dish),"qty":1})
	return rows

static func _error(message: String) -> Dictionary:
	return {"definition":{},"error":message}
