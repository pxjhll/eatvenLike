extends "res://tests/test_case.gd"
const PATH := "res://game/rules/template/recipe_normalizer.gd"
const Compiler := preload("res://game/rules/template/compiler.gd")
const Runtime := preload("res://game/rules/template/runtime.gd")
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
const PANCAKE: SpecShop = preload("res://content/shops/pancake/shop.tres")
const STIRFRY: SpecShop = preload("res://content/shops/stirfry/shop.tres")

func _normalize(shop: SpecShop, dishes: Array = []) -> Dictionary:
	check(ResourceLoader.exists(PATH), "formal recipes need a strict definition-boundary normalizer")
	if not ResourceLoader.exists(PATH): return {}
	return load(PATH).from_shop(shop, dishes)

func test_formal_explicit_recipes_compile_without_modifying_the_authored_shop() -> void:
	var before := preload("res://game/rules/shop_content_contract.gd").describe(STIRFRY)
	var result := _normalize(STIRFRY)
	if result.is_empty(): return
	check_eq(result.errors, [], "explicit formal production graph is supported")
	check_eq(result.template.recipes.size(), STIRFRY.dishes.size(), "every formal dish preserved")
	check_eq(Compiler.compile(result.template).errors, [], "same public compiler accepts normalized graph")
	check_eq(preload("res://game/rules/shop_content_contract.gd").describe(STIRFRY), before, "normalization is definition-only and read-only")
	var meal: Dictionary = Compiler.compile(result.template).definition.recipes.tomato_rice
	var output: Dictionary = meal.nodes[meal.output.node]
	check_eq(output.consumes, {"rice":1, "tomato_egg":1}, "rice and cooked topping are both required at merge")
	check_eq(output.dependencies.size(), 2, "both production branches are preserved")

func test_normalized_formal_recipes_run_with_real_shop_navigation_and_the_common_runtime() -> void:
	var result := _normalize(STIRFRY)
	if result.is_empty(): return
	if not result.errors.is_empty(): check_eq(result.errors, [], "normalization succeeds before runtime"); return
	var dishes: Array = []
	for dish in STIRFRY.dishes: dishes.append(dish.id)
	_exercise_products(STIRFRY, result.template, dishes, "window")

func _exercise_products(authored: SpecShop, template: Resource, dishes: Array, receiving_port: String) -> void:
	for dish_id in dishes:
		var shop: SpecShop = authored.copy_for_editing()
		var owner := ShopRules.new(shop,42)
		for station in shop.stations: owner.unlocked[station.id] = true
		owner.nav.set_open(owner.unlocked)
		var test_template: Resource = template.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
		test_template.places["test:receiving"] = {"port":shop.layout.points[receiving_port]}
		var runtime := Runtime.new(owner, test_template)
		check_eq(runtime.last_error, "", "actual shop defines the common movement and employee services")
		var unit: Dictionary = runtime.request_production(dish_id)
		for tick in 3000:
			check_eq(runtime.step(0.1), "", "normalized formal production step")
			if runtime.ready(unit.id): break
		check(runtime.ready(unit.id), "formal recipe completed through shared capabilities: " + dish_id)
		var output: Dictionary = runtime.production_output(unit.id)
		var worker: Dictionary = {}
		for candidate in owner.workers:
			if candidate.deployed and runtime.runner.idle(candidate.id): worker = candidate; break
		check(not worker.is_empty(), "real employee available to harvest " + dish_id)
		if worker.is_empty(): continue
		check_eq(runtime.runner.transfer(worker.id, output.place, "test:receiving", output.item, output.count,
			template.hop_seconds, output.owner, unit.id, output.pickup_seconds), "", "harvest uses the common transfer capability")
		check_eq(runtime.frame().held, {}, "ready stock and its reservation do not appear in hands")
		var picked := false
		var pickup_ticks := 0
		for tick in 1000:
			if worker.phase == "pickup": pickup_ticks += 1
			check_eq(runtime.step(0.1), "", "real pickup and delivery step")
			if worker.carry_count > 0:
				if not picked: check(worker.pos.is_equal_approx(runtime.runner.ports[output.place]), "pickup commits at the actual source")
				picked = true
				check_eq(runtime.frame().held[worker.id].items, [{"item":output.item, "count":output.count}], "only real carried output appears in hands")
			if runtime.runner.idle(worker.id): break
		check(picked, "employee physically carries " + dish_id)
		check_eq(runtime.runner.inventory.quantity("test:receiving", output.item, unit.id), output.count, "owned final output reaches receiving buffer")
		check_eq(worker.carry_count, 0, "drop clears the real employee hand")
		check_eq(runtime.frame().held, {}, "drop also clears the public held icon")
		if dish_id == "soup":
			check_eq(output.pickup_seconds, 3.0, "source-only soup keeps the authored three-second ladle")
			check_eq(pickup_ticks, ceili(30.0 / owner.skill(worker)), "ready soup still requires actual ladling before it is carried")
		check_eq(runtime.runner.inventory.audit(), [], "physical production conserves goods: " + dish_id)
		check_eq(runtime.frame().draws, [], "normalization does not revive loose stock icons")

func test_existing_front_products_in_other_shops_reuse_the_same_normalizer() -> void:
	for entry in [{"shop":TEA, "dishes":["lemonade", "lemon_tea"], "port":"counter"}, {"shop":PANCAKE, "dishes":["soy"], "port":"front_counter"}]:
		var result := _normalize(entry.shop, entry.dishes)
		if result.is_empty(): return
		check_eq(result.errors, [], "explicit supported subset is not selected by shop name")
		check_eq(Compiler.compile(result.template).errors, [], "front recipe uses existing common process capabilities")
		check_eq(result.template.recipes.size(), entry.dishes.size(), "no extra or missing requested recipe")
		_exercise_products(entry.shop, result.template, entry.dishes, entry.port)

func test_unmapped_carried_inputs_display_and_dynamic_stock_rules_are_errors_instead_of_dropped_steps() -> void:
	for shop in [TEA, PANCAKE]:
		var result := _normalize(shop)
		if result.is_empty(): return
		check(not result.errors.is_empty(), "implicit formal rules must be explicitly mapped before adoption")
		check_eq(result.template, null, "unsupported conversion cannot return a deceptively usable partial template")
		for error in result.errors:
			check(not String(error.path).is_empty() and not String(error.code).is_empty(), "precise capability and source path")
	var result := _normalize(PANCAKE, ["guozi"])
	if result.is_empty(): return
	var codes: Array = []
	for error in result.errors: codes.append(String(error.code))
	check("implicit_carried_input" in codes, "thin crisp step cannot discard the pancake already in hand")
	check("processing_display" in codes, "put_down needs an explicit public processing display binding")

func test_unknown_selection_and_ambiguous_producers_are_rejected_without_mutating_source_resources() -> void:
	var result := _normalize(STIRFRY, ["missing"])
	if result.is_empty(): return
	check(not result.errors.is_empty() and result.template == null, "missing selected dish is explicit")
	var shop: SpecShop = STIRFRY.copy_for_editing()
	var duplicate: SpecStep = shop.dishes[0].steps[0].duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	shop.dishes[0].steps.insert(1, duplicate)
	result = _normalize(shop, [shop.dishes[0].id])
	check(not result.errors.is_empty() and result.template == null, "ambiguous producer cannot silently choose one")

func test_incomplete_source_ports_and_stock_return_errors_without_a_partial_template() -> void:
	for variant in ["port", "empty_stock", "null_stock"]:
		var shop: SpecShop = STIRFRY.copy_for_editing()
		var station: SpecStation
		var selected: Array
		var expected: String
		if variant == "port":
			station = shop.station("pantry")
			shop.layout.points.erase(shop.layout.aliases.get(station.id, station.id))
			selected = ["tomato_rice"]
			expected = "missing_operation_port"
		else:
			station = shop.station("soup_pot")
			station.stock.clear()
			if variant == "null_stock": station.stock.append(null)
			selected = ["soup"]
			expected = "batch_stock"
		var result := _normalize(shop, selected)
		if result.is_empty(): return
		check_eq(result.template, null, "invalid source cannot become a partial runtime")
		var found := false
		for error in result.errors:
			if error.code == expected and error.path.begins_with("stations." + station.id): found = true
		check(found, "structured source error for " + variant)

func test_incomplete_catalog_entries_are_reported_before_indexing_selected_dishes() -> void:
	for variant in ["dish", "station"]:
		var shop: SpecShop = STIRFRY.copy_for_editing()
		if variant == "dish": shop.dishes.push_front(null)
		else: shop.stations.push_front(null)
		var result := _normalize(shop, ["tomato_rice"])
		if result.is_empty(): return
		check_eq(result.template, null, "incomplete catalog is not usable")
		var found := false
		for error in result.errors:
			if error.code == "missing_" + variant: found = true
		check(found, "null " + variant + " has an authoring error instead of a runtime exception")

func test_batch_parameters_are_validated_before_coercion_or_copying() -> void:
	for entry in [{"key":"stir_points", "value":1}, {"key":"batch", "value":2.5}, {"key":"manual_load", "value":"true"}]:
		var shop: SpecShop = STIRFRY.copy_for_editing()
		shop.station("soup_pot").params[entry.key] = entry.value
		var result := _normalize(shop, ["soup"])
		if result.is_empty(): return
		check_eq(result.template, null, "malformed batch parameter cannot produce a runtime")
		check(result.errors.any(func(error: Dictionary) -> bool: return error.path == "stations.soup_pot.params." + entry.key),
			"invalid parameter retains its authoring path: " + entry.key)

func test_normalized_batch_fetch_keeps_fixed_machine_effects_and_target_tuning() -> void:
	var result := _normalize(STIRFRY, ["soup"])
	if result.is_empty() or not result.errors.is_empty(): return
	var owner := ShopRules.new(STIRFRY.copy_for_editing(),42)
	owner.tune["soup_pot"] = 2.0
	owner.apply_effect("event", "soup_speed", SpecEffect.make("speed", "mul", 5.0, "soup_pot"))
	var runtime := Runtime.new(owner, result.template)
	var unit: Dictionary = runtime.request_production("soup")
	check_eq(runtime.production_output(unit.id).pickup_seconds, 6.0, "batch ladle ignores cooking speed but keeps its three-second clock × target tuning")

func test_automatic_workbench_does_not_silently_replace_machine_time_with_manual_step_time() -> void:
	var shop: SpecShop = STIRFRY.copy_for_editing()
	var station := shop.station("plum_dispenser")
	station.block = "combine"
	station.params = {"manual":false, "seconds":8.0, "capacity":4}
	var result := _normalize(shop, ["plum_juice"])
	if result.is_empty(): return
	check_eq(result.template, null, "automatic batch conversion needs an explicit timing and batch mapping")
	check(result.errors.any(func(error: Dictionary) -> bool: return error.code == "automatic_workbench"),
		"manual step clock cannot silently become the automatic device clock")
