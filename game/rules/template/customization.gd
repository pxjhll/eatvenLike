extends RefCounted
## Optional order selection/quote policy. Variants name ordinary recipe graphs;
## this module never executes finishing actions or maintains physical stock.
const Numbers := preload("res://game/rules/rule_numbers.gd")

static func compile(raw: Variant, menu: Dictionary, recipes: Dictionary, rounding: String) -> Dictionary:
	if not raw is Dictionary: return _error("invalid customization definition")
	if raw.is_empty(): return {"definition":{},"error":""}
	if raw.size() != 2 or not raw.get("options") is Array or not raw.get("variants") is Dictionary or raw.options.is_empty() or raw.options.size() > 8 or raw.variants.is_empty(): return _error("customization needs options and explicit recipe variants")
	if rounding != "order_round": return _error("customization requires raw prices with whole-order rounding")
	var result := {"options":[],"variants":{}}
	var ids := {}
	for entry in raw.options:
		if not entry is Dictionary or entry.size() != 4 or not entry.get("id") is String or not entry.get("unlock") is String: return _error("invalid order option")
		for key in ["share","price_mult"]:
			if not (entry.get(key) is int or entry.get(key) is float): return _error("invalid order option number")
		if entry.id.is_empty() or entry.unlock.is_empty() or ids.has(entry.id) or not is_finite(entry.share) or entry.share < 0.0 or entry.share > 1.0 or not is_finite(entry.price_mult) or entry.price_mult <= 0.0: return _error("invalid order option identity or values")
		ids[entry.id] = true
		result.options.append({"id":entry.id,"unlock":entry.unlock,"share":float(entry.share),"price_mult":float(entry.price_mult)})
	var used := {}
	for dish in raw.variants:
		if not dish is String or not menu.has(dish) or not raw.variants[dish] is Array or raw.variants[dish].is_empty(): return _error("invalid variant dish")
		var variants: Array = []
		var keys := {}
		var applicable := {}
		for row in raw.variants[dish]:
			if not row is Dictionary or row.size() != 2 or not row.get("options") is Array or not row.get("recipe") is String or not recipes.has(row.recipe) or recipes[row.recipe].output.count != 1: return _error("invalid variant recipe")
			var selected := canonical(result,row.options)
			if not selected.error.is_empty() or selected.ids.is_empty(): return _error("invalid variant options")
			var key := JSON.stringify(selected.ids)
			if keys.has(key): return _error("duplicate variant combination")
			keys[key] = true
			var multiplier := 1.0
			for option in result.options:
				if option.id in selected.ids:
					multiplier *= option.price_mult
					applicable[option.id] = true
					used[option.id] = true
			if not is_finite(multiplier) or multiplier <= 0.0: return _error("option multiplier overflow or underflow")
			variants.append({"options":selected.ids,"recipe":row.recipe})
		var choices: Array = []
		for option in result.options:
			if applicable.has(option.id): choices.append(option.id)
		for mask in range(1,1 << choices.size()):
			var combination: Array = []
			for index in choices.size():
				if mask & (1 << index): combination.append(choices[index])
			if not keys.has(JSON.stringify(combination)): return _error("missing explicit option combination recipe")
		result.variants[dish] = variants
	if used.size() != ids.size(): return _error("unused order option")
	return {"definition":result,"error":""}

static func canonical(definition: Dictionary, selected: Variant) -> Dictionary:
	if not selected is Array: return {"ids":[],"error":"selected options must be an array"}
	var wanted := {}
	for id in selected:
		if not id is String or wanted.has(id): return {"ids":[],"error":"invalid or duplicated selected option"}
		wanted[id] = true
	var ordered: Array = []
	for option in definition.get("options",[]):
		if wanted.has(option.id): ordered.append(option.id)
	return {"ids":ordered,"error":"unknown selected option" if wanted.size() != ordered.size() else ""}

static func resolve(definition: Dictionary, dish: String, base: String, selected: Variant) -> Dictionary:
	var normalized := canonical(definition,selected)
	if not normalized.error.is_empty(): return {"recipe":"","error":normalized.error}
	if normalized.ids.is_empty(): return {"recipe":base,"error":""}
	for variant in definition.get("variants",{}).get(dish,[]):
		if variant.options == normalized.ids: return {"recipe":variant.recipe,"error":""}
	return {"recipe":"","error":"option combination is not declared for this primary dish"}

static func select(definition: Dictionary, dish: String, base: String, selected: Variant, owner: RefCounted) -> Dictionary:
	var available := {}
	for variant in definition.get("variants",{}).get(dish,[]):
		for id in variant.options: available[id] = true
	var chosen: Array = []
	if selected != null:
		var normalized := canonical(definition,selected)
		if not normalized.error.is_empty(): return {"ids":[],"recipe":"","error":normalized.error}
		chosen = normalized.ids
		for option in definition.get("options",[]):
			if option.id in chosen and (not available.has(option.id) or not owner.station_unlocked(option.unlock)): return {"ids":[],"recipe":"","error":"selected option is unavailable"}
	else:
		for option in definition.get("options",[]):
			if available.has(option.id) and owner.station_unlocked(option.unlock) and owner.rng.randf() < option.share: chosen.append(option.id)
	var resolved := resolve(definition,dish,base,chosen)
	return {"ids":chosen,"recipe":resolved.recipe,"error":resolved.error}

static func quote(definition: Dictionary, owner: RefCounted, dish: String, selected: Array) -> float:
	var price := Numbers.raw_price(owner.shop,owner.mods,owner.tune,dish)
	for option in definition.options:
		if option.id in selected: price *= option.price_mult
	return price

static func _error(message: String) -> Dictionary:
	return {"definition":{},"error":message}
