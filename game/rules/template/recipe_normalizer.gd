extends RefCounted
## Definition/authoring boundary only. Converts supported explicit production
## into public capabilities, or returns no template with precise missing rules.
## It never selects an executor or converts a live player's running state.
const Schema := preload("res://content/rules/spec_shop_template.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")
const Inventory := preload("res://game/rules/template/inventory.gd")

static func from_shop(shop: SpecShop, selection: Array = []) -> Dictionary:
	var errors: Array = []
	if shop == null or shop.layout == null: return _result(null, [_error("missing_shop_layout", "layout")])
	for catalog in ["dishes", "stations"]:
		var entries: Array = shop.get(catalog)
		var ids := {}
		var kind: String = "dish" if catalog == "dishes" else "station"
		for index in entries.size():
			var entry: Resource = entries[index]
			var path: String = "%s[%d]" % [catalog, index]
			if entry == null: errors.append(_error("missing_" + kind, path)); continue
			if entry.id.is_empty() or ids.has(entry.id): errors.append(_error("duplicate_" + kind, path))
			ids[entry.id] = true
	if not errors.is_empty(): return _result(null, errors)
	var requested := {}
	for id in selection:
		if not id is String or id.is_empty() or requested.has(id) or shop.dish(id) == null: errors.append(_error("invalid_dish_selection", "dishes." + str(id)))
		requested[id] = true
	var template := Schema.new()
	if shop.dispatch != null: template.hop_seconds = shop.dispatch.hop_seconds
	var seen := {}
	for dish in shop.dishes:
		if not selection.is_empty() and not requested.has(dish.id): continue
		var path := "dishes." + dish.id
		if dish.id.is_empty() or seen.has(dish.id): errors.append(_error("duplicate_dish", path)); continue
		seen[dish.id] = true
		template.recipes[dish.id] = _recipe(shop, dish, template, path, errors)
	if seen.is_empty(): errors.append(_error("missing_recipes", "dishes"))
	if not errors.is_empty(): return _result(null, errors)
	var compiled := Compiler.compile(template)
	if not compiled.errors.is_empty(): return _result(null, compiled.errors)
	return _result(template, [])

static func _recipe(shop: SpecShop, dish: SpecDish, template: Resource, path: String, errors: Array) -> Dictionary:
	var nodes: Array = []
	var producers := {}
	var carried := ""
	for index in dish.steps.size():
		var step: SpecStep = dish.steps[index]
		var step_path := path + ".steps[%d]" % index
		if step == null: errors.append(_error("missing_step", step_path)); continue
		var station := shop.station(step.station)
		if station == null: errors.append(_error("missing_station", step_path + ".station")); continue
		if step.put_down: errors.append(_error("processing_display", step_path + ".put_down"))
		if step.into_machine: errors.append(_error("continuous_workbench", step_path + ".into_machine"))
		if step.repeat < 1 or not is_finite(step.seconds) or step.seconds < 0.0: errors.append(_error("invalid_step_timing", step_path)); continue
		if not Inventory._counts_valid(step.consumes) or not Inventory._counts_valid(step.produces): errors.append(_error("invalid_step_counts", step_path)); continue
		if step.produces.is_empty(): errors.append(_error("handoff_step", step_path + ".produces"))
		var source: bool = station.block in ["supply", "batch_pot"]
		if station.block == "batch_pot" and not carried.is_empty() and not step.consumes.is_empty() and not step.consumes.has(carried):
			errors.append(_error("implicit_carried_input", step_path + ".consumes"))
		if not _ensure_station(shop, station, template, errors): continue
		var id := "step:" + str(index)
		var node := {"id":id, "seconds":float(step.seconds) * int(step.repeat), "label":String(step.label)}
		if source:
			if not step.consumes.is_empty() or step.produces.size() != 1 or int(step.produces.values()[0]) != 1:
				errors.append(_error("source_step_shape", step_path)); continue
			var item: String = step.produces.keys()[0]
			if station.block == "supply":
				var infinite: Array = template.places[station.id + ":out"].infinite
				if item not in infinite: infinite.append(item)
			elif station.stock.size() != 1 or station.stock[0].item != item: errors.append(_error("source_stock_item", step_path))
			node.capability = "source"
			node.place = station.id + ":out"
			node.item = item
			node.timing_target = String(station.id)
			node.fixed = bool(step.fixed) or station.block == "batch_pot"
		else:
			if station.block not in ["hand", "combine", "dispenser"]: errors.append(_error("station_capability", step_path + ".station"))
			node.capability = "process"
			node.machine = station.id
			node.consumes = step.consumes.duplicate()
			node.produces = step.produces.duplicate()
			node.inputs = {}
			node.fixed = bool(step.fixed)
			if not step.produces.is_empty(): carried = String(step.produces.keys()[0])
		for item in step.produces:
			if producers.has(item): errors.append(_error("ambiguous_producer", step_path + ".produces." + item))
			else: producers[item] = id
		nodes.append(node)
	for node in nodes:
		if node.capability != "process": continue
		for item in node.consumes:
			if not producers.has(item): errors.append(_error("missing_input_binding", path + ".nodes." + node.id + ".inputs." + str(item)))
			else: node.inputs[item] = producers[item]
	if not producers.has(dish.item): errors.append(_error("missing_final_output", path + ".item"))
	return {"nodes":nodes, "output":{"node":producers.get(dish.item, ""), "item":String(dish.item), "count":1}}

static func _ensure_station(shop: SpecShop, station: SpecStation, template: Resource, errors: Array) -> bool:
	if template.places.has(station.id + ":out"): return true
	var path := "stations." + station.id
	if not _parameters_valid(station, errors): return false
	var key: String = shop.layout.aliases.get(station.id, station.id)
	if not shop.layout.points.has(key): errors.append(_error("missing_operation_port", path)); return false
	var port: Vector2 = shop.layout.points[key]
	if station.block == "supply":
		template.places[station.id + ":out"] = {"port":port, "infinite":[]}
		return true
	if station.block == "batch_pot":
		if station.stock.size() != 1 or station.stock[0] == null: errors.append(_error("batch_stock", path + ".stock")); return false
		var rule: SpecStockRule = station.stock[0]
		if rule.base != 0 or rule.per_waiting != 0 or rule.low != 0: errors.append(_error("stock_policy", path + ".stock[0]"))
		var capacity: int = rule.cap if rule.cap > 0 else int(station.params.get("capacity", 0))
		var batch: int = int(station.params.get("batch", 3))
		if capacity < 1 or batch < 1 or rule.start < 0: errors.append(_error("invalid_stock_capacity", path + ".params")); return false
		var profile := {"manual":false, "stir_points":station.params.get("stir_points", []).duplicate(), "stir_seconds":float(station.params.get("stir_seconds", 0.0))}
		for stage in ["load", "unload"]:
			var manual: bool = bool(station.params.get("manual_" + stage, false))
			var seconds: float = float(station.params.get(stage + "_seconds", 0.0)) if manual else 0.0
			if manual and seconds <= 0.0: errors.append(_error("zero_manual_stage", path + ".params." + stage + "_seconds"))
			profile[stage + "_seconds"] = seconds
		template.places[station.id + ":in"] = {"port":port}
		template.places[station.id + ":out"] = {"port":port, "capacity":capacity, "initial":{rule.item:rule.start} if rule.start > 0 else {}}
		template.machines[station.id] = {"input":station.id + ":in", "output":station.id + ":out", "profile":profile}
		template.restocks[station.id] = {"machine":station.id, "consumes":{}, "produces":{rule.item:batch},
			"seconds":float(station.params.get("cook_seconds", 0.0)), "stock_limit":capacity}
		return true
	var manual: bool = bool(station.params.get("manual", false)) if station.block == "combine" else true
	if not manual: errors.append(_error("automatic_workbench", path + ".params.manual")); return false
	if station.block == "hand" and int(station.params.get("users", 1)) != 1: errors.append(_error("work_slots", path + ".params.users"))
	template.places[station.id + ":in"] = {"port":port}
	template.places[station.id + ":out"] = {"port":port}
	template.machines[station.id] = {"input":station.id + ":in", "output":station.id + ":out", "profile":{"manual":manual}}
	return true

static func _parameters_valid(station: SpecStation, errors: Array) -> bool:
	var types := {}
	if station.block == "batch_pot":
		types = {"batch":TYPE_INT, "capacity":TYPE_INT, "stir_points":TYPE_ARRAY,
			"manual_load":TYPE_BOOL, "manual_unload":TYPE_BOOL, "load_seconds":TYPE_FLOAT,
			"unload_seconds":TYPE_FLOAT, "stir_seconds":TYPE_FLOAT, "cook_seconds":TYPE_FLOAT}
	elif station.block == "hand": types = {"users":TYPE_INT}
	elif station.block == "combine": types = {"manual":TYPE_BOOL}
	var valid := true
	for key in types:
		if not station.params.has(key): continue
		var value: Variant = station.params[key]
		var accepted: bool = typeof(value) == types[key]
		if types[key] == TYPE_FLOAT:
			accepted = (value is float or value is int) and is_finite(float(value)) and value >= 0.0
		if not accepted:
			errors.append(_error("invalid_station_parameter", "stations." + station.id + ".params." + key))
			valid = false
	return valid

static func _error(code: String, path: String) -> Dictionary:
	return {"code":code, "path":path, "message":code.replace("_", " ")}

static func _result(template: Resource, errors: Array) -> Dictionary:
	return {"scope":"production_only", "template":template, "errors":errors}
