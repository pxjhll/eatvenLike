extends RefCounted
const Production := preload("res://game/rules/production_plan.gd")
## Pure configuration contract. No resources are loaded and no runtime rules are built.

static func _supported(values: Array = []) -> Dictionary:
	return {"status": "supported", "values": values}

static func _fixed(values: Array) -> Dictionary:
	return {"status": "mode_fixed", "values": values}

static func _reserved(value: Variant) -> Dictionary:
	return {"status": "reserved", "default": value}

static func capabilities(mode: String) -> Dictionary:
	if mode == "serve": return _serve_capabilities()
	if mode not in ["single", "handoff"]: return {}
	var single := mode == "single"
	var f := {
		"flow_version":_reserved(0),"delivery_batch":_reserved("item"),"delivery_points":_reserved({}),
		"handoff": _fixed([mode]), "taker": _fixed(["follower" if single else "front"]),
		"dine_rule": _fixed(["takeaway_only" if single else "seat_first"]),
		"pay_at": _supported(["on_take", "on_deliver"]) if single else _fixed(["on_deliver"]),
		"price_rounding": _fixed(["order_round" if single else "dish_tenth_carry"]),
		"leave_queue": _fixed(["after_take", "after_pay"] if single else ["after_deliver"]),
		"wait_area": _fixed(["wait_seats" if single else ""]),
		"leave_who": _fixed(["queued_unclaimed" if single else "none"]),
		"arrival": _supported(["fixed", "exponential"]) if single else _fixed(["fixed"]),
		"mood_seconds": _supported(),
		"addon_dish": _supported() if single else _reserved(""),
		"addon_chance": _supported() if single else _reserved(0.0),
		"addon_first": _supported() if single else _reserved(true),
		"takeaway_station": _reserved("") if single else _supported(),
		"seated_patience": _reserved(1.0) if single else _supported(),
		"leave_after": _supported() if single else _reserved(0.0),
		"ramp_start": _reserved(1.0) if single else _supported(),
		"ramp_orders": _reserved(0) if single else _supported(),
		"opening_customers": _reserved(0) if single else _supported(),
		"first_customer_delay": _supported() if single else _reserved(0.0),
		"customer_walk": _reserved(0.0),
	}
	var d := {
		"action_version": _supported([0,1]),
		"transport_helpers": _reserved([]),
		"preposition_work": _reserved(false),
		"prefetch_inputs": _reserved(false),
		"base_scores": _reserved({}) if single else _supported(),
		"merge": _fixed(["fixed" if single else "carry"]), "merge_cap": _fixed([1]),
		"resume_from_stock": _reserved(true) if single else _supported(),
		"help_while_waiting": _fixed([true]), "leave_seated_segments": _fixed([true]),
		"chores_first": _supported() if single else _reserved(false),
		"shortage_bonus": _reserved(0.0), "shortage_per": _reserved(0.0), "shortage_cap": _reserved(0.0),
	}
	for key in ["wait_bonus_per_second", "wait_bonus_cap", "travel_penalty", "throughput_weight", "fatigue_weight", "fatigue_gain", "fatigue_recover", "hop_seconds", "ticket_give_up"]:
		d[key] = _reserved(0.0) if single else _supported()
	return {"fulfillment": f, "dispatch": d}

## serve（§10 草案，首轮原型）：前厅接单分座 → 后厨按配方依赖合流 → 出餐口 → 前厅送到座位（seat_wait）
## 或客人在出餐口自取整单（self_pickup）→ 就座且整单送齐开吃。
## 每趟端 1 件、不合送；整单送齐时一次结账；附加菜（例汤）作为订单第二条明细。
static func _serve_capabilities() -> Dictionary:
	var f := {
		"flow_version":_supported([0,1]),"delivery_batch":_supported(["item","order"]),"delivery_points":_supported(),
		"handoff": _fixed(["serve"]), "taker": _fixed(["front"]), "dine_rule": _supported(["seat_wait", "self_pickup"]),
		"pay_at": _fixed(["on_deliver"]), "price_rounding": _fixed(["dish_tenth_carry"]), "leave_queue": _fixed(["after_take"]),
		"wait_area": _fixed([""]), "leave_who": _supported(["none", "queued_unclaimed"]), "arrival": _supported(["fixed", "exponential"]),
		"mood_seconds": _supported(), "addon_dish": _supported(), "addon_chance": _supported(), "addon_first": _reserved(true),
		"takeaway_station": _reserved(""), "seated_patience": _reserved(1.0), "leave_after": _supported(),
		"ramp_start": _reserved(1.0), "ramp_orders": _reserved(0), "opening_customers": _reserved(0),
		"first_customer_delay": _supported(), "customer_walk": _supported(),
	}
	var d := {
		"action_version": _supported([0,1]),
		"transport_helpers": _supported(),
		"preposition_work": _supported(),
		"prefetch_inputs": _supported(),
		"base_scores": _supported(), "merge": _fixed(["fixed"]), "merge_cap": _fixed([1]), "resume_from_stock": _reserved(true),
		"help_while_waiting": _fixed([true]), "leave_seated_segments": _fixed([true]), "chores_first": _reserved(false),
		"shortage_bonus": _reserved(0.0), "shortage_per": _reserved(0.0), "shortage_cap": _reserved(0.0),
		"wait_bonus_per_second": _supported(), "wait_bonus_cap": _supported(), "travel_penalty": _supported(), "hop_seconds": _supported(),
		"throughput_weight": _reserved(0.0), "fatigue_weight": _reserved(0.0), "fatigue_gain": _reserved(0.0), "fatigue_recover": _reserved(0.0),
		"ticket_give_up": _reserved(0.0),
	}
	return {"fulfillment": f, "dispatch": d}

const SERVE_SCORES := ["take", "serve", "carry", "work", "pass", "continuation"]

static func summary(errors: Array) -> String:
	var lines: PackedStringArray = []
	for e in errors: lines.append("%s: %s" % [e.path, e.message])
	return "\n".join(lines)

static func _error(errors: Array[Dictionary], path: String, message: String, code := "invalid") -> void:
	errors.append({"code": code, "path": path, "message": message})

static func _number(value: Variant, path: String, errors: Array[Dictionary], minimum := 0.0, positive := false, maximum := INF) -> void:
	if not (value is int or value is float) or not is_finite(float(value)):
		_error(errors, path, "Expected a finite number.", "number")
	elif float(value) < minimum or (positive and float(value) <= minimum) or float(value) > maximum:
		_error(errors, path, "Number is outside the supported range.", "range")

static func _enum(value: Variant, values: Array, path: String, errors: Array[Dictionary]) -> void:
	if value not in values: _error(errors, path, "Expected one of %s." % str(values), "unsupported")

static func _ref(id: String, ids: Dictionary, path: String, errors: Array[Dictionary], optional := false) -> void:
	if optional and id.is_empty(): return
	if not ids.has(id): _error(errors, path, "Unknown reference: " + id, "reference")

static func _ids(values: Array, path: String, errors: Array[Dictionary], required := false, allow_empty_id := false) -> Dictionary:
	var ids := {}
	if required and values.is_empty(): _error(errors, path, "At least one entry is required.", "required")
	for i in values.size():
		var p := "%s[%d]" % [path, i]
		if values[i] == null:
			_error(errors, p, "Resource is required.", "required")
			continue
		var id: String = values[i].id
		if id.strip_edges().is_empty() and not allow_empty_id: _error(errors, p + ".id", "ID must not be empty.", "id")
		elif ids.has(id): _error(errors, p + ".id", "Duplicate ID: " + id, "duplicate")
		else: ids[id] = values[i]
	return ids

## Traverse exported values to catch null entries and non-finite numbers before consumers.
## Metadata dictionaries stay extensible; domain-specific checks below define their shape.
static func _walk(value: Variant, path: String, errors: Array[Dictionary]) -> void:
	if value is Resource:
		for prop in value.get_property_list():
			if not (int(prop.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE): continue
			var p: String = prop.name if path.is_empty() else path + "." + prop.name
			var child: Variant = value.get(prop.name)
			if child == null:
				if prop.name in ["fulfillment", "dispatch", "flyer", "staff", "goals", "layout", "track", "step"]:
					_error(errors, p, "Resource is required.", "required")
			else: _walk(child, p, errors)
	elif value is Array:
		for i in value.size():
			var p := "%s[%d]" % [path, i]
			if value[i] == null: _error(errors, p, "Entry must not be null.", "required")
			else: _walk(value[i], p, errors)
	elif value is Dictionary:
		for key in value: _walk(value[key], path + "." + str(key), errors)
	elif value is float:
		if not is_finite(value): _error(errors, path, "Expected a finite number.", "number")
	elif value is Vector2:
		if not value.is_finite(): _error(errors, path, "Expected finite coordinates.", "number")
	elif value is Rect2:
		if not value.position.is_finite() or not value.size.is_finite(): _error(errors, path, "Expected finite bounds.", "number")

static func validate(shop: SpecShop, campaign: SpecCampaign = null) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	if shop == null:
		_error(errors, "shop", "Shop resource is required.", "required")
		return errors
	_walk(shop, "", errors)
	var public_definition := {}
	if shop.runtime_template!=null:
		if shop.runtime_template.get_script()!=load("res://content/rules/spec_shop_template.gd"):
			_error(errors,"runtime_template.script","Use the shared declarative template schema; private scripts are not supported.","unsupported")
		elif shop.layout!=null:
			var menu: Variant = shop.runtime_template.service.get("menu",{})
			if menu is Dictionary:
				for id in menu:
					if id is String and shop.dish(id)==null: _error(errors,"runtime_template.service.menu."+id,"Menu dish has no shared price/art catalog definition.","reference")
			var compiler: Script = load("res://game/rules/template/compiler.gd")
			var compiled: Dictionary = compiler.compile(shop.runtime_template,compiler.ports_from_layout(shop.layout))
			for row in compiled.errors: _error(errors,"runtime_template."+row.path,row.message,row.code)
			if compiled.errors.is_empty():
				public_definition = compiled.definition
				if compiled.definition.service.is_empty() or compiled.definition.service.arrivals.is_empty():
					_error(errors,"runtime_template.service","Formal shops require an explicit service and arrival policy.","required")
	if shop.id.strip_edges().is_empty(): _error(errors, "id", "ID must not be empty.", "id")
	_number(shop.start_gold, "start_gold", errors)
	_number(shop.flavor_flow, "flavor_flow", errors)
	_number(shop.level_flow, "level_flow", errors)
	var context := {
		"items": _ids(shop.items, "items", errors, true), "dishes": _ids(shop.dishes, "dishes", errors, true),
		"stations": _ids(shop.stations, "stations", errors, true), "stages": _ids(shop.stages, "stages", errors, true),
		"seats": _ids(shop.seat_groups, "seat_groups", errors), "connections": _ids(shop.connections, "connections", errors),
		"options": _ids(shop.order_options, "order_options", errors), "events": _ids(shop.events, "events", errors),
		"guides": _ids(shop.guide, "guide", errors), "kinds": {}, "zones": {"": true}, "materials": {}, "tracks": {}, "campaign": {},
		"public":shop.runtime_template!=null,"public_definition":public_definition,
		"mode": shop.fulfillment.handoff if shop.fulfillment != null else "",
		"zoned": shop.staff != null and not shop.staff.zones.is_empty(),
	}
	if campaign != null:
		var cities := _ids(campaign.cities, "campaign.cities", errors, true)
		for city_id in cities:
			var city: SpecCity = cities[city_id]
			for entry in city.shops:
				if entry == null:
					_error(errors, "campaign.cities." + city_id + ".shops", "Shop entry is required.")
					continue
				if entry.id.is_empty() or context.campaign.has(entry.id): _error(errors, "campaign.shops", "Shop IDs must be nonempty and unique.")
				context.campaign[entry.id] = true
		_ref(shop.id, context.campaign, "id", errors)
	if shop.staff != null:
		context.kinds = _ids(shop.staff.kinds, "staff.kinds", errors, true)
		for zone in shop.staff.zones:
			if zone in ["front", "kitchen"]: context.zones[zone] = true
	for i in shop.stations.size():
		var station := shop.stations[i]
		if station == null: continue
		var p := "stations[%d]" % i
		var materials := _ids(station.materials, p + ".materials", errors)
		for id in materials: context.materials[id] = materials[id]
		context.tracks[station.id] = true
		for id in materials: context.tracks[station.id + "/" + id] = true
	if shop.staff != null:
		for track in shop.staff.tracks:
			if track != null: context.tracks["staff/" + track.id] = true
	context.tracks["flyer"] = true
	for id in context.seats: context.tracks["seat/" + id] = true
	_validate_policies(shop, context, errors)
	for i in shop.stations.size():
		if shop.stations[i] != null: _station(shop.stations[i], "stations[%d]" % i, context, errors)
	for i in shop.dishes.size():
		if shop.dishes[i] != null: _dish(shop.dishes[i], "dishes[%d]" % i, context, errors)
	for i in shop.stages.size():
		if shop.stages[i] != null: _stage(shop.stages[i], "stages[%d]" % i, context, errors)
	_validate_staff(shop, context, errors)
	_validate_auxiliary(shop, context, errors)
	_validate_layout(shop, context, errors)
	_validate_graph(shop, context, errors)
	return errors

static func _validate_policies(shop: SpecShop, c: Dictionary, errors: Array[Dictionary]) -> void:
	if shop.fulfillment == null: return
	if c.public:
		_enum(shop.fulfillment.handoff,["single","handoff","serve"],"fulfillment.handoff",errors)
		if shop.layout==null or shop.layout.motion_version!=1: _error(errors,"layout.motion_version","Public capabilities require shared motion version 1.")
		if shop.dispatch==null or shop.dispatch.action_version!=1: _error(errors,"dispatch.action_version","Public capabilities require shared actions version 1.")
		_number(shop.fulfillment.seated_patience,"fulfillment.seated_patience",errors)
		if not shop.fulfillment.mood_seconds.is_empty() and shop.fulfillment.mood_seconds.size()!=2: _error(errors,"fulfillment.mood_seconds","Use zero or two mood thresholds.")
		for index in shop.fulfillment.mood_seconds.size():
			_number(shop.fulfillment.mood_seconds[index],"fulfillment.mood_seconds[%d]"%index,errors)
			if index>0 and shop.fulfillment.mood_seconds[index]<shop.fulfillment.mood_seconds[index-1]: _error(errors,"fulfillment.mood_seconds","Thresholds must be ordered.")
		return
	var f := shop.fulfillment
	if f.flow_version==0 and (f.delivery_batch!="item" or not f.delivery_points.is_empty()): _error(errors,"fulfillment.flow_version","Delivery extensions require flow version 1.")
	if f.delivery_batch=="order" and (f.handoff!="serve" or f.dine_rule!="seat_wait" or shop.dispatch==null or shop.dispatch.action_version!=1 or shop.layout==null or shop.layout.motion_version!=1):
		_error(errors,"fulfillment.delivery_batch","Order delivery requires serve/seat_wait with shared motion and actions.")
	if not f.delivery_points.is_empty() and f.delivery_batch!="order": _error(errors,"fulfillment.delivery_points","Multiple collection ports require order delivery.")
	for dish in f.delivery_points:
		_ref(dish,c.dishes,"fulfillment.delivery_points."+dish,errors)
		var point: String = f.delivery_points[dish]
		if not c.stations.has(point) or c.stations[point].block!="pickup": _error(errors,"fulfillment.delivery_points."+dish,"Collection point must be a pickup station.")
	var matrix := capabilities(f.handoff)
	if matrix.is_empty():
		_error(errors, "fulfillment.handoff", "Unsupported fulfillment mode.", "unsupported")
		return
	for group in matrix:
		var resource: Resource = shop.get(group)
		if resource == null: continue
		for field in matrix[group]:
			var policy: Dictionary = matrix[group][field]
			if policy.has("values") and not policy.values.is_empty(): _enum(resource.get(field), policy.values, group + "." + field, errors)
			elif policy.status == "reserved" and resource.get(field) != policy.default:
				_error(errors, group + "." + field, "Reserved in this mode; retain default %s." % str(policy.default), "unsupported")
	if f.handoff == "single" and f.leave_queue == "after_pay" and f.pay_at != "on_take":
		_error(errors, "fulfillment.leave_queue", "after_pay is only an alias for after_take with on_take payment.", "unsupported")
	_ref(f.addon_dish, c.dishes, "fulfillment.addon_dish", errors, true)
	_ref(f.takeaway_station, c.stations, "fulfillment.takeaway_station", errors, true)
	if f.addon_chance > 0 and f.addon_dish.is_empty(): _error(errors, "fulfillment.addon_dish", "An addon dish is required when chance is positive.")
	for key in ["addon_chance", "ramp_start"]: _number(f.get(key), "fulfillment." + key, errors, 0, false, 1)
	for key in ["seated_patience", "leave_after", "ramp_orders", "opening_customers", "first_customer_delay", "customer_walk"]: _number(f.get(key), "fulfillment." + key, errors)
	if f.handoff == "serve" and f.customer_walk <= 0.0: _error(errors, "fulfillment.customer_walk", "Serve fulfillment needs a positive customer walking speed.")
	if not f.mood_seconds.is_empty() and f.mood_seconds.size() != 2: _error(errors, "fulfillment.mood_seconds", "Use zero or two mood thresholds.")
	for i in f.mood_seconds.size():
		_number(f.mood_seconds[i], "fulfillment.mood_seconds[%d]" % i, errors)
		if i > 0 and f.mood_seconds[i] < f.mood_seconds[i - 1]: _error(errors, "fulfillment.mood_seconds", "Thresholds must be ordered.")
	if shop.dispatch != null:
		if shop.dispatch.action_version==1 and (shop.layout==null or shop.layout.motion_version!=1): _error(errors,"dispatch.action_version","Actions require shared movement version 1.")
		for prop in shop.dispatch.get_property_list():
			if (int(prop.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) and prop.type == TYPE_FLOAT: _number(shop.dispatch.get(prop.name), "dispatch." + prop.name, errors)
		for key in shop.dispatch.base_scores:
			var keys: Array = SERVE_SCORES if f.handoff == "serve" else ["chore", "follow", "follow_step", "load", "load_short", "pot_short_bonus", "serve", "stir", "to_process", "to_rack", "topping"]
			_enum(key, keys, "dispatch.base_scores." + key, errors)
			_number(shop.dispatch.base_scores[key], "dispatch.base_scores." + key, errors, -INF)
		_number(shop.dispatch.fatigue_weight, "dispatch.fatigue_weight", errors, 0, false, 1)

const PARAMS := {
	"supply": ["fetch_seconds"],
	"batch_pot": ["cook_seconds", "load_seconds", "unload_seconds", "batch", "capacity", "manual_load", "manual_unload", "stir_points", "stir_seconds", "fetch_seconds", "load_label", "unload_label"],
	"hand": ["seconds", "users", "fetch_seconds"], "combine": ["seconds", "manual", "capacity"],
	"topping": ["seconds", "users", "flavor_cap", "capacity"], "dispenser": ["seconds", "fetch_seconds"],
	"pickup": ["zones", "process_seconds", "process_slots", "process_into", "dine_at_least_queue", "dine_per_dish", "capacity"],
	"counter": ["take_seconds", "hand_seconds", "posts"],
}

static func _station(s: SpecStation, p: String, c: Dictionary, errors: Array[Dictionary]) -> void:
	_enum(s.block, SpecStation.BLOCKS, p + ".block", errors)
	if s.id in ["shelf", "rack"]: _error(errors, p + ".id", "ID is reserved for a fulfillment destination.")
	_ref(s.zone, c.zones, p + ".zone", errors)
	_ref(s.companion_of, c.stations, p + ".companion_of", errors, true)
	for key in ["seated_bonus", "unlock_cost"]: _number(s.get(key), p + "." + key, errors, 0, key == "seated_bonus")
	for key in s.params:
		var at := p + ".params." + str(key)
		if key not in PARAMS.get(s.block, []) and key not in ["unit", "slot_label", "facing", "panel_title", "frame_title", "materials_label"]:
			_error(errors, at, "Unknown parameter for station block.", "unsupported")
			continue
		var value: Variant = s.params[key]
		if key in ["manual", "manual_load", "manual_unload", "dine_at_least_queue", "dine_per_dish"]:
			if not value is bool: _error(errors, at, "Expected boolean.")
		elif key in ["unit", "slot_label", "load_label", "unload_label", "process_into", "panel_title", "frame_title", "materials_label"]:
			if not value is String: _error(errors, at, "Expected text.")
		elif key == "zones":
			if not value is Dictionary: _error(errors, at, "Expected a capacity dictionary.")
			else:
				for zone in value:
					_enum(zone, ["dine", "takeaway"], at + "." + str(zone), errors)
					_number(value[zone], at + "." + str(zone), errors)
		elif key == "stir_points":
			if not value is Array: _error(errors, at, "Expected an array of cook fractions.")
			else:
				for i in value.size(): _number(value[i], at + "[%d]" % i, errors, 0, false, 1)
		else: _number(value, at, errors, -1 if key == "facing" else 0, key in ["batch", "process_slots", "capacity"])
	for id in s.price_dishes: _ref(id, c.dishes, p + ".price_dishes", errors)
	_tracks(s.tracks, p + ".tracks", c, errors, s.id)
	for i in s.materials.size():
		var m := s.materials[i]
		if m == null: continue
		var at := p + ".materials[%d]" % i
		_ref(m.item, c.items, at + ".item", errors)
		_ref(m.box_station, c.stations, at + ".box_station", errors, true)
		_number(m.box_cost, at + ".box_cost", errors)
		if m.track != null: _track(m.track, at + ".track", c, errors, s.id, "material")
	for i in s.stock.size():
		var stock := s.stock[i]
		if stock == null: continue
		var at := p + ".stock[%d]" % i
		_ref(stock.item, c.items, at + ".item", errors)
		for key in ["base", "per_waiting", "cap", "low", "start"]: _number(stock.get(key), at + "." + key, errors)

static func _step(step: SpecStep, p: String, c: Dictionary, errors: Array[Dictionary], default_station := "") -> void:
	_ref(step.station if not step.station.is_empty() else default_station, c.stations, p + ".station", errors)
	if step.action.is_empty(): _error(errors, p + ".action", "Action must not be empty.")
	if not c.public and c.mode == "single" and step.action in ["take", "hand"]:
		_error(errors, p + ".action", "Single fulfillment inserts take and hand actions; recipe steps cannot repeat them.", "unsupported")
	_number(step.seconds, p + ".seconds", errors)
	_number(step.repeat, p + ".repeat", errors, 0, true)
	for field in ["consumes", "produces"]:
		for id in step.get(field):
			_ref(id, c.items, p + "." + field + "." + id, errors)
			_number(step.get(field)[id], p + "." + field + "." + id, errors, 0, true)

static func _dish(d: SpecDish, p: String, c: Dictionary, errors: Array[Dictionary]) -> void:
	_ref(d.item, c.items, p + ".item", errors)
	if d.price_parts.is_empty(): _error(errors, p + ".price_parts", "At least one price part is required.")
	for part in d.price_parts: _number(d.price_parts[part], p + ".price_parts." + part, errors)
	if d.steps.is_empty() and not c.public: _error(errors, p + ".steps", "At least one recipe step is required.")
	for i in d.steps.size():
		if d.steps[i] != null: _step(d.steps[i], p + ".steps[%d]" % i, c, errors)
	_ref(d.flavor_station, c.stations, p + ".flavor_station", errors, true)
	if c.stations.has(d.flavor_station):
		var found := false
		for material in c.stations[d.flavor_station].materials:
			if material != null and material.id == d.flavor_material: found = true
		if not found and not c.stations[d.flavor_station].materials.is_empty(): _error(errors, p + ".flavor_material", "Flavor material must belong to its station.", "reference")
	elif not d.flavor_material.is_empty(): _error(errors, p + ".flavor_station", "A flavor station is required.")
	_number(d.topping_count, p + ".topping_count", errors)

static func _tracks(tracks: Array, p: String, c: Dictionary, errors: Array[Dictionary], target := "", attachment := "station") -> void:
	_ids(tracks, p, errors, false, p == "staff.tracks")
	for i in tracks.size():
		if tracks[i] != null:
			var default_target: String = tracks[i].id if attachment == "staff" else target
			_track(tracks[i], p + "[%d]" % i, c, errors, default_target, attachment)

static func _track(track: SpecUpgradeTrack, p: String, c: Dictionary, errors: Array[Dictionary], target := "", attachment := "station") -> void:
	_number(track.requires_level, p + ".requires_level", errors, 0, true)
	for id in track.preview_dishes: _ref(id, c.dishes, p + ".preview_dishes", errors)
	_effects(track.base_effects, p + ".base_effects", c, errors, target, attachment + "_base")
	for i in track.levels.size():
		var level := track.levels[i]
		if level == null: continue
		_number(level.cost, p + ".levels[%d].cost" % i, errors)
		_effects(level.effects, p + ".levels[%d].effects" % i, c, errors, target, attachment + "_level")

static func _effects(effects: Array, p: String, c: Dictionary, errors: Array[Dictionary], target := "", attachment := "event") -> void:
	for i in effects.size():
		var e: SpecEffect = effects[i]
		if e == null: continue
		var at := p + "[%d]" % i
		_enum(e.kind, SpecEffect.KINDS, at + ".kind", errors)
		if e.kind == "capacity": _error(errors,at + ".kind","Capacity effects require a shared-template binding; the legacy shop entry has no consumer.","unsupported")
		var upgrade := attachment != "event"
		if upgrade and e.kind in SpecEffect.ONE_SHOT:
			_error(errors, at + ".kind", "Upgrade tracks do not execute one-shot effects.", "unsupported")
		if e.kind in ["seats", "unlock_recipe", "shop_news"]:
			_error(errors, at + ".kind", "This effect has no implemented gameplay consumer.", "unsupported")
		if e.kind == "open_flavor" and attachment != "station_level":
			_error(errors, at + ".kind", "open_flavor is a station upgrade label only, not a gameplay effect.", "unsupported")
		_enum(e.op, ["mul", "add", "set"], at + ".op", errors)
		_number(e.value, at + ".value", errors, -INF)
		if e.kind in ["speed", "duration", "flow", "walk", "work", "patience"] and e.op != "add": _number(e.value, at + ".value", errors, 0, true)
		if e.kind in ["batch", "process_slots", "carry"] and e.op == "set": _number(e.value, at + ".value", errors, 0, true)
		var id := e.target if not e.target.is_empty() else ("" if e.kind == "price" else target)
		match e.kind:
			"speed", "duration", "batch", "process_slots": _ref(id, c.stations, at + ".target", errors, true)
			"price", "flow", "flyer_customers", "flyer_cooldown", "event_chance", "patience", "grant_gold", "customer_wave":
				if not id.is_empty(): _error(errors, at + ".target", "This effect requires the global empty target.", "unsupported")
			"open_flavor":
				if not c.materials.has(e.target): _ref(e.target, c.dishes, at + ".target", errors)
			"seats": _ref(e.target, c.seats, at + ".target", errors)
			"unlock_staff_kind": _ref(e.target, c.kinds, at + ".target", errors)
			"unlock_recipe": _ref(e.target, c.dishes, at + ".target", errors)
			"shop_news":
				if not c.campaign.is_empty(): _ref(e.target, c.campaign, at + ".target", errors)
			"staff_slot":
				if not c.zones.has("front") or id not in ["", "front"]:
					_error(errors, at + ".target", "Staff slot effects only change the zoned front capacity.", "unsupported")
			"walk", "work", "carry", "luck":
				if not _staff_target(id, c): _error(errors, at + ".target", "Use an empty target, active zone, or canonical staff:N ID.", "unsupported")
		if e.kind != "price":
			if not e.dishes.is_empty(): _error(errors, at + ".dishes", "Dish scopes are only supported by price effects.", "unsupported")
			if not e.price_part.is_empty(): _error(errors, at + ".price_part", "Price parts are only supported by price effects.", "unsupported")
		for dish in e.dishes: _ref(dish, c.dishes, at + ".dishes", errors)
		if not e.price_part.is_empty():
			var matches := false
			var scope: Array = e.dishes
			if scope.is_empty() and upgrade and c.stations.has(target): scope = c.stations[target].price_dishes
			if scope.is_empty(): scope = c.dishes.keys()
			for dish in scope:
				if c.dishes.has(dish) and c.dishes[dish].price_parts.has(e.price_part): matches = true
			if not matches: _error(errors, at + ".price_part", "Price part is absent from the affected dishes.", "reference")

static func _staff_target(id: String, c: Dictionary) -> bool:
	if id.is_empty(): return true
	if id in ["front", "kitchen"] and c.zones.has(id): return true
	if not id.begins_with("staff:"): return false
	var suffix := id.trim_prefix("staff:")
	return suffix.is_valid_int() and int(suffix) > 0 and str(int(suffix)) == suffix

static func _stage(stage: SpecStage, p: String, c: Dictionary, errors: Array[Dictionary]) -> void:
	if stage.stations.is_empty() and stage.recipe_at.is_empty(): _error(errors, p + ".stations", "Each stage needs an unlock station or a recipe station.")
	if not stage.recipe_at.is_empty():
		if not stage.stations.is_empty(): _error(errors, p + ".recipe_at", "A recipe stage opens no stations; use either stations or recipe_at.", "combination")
		_ref(stage.recipe_at, c.stations, p + ".recipe_at", errors)
		if stage.dish.is_empty(): _error(errors, p + ".dish", "A recipe stage must name the dish it adds.", "required")
	for id in stage.stations: _ref(id, c.stations, p + ".stations", errors)
	_ref(stage.dish, c.dishes, p + ".dish", errors, true)
	_ref(stage.flavor_fallback, c.dishes, p + ".flavor_fallback", errors, true)
	_number(stage.customer_interval, p + ".customer_interval", errors, 0, true)
	for key in ["cost", "queue_capacity", "wait_seats", "seat_seconds"]: _number(stage.get(key), p + "." + key, errors)
	_number(stage.takeaway_share, p + ".takeaway_share", errors, 0, false, 1)
	var total := 0.0
	for id in stage.order_weights:
		if id != stage.flavor_group: _ref(id, c.dishes, p + ".order_weights." + id, errors)
		_number(stage.order_weights[id], p + ".order_weights." + id, errors)
		total += stage.order_weights[id]
	if total <= 0 and not c.public: _error(errors, p + ".order_weights", "Menu needs a positive weight.")

	for zone in stage.staff_slots:
		_enum(zone, ["kitchen"] if c.zoned else [""], p + ".staff_slots." + zone, errors)
		_number(stage.staff_slots[zone], p + ".staff_slots." + zone, errors)
	_ids(stage.tasks, p + ".tasks", errors)
	for i in stage.tasks.size():
		var task := stage.tasks[i]
		if task == null: continue
		var at := p + ".tasks[%d]" % i
		_enum(task.condition, ["sell_count", "track_level", "flavor_open", "revenue"], at + ".condition", errors)
		_number(task.amount, at + ".amount", errors)
		if task.condition in ["sell_count", "flavor_open"]: _ref(task.target, c.dishes, at + ".target", errors)
		elif task.condition == "track_level": _ref(task.target, c.tracks, at + ".target", errors)

static func _validate_staff(shop: SpecShop, c: Dictionary, errors: Array[Dictionary]) -> void:
	var staff := shop.staff
	if staff == null: return
	var seen_zones := {}
	for i in staff.zones.size():
		_enum(staff.zones[i], ["front", "kitchen"], "staff.zones[%d]" % i, errors)
		if seen_zones.has(staff.zones[i]): _error(errors, "staff.zones[%d]" % i, "Duplicate zone.", "duplicate")
		seen_zones[staff.zones[i]] = true
	if not staff.zones.is_empty() and (staff.zones.size() != 2 or not seen_zones.has("front") or not seen_zones.has("kitchen")):
		_error(errors, "staff.zones", "Use no zones or exactly front and kitchen.", "unsupported")
	_enum(staff.hire_rule, ["fewest", "cycle"], "staff.hire_rule", errors)
	for field in ["starting", "hire_pool", "hire_order"]:
		for i in staff.get(field).size(): _ref(staff.get(field)[i], c.kinds, "staff.%s[%d]" % [field, i], errors)
	if staff.starting.is_empty(): _error(errors, "staff.starting", "An initial worker is required.")
	if staff.hire_rule == "cycle" and staff.hire_order.is_empty(): _error(errors, "staff.hire_order", "Cycle recruitment requires a nonempty order.")
	if staff.hire_rule == "fewest" and staff.hire_pool.is_empty(): _error(errors, "staff.hire_pool", "Recruitment requires a nonempty pool.")
	for i in staff.kinds.size():
		var kind := staff.kinds[i]
		if kind == null: continue
		for stat in kind.stats: _number(kind.stats[stat], "staff.kinds[%d].stats.%s" % [i, stat], errors, 0, stat in ["walk", "work", "carry"])
	for field in ["hire_cost_base", "hire_cost_step", "front_base_slots"]: _number(staff.get(field), "staff." + field, errors)
	for i in staff.hire_costs.size(): _number(staff.hire_costs[i], "staff.hire_costs[%d]" % i, errors)
	_ref(staff.starting_post, c.stations, "staff.starting_post", errors, true)
	if not staff.starting_posts.is_empty() and staff.starting_posts.size() != staff.starting.size(): _error(errors, "staff.starting_posts", "Starting posts must match starting workers one to one.")
	for i in staff.starting_posts.size():
		var post := staff.starting_posts[i]
		_ref(post, c.stations, "staff.starting_posts[%d]" % i, errors, true)
		if c.stations.has(post) and not c.stations[post].seatable and c.stations[post].block != "counter": _error(errors, "staff.starting_posts[%d]" % i, "Starting post must be seatable.")
	if c.stations.has(staff.starting_post) and not c.stations[staff.starting_post].seatable and c.stations[staff.starting_post].block != "counter": _error(errors, "staff.starting_post", "Starting post must be seatable.")
	_tracks(staff.tracks, "staff.tracks", c, errors, "", "staff")

static func _validate_auxiliary(shop: SpecShop, c: Dictionary, errors: Array[Dictionary]) -> void:
	if not c.public and c.mode in ["single", "serve"] and not shop.connections.is_empty():
		_error(errors, "connections", "Conveyor dispatch requires handoff fulfillment.", "unsupported")
	if shop.flyer != null:
		_number(shop.flyer.wave_seconds, "flyer.wave_seconds", errors)
		_number(shop.flyer.gap, "flyer.gap", errors)
		_enum(shop.flyer.when_full, ["wait_outside", "lost"], "flyer.when_full", errors)
		if shop.flyer.track != null: _track(shop.flyer.track, "flyer.track", c, errors, "", "flyer")
	if shop.goals != null:
		_ref(shop.goals.opening_station, c.stations, "goals.opening_station", errors)
		for key in shop.goals.order: _enum(key, ["open", "box", "stage", "tasks"], "goals.order", errors)
		for key in shop.goals.complete_when: _enum(key, ["all_stages", "all_tasks", "all_flavors"], "goals.complete_when", errors)
		for i in shop.goals.rating_minutes.size(): _number(shop.goals.rating_minutes[i], "goals.rating_minutes[%d]" % i, errors)
		_number(shop.goals.rating_lost_share, "goals.rating_lost_share", errors, 0, false, 1)
	for i in shop.seat_groups.size():
		var seat := shop.seat_groups[i]
		if seat == null: continue
		var p := "seat_groups[%d]" % i
		_enum(seat.purpose, ["dine", "wait"], p + ".purpose", errors)
		for key in ["start", "seconds", "patience"]: _number(seat.get(key), p + "." + key, errors)
		_number(seat.step, p + ".step", errors, 0, true)
		for n in seat.costs.size(): _number(seat.costs[n], p + ".costs[%d]" % n, errors)
		for n in seat.steps.size(): _number(seat.steps[n], p + ".steps[%d]" % n, errors, 0, true)
	for i in shop.connections.size():
		var connection := shop.connections[i]
		if connection == null: continue
		var p := "connections[%d]" % i
		var destinations: Dictionary = c.stations.duplicate()
		destinations["shelf"] = true
		destinations["rack"] = true
		_ref(connection.from, destinations, p + ".from", errors)
		_ref(connection.to, destinations, p + ".to", errors)
		_number(connection.cost, p + ".cost", errors)
		_number(connection.stage, p + ".stage", errors, 0, false, shop.stages.size() - 1)
		_number(connection.seconds, p + ".seconds", errors, 0, true)
		_number(connection.interval, p + ".interval", errors, 0, true)
	for i in shop.order_options.size():
		var option := shop.order_options[i]
		if option == null: continue
		var p := "order_options[%d]" % i
		if not c.public and shop.fulfillment != null and shop.fulfillment.handoff != "single": _error(errors, p, "Order options require single fulfillment.", "unsupported")
		_ref(option.station, c.stations, p + ".station", errors)
		_number(option.share, p + ".share", errors, 0, false, 1)
		_number(option.price_mult, p + ".price_mult", errors)
		if option.step != null: _step(option.step, p + ".step", c, errors, option.station)
	for i in shop.events.size():
		var event := shop.events[i]
		if event == null: continue
		var p := "events[%d]" % i
		if event.trigger.is_empty(): _error(errors, p + ".trigger", "Event trigger is required.")
		_number(event.chance, p + ".chance", errors, 0, false, 1)
		_number(event.cooldown, p + ".cooldown", errors)
		_number(event.duration, p + ".duration", errors)
		for n in event.choices.size():
			var choice: Dictionary = event.choices[n]
			if not choice.get("label", "") is String: _error(errors, p + ".choices[%d].label" % n, "Expected text.")
			_number(choice.get("cost", 0), p + ".choices[%d].cost" % n, errors)
		_effects(event.effects, p + ".effects", c, errors)
	for i in shop.guide.size():
		var guide := shop.guide[i]
		if guide == null: continue
		var p := "guide[%d]" % i
		_enum(guide.trigger, ["start", "angry", "next"], p + ".trigger", errors)
		_enum(guide.style, ["hint", "card"], p + ".style", errors)
		_ref(guide.next, c.guides, p + ".next", errors, true)
		for n in guide.cues.size():
			var cue: Dictionary = guide.cues[n]
			var at := p + ".cues[%d]" % n
			if cue.has("then"):
				if cue.then is String: _ref(cue.then, c.guides, at + ".then", errors)
				else: _error(errors, at + ".then", "Expected a guide ID.")
			if cue.has("if"):
				if not (cue["if"] is String or cue["if"] is Array): _error(errors, at + ".if", "Expected condition text or array.")
				elif cue["if"] is Array:
					for k in cue["if"].size():
						if not cue["if"][k] is String: _error(errors, at + ".if[%d]" % k, "Expected condition text.")
			for key in ["at", "text", "go"]:
				if cue.has(key) and not cue[key] is String: _error(errors, at + "." + key, "Expected text.")
			var anchor: Variant = cue.get("at", "")
			if anchor is String and not "{" in anchor:
				if anchor.begins_with("station:") or anchor.begins_with("frame:"):
					var id: String = anchor.get_slice(":", 1)
					if id != "slow": _ref(id, c.stations, at + ".at", errors)
		for n in guide.rows.size():
			if not guide.rows[n] is Array or guide.rows[n].size() < 2: _error(errors, p + ".rows[%d]" % n, "Expected icon and text.")
		for n in guide.stats.size():
			if not guide.stats[n] is Array or guide.stats[n].size() < 3: _error(errors, p + ".stats[%d]" % n, "Expected icon, label and value key.")

static func _validate_layout(shop: SpecShop, c: Dictionary, errors: Array[Dictionary]) -> void:
	var layout := shop.layout
	if layout == null: return
	_validate_motion(shop,errors)
	_enum(layout.nav, ["straight", "grid"], "layout.nav", errors)
	_number(layout.cell, "layout.cell", errors, 0, true)
	if layout.nav == "grid":
		if layout.grid_size.x <= 0 or layout.grid_size.y <= 0: _error(errors, "layout.grid_size", "Grid dimensions must be positive.")
		if layout.areas.is_empty(): _error(errors, "layout.areas", "Grid navigation requires a walkable area.")
	for i in layout.areas.size():
		if layout.areas[i].size.x <= 0 or layout.areas[i].size.y <= 0: _error(errors, "layout.areas[%d]" % i, "Area dimensions must be positive.")
	for i in layout.obstacles.size():
		if layout.obstacles[i].size.x <= 0 or layout.obstacles[i].size.y <= 0: _error(errors, "layout.obstacles[%d]" % i, "Obstacle dimensions must be positive.")
	for i in layout.obstacle_stations.size(): _ref(layout.obstacle_stations[i], c.stations, "layout.obstacle_stations[%d]" % i, errors, true)
	if layout.obstacle_stations.size() > layout.obstacles.size(): _error(errors, "layout.obstacle_stations", "Obstacle station list exceeds obstacle count.")
	for key in layout.aliases: _ref(layout.aliases[key], layout.points, "layout.aliases." + key, errors)
	_ref(layout.spawn_point, layout.points, "layout.spawn_point", errors)
	if shop.staff != null and not shop.staff.home_anchor.is_empty(): _ref(shop.staff.home_anchor, layout.points, "staff.home_anchor", errors)
	for id in c.stations:
		var point: String = layout.aliases.get(id, id)
		_ref(point, layout.points, "layout.points." + id, errors)

static func _validate_motion(shop: SpecShop, errors: Array[Dictionary]) -> void:
	var layout := shop.layout
	_enum(layout.motion_version,[0,1],"layout.motion_version",errors)
	if layout.motion_version!=1: return
	_enum(layout.nav,["grid"],"layout.nav",errors)
	_number(layout.motion_units,"layout.motion_units",errors,0,true)
	for profile in ["staff","customer"]:
		if not layout.actor_areas.has(profile): _error(errors,"layout.actor_areas."+profile,"An explicit permission area is required.")
	for profile in layout.actor_areas:
		var areas: Variant = layout.actor_areas[profile]
		if not profile is String or String(profile).is_empty() or not areas is Array or areas.is_empty():
			_error(errors,"layout.actor_areas","Permission names require a nonempty array of grid rectangles.")
			continue
		for area in areas:
			if not area is Rect2i or area.size.x<=0 or area.size.y<=0 or not Rect2i(Vector2i.ZERO,layout.grid_size).encloses(area):
				_error(errors,"layout.actor_areas."+profile,"Permission rectangles must fit inside the grid.")
	for name in ["entrance","exit","pickup"]:
		if not layout.customer_points.has(name): _error(errors,"layout.customer_points."+name,"Customer port is required.")
	for group in shop.seat_groups:
		var count := group.start+group.step*group.costs.size()
		if not group.steps.is_empty():
			count = group.start
			for extra in group.steps: count += extra
		for index in count:
			var name := ("wait:" if group.purpose=="wait" else "seat:")+"%s/%d"%[group.id,index]
			if not layout.customer_points.has(name): _error(errors,"layout.customer_points."+name,"Seat approach port is required.")
	for name in layout.customer_points:
		if not layout.customer_points[name].is_finite(): _error(errors,"layout.customer_points."+name,"Port must be finite.")
	if layout.customer_queue.is_empty(): _error(errors,"layout.customer_queue","Queue must have at least one explicit point.")
	for index in layout.customer_queue.size():
		if not layout.customer_queue[index].is_finite(): _error(errors,"layout.customer_queue[%d]"%index,"Queue point must be finite.")

## Check the necessary staged production graph, without trying to solve economy/balance.
static func _validate_graph(shop: SpecShop, c: Dictionary, errors: Array[Dictionary]) -> void:
	if c.public:
		if not c.public_definition.get("service",{}).is_empty(): errors.append_array(load("res://game/rules/template/authoring.gd").validate(shop,c.public_definition))
		return
	var counters := 0
	var outputs := {}
	for dish in shop.dishes:
		if dish == null: continue
		var has_kitchen := false
		for step in dish.steps:
			if step == null or not c.stations.has(step.station): continue
			var station: SpecStation = c.stations[step.station]
			if station.block not in ["supply", "pickup", "counter"] and station.zone != "front":
				has_kitchen = true
				if not step.produces.is_empty(): outputs[step.station] = true
		if shop.fulfillment != null and shop.fulfillment.handoff == "handoff" and not dish.front and not has_kitchen:
			_error(errors, "dishes." + dish.id + ".steps", "Handoff kitchen dishes need a production chain.", "unreachable")
	if shop.fulfillment != null and shop.fulfillment.handoff == "handoff":
		for i in shop.stations.size():
			var station := shop.stations[i]
			if station != null and station.block in ["batch_pot", "combine", "topping"] and not outputs.has(station.id):
				_error(errors, "stations[%d]" % i, "Handoff processing stations need a recipe output.", "unreachable")
	var pickups := 0
	var available := {}
	var initial := {}
	for id in c.stations:
		var station: SpecStation = c.stations[id]
		if station.block == "counter": counters += 1
		if station.block == "pickup" and station.params.has("process_seconds"): pickups += 1
		if station.starts_unlocked:
			available[id] = true
			initial[id] = true
	if counters != 1: _error(errors, "stations", "Exactly one counter station is required.")
	if pickups > 1: _error(errors, "stations", "Only one processing pickup station is supported.")
	if shop.fulfillment != null and shop.fulfillment.handoff == "handoff":
		for id in c.dishes:
			if not c.dishes[id].front and pickups != 1: _error(errors, "stations", "Handoff kitchen recipes require a processing pickup station.")
	var guaranteed := initial.duplicate()
	for i in shop.stages.size():
		var stage := shop.stages[i]
		if stage == null: continue
		for id in stage.stations: available[id] = true
		for unused in c.stations.size():
			for id in c.stations:
				if available.has(c.stations[id].companion_of): available[id] = true
		if i > 0: _stage_unlocks(stage, c, guaranteed)
		if not stage.flavor_group.is_empty() and stage.order_weights.has(stage.flavor_group) and stage.flavor_fallback.is_empty():
			var has_flavor := false
			# Stage zero can be queried before opening. Later stages are selected by unlock().
			var earliest: Dictionary = initial if i == 0 else guaranteed
			for id in c.dishes:
				var dish: SpecDish = c.dishes[id]
				if dish.flavor_station.is_empty() or dish.topping_count <= 0: continue
				if _flavor_ready(dish, c, earliest): has_flavor = true
			if not has_flavor: _error(errors, "stages[%d].flavor_fallback" % i, "Flavor groups need a fallback unless a flavor is already available.", "unreachable")
		var has_recipe := false
		for id in stage.order_weights:
			var dish_id: String = stage.flavor_fallback if id == stage.flavor_group else id
			if not c.dishes.has(dish_id) or stage.order_weights[id] <= 0: continue
			var dish: SpecDish = c.dishes[dish_id]
			var ready := not dish.steps.is_empty()
			for step in dish.steps:
				if step == null or not available.has(step.station): ready = false
			if ready: has_recipe = true
		if not has_recipe: _error(errors, "stages[%d].order_weights" % i, "Stage needs a weighted recipe whose stations can be unlocked by this stage.", "unreachable")
		# If the opening station starts unlocked, stage zero is never purchased.
		if i == 0 and shop.goals != null and not initial.has(shop.goals.opening_station):
			_stage_unlocks(stage, c, guaranteed)
	for id in c.stations:
		if not available.has(id): _error(errors, "stations." + id, "Station is neither initially available nor reachable through a stage/companion.", "unreachable")
	if c.mode == "serve": _validate_serve(shop, c, errors)


## serve 模式能执行的配方形状（§10.5：不支持的组合明确拒绝）：
## 原料箱 / 自动批量锅只当来源；手工台、要人的组合台是工序；每道菜最后做出 dish.item；有出餐口、堂食座位组和每个座位的站位。
static func _validate_serve(shop: SpecShop, c: Dictionary, errors: Array[Dictionary]) -> void:
	if shop.dispatch.prefetch_inputs and (shop.fulfillment.flow_version!=1 or shop.dispatch.action_version!=1):
		_error(errors,"dispatch.prefetch_inputs","Parallel preparation requires serve flow1 and shared actions.","unsupported")
	if shop.dispatch.preposition_work and (shop.fulfillment.flow_version!=1 or shop.dispatch.action_version!=1):
		_error(errors,"dispatch.preposition_work","Prepositioned work requires serve flow1 and shared actions.","unsupported")
	var helpers := shop.dispatch.transport_helpers
	if not helpers.is_empty() and (shop.fulfillment.flow_version!=1 or shop.dispatch.action_version!=1 or not c.zoned):
		_error(errors,"dispatch.transport_helpers","Transport assistance requires zoned serve flow1 and shared actions.","unsupported")
	var helper_roles := {}
	for index in helpers.size():
		var role := helpers[index]
		_enum(role,["front","kitchen"],"dispatch.transport_helpers[%d]"%index,errors)
		if helper_roles.has(role): _error(errors,"dispatch.transport_helpers","Helper roles must be unique.")
		helper_roles[role] = true
	var pickups := 0
	for id in c.stations:
		var st: SpecStation = c.stations[id]
		var p: String = "stations." + id
		match st.block:
			"pickup": pickups += 1
			"batch_pot":
				if bool(st.params.get("manual_load", false)) or bool(st.params.get("manual_unload", false)) or st.params.has("stir_points"):
					_error(errors, p, "Serve fulfillment supports automatic batch pots only.", "unsupported")
			"combine":
				if not bool(st.params.get("manual", false)): _error(errors, p, "Serve fulfillment supports staffed combine stations only.", "unsupported")
			"topping", "dispenser":
				_error(errors, p, "Serve fulfillment does not support this block yet.", "unsupported")
		if st.zone == "front" and st.block != "counter" and shop.fulfillment.flow_version!=1:
			_error(errors, p, "Front production requires flow version 1.", "unsupported")
	if pickups<1 or (shop.fulfillment.flow_version==0 and pickups!=1): _error(errors, "stations", "Serve fulfillment needs exactly one pickup station unless flow version 1 is enabled.")
	var dine: SpecSeatGroup = null
	for g in shop.seat_groups:
		if g != null and g.purpose == "dine" and dine == null: dine = g
		elif g != null: _error(errors, "seat_groups." + g.id, "Serve fulfillment supports one dine seat group.", "unsupported")
	if dine == null: _error(errors, "seat_groups", "Serve fulfillment needs a dine seat group.")
	elif shop.layout != null:
		var most := dine.start + (_sum(dine.steps) if not dine.steps.is_empty() else dine.step * dine.costs.size())
		for n in most:
			if not shop.layout.points.has("%s/%d" % [dine.id, n]): _error(errors, "layout.points", "Seat %s/%d needs a point." % [dine.id, n], "reference")
	for dish in shop.dishes:
		if dish == null: continue
		var p: String = "dishes." + dish.id
		if shop.fulfillment.flow_version==1:
			for error: Dictionary in Production.compile(shop,dish.id).errors: _error(errors,p+"."+error.path,error.message,error.code)
		if dish.front and shop.fulfillment.flow_version!=1: _error(errors, p + ".front", "Front recipes require flow version 1.", "unsupported")
		var made := {}
		var final := false
		for i in dish.steps.size():
			var s := dish.steps[i]
			if s == null or not c.stations.has(s.station): continue
			var st: SpecStation = c.stations[s.station]
			if dish.front and st.zone!="front": _error(errors,"%s.steps[%d].station"%[p,i],"Front recipes must use front production stations.","unsupported")
			elif not dish.front and st.zone=="front": _error(errors,"%s.steps[%d].station"%[p,i],"Kitchen recipes cannot implicitly require front production.","unsupported")
			if st.block in ["supply", "batch_pot"]:
				if not s.consumes.is_empty() or s.produces.size() != 1: _error(errors, "%s.steps[%d]" % [p, i], "Source steps produce exactly one item and consume nothing.", "unsupported")
			elif st.block in ["hand", "combine"]:
				for item in s.consumes:
					if shop.fulfillment.flow_version==0 and not made.has(item): _error(errors, "%s.steps[%d].consumes.%s" % [p, i, item], "Inputs must be produced by an earlier step.", "unreachable")
			else: _error(errors, "%s.steps[%d]" % [p, i], "Serve recipes use supply, batch_pot, hand and combine steps.", "unsupported")
			for item in s.produces:
				made[item] = true
				if item == dish.item: final = true
		if not final: _error(errors, p + ".item", "A step must produce the dish item.", "unreachable")


static func _sum(values: Array) -> int:
	var total := 0
	for v in values: total += int(v)
	return total

static func _stage_unlocks(stage: SpecStage, c: Dictionary, available: Dictionary) -> void:
	for id in stage.stations:
		available[id] = true
		for station in c.stations.values():
			if station.companion_of == id: available[station.id] = true

## A fallback may be omitted only when a flavor is usable without purchases or hiring.
## This mirrors the necessary dish_open gates, not eventual unlockability/balance.
static func _flavor_ready(dish: SpecDish, c: Dictionary, available: Dictionary) -> bool:
	if c.mode == "handoff" and not dish.front: return false
	if not c.stations.has(dish.flavor_station) or not available.has(dish.flavor_station): return false
	for material in c.stations[dish.flavor_station].materials:
		if material != null and material.id == dish.flavor_material and (material.track == null or material.track.requires_level > 1): return false
	var boxed_items := {}
	for station in c.stations.values():
		if station.block != "supply": continue
		for material in station.materials:
			if material != null and material.box_cost > 0: boxed_items[material.item] = true
		break # ShopRules uses the first supply station.
	for step in dish.steps:
		if step == null or not c.stations.has(step.station): return false
		var station: SpecStation = c.stations[step.station]
		if station.block == "pickup": continue
		if not available.has(station.companion_of if not station.companion_of.is_empty() else station.id): return false
		for item in step.consumes:
			if boxed_items.has(item): return false
		if station.block == "supply":
			for item in step.produces:
				if boxed_items.has(item): return false
	return true
