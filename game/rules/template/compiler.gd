extends RefCounted
## Compile explicit capability data, not an alternate shop scripting language.
const Schema := preload("res://content/rules/spec_shop_template.gd")
const Inventory := preload("res://game/rules/template/inventory.gd")
const Machines := preload("res://game/rules/template/machines.gd")
const Contract := preload("res://game/rules/shop_content_contract.gd")
const Restock := preload("res://game/rules/template/restock.gd")
const ServicePolicy := preload("res://game/rules/template/service_policy.gd")
const Dispatch := preload("res://game/rules/template/dispatch.gd")

static func compile(template: Resource) -> Dictionary:
	var errors: Array = []
	if template == null or template.get_script() != Schema: return {"definition":{}, "errors":[_error("invalid_template", "template")]}
	if template.version != 1: return {"definition":{}, "errors":[_error("unsupported_version", "version")]}
	if not is_finite(template.hop_seconds) or template.hop_seconds < 0.0: return {"definition":{}, "errors":[_error("invalid_duration", "hop_seconds")]}
	var definition := {"version":1, "hop_seconds":template.hop_seconds, "places":{}, "machines":{}, "recipes":{}}
	var inventory := Inventory.new()
	if template.places.is_empty(): errors.append(_error("missing_places", "places"))
	for id in template.places:
		var path := "places." + str(id)
		var place: Variant = template.places[id]
		if not _id(id) or not place is Dictionary:
			errors.append(_error("invalid_place", path))
			continue
		if Inventory.is_hand_place(id):
			errors.append(_error("reserved_container", path))
			continue
		_keys(place, ["port", "capacity", "infinite", "initial"], path, errors)
		if not place.get("port") is Vector2 or not Vector2(place.port).is_finite():
			errors.append(_error("missing_port", path + ".port"))
			continue
		var capacity: Variant = place.get("capacity", -1)
		var infinite: Variant = place.get("infinite", [])
		var initial: Variant = place.get("initial", {})
		if not capacity is int or not infinite is Array or not initial is Dictionary or not Inventory._counts_valid(initial):
			errors.append(_error("invalid_place", path))
			continue
		var error := inventory.configure(id, capacity, infinite)
		if not error.is_empty():
			errors.append(_error("invalid_place", path, error))
			continue
		for item in initial:
			var seeded := inventory.seed(id, item, initial[item])
			if not String(seeded.error).is_empty(): errors.append(_error("invalid_initial_stock", path + ".initial." + str(item), seeded.error))
		definition.places[id] = {"port":place.port, "capacity":capacity, "infinite":infinite.duplicate(), "initial":initial.duplicate()}
	var machines := Machines.new(inventory)
	for id in template.machines:
		var path := "machines." + str(id)
		var machine: Variant = template.machines[id]
		if not _id(id) or not machine is Dictionary:
			errors.append(_error("invalid_machine", path))
			continue
		_keys(machine, ["input", "output", "profile"], path, errors)
		if not machine.get("input") is String or not machine.get("output") is String or not machine.get("profile", {}) is Dictionary:
			errors.append(_error("invalid_machine", path))
			continue
		var error := machines.configure(id, machine.input, machine.output, machine.get("profile", {}))
		if not error.is_empty(): errors.append(_error("invalid_machine_capability", path, error))
	definition.machines = machines.snapshot().definitions
	if not errors.is_empty(): return {"definition":{}, "errors":errors}
	var restocks := Restock.compile(template.restocks, definition.places, definition.machines)
	errors.append_array(restocks.errors)
	definition.restocks = restocks.definition
	if template.recipes.is_empty(): errors.append(_error("missing_recipes", "recipes"))
	for id in template.recipes:
		if not _id(id):
			errors.append(_error("invalid_recipe_id", "recipes." + str(id)))
			continue
		var recipe := _recipe(template.recipes[id], definition, "recipes." + id, errors)
		definition.recipes[id] = recipe
	if not errors.is_empty(): return {"definition":{}, "errors":errors}
	var service := ServicePolicy.compile(template.service, definition.places, definition.recipes)
	if not String(service.error).is_empty(): return {"definition":{}, "errors":[_error("invalid_service", "service", service.error)]}
	definition.service = service.definition
	var dispatch := Dispatch.compile(template.dispatch, definition.places, definition.machines)
	if not String(dispatch.error).is_empty(): return {"definition":{}, "errors":[_error("invalid_dispatch", "dispatch", dispatch.error)]}
	definition.dispatch = dispatch.definition
	definition.signature = Contract._canonical(definition).sha256_text()
	return {"definition":definition, "errors":[]}

static func _recipe(raw: Variant, definition: Dictionary, path: String, errors: Array) -> Dictionary:
	var nodes := {}
	var order: Array = []
	if not raw is Dictionary or not raw.get("nodes") is Array or raw.nodes.is_empty() or not raw.get("output") is Dictionary:
		errors.append(_error("invalid_recipe", path))
		return {}
	_keys(raw, ["nodes", "output"], path, errors)
	for index in raw.nodes.size():
		var row: Variant = raw.nodes[index]
		var node_path := path + ".nodes[%d]" % index
		if not row is Dictionary or not _id(row.get("id")):
			errors.append(_error("invalid_node", node_path))
			continue
		var id: String = row.id
		node_path = path + ".nodes." + id
		if nodes.has(id):
			errors.append(_error("duplicate_node", node_path))
			continue
		var capability: Variant = row.get("capability")
		if capability not in ["source", "process"]:
			errors.append(_error("unsupported_capability", node_path + ".capability"))
			continue
		var seconds: Variant = row.get("seconds", 0.0)
		var after: Variant = row.get("after", [])
		if not (seconds is int or seconds is float) or not is_finite(float(seconds)) or seconds < 0.0 or not after is Array or not row.get("label", "") is String or not row.get("fixed", false) is bool:
			errors.append(_error("invalid_node_parameters", node_path))
			continue
		var node := {"id":id, "capability":capability, "seconds":float(seconds), "label":String(row.get("label", "")),
			"dependencies":after.duplicate(), "consumes":{}, "produces":{}, "inputs":{}, "input_places":{}, "place":"", "machine":"", "fixed":bool(row.get("fixed", false))}
		if capability == "source":
			_keys(row, ["id", "capability", "place", "item", "seconds", "after", "label", "timing_target", "fixed"], node_path, errors)
			if not row.get("timing_target", "") is String:
				errors.append(_error("invalid_timing_target", node_path + ".timing_target"))
				continue
			node.timing_target = row.get("timing_target", "")
			if not _id(row.get("item")) or not _id(row.get("place")) or not definition.places.has(row.place):
				errors.append(_error("invalid_source", node_path))
				continue
			node.place = row.place
			node.produces[row.item] = 1
		else:
			_keys(row, ["id", "capability", "machine", "consumes", "produces", "inputs", "seconds", "fixed", "after", "label"], node_path, errors)
			if not _id(row.get("machine")) or not definition.machines.has(row.machine):
				errors.append(_error("missing_machine", node_path + ".machine"))
				continue
			if not row.get("consumes", {}) is Dictionary or not row.get("produces") is Dictionary or not row.get("inputs", {}) is Dictionary:
				errors.append(_error("invalid_recipe_counts", node_path))
				continue
			if not Inventory._counts_valid(row.get("consumes", {})) or not Inventory._counts_valid(row.produces) or row.produces.is_empty():
				errors.append(_error("invalid_recipe_counts", node_path))
				continue
			node.machine = row.machine
			node.place = definition.machines[row.machine].output
			node.consumes = row.get("consumes", {}).duplicate()
			node.produces = row.produces.duplicate()
			node.inputs = row.get("inputs", {}).duplicate()
		nodes[id] = node
		order.append(id)
	var demand := {}
	for id in nodes:
		var node: Dictionary = nodes[id]
		var node_path: String = path + ".nodes." + id
		for item in node.inputs:
			if not node.consumes.has(item): errors.append(_error("unused_input_binding", node_path + ".inputs." + str(item)))
		for item in node.consumes:
			var producer: Variant = node.inputs.get(item)
			if not producer is String or not nodes.has(producer):
				errors.append(_error("missing_input_binding", node_path + ".inputs." + str(item)))
				continue
			if not nodes[producer].produces.has(item):
				errors.append(_error("producer_item_differs", node_path + ".inputs." + str(item)))
				continue
			if producer not in node.dependencies: node.dependencies.append(producer)
			node.input_places[item] = nodes[producer].place
			if not demand.has(producer): demand[producer] = {}
			demand[producer][item] = int(demand[producer].get(item, 0)) + int(node.consumes[item])
		for dependency in node.dependencies:
			if not dependency is String or not nodes.has(dependency): errors.append(_error("missing_dependency", node_path + ".after"))
	var output: Dictionary = raw.output
	_keys(output, ["node", "item", "count"], path + ".output", errors)
	if not _id(output.get("node")) or not nodes.has(output.node) or not _id(output.get("item")) or not output.get("count", 1) is int or int(output.get("count", 1)) < 1:
		errors.append(_error("invalid_output", path + ".output"))
	elif not nodes[output.node].produces.has(output.item): errors.append(_error("missing_output_item", path + ".output.item"))
	else:
		if not demand.has(output.node): demand[output.node] = {}
		demand[output.node][output.item] = int(demand[output.node].get(output.item, 0)) + int(output.get("count", 1))
	for producer in demand:
		if nodes[producer].capability == "source": continue
		for item in demand[producer]:
			if int(nodes[producer].produces[item]) < int(demand[producer][item]): errors.append(_error("insufficient_output", path + ".nodes." + producer + ".produces." + str(item)))
	var sorted_nodes: Array = []
	while sorted_nodes.size() < nodes.size():
		var next := ""
		for id in order:
			if id in sorted_nodes: continue
			var ready := true
			for dependency in nodes[id].dependencies:
				if dependency not in sorted_nodes: ready = false; break
			if ready: next = id; break
		if next.is_empty():
			errors.append(_error("cycle", path + ".nodes"))
			break
		sorted_nodes.append(next)
	return {"nodes":nodes, "order":sorted_nodes, "output":{"node":output.get("node", ""), "item":output.get("item", ""), "count":output.get("count", 1)}}

static func _keys(data: Dictionary, supported: Array, path: String, errors: Array) -> void:
	for key in data:
		if key not in supported: errors.append(_error("unsupported_parameter", path + "." + str(key)))

static func _id(value: Variant) -> bool:
	return value is String and not value.is_empty()

static func _error(code: String, path: String, message := "") -> Dictionary:
	return {"code":code, "path":path, "message":code.replace("_", " ") if message.is_empty() else message}
