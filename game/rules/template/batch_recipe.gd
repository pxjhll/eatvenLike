extends RefCounted
## Batch size is a bounded numeric parameter, not another inventory counter.
## Active operations retain their committed quantities in the ordinary claim.
const Inventory := preload("res://game/rules/template/inventory.gd")
const MAX_COUNT := 9223372036854775807
const MAX_BATCH := 9007199254740991

static func compile(raw: Variant, consumes: Dictionary, produces: Dictionary, input: Dictionary, output: Dictionary, limit: int) -> Dictionary:
	var invalid := {"definition":{},"error":"invalid batch binding or maximum exceeds declared storage"}
	if not raw is Dictionary: return invalid
	if raw.is_empty(): return {"definition":{},"error":""}
	for key in raw:
		if key not in ["target","base","max"]: return invalid
	if not raw.get("target") is String or raw.target.is_empty() or not raw.get("base") is int or not raw.get("max") is int: return invalid
	if raw.base < 1 or raw.max < raw.base or raw.max > MAX_BATCH: return invalid
	var maximum := scale(produces, raw.max)
	var materials := scale(consumes, raw.max)
	if not maximum.error.is_empty() or not materials.error.is_empty(): return invalid
	if Inventory._total(maximum.counts) > limit or (output.capacity >= 0 and Inventory._total(maximum.counts) > output.capacity): return invalid
	for item in input.infinite: materials.counts.erase(item)
	if input.capacity >= 0 and Inventory._total(materials.counts) > input.capacity: return invalid
	return {"definition":raw.duplicate(true),"error":""}

static func evaluate(rule: Dictionary, mods: RefCounted) -> Dictionary:
	var binding: Dictionary = rule.get("batch", {})
	if binding.is_empty(): return {"definition":rule,"error":""}
	var amount: float = mods.value("batch", float(binding.base), binding.target)
	if not is_finite(amount) or amount < 1.0 or amount > float(binding.max) or amount != floorf(amount):
		return {"definition":{},"error":"effective batch must be a whole number within its declared range"}
	var result: Dictionary = rule.duplicate(true)
	result.consumes = scale(rule.consumes, int(amount)).counts
	result.produces = scale(rule.produces, int(amount)).counts
	return {"definition":result,"error":""}

static func matches(rule: Dictionary, claim: Dictionary) -> bool:
	var binding: Dictionary = rule.get("batch", {})
	if binding.is_empty(): return claim.consumes == rule.consumes and claim.produces == rule.produces
	var item: String = rule.produces.keys()[0]
	var actual: int = int(claim.produces.get(item,0))
	var per_serving: int = int(rule.produces[item])
	if actual < 1 or actual % per_serving != 0: return false
	@warning_ignore("integer_division")
	var amount: int = actual / per_serving
	if amount < 1 or amount > int(binding.max): return false
	return claim.consumes == scale(rule.consumes,amount).counts and claim.produces == scale(rule.produces,amount).counts

static func scale(counts: Dictionary, amount: int) -> Dictionary:
	if amount < 1: return {"counts":{},"error":"batch size must be positive"}
	var result := {}
	var total := 0
	for item in counts:
		@warning_ignore("integer_division")
		var overflow: bool = int(counts[item]) > MAX_COUNT / amount
		if overflow: return {"counts":{},"error":"batch quantity overflow"}
		var quantity: int = int(counts[item]) * amount
		if total > MAX_COUNT - quantity: return {"counts":{},"error":"batch quantity overflow"}
		total += quantity
		result[item] = quantity
	return {"counts":result,"error":""}
