extends RefCounted
## Read-only processing-item projection. Slots are machine identities; visible
## quantities and excluded showcase units come from the existing stock claim.

static func compile(raw: Variant, id: String, machine: Dictionary, places: Dictionary) -> Dictionary:
	if not raw is Dictionary: return _error("invalid processing display")
	if raw.is_empty(): return {"definition":{},"error":""}
	for key in raw:
		if key not in ["capability","items","points","host"]: return _error("unsupported processing display parameter: " + str(key))
	var binding: Dictionary = raw.duplicate(true)
	binding.machine = id
	if not binding.has("host"): binding.host = ""
	var ceiling: int = binding.points.size() if binding.get("points") is Array else 0
	var device := machine.duplicate(true)
	device.slot_ceiling = ceiling
	var error := binding_error(binding,places,{id:device},{})
	if not error.is_empty(): return _error(error)
	var needed: int = machine.slots_binding.max if machine.has("slots_binding") else machine.profile.slots
	if ceiling < needed: return _error("processing display needs a port for every declared slot")
	return {"definition":binding,"error":""}

static func binding_error(binding: Variant, places: Dictionary, devices: Dictionary, shown: Dictionary) -> String:
	if not binding is Dictionary: return "invalid processing display binding"
	for key in binding:
		if key not in ["capability","machine","items","points","host"]: return "unsupported processing display parameter: " + str(key)
	if binding.get("capability") != "processing_item" or not binding.get("machine") is String or not devices.has(binding.machine) or shown.has(binding.machine): return "invalid or duplicated processing display machine"
	var device: Dictionary = devices[binding.machine]
	if not device.has("slot_ceiling") or device.slot_ceiling < 1: return "processing display requires stable machine slots"
	if not binding.get("points") is Array or binding.points.size() < device.slot_ceiling: return "processing display needs explicit ports for all slots"
	for point in binding.points:
		if not point is Vector2 or not point.is_finite(): return "invalid processing display port"
	if not binding.get("host","") is String or not binding.get("items") is Array or binding.items.is_empty(): return "invalid processing display items or host"
	var ids := {}
	for item in binding.items:
		if not item is String or item.is_empty() or ids.has(item) or item in places[device.input].infinite: return "processing display requires unique finite input items"
		ids[item] = true
	return ""

static func usage_error(binding: Dictionary, recipes: Dictionary, restocks: Dictionary) -> String:
	var used := {}
	var inputs: Array = []
	for recipe in recipes.values():
		for node in recipe.nodes.values():
			if node.capability == "process" and node.machine == binding.machine: inputs.append(node.consumes)
	for rule in restocks.values():
		if rule.machine == binding.machine: inputs.append(rule.consumes)
	for counts in inputs:
		var matched := 0
		for item in binding.items:
			if counts.has(item): matched += 1; used[item] = true
		if matched > 1: return "processing display must select at most one input per operation"
	if used.size() != binding.items.size(): return "unused processing display input item"
	return ""

static func project(binding: Dictionary, stock: Dictionary, machines: Dictionary) -> Dictionary:
	var result := {"error":"","draws":[],"hidden":{}}
	var lots := {}
	var claims := {}
	for lot in stock.lots: lots[lot.id] = lot
	for claim in stock.claims: claims[claim.id] = claim
	for run in machines.runs:
		if run.machine != binding.machine or run.phase in ["completed","cancelled"]: continue
		var claim: Dictionary = claims[run.claim]
		var selected: Array = []
		for item in binding.items:
			if claim.consumes.has(item): selected.append(item)
		if selected.is_empty(): continue
		if selected.size() != 1: return {"error":"ambiguous processing display input","draws":[],"hidden":{}}
		var item: String = selected[0]
		var count := 0
		for part in claim.parts:
			var lot: Dictionary = lots[part.lot]
			if lot.item != item: continue
			if lot.place != claim.from: return {"error":"processing input is not at its container","draws":[],"hidden":{}}
			count += int(part.count)
			result.hidden[lot.id] = int(result.hidden.get(lot.id,0)) + int(part.count)
		if claim.state != "reserved" or count != claim.consumes[item] or not run.get("slot") is int or run.slot < 0 or run.slot >= binding.points.size(): return {"error":"processing display differs from real claim or slot","draws":[],"hidden":{}}
		result.draws.append({"capability":"processing_item","machine":run.machine,"run":int(run.id),"slot":int(run.slot),
			"item":item,"count":count,"pos":binding.points[run.slot],"host":String(binding.get("host",""))})
	return result

static func _error(message: String) -> Dictionary:
	return {"definition":{},"error":message}
