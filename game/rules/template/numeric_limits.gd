extends RefCounted
## Derived numeric targets. Inventory/operation occupancy stays authoritative;
## neither targets nor retained headroom introduce another quantity ledger.
const MAX_EXACT := 9007199254740991

static func compile_binding(raw: Variant, base: int, minimum: int) -> Dictionary:
	var invalid := {"definition":{},"error":"invalid numeric limit binding"}
	if not raw is Dictionary: return invalid
	if raw.is_empty(): return {"definition":{},"error":""}
	for key in raw:
		if key not in ["target","max"]: return invalid
	if not raw.get("target") is String or raw.target.is_empty() or not raw.get("max") is int: return invalid
	if base < minimum or raw.max < base or raw.max > MAX_EXACT: return invalid
	return {"definition":{"target":raw.target,"base":base,"max":raw.max},"error":""}

static func storage_ceiling(place: Dictionary) -> Dictionary:
	if not place.has("capacity_binding"): return place
	var result := place.duplicate(true)
	result.capacity = place.capacity_binding.max
	return result

static func plan(definition: Dictionary, mods: RefCounted) -> Dictionary:
	var result := {"capacity":{},"slots":{}}
	for scope in ["capacity","slots"]:
		var entries: Dictionary = definition.places if scope == "capacity" else definition.machines
		var key := "capacity_binding" if scope == "capacity" else "slots_binding"
		var kind := "capacity" if scope == "capacity" else "process_slots"
		var minimum := 0 if scope == "capacity" else 1
		for id in entries:
			if not entries[id].has(key): continue
			var binding: Dictionary = entries[id][key]
			var value: float = mods.value(kind,float(binding.base),binding.target)
			if not is_finite(value) or value < minimum or value > float(binding.max) or value != floorf(value):
				return {"definition":{},"error":scope + "." + id + ": numeric target must be a whole number within its declared range"}
			result[scope][id] = int(value)
	return {"definition":result,"error":""}

static func apply_plan(values: Dictionary, runner: RefCounted) -> String:
	for id in values.capacity:
		var error: String = runner.inventory.set_capacity_limit(id,values.capacity[id])
		if not error.is_empty(): return error
	for id in values.slots:
		var error: String = runner.machines.set_slots_limit(id,values.slots[id])
		if not error.is_empty(): return error
	return ""

static func sync(definition: Dictionary, runner: RefCounted) -> String:
	var values := plan(definition,runner.owner.mods)
	return String(values.error) if not values.error.is_empty() else apply_plan(values.definition,runner)

static func restore_overrides(definition: Dictionary, data: Dictionary) -> Dictionary:
	var result := {"capacity":{},"slots":{}}
	for scope in ["capacity","slots"]:
		var entries: Dictionary = definition.places if scope == "capacity" else definition.machines
		var key := "capacity_binding" if scope == "capacity" else "slots_binding"
		for id in entries:
			if not entries[id].has(key): continue
			var state: Variant = data.get("inventory" if scope == "capacity" else "machines")
			if not state is Dictionary: return {"definition":{},"error":"missing numeric limit state"}
			var records: Variant = state.get("places" if scope == "capacity" else "definitions")
			if not records is Dictionary or not records.get(id) is Dictionary: return {"definition":{},"error":"missing declared numeric limit"}
			var value: Variant
			if scope == "capacity": value = records[id].get("capacity")
			else:
				if not records[id].get("profile") is Dictionary: return {"definition":{},"error":"missing machine profile"}
				value = records[id].profile.get("slots")
			if not value is int or value < (0 if scope == "capacity" else 1) or value > int(entries[id][key].max):
				return {"definition":{},"error":"saved numeric limit exceeds its declaration"}
			result[scope][id] = value
	return {"definition":result,"error":""}

static func frame(definition: Dictionary, runner: RefCounted) -> Dictionary:
	var values := plan(definition,runner.owner.mods)
	if not values.error.is_empty(): return {"error":values.error,"capacity":{},"slots":{}}
	var result := {"error":"","capacity":{},"slots":{}}
	var stock: Dictionary = runner.inventory.snapshot()
	var machines: Dictionary = runner.machines.snapshot()
	for id in values.definition.capacity:
		result.capacity[id] = {"target":values.definition.capacity[id],"applied":stock.places[id].capacity,"used":runner.inventory.occupied_capacity(id)}
	for id in values.definition.slots:
		result.slots[id] = {"target":values.definition.slots[id],"applied":machines.definitions[id].profile.slots,"used":runner.machines.occupied_slots(id)}
	return result

static func enabled(definition: Dictionary) -> bool:
	for place in definition.places.values():
		if place.has("capacity_binding"): return true
	for machine in definition.machines.values():
		if machine.has("slots_binding"): return true
	return false
