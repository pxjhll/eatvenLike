extends "res://tests/test_case.gd"
const LegacyRules := preload("res://tests/fixtures/legacy_shops/reference_rules.gd")
## Frozen v0 business regression; formal v1 coverage: test_first_shops_migration.

const SHOPS := [preload("res://tests/fixtures/legacy_shops/tea.tres"), preload("res://tests/fixtures/legacy_shops/pancake.tres"), preload("res://tests/fixtures/noodle/shop.tres")]

func _planner() -> Script:
	var path := "res://game/rules/fulfillment_plan.gd"
	check(ResourceLoader.exists(path), "fulfillment planning is independently usable")
	return load(path) if ResourceLoader.exists(path) else null

func _station(id: String, block: String, zone := "", params: Dictionary = {}, seatable := false) -> SpecStation:
	var st := SpecStation.new()
	st.id = id
	st.block = block
	st.zone = zone
	st.params = params
	st.seatable = seatable
	return st

func _step(station: String, action: String, consumes: Dictionary = {}, produces: Dictionary = {}) -> SpecStep:
	var step := SpecStep.new()
	step.station = station
	step.action = action
	step.consumes.assign(consumes)
	step.produces.assign(produces)
	return step

func _dish(id: String, steps: Array, front := false) -> SpecDish:
	var dish := SpecDish.new()
	dish.id = id
	dish.steps.assign(steps)
	dish.front = front
	return dish

func _shop() -> SpecShop:
	# Intentionally has no staff, stages, dispatch, navigation or live Rules.
	var shop := SpecShop.new()
	shop.stations.assign([
		_station("s0", "supply"), _station("c0", "counter"), _station("s1", "supply"),
		_station("p0", "pickup", "", {"process_seconds": 1}), _station("p1", "pickup"),
		_station("pot", "batch_pot", "kitchen", {}, true), _station("manual", "combine", "kitchen", {"manual": true}),
		_station("auto", "combine", "kitchen"), _station("front", "hand", "front", {}, true),
		_station("p2", "pickup", "", {"process_seconds": 2}), _station("c1", "counter", "", {"take_seconds": 0.25, "hand_seconds": 0.75})])
	shop.dishes.assign([
		_dish("main", [_step("s0", "fetch", {}, {"x": 1, "y": 1}), _step("front", "mix", {}, {"z": 1}),
			_step("pot", "boil", {"raw": 1, "y": 1, "x": 1}, {"p1": 1, "p2": 1}),
			_step("auto", "mix", {"x": 1, "y": 1}, {"a1": 1, "a2": 1}),
			_step("pot", "take", {"z": 1}, {"last": 1}), _step("p0", "take"), _step("c1", "hand"), _step("missing", "noop")]),
		_dish("addon", [_step("s0", "fetch", {}, {"x": 1}), _step("pot", "boil", {"x": 1}, {"other": 1}), _step("manual", "mix")], true)])
	shop.fulfillment = SpecFulfillment.new()
	shop.fulfillment.addon_dish = "addon"
	shop.layout = SpecLayout.new()
	return shop

func _has_object(value: Variant) -> bool:
	if value is Object: return true
	if value is Array:
		for item in value:
			if _has_object(item): return true
	if value is Dictionary:
		for key in value:
			if _has_object(key) or _has_object(value[key]): return true
	return false

func test_derive_literal_roles_and_definition_order_without_live_simulation() -> void:
	var planner := _planner()
	if planner == null: return
	var shop := _shop()
	var actual: Dictionary = planner.derive(shop)
	check_eq(actual, {
		"counter_id": "c1", "supply_id": "s0", "pickup_id": "p2", "pots": ["pot"], "autos": ["auto"],
		"seatables": ["pot", "front"], "dish_ids": ["main", "addon"], "front_dishes": ["addon"], "kitchen_dishes": ["main"],
		"chains": {"main": ["pot", "auto"], "addon": ["pot", "manual"]},
		"station_output": {"pot|main": "last", "auto|main": "a2", "pot|addon": "other"},
		"station_input": {"pot": "y", "auto": "x"}}, "literal first/last, chain exclusion/dedup and overwrite rules")
	check(not _has_object(actual), "derive returns data only")
	var empty: Dictionary = planner.derive(SpecShop.new())
	check_eq(empty, {"counter_id": "", "supply_id": "", "pickup_id": "", "pots": [], "autos": [], "seatables": [], "dish_ids": [], "front_dishes": [], "kitchen_dishes": [], "chains": {}, "station_output": {}, "station_input": {}}, "empty definitions have fresh empty defaults")

func _single_shop() -> SpecShop:
	var shop := _shop()
	var main := _step("pot", "cook", {}, {"first": 1, "second": 1})
	main.seconds = 1.25
	main.repeat = 3
	main.label = "cook label"
	main.fixed = true
	main.into_machine = true
	main.put_down = true
	shop.dishes.assign([_dish("main", [main]), _dish("addon", [_step("front", "pour")])])
	shop.layout.aliases.assign({"pot.cook": "actual-anchor", "front.pack": "bag-anchor"})
	var option := SpecOrderOption.new()
	option.id = "bag"
	option.station = "front"
	option.step = _step("", "pack", {}, {"bagged": 1})
	option.step.seconds = 0.5
	option.step.repeat = 2
	option.step.label = "bag label"
	var null_option := SpecOrderOption.new()
	null_option.id = "null"
	shop.order_options.assign([option, null_option])
	return shop

func test_single_literal_rows_addon_order_payment_and_option_fallback() -> void:
	var planner := _planner()
	if planner == null: return
	var shop := _single_shop()
	shop.fulfillment.pay_at = "on_take"
	var order := {"kind": "main", "addon": true, "options": ["missing", "null", "bag", "bag"]}
	var take := {"point": "c1", "action": "take", "seconds": 0.25, "label": "收钱", "station": "c1"}
	var addon := {"point": "front", "action": "pour", "seconds": 0.0, "label": "", "station": "front", "holds": "", "fixed": false, "into_machine": false, "put_down": false}
	var main := {"point": "pot.cook", "action": "cook", "seconds": 3.75, "label": "cook label", "station": "pot", "holds": "first", "fixed": true, "into_machine": true, "put_down": true}
	var bag := {"point": "front.pack", "action": "pack", "seconds": 1.0, "label": "bag label", "station": "front", "holds": "bagged", "fixed": false, "into_machine": false, "put_down": false}
	var hand := {"point": "c1", "action": "hand", "seconds": 0.75, "label": "递餐", "station": "c1"}
	check_eq(planner.single_steps(shop, "c1", order), [take, addon, main, bag, bag, hand], "complete literal rows: addon first; options retain order and repeats; alias keys are points")
	shop.fulfillment.addon_first = false
	check_eq(planner.single_steps(shop, "c1", order), [take, main, addon, bag, bag, hand], "addon after")
	check_eq(planner.single_steps(shop, "c1", {"kind": "addon", "addon": true}), [take, addon, hand], "main addon is never duplicated and absent options is allowed")
	shop.fulfillment.pay_at = "on_deliver"
	take.label = "接单"
	hand.label = "递餐收钱"
	check_eq(planner.single_steps(shop, "c1", {"kind": "main", "addon": false}), [take, main, hand], "delivery payment labels")
	shop.order_options[0].step.station = "pot"
	bag.point = "pot"
	bag.station = "pot"
	check_eq(planner.single_steps(shop, "c1", {"kind": "main", "addon": false, "options": ["bag"]}), [take, main, bag, hand], "explicit option station overrides fallback and unmatched alias uses station")

func test_real_pancake_route_matches_literal_fields() -> void:
	var planner := _planner()
	if planner == null: return
	var rows: Array = planner.single_steps(SHOPS[1], "front_counter", {"kind": "plain", "addon": true, "options": ["bag"]})
	check_eq(rows.map(func(row: Dictionary) -> String: return row.station + ":" + row.action), ["front_counter:take", "soy_milk:pour", "raw_ingredients:fetch", "rear_equipment:mix", "rear_equipment:grill", "roll:roll", "bag:bag", "front_counter:hand"], "real pancake full route")
	check_eq(rows.map(func(row: Dictionary) -> float: return row.seconds), [0.0, 1.5, 1.0, 1.0, 10.0, 2.5, 2.0, 0.6], "real timings")
	check_eq(rows[3], {"point": "rear_equipment.mix", "action": "mix", "seconds": 1.0, "label": "打面糊", "station": "rear_equipment", "holds": "batter", "fixed": true, "into_machine": true, "put_down": false}, "real alias and flags")
	check_eq(rows[5].put_down, true, "real roll puts food down")

func test_nested_mutation_and_retained_plans_are_detached_from_definitions() -> void:
	var planner := _planner()
	if planner == null: return
	var shop := _single_shop()
	var order := {"kind": "main", "addon": true, "options": ["bag"]}
	var before := var_to_bytes(order)
	var roles: Dictionary = planner.derive(shop)
	var retained := roles.duplicate(true)
	var rows: Array = planner.single_steps(shop, "c1", order)
	var original_rows := rows.duplicate(true)
	var retained_roles: Dictionary = planner.derive(shop)
	var retained_rows: Array = planner.single_steps(shop, "c1", order)
	var retained_roles_expected := retained_roles.duplicate(true)
	var retained_rows_expected := retained_rows.duplicate(true)
	roles.chains.main.append("mutation")
	roles.station_input["pot"] = "mutation"
	roles.pots.clear()
	rows[1].label = "mutation"
	rows.append({"mutation": []})
	check_eq(planner.derive(shop), retained, "editing nested returned roles cannot change future plans")
	check_eq(planner.single_steps(shop, "c1", order), original_rows, "editing returned rows cannot change future plans")
	check_eq(var_to_bytes(order), before, "caller order unchanged")
	shop.dishes[0].steps[0].label = "changed definition"
	shop.dishes[0].steps[0].produces["third"] = 1
	shop.stations[5].id = "new-pot"
	var updated_rows: Array = planner.single_steps(shop, "c1", order)
	var updated_roles: Dictionary = planner.derive(shop)
	check_eq(updated_rows[2].label, "changed definition", "new planning observes current definition")
	check_eq(updated_roles.pots, ["new-pot"], "derive is not cached")
	check(updated_rows != retained_rows_expected, "definition edit changes the new step plan")
	check(updated_roles != retained_roles_expected, "definition edit changes the new role plan")
	check_eq(retained_rows, retained_rows_expected, "retained returned rows remain completely unchanged after definition edits and later planning")
	check_eq(retained_roles, retained_roles_expected, "retained returned roles remain completely unchanged after definition edits and later planning")
	check(not _has_object(original_rows), "rows contain no Objects")

func test_all_three_shops_planning_leaves_live_state_rng_events_and_inputs_unchanged() -> void:
	var planner := _planner()
	if planner == null: return
	for source in SHOPS:
		var shop: SpecShop = source.duplicate(true)
		var rules := LegacyRules.new(shop, 42)
		rules.gold = 1e8
		if not rules.next_unlock().is_empty(): rules.unlock(rules.next_unlock())
		rules.run(10.0)
		var state := var_to_bytes(rules.to_dict())
		var definition := ResourceSaver.save(shop, "user://fulfillment-definition-before.tres")
		check_eq(definition, OK, "definition can be recorded")
		var definition_before := FileAccess.get_file_as_bytes("user://fulfillment-definition-before.tres")
		var order := {"kind": shop.dishes[0].id, "addon": false, "options": []}
		var order_before := var_to_bytes(order)
		var roles: Dictionary = planner.derive(shop)
		var rows: Array = planner.single_steps(shop, rules.counter_id, order)
		check(not _has_object(roles) and not _has_object(rows), shop.id + " returns only data")
		var expected_roles := roles.duplicate(true)
		var expected_rows := rows.duplicate(true)
		roles.chains[order.kind].append("mutated")
		roles.station_output.clear()
		rows[0].seconds = 999
		check_eq(planner.derive(shop), expected_roles, shop.id + " fresh nested derive")
		check_eq(planner.single_steps(shop, rules.counter_id, order), expected_rows, shop.id + " fresh single rows")
		check_eq(var_to_bytes(order), order_before, shop.id + " order read only")
		check_eq(var_to_bytes(rules.to_dict()), state, shop.id + " live state, RNG and event log read only")
		ResourceSaver.save(shop, "user://fulfillment-definition-before.tres")
		check_eq(FileAccess.get_file_as_bytes("user://fulfillment-definition-before.tres"), definition_before, shop.id + " complete definition read only")
