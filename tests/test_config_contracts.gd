extends "res://tests/test_case.gd"

const Profile := preload("res://game/app/profile.gd")
const Session := preload("res://game/app/shop_session.gd")
const PANCAKE: SpecShop = preload("res://content/shops/pancake/shop.tres")
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
const VALIDATOR := "res://game/rules/shop_spec_validator.gd"
var paths: Array[String] = []

func _validator() -> Script:
	check(ResourceLoader.exists(VALIDATOR), "pure configuration validator exists")
	return load(VALIDATOR) if ResourceLoader.exists(VALIDATOR) else null

func _path(label: String) -> String:
	var p := "user://config-%d-%d-%s.json" % [OS.get_process_id(), Time.get_ticks_usec(), label]
	paths.append(p)
	return p

func cleanup() -> void:
	for p in paths:
		for name in DirAccess.get_files_at(p.get_base_dir()):
			if name.begins_with(p.get_file()): DirAccess.remove_absolute(p.get_base_dir().path_join(name))

func _bad(shop: SpecShop, path: String) -> void:
	var validator := _validator()
	if validator == null: return
	var errors: Array = validator.validate(shop)
	check(errors.any(func(e): return e.path == path), "invalid configuration identifies " + path + ": " + validator.summary(errors))
	for e in errors: check(e.has("code") and e.has("message"), "structured diagnostic")

func test_invalid_configuration_never_reads_quarantines_or_overwrites_shop() -> void:
	for fresh in [false, true]:
		var profile := Profile.new(_path("profile"))
		profile.fresh_shop = fresh
		profile.save()
		var bad: SpecShop = PANCAKE.duplicate(true)
		bad.dispatch.shortage_per = 23.0
		var store := ShopSave.new(bad, _path("shop"))
		var file := FileAccess.open(store.path, FileAccess.WRITE)
		file.store_string("uninterpretable existing shop bytes")
		file.close()
		var before := FileAccess.get_file_as_bytes(store.path)
		var profile_before := FileAccess.get_file_as_bytes(profile.path)
		var state: Dictionary = profile.to_dict()
		var session := Session.new(profile, store)
		check(session.start() != OK, "invalid schema rejected before storage")
		check(not session.started and session.rules == null, "no playable state")
		check(FileAccess.file_exists(store.path), "invalid schema does not quarantine")
		if FileAccess.file_exists(store.path): check_eq(FileAccess.get_file_as_bytes(store.path), before, "original bytes preserved")
		check_eq(FileAccess.get_file_as_bytes(profile.path), profile_before, "profile bytes preserved")
		check_eq(profile.to_dict(), state, "profile memory preserved")

func test_required_resources_references_and_numbers_are_rejected_without_runtime_errors() -> void:
	var v := _validator()
	if v == null: return
	check(not v.validate(null).is_empty(), "null shop rejected")
	var bad: SpecShop = PANCAKE.duplicate(true)
	bad.staff = null
	_bad(bad, "staff")
	bad = PANCAKE.duplicate(true)
	bad.dishes.append(null)
	_bad(bad, "dishes[%d]" % (bad.dishes.size() - 1))
	bad = PANCAKE.duplicate(true)
	bad.stations[1].id = bad.stations[0].id
	_bad(bad, "stations[1].id")
	bad = PANCAKE.duplicate(true)
	bad.dishes[0].steps[0].station = "missing"
	_bad(bad, "dishes[0].steps[0].station")
	bad = PANCAKE.duplicate(true)
	bad.stages[0].customer_interval = NAN
	_bad(bad, "stages[0].customer_interval")
	bad = PANCAKE.duplicate(true)
	bad.stations[0].params["unknown_machine_knob"] = 5
	_bad(bad, "stations[0].params.unknown_machine_knob")

func test_mode_contract_rejects_ignored_and_misleading_declarations() -> void:
	var bad: SpecShop = TEA.duplicate(true)
	bad.fulfillment.arrival = "exponential"
	_bad(bad, "fulfillment.arrival")
	bad = PANCAKE.duplicate(true)
	bad.fulfillment.pay_at = "on_deliver"
	bad.fulfillment.leave_queue = "after_pay"
	_bad(bad, "fulfillment.leave_queue")
	bad = PANCAKE.duplicate(true)
	bad.dispatch.base_scores = {"take": 100.0}
	_bad(bad, "dispatch.base_scores")

func _arrival_times(rules: ShopRules) -> Array:
	var times: Array = []
	for e in rules.events.log:
		if e.name == "arrived": times.append(e.time)
	return times

func test_single_fixed_and_exponential_arrivals_are_real_and_resume_exactly() -> void:
	var histories: Array = []
	for policy in ["fixed", "exponential"]:
		var shop: SpecShop = PANCAKE.duplicate(true)
		shop.fulfillment.arrival = policy
		shop.fulfillment.leave_after = 0.0
		shop.stages[0].queue_capacity = 1000
		shop.stages[0].customer_interval = 2.0
		var rules := ShopRules.new(shop)
		rules.unlock(shop.goals.opening_station)
		rules.run(30.0)
		var times := _arrival_times(rules)
		check(times.size() >= 8, "observed natural arrivals")
		var gaps: Array = []
		for i in range(1, times.size()): gaps.append(snappedf(times[i] - times[i - 1], 0.1))
		if policy == "fixed": check(gaps.all(func(g): return absf(g - 2.0) < 0.11), "fixed arrivals use configured interval: " + str(gaps))
		else: check(gaps.any(func(g): return absf(g - gaps[0]) > 0.11), "exponential arrivals vary")
		histories.append(times)
		var store := ShopSave.new(shop, _path(policy))
		check_eq(store.save_game(rules), OK, "save midgame")
		var resumed := store.load_game()
		rules.run(30.0)
		resumed.run(30.0)
		check_eq(resumed.to_dict(), rules.to_dict(), "exact continuation for " + policy)
	check(histories[0] != histories[1], "arrival choice changes actual customer history")

func test_production_and_third_fixture_are_accepted_and_every_policy_field_is_declared() -> void:
	var v := _validator()
	if v == null: return
	for shop in [PANCAKE, TEA, load("res://tests/fixtures/noodle/shop.tres")]:
		check_eq(v.validate(shop), [], "valid shop " + shop.id + ": " + v.summary(v.validate(shop)))
	for mode in ["single", "handoff"]:
		var matrix: Dictionary = v.capabilities(mode)
		for pair in [["fulfillment", SpecFulfillment.new()], ["dispatch", SpecDispatch.new()]]:
			for prop in pair[1].get_property_list():
				if int(prop.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
					check(matrix[pair[0]].has(prop.name), "matrix documents " + pair[0] + "." + prop.name)

func test_fixed_arrival_does_not_consume_an_interval_random_draw() -> void:
	for policy in ["fixed", "exponential"]:
		var shop: SpecShop = PANCAKE.duplicate(true)
		shop.fulfillment.arrival = policy
		shop.fulfillment.addon_dish = ""
		shop.fulfillment.addon_chance = 0.0
		shop.fulfillment.first_customer_delay = 0.0
		shop.order_options.clear()
		var rules := ShopRules.new(shop)
		rules.unlock(shop.goals.opening_station)
		var expected := RandomNumberGenerator.new()
		expected.seed = rules.rng.seed
		expected.state = rules.rng.state
		expected.randf() # Dish selection is the sole customer draw in this fixture.
		if policy == "exponential": expected.randf()
		rules.step(0.1)
		check_eq(_arrival_times(rules).size(), 1, "one actual customer")
		check_eq(rules.rng.state, expected.state, "only exponential draws an arrival interval")

func test_nested_shapes_ranges_and_unreachable_stages_are_rejected() -> void:
	var bad: SpecShop = PANCAKE.duplicate(true)
	bad.stations[1].tracks[0].levels.append(null)
	_bad(bad, "stations[1].tracks[0].levels[%d]" % (bad.stations[1].tracks[0].levels.size() - 1))
	bad = PANCAKE.duplicate(true)
	bad.staff.hire_rule = "cycle"
	bad.staff.hire_order.clear()
	_bad(bad, "staff.hire_order")
	bad = PANCAKE.duplicate(true)
	bad.layout.aliases[bad.stations[0].id] = "missing"
	_bad(bad, "layout.aliases." + bad.stations[0].id)
	bad = PANCAKE.duplicate(true)
	bad.stages[0].stations.clear()
	_bad(bad, "stages[0].order_weights")
	bad = PANCAKE.duplicate(true)
	bad.stations[0].params["take_seconds"] = "slow"
	_bad(bad, "stations[0].params.take_seconds")
	bad = PANCAKE.duplicate(true)
	bad.staff.kinds[0].stats["walk"] = 0.0
	_bad(bad, "staff.kinds[0].stats.walk")
	bad = PANCAKE.duplicate(true)
	bad.guide[0].cues = [{"if": [12]}]
	_bad(bad, "guide[0].cues[0].if[0]")
	bad = PANCAKE.duplicate(true)
	bad.stations[1].tracks[0].levels[0].effects[0].target = "missing"
	_bad(bad, "stations[1].tracks[0].levels[0].effects[0].target")
	bad = TEA.duplicate(true)
	bad.dispatch.base_scores["ignored_key"] = 10.0
	_bad(bad, "dispatch.base_scores.ignored_key")

func test_unresolved_app_shop_and_invalid_campaign_entries_are_safe() -> void:
	var app: Node = load("res://game/app/app.gd").new()
	var profile := Profile.new(_path("unresolved"))
	profile.shop = "missing"
	app.profile = profile
	var session: RefCounted = app.create_session()
	check(session.store == null, "unresolved shop does not construct ShopSave")
	check(session.start() != OK, "unresolved startup fails explicitly")
	var campaign := SpecCampaign.new()
	campaign.cities.append(null)
	profile = Profile.new(_path("null-city"), campaign)
	check(Session.shop_for(profile) == null, "invalid campaign has no resolvable shop")
	app.free()

func test_unsafe_recipe_and_presentation_nested_shapes_fail_before_session_io() -> void:
	var variants: Array[SpecShop] = []
	var bad: SpecShop = PANCAKE.duplicate(true)
	bad.stages[1].stations.clear()
	_bad(bad, "stages[1].stations")
	variants.append(bad)
	bad = PANCAKE.duplicate(true)
	bad.guide[0].rows = [["icon"]]
	_bad(bad, "guide[0].rows[0]")
	variants.append(bad)
	bad = PANCAKE.duplicate(true)
	bad.stations[0] = null
	variants.append(bad)
	bad = PANCAKE.duplicate(true)
	bad.dishes[0].steps[0].station = "missing"
	variants.append(bad)
	bad = PANCAKE.duplicate(true)
	bad.stages[0].customer_interval = INF
	variants.append(bad)
	for shop in variants:
		var profile := Profile.new(_path("bad-profile"))
		profile.fresh_shop = true
		profile.save()
		var store := ShopSave.new(shop, _path("bad-shop"))
		var file := FileAccess.open(store.path, FileAccess.WRITE)
		file.store_string("original invalid save")
		file.close()
		var original := FileAccess.get_file_as_bytes(store.path)
		var session := Session.new(profile, store)
		check(session.start() != OK, "structural invalidity blocks real startup")
		check(FileAccess.file_exists(store.path), "existing file remains in place")
		if FileAccess.file_exists(store.path): check(FileAccess.get_file_as_bytes(store.path) == original, "original bytes remain")
		check(profile.fresh_shop and session.rules == null, "no fresh acknowledgement or rules")
	bad = TEA.duplicate(true)
	for dish in bad.dishes:
		for step in dish.steps:
			if bad.station(step.station).block == "batch_pot": step.produces.clear()
	_bad(bad, "stations[3]")

func test_flavor_fallback_and_guide_references_cannot_hide_runtime_errors() -> void:
	var bad: SpecShop = PANCAKE.duplicate(true)
	bad.stages[0].flavor_group = "unavailable_flavors"
	bad.stages[0].flavor_fallback = ""
	bad.stages[0].order_weights["unavailable_flavors"] = 1.0
	_bad(bad, "stages[0].flavor_fallback")
	bad = PANCAKE.duplicate(true)
	bad.guide[0].cues = [{"at": "station:missing"}]
	_bad(bad, "guide[0].cues[0].at")
	bad = PANCAKE.duplicate(true)
	bad.stations[1].tracks[0].levels[0].effects[0].price_part = "missing"
	_bad(bad, "stations[1].tracks[0].levels[0].effects[0].price_part")

func test_single_rejects_reserved_recipe_actions_and_conveyor_declarations() -> void:
	for action in ["take", "hand"]:
		var bad: SpecShop = PANCAKE.duplicate(true)
		bad.dishes[0].steps[0].action = action
		_bad(bad, "dishes[0].steps[0].action")
		bad = PANCAKE.duplicate(true)
		bad.order_options[0].step.action = action
		_bad(bad, "order_options[0].step.action")
	var bad: SpecShop = PANCAKE.duplicate(true)
	var connection := SpecConnection.new()
	connection.id = "unsupported_belt"
	connection.from = bad.stations[0].id
	connection.to = bad.stations[1].id
	bad.connections.append(connection)
	_bad(bad, "connections")
