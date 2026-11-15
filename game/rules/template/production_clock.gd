extends RefCounted
## Optional processing-position rate binding. It changes the declared clock,
## independently from physical parallel machine occupancy.
const Numbers := preload("res://game/rules/rule_numbers.gd")
const Limits := preload("res://game/rules/template/numeric_limits.gd")

static func compile(raw: Variant) -> Dictionary:
	var invalid := {"definition":{},"error":"invalid processing rate binding"}
	if not raw is Dictionary: return invalid
	if raw.is_empty(): return {"definition":{},"error":""}
	for key in raw:
		if key not in ["target","base","max","ignore_duration"]: return invalid
	if not raw.get("base") is int or not raw.get("ignore_duration",false) is bool: return invalid
	var binding := Limits.compile_binding({"target":raw.get("target"),"max":raw.get("max")},raw.base,1)
	if not binding.error.is_empty(): return invalid
	binding.definition.ignore_duration = bool(raw.get("ignore_duration",false))
	return binding

static func evaluate(node: Dictionary, owner: RefCounted) -> Dictionary:
	var binding: Dictionary = node.get("slot_rate",{})
	var rate := 1.0
	if not binding.is_empty():
		rate = owner.mods.value("process_slots",float(binding.base),binding.target)
		if not is_finite(rate) or rate < 1.0 or rate > float(binding.max) or rate != floorf(rate): return {"seconds":0.0,"error":"processing rate must be a whole number within its declaration"}
	var seconds := Numbers.capability_seconds(owner.mods,owner.tune,node.machine,node.seconds,node.fixed,bool(binding.get("ignore_duration",false)))/rate
	return {"seconds":seconds,"error":"" if is_finite(seconds) and seconds >= 0.0 else "invalid effective production clock"}

static func validate(definition: Dictionary, owner: RefCounted) -> String:
	for recipe in definition.recipes.values():
		for node in recipe.nodes.values():
			if not node.has("slot_rate"): continue
			var result := evaluate(node,owner)
			if not result.error.is_empty(): return result.error
	return ""
