extends RefCounted
## Numeric formulas shared by live rules and detached query snapshots.

const TUNING_MIN := 0.25
const TUNING_MAX := 3.0
const TUNING_STEP := 0.05

static func tuning_limits() -> Dictionary:
	return {"min": TUNING_MIN, "max": TUNING_MAX, "step": TUNING_STEP}

static func normalize_tuning(value: float, snap := false) -> float:
	return clampf(snappedf(value, TUNING_STEP) if snap else value, TUNING_MIN, TUNING_MAX)


static func tuned(tune: Dictionary, key: String) -> float:
	return normalize_tuning(float(tune.get(key, 1.0)))

static func flow_interval(base_seconds: float, flow: float, tune: Dictionary) -> float:
	return base_seconds / flow * tuned(tune, "customer")


static func speed(mods: RuleModifiers, id: String) -> float:
	return mods.value("speed", 1.0, id)


static func duration_mult(mods: RuleModifiers, id: String) -> float:
	return mods.value("duration", 1.0, id)


static func pot_batch(shop: SpecShop, mods: RuleModifiers, id: String) -> int:
	return int(mods.value("batch", float(shop.station(id).params.get("batch", 3)), id))


static func process_slots(shop: SpecShop, mods: RuleModifiers, id: String) -> int:
	return int(mods.value("process_slots", float(shop.station(id).params.get("process_slots", 1)), id))


static func raw_price(shop: SpecShop, mods: RuleModifiers, tune: Dictionary, dish_id: String) -> float:
	var dish := shop.dish(dish_id)
	var total := 0.0
	for part in dish.price_parts:
		total += dish.price_parts[part] * mods.value("price", 1.0, "", dish_id) * mods.value("price", 1.0, "", dish_id, part)
	return total * tuned(tune, "price")


static func dish_price(shop: SpecShop, mods: RuleModifiers, tune: Dictionary, dish_id: String) -> float:
	return snappedf(raw_price(shop, mods, tune, dish_id), 0.1) if shop.fulfillment.price_rounding == "dish_tenth_carry" else raw_price(shop, mods, tune, dish_id)


## Calculated dish amount and settlement policy. Solo payment excludes options/addons.


static func dish_quote(shop: SpecShop, mods: RuleModifiers, tune: Dictionary, dish_id: String) -> Dictionary:
	var quote := {"calculated": dish_price(shop, mods, tune, dish_id), "policy": shop.fulfillment.price_rounding}
	if shop.fulfillment.price_rounding != "dish_tenth_carry":
		quote.solo_payment = order_price_single(shop, mods, tune, {"kind": dish_id, "addon": false, "options": []})
	return quote


static func order_price_single(shop: SpecShop, mods: RuleModifiers, tune: Dictionary, c: Dictionary) -> int:
	var f := shop.fulfillment
	# 点的那份（只点豆浆时就是豆浆）乘订单选项的倍数；搭配的那杯豆浆不乘
	var total := raw_price(shop, mods, tune, c.kind)
	for id in c.get("options", []):
		var option: SpecOrderOption = null
		for candidate in shop.order_options:
			if candidate.id == String(id):
				option = candidate
				break
		if option != null: total *= option.price_mult
	if c.addon and c.kind != f.addon_dish: total += raw_price(shop, mods, tune, f.addon_dish)
	return int(round(total))


static func side_of(shop: SpecShop, worker: Dictionary) -> String:
	if shop.staff.zones.is_empty(): return ""
	var counter_id := ""
	for station in shop.stations:
		if station.block == "counter": counter_id = station.id
	return "front" if worker.post == counter_id else "kitchen"


static func stat(shop: SpecShop, mods: RuleModifiers, tune: Dictionary, worker: Dictionary, name: String) -> float:
	var base: float = float(worker.stats.get(name, 1.0))
	var side := side_of(shop, worker)
	var seated := 1.0
	var post := shop.station(worker.post)
	if name in ["walk", "work"] and post != null and post.seatable: seated = post.seated_bonus
	var value := mods.value(name, base, side, "", "", "staff:%d" % worker.id)
	if name == "walk": return value * seated * tuned(tune, "walk")
	if name == "work": return value * seated * tuned(tune, "work")
	return value


static func walk_speed(shop: SpecShop, mods: RuleModifiers, tune: Dictionary, worker: Dictionary) -> float:
	return stat(shop, mods, tune, worker, "walk")


static func skill(shop: SpecShop, mods: RuleModifiers, tune: Dictionary, worker: Dictionary) -> float:
	return stat(shop, mods, tune, worker, "work")


static func carry(shop: SpecShop, mods: RuleModifiers, tune: Dictionary, worker: Dictionary) -> int:
	if worker.get("courier", false): return 1
	return int(stat(shop, mods, tune, worker, "carry"))


static func effective_worker_stats(shop: SpecShop, mods: RuleModifiers, tune: Dictionary, worker: Dictionary) -> Dictionary:
	return {"walk": walk_speed(shop, mods, tune, worker), "work": skill(shop, mods, tune, worker), "carry": carry(shop, mods, tune, worker)}


static func manual_operation_seconds(shop: SpecShop, mods: RuleModifiers, tune: Dictionary, id: String, base_seconds: float, worker: Dictionary = {}, fixed := false) -> float:
	var station := shop.station(id)
	return capability_seconds(mods, tune, id, base_seconds, fixed or station.block == "batch_pot") / (skill(shop, mods, tune, worker) if not worker.is_empty() else 1.0)


## Public capability clocks do not infer execution policy from a shop mode or
## require a legacy station object. Employee rate is applied by the work stage.
static func capability_seconds(mods: RuleModifiers, tune: Dictionary, id: String, base_seconds: float, fixed := false, ignore_duration := false) -> float:
	var machine := 1.0 if fixed else (1.0 if ignore_duration else duration_mult(mods, id)) / speed(mods, id)
	return base_seconds * machine * tuned(tune, id)


## Baseline operation, not a complete order; automatic machines retain batch semantics.


static func station_timing(shop: SpecShop, mods: RuleModifiers, tune: Dictionary, id: String) -> Dictionary:
	var station := shop.station(id)
	if station == null: return {}
	if station.block == "batch_pot" or (shop.fulfillment.handoff != "single" and station.block in ["combine", "pickup"] and not station.params.get("manual", false)):
		return {"seconds": machine_seconds(shop, mods, tune, id), "base_seconds": float(station.params.get("cook_seconds", station.params.get("seconds", station.params.get("process_seconds", 0.0)))),
			"unit": "cooking_batch" if station.block == "batch_pot" else "batch" if station.block == "combine" else "item", "automatic": true}
	var base := float(station.params.get("seconds", station.params.get("fetch_seconds", 0.0)))
	var fixed := false
	if shop.fulfillment.handoff == "single":
		# The first non-fixed recipe action is the station's representative operation.
		var found := false
		for dish in shop.dishes:
			for step in dish.steps:
				if step.station == id and not step.fixed and not found:
					base = step.seconds * step.repeat
					fixed = step.fixed
					found = true
		for option in shop.order_options:
			if not found and option.step != null and (option.step.station == id or (option.step.station.is_empty() and option.station == id)):
				base = option.step.seconds * option.step.repeat
				fixed = option.step.fixed
				found = true
	return {"seconds": manual_operation_seconds(shop, mods, tune, id, base, {}, fixed), "base_seconds": base, "unit": "operation", "automatic": false}


static func pot_seconds(shop: SpecShop, mods: RuleModifiers, tune: Dictionary, id: String) -> float:
	var st := shop.station(id)
	var seconds := float(st.params.get("cook_seconds", 0.0))
	return seconds * duration_mult(mods, id) / speed(mods, id) * tuned(tune, id)


static func machine_seconds(shop: SpecShop, mods: RuleModifiers, tune: Dictionary, id: String) -> float:
	var st := shop.station(id)
	match st.block:
		"batch_pot": return pot_seconds(shop, mods, tune, id)
		"combine": return float(st.params.get("seconds", 0.0)) * duration_mult(mods, id) / speed(mods, id) * tuned(tune, id)
		"pickup":
			return float(st.params.get("process_seconds", 0.0)) / speed(mods, id) / process_slots(shop, mods, id) * tuned(tune, id)
	return 0.0


static func flyer_customers(mods: RuleModifiers) -> int:
	return int(mods.value("flyer_customers", 0.0))


static func flyer_cooldown(mods: RuleModifiers) -> float:
	return mods.value("flyer_cooldown", 0.0)
