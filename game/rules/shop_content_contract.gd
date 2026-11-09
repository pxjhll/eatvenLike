extends RefCounted
## Versioned canonical fingerprints of exported gameplay resources.
const PRESENTATION := ["display_name", "description", "icon", "art", "tint", "label", "effect_label", "preview_label", "preview_dishes", "speaker", "card_text", "unlock_note", "texts", "guide", "scene_path", "save_file", "background_music", "scale_anchor"]
const TYPES := ["SpecShop", "SpecItem", "SpecDish", "SpecStation", "SpecStage", "SpecFulfillment", "SpecDispatch", "SpecFlyer", "SpecSeatGroup", "SpecStaffRules", "SpecStaffKind", "SpecConnection", "SpecOrderOption", "SpecGoalRules", "SpecLayout", "SpecMaterial", "SpecStep", "SpecStockRule", "SpecTask", "SpecUpgradeTrack", "SpecUpgradeLevel", "SpecEffect", "SpecEvent"]

static func describe(shop: SpecShop) -> Dictionary:
	return {"version": 1, "gameplay": _canonical(_project(shop, false)).sha256_text(), "structure": _canonical(_project(shop, true)).sha256_text()}

static func _project(value: Variant, structural: bool, geometry := false) -> Variant:
	if value is Resource:
		var script: Script = value.get_script()
		if script == null: return null
		var type_name: String = script.get_global_name()
		if not type_name in TYPES: return null
		if structural and type_name in ["SpecEffect", "SpecUpgradeLevel"]: return null
		var out := {"type": type_name}
		if structural and type_name == "SpecMaterial": out["has_box"] = value.box_cost > 0
		if structural and type_name == "SpecStation":
			if value.block == "pickup": out["process_role"] = value.params.has("process_seconds")
			if value.block == "hand": out["locks_user"] = int(value.params.get("users", 0)) > 0
		for prop in value.get_property_list():
			var key: String = prop.name
			if not (int(prop.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (int(prop.usage) & PROPERTY_USAGE_STORAGE): continue
			if key in PRESENTATION or (type_name == "SpecStaffKind" and key == "role"): continue
			if structural and key in ["effects", "base_effects", "stats"]: continue
			if structural and type_name == "SpecUpgradeTrack" and key == "levels":
				out[key] = value.levels.size()
				continue
			var item: Variant = value.get(key)
			if type_name == "SpecStation" and key == "params":
				item = item.duplicate(true)
				for parameter in item.keys():
					if parameter == "unit" or String(parameter).ends_with("_label") or (structural and (item[parameter] is int or item[parameter] is float)): item.erase(parameter)
			if type_name == "SpecEvent" and key == "choices":
				item = item.duplicate(true)
				for choice in item: choice.erase("label")
			if structural and type_name == "SpecSeatGroup" and key == "costs":
				out[key] = item.size()
				continue
			var identity_number: bool = (type_name == "SpecSeatGroup" and key in ["start", "step", "steps"]) or (type_name == "SpecStep" and key in ["repeat", "consumes", "produces"]) or (type_name == "SpecUpgradeTrack" and key == "requires_level") or (type_name == "SpecConnection" and key == "stage")
			if structural and not geometry and type_name != "SpecLayout" and not identity_number and (item is int or item is float): continue
			out[key] = _project(item, structural, geometry or type_name == "SpecLayout" or identity_number)
		return out
	if value is Dictionary:
		var out := {}
		for key in value:
			var item: Variant = value[key]
			out[key] = null if structural and not geometry and (item is int or item is float) else _project(item, structural, geometry)
		return out
	if value is Array:
		var out: Array = []
		for item in value: out.append(null if structural and not geometry and (item is int or item is float) else _project(item, structural, geometry))
		return out
	return value

static func _canonical(value: Variant) -> String:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return var_to_str(a) < var_to_str(b))
		var parts: PackedStringArray = []
		for key in keys: parts.append(_canonical(key) + ":" + _canonical(value[key]))
		return "{" + ",".join(parts) + "}"
	if value is Array:
		var parts: PackedStringArray = []
		for item in value: parts.append(_canonical(item))
		return "[" + ",".join(parts) + "]"
	return var_to_bytes(value).hex_encode()
