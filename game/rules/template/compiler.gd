extends RefCounted
## Compile explicit capability data, not an alternate shop scripting language.
const Schema := preload("res://content/rules/spec_shop_template.gd")
const Inventory := preload("res://game/rules/template/inventory.gd")
const Machines := preload("res://game/rules/template/machines.gd")
const Contract := preload("res://game/rules/shop_content_contract.gd")
const Restock := preload("res://game/rules/template/restock.gd")
const ServicePolicy := preload("res://game/rules/template/service_policy.gd")
const Dispatch := preload("res://game/rules/template/dispatch.gd")
const Limits := preload("res://game/rules/template/numeric_limits.gd")
const ProcessingDisplay := preload("res://game/rules/template/processing_display.gd")
const Clock := preload("res://game/rules/template/production_clock.gd")

static func compile(template: Resource, anchors: Dictionary = {}) -> Dictionary:
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
		_keys(place, ["port", "anchor", "capacity", "infinite", "initial", "capacity_binding"], path, errors)
		var port: Variant = place.get("port")
		if place.has("anchor"):
			if place.has("port") or not _id(place.anchor) or not anchors.get(place.anchor) is Vector2:
				errors.append(_error("invalid_scene_anchor",path + ".anchor")); continue
			port = anchors[place.anchor]
		if not port is Vector2 or not Vector2(port).is_finite():
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
		definition.places[id] = {"port":port, "capacity":capacity, "infinite":infinite.duplicate(), "initial":initial.duplicate()}
		var binding := Limits.compile_binding(place.get("capacity_binding",{}),capacity,0)
		if not binding.error.is_empty(): errors.append(_error("invalid_capacity_binding",path + ".capacity_binding",binding.error))
		elif not binding.definition.is_empty(): definition.places[id].capacity_binding = binding.definition
	var machines := Machines.new(inventory)
	var slot_bindings := {}
	var processing_displays := {}
	for id in template.machines:
		var path := "machines." + str(id)
		var machine: Variant = template.machines[id]
		if not _id(id) or not machine is Dictionary:
			errors.append(_error("invalid_machine", path))
			continue
		_keys(machine, ["input", "output", "profile", "slots_binding", "processing_display", "work_port", "stage_ports", "stage_timing"], path, errors)
		if not machine.get("input") is String or not machine.get("output") is String or not machine.get("profile", {}) is Dictionary or not machine.get("work_port","") is String or not machine.get("stage_ports",{}) is Dictionary or not machine.get("stage_timing",{}) is Dictionary:
			errors.append(_error("invalid_machine", path))
			continue
		var error := machines.configure(id, machine.input, machine.output, machine.get("profile", {}),machine.get("work_port",""),machine.get("stage_ports",{}),machine.get("stage_timing",{}))
		if not error.is_empty(): errors.append(_error("invalid_machine_capability", path, error))
		else:
			var binding := Limits.compile_binding(machine.get("slots_binding",{}),int(machines.snapshot().definitions[id].profile.slots),1)
			if not binding.error.is_empty(): errors.append(_error("invalid_slots_binding",path + ".slots_binding",binding.error))
			elif not binding.definition.is_empty(): slot_bindings[id] = binding.definition
			var device: Dictionary = machines.snapshot().definitions[id]
			if not binding.definition.is_empty(): device.slots_binding = binding.definition
			var display := ProcessingDisplay.compile(machine.get("processing_display",{}),id,device,definition.places)
			if not display.error.is_empty(): errors.append(_error("invalid_processing_display",path + ".processing_display",display.error))
			elif not display.definition.is_empty():
				processing_displays[id] = display.definition
				machines.track_slots(id,display.definition.points.size())
	definition.machines = machines.snapshot().definitions
	for id in slot_bindings: definition.machines[id].slots_binding = slot_bindings[id]
	for id in processing_displays: definition.machines[id].processing_display = processing_displays[id]
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
	for id in processing_displays:
		var display_error := ProcessingDisplay.usage_error(processing_displays[id],definition.recipes,definition.restocks)
		if not display_error.is_empty(): errors.append(_error("invalid_processing_display_input","machines." + id + ".processing_display",display_error))
	if not errors.is_empty(): return {"definition":{}, "errors":errors}
	var service := ServicePolicy.compile(template.service, definition.places, definition.recipes)
	if not String(service.error).is_empty(): return {"definition":{}, "errors":[_error("invalid_service", "service", service.error)]}
	definition.service = service.definition
	var dispatch := Dispatch.compile(template.dispatch, definition.places, definition.machines)
	if not String(dispatch.error).is_empty(): return {"definition":{}, "errors":[_error("invalid_dispatch", "dispatch", dispatch.error)]}
	definition.dispatch = dispatch.definition
	definition.signature = Contract._canonical(definition).sha256_text()
	return {"definition":definition, "errors":[]}

static func ports_from_layout(layout: SpecLayout) -> Dictionary:
	var result: Dictionary = layout.points.duplicate()
	for alias in layout.aliases:
		result.erase(alias)
		if layout.points.has(layout.aliases[alias]): result[alias] = layout.points[layout.aliases[alias]]
	for post in layout.posts: result["post:"+str(post)] = layout.posts[post]
	return result

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
		if capability not in ["source", "process", "transfer"]:
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
		elif capability == "transfer":
			_keys(row, ["id", "capability", "input", "place", "item", "count", "seconds", "after", "label", "timing_target", "fixed"], node_path, errors)
			if not _id(row.get("input")) or not _id(row.get("place")) or not definition.places.has(row.place) or not _id(row.get("item")):
				errors.append(_error("invalid_transfer", node_path)); continue
			var count: Variant = row.get("count",1)
			if not count is int or count < 1 or not row.get("timing_target","") is String or (node.fixed and String(row.get("timing_target","")).is_empty()):
				errors.append(_error("invalid_transfer_parameters", node_path)); continue
			node.place = row.place
			node.timing_target = row.get("timing_target","")
			node.consumes = {row.item:count}
			node.produces = {row.item:count}
			node.inputs = {row.item:row.input}
			if row.item in definition.places[row.place].infinite: errors.append(_error("integrated_transfer_destination",node_path + ".place"))
		else:
			_keys(row, ["id", "capability", "machine", "consumes", "produces", "inputs", "seconds", "fixed", "after", "label", "slot_rate"], node_path, errors)
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
			var clock := Clock.compile(row.get("slot_rate",{}))
			if not clock.error.is_empty(): errors.append(_error("invalid_slot_rate",node_path + ".slot_rate",clock.error))
			elif not clock.definition.is_empty(): node.slot_rate = clock.definition
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
			if producer is Dictionary:
				if node.capability != "process" or not Inventory._shape(producer, {"capability":""}) or producer.capability != "integrated":
					errors.append(_error("invalid_integrated_binding", node_path + ".inputs." + str(item)))
					continue
				var input: String = definition.machines[node.machine].input
				if item not in definition.places[input].infinite:
					errors.append(_error("integrated_input_unavailable", node_path + ".inputs." + str(item)))
					continue
				node.input_places[item] = input
				continue
			if not producer is String or not nodes.has(producer):
				errors.append(_error("missing_input_binding", node_path + ".inputs." + str(item)))
				continue
			if not nodes[producer].produces.has(item):
				errors.append(_error("producer_item_differs", node_path + ".inputs." + str(item)))
				continue
			if producer not in node.dependencies: node.dependencies.append(producer)
			node.input_places[item] = nodes[producer].place
			if node.capability == "transfer" and node.place == nodes[producer].place:
				errors.append(_error("same_transfer_container",node_path + ".place"))
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
