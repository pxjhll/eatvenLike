extends RefCounted
## Path-aware projection: quantities and dependencies are structural unless a
## specific clock/score field is declared tunable. Semantic item names are data.

static func project(template: Resource, structural: bool) -> Dictionary:
	var data := {"type":"SpecShopTemplate"}
	for key in ["version", "hop_seconds", "places", "machines", "restocks", "recipes", "service", "dispatch"]:
		if structural and key == "hop_seconds": continue
		data[key] = _walk(template.get(key), [key], structural)
	return data

static func _walk(value: Variant, path: Array, structural: bool) -> Variant:
	if value is Dictionary:
		var out := {}
		if structural and path.size() == 3 and path[0] == "machines" and path[2] == "profile":
			out.load_stage = float(value.get("load_seconds", 0.0)) > 0.0
			out.unload_stage = float(value.get("unload_seconds", 0.0)) > 0.0
		for key in value:
			var next := path + [String(key)]
			if _label(next) or (structural and _tunable(next)): continue
			out[key] = _walk(value[key], next, structural)
		return out
	if value is Array:
		var out: Array = []
		for item in value: out.append(_walk(item, path + ["[]"], structural))
		return out
	return value

static func _label(path: Array) -> bool:
	return path.size() == 5 and path[0] == "recipes" and path[2] == "nodes" and path[3] == "[]" and path[4] == "label"

static func _tunable(path: Array) -> bool:
	if path.size() == 5 and path[0] == "recipes" and path[2] == "nodes" and path[3] == "[]": return path[4] == "seconds"
	if path.size() == 4 and path[0] == "machines" and path[2] == "profile": return path[3] in ["load_seconds", "unload_seconds", "stir_seconds"]
	if path.size() == 3 and path[0] == "restocks": return path[2] in ["seconds", "fetch_seconds"]
	if path.size() == 2 and path[0] == "dispatch": return path[1] in ["affinity_bonus", "continuation_bonus", "travel_penalty"]
	if path.size() == 3 and path[0] == "dispatch" and path[1] == "scores": return true
	if path.size() == 2 and path[0] == "service": return path[1] in ["admission_seconds", "eat_seconds"]
	if path == ["service", "orders", "patience"]: return true
	if path.size() == 3 and path[0] == "service" and path[1] == "arrivals": return path[2] in ["interval", "first_delay"]
	return path == ["service", "arrivals", "choices", "[]", "weight"]
