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

func _reject_before_io(shop: SpecShop) -> void:
	for fresh in [false, true]:
		var profile := Profile.new(_path("review-profile"))
		if profile.shop != shop.id: check_eq(profile.select_shop(shop.id), OK, "select configured shop before probing startup")
		profile.fresh_shop = fresh
		profile.save()
		var store := ShopSave.new(shop, _path("review-shop"))
		var file := FileAccess.open(store.path, FileAccess.WRITE)
		file.store_string("original shop bytes must not be interpreted")
		file.close()
		var original := FileAccess.get_file_as_bytes(store.path)
		var profile_bytes := FileAccess.get_file_as_bytes(profile.path)
		var state: Dictionary = profile.to_dict()
		var session := Session.new(profile, store)
		check(session.start() != OK, "review defect blocked before save IO")
		check(FileAccess.file_exists(store.path), "no quarantine")
		if FileAccess.file_exists(store.path): check(FileAccess.get_file_as_bytes(store.path) == original, "old store bytes unchanged")
		check(FileAccess.get_file_as_bytes(profile.path) == profile_bytes, "old profile bytes unchanged")
		check_eq(profile.to_dict(), state, "profile memory unchanged")
		check(not session.started and session.rules == null, "no playable runtime exposed")

func _event_effect(shop: SpecShop, effect: SpecEffect) -> SpecEvent:
	var event := SpecEvent.new()
	event.id = "contract_probe"
	event.trigger = "sale"
	event.effects.append(effect)
	shop.events.append(event)
	return event

func test_flavor_group_cannot_assume_listed_stations_mean_an_available_dish() -> void:
	var bad: SpecShop = PANCAKE.duplicate(true)
	bad.stages[0].flavor_group = "probe_flavors"
	bad.stages[0].flavor_fallback = ""
	bad.stages[0].order_weights["probe_flavors"] = 1.0
	for dish in bad.dishes:
		if dish.flavor_station.is_empty() or dish.topping_count <= 0: continue
		if dish.flavor_station not in bad.stages[0].stations: bad.stages[0].stations.append(dish.flavor_station)
		for step in dish.steps:
			if step.station not in bad.stages[0].stations: bad.stages[0].stations.append(step.station)
		for material in bad.station(dish.flavor_station).materials: material.track.requires_level = 1
	_bad(bad, "stages[0].flavor_fallback")
	_reject_before_io(bad)
	bad.stages[0].flavor_fallback = bad.stages[0].dish
	var v := _validator()
	check_eq(v.validate(bad), [], "explicit fallback repairs opening menu")
	var rules := ShopRules.new(bad)
	rules.unlock(bad.goals.opening_station)
	check(not rules.order_weights().is_empty(), "repaired opening menu evaluates without nil access")

func test_effect_attachment_and_scope_match_real_consumers() -> void:
	for kind in ["grant_gold", "unlock_recipe"]:
		var bad: SpecShop = PANCAKE.duplicate(true)
		var effect := SpecEffect.make(kind, "add", 777.0, bad.dishes[0].id if kind == "unlock_recipe" else "")
		bad.stations[1].tracks[0].base_effects.append(effect)
		_bad(bad, "stations[1].tracks[0].base_effects[%d].kind" % (bad.stations[1].tracks[0].base_effects.size() - 1))
		_reject_before_io(bad)
	var bad: SpecShop = PANCAKE.duplicate(true)
	_event_effect(bad, SpecEffect.make("price", "mul", 3.0, bad.stations[1].id))
	_bad(bad, "events[%d].effects[0].target" % (bad.events.size() - 1))
	_reject_before_io(bad)
	var good: SpecShop = PANCAKE.duplicate(true)
	var price := SpecEffect.make("price", "mul", 3.0)
	price.dishes = [good.dishes[0].id]
	var event := _event_effect(good, price)
	event.effects.append(SpecEffect.make("grant_gold", "add", 777.0))
	var v := _validator()
	check_eq(v.validate(good), [], "event global/dish price and gold effects supported")
	var rules := ShopRules.new(good)
	var before_price := rules.raw_price(good.dishes[0].id)
	var other_price := rules.raw_price(good.dishes[1].id)
	var gold := rules.gold
	rules.trigger_event(event)
	check_eq(rules.raw_price(good.dishes[0].id), before_price * 3.0, "declared event changes actual dish price")
	check_eq(rules.raw_price(good.dishes[1].id), other_price, "dish selector limits actual effect")
	check_eq(rules.gold, gold + 777.0, "event one-shot actually grants gold")

func test_staff_effect_selectors_use_canonical_runtime_worker_ids() -> void:
	var v := _validator()
	for target in [PANCAKE.staff.kinds[0].id, "1", "staff:01", "staff:+1", "staff:0", "staff:-1", "staff:1.0", "staff:"]:
		var bad: SpecShop = PANCAKE.duplicate(true)
		_event_effect(bad, SpecEffect.make("walk", "mul", 3.0, target))
		_bad(bad, "events[%d].effects[0].target" % (bad.events.size() - 1))
		_reject_before_io(bad)
	for target in ["", "staff:1"]:
		var good: SpecShop = PANCAKE.duplicate(true)
		var event := _event_effect(good, SpecEffect.make("walk", "mul", 3.0, target))
		check_eq(v.validate(good), [], "supported staff selector " + target)
		var rules := ShopRules.new(good)
		var before := rules.walk_speed(rules.workers[0])
		rules.trigger_event(event)
		check_eq(rules.walk_speed(rules.workers[0]), before * 3.0, "supported selector changes real walk speed")
	var tea: SpecShop = TEA.duplicate(true)
	var event := _event_effect(tea, SpecEffect.make("work", "mul", 2.0, "front"))
	check_eq(v.validate(tea), [], "zone selector supported")
	var rules := ShopRules.new(tea)
	var before := rules.skill(rules.workers[0])
	rules.trigger_event(event)
	check_eq(rules.skill(rules.workers[0]), before * 2.0, "zone effect changes actual worker skill")

func test_effect_context_restrictions_cover_every_upgrade_attachment() -> void:
	var bad: SpecShop = PANCAKE.duplicate(true)
	var material_station := -1
	for i in bad.stations.size():
		if not bad.stations[i].materials.is_empty():
			material_station = i
			break
	check(material_station >= 0, "fixture contains material upgrade context")
	var tracks := [
		[bad.stations[1].tracks[0], "stations[1].tracks[0]"],
		[bad.stations[material_station].materials[0].track, "stations[%d].materials[0].track" % material_station],
		[bad.staff.tracks[0], "staff.tracks[0]"],
		[bad.flyer.track, "flyer.track"],
	]
	for pair in tracks:
		var track: SpecUpgradeTrack = pair[0]
		var path: String = pair[1]
		track.base_effects.append(SpecEffect.make("grant_gold", "add", 777))
		var level := SpecUpgradeLevel.new()
		level.effects.append(SpecEffect.make("unlock_recipe", "add", 1, bad.dishes[0].id))
		track.levels.append(level)
		_bad(bad, path + ".base_effects[%d].kind" % (track.base_effects.size() - 1))
		_bad(bad, path + ".levels[%d].effects[0].kind" % (track.levels.size() - 1))
	_reject_before_io(bad)
	for kind in ["open_flavor", "seats", "unlock_recipe", "shop_news"]:
		bad = PANCAKE.duplicate(true)
		_event_effect(bad, SpecEffect.make(kind, "add", 1))
		_bad(bad, "events[%d].effects[0].kind" % (bad.events.size() - 1))

func test_valid_event_choice_and_implicit_staff_track_target_are_effective() -> void:
	var v := _validator()
	var good: SpecShop = PANCAKE.duplicate(true)
	var event := _event_effect(good, SpecEffect.make("grant_gold", "add", 200))
	event.choices = [{"label": "Accept", "cost": 5}]
	event.effects.append(SpecEffect.make("walk", "mul", 2.0, "staff:1"))
	check_eq(v.validate(good), [], "choice event with one-shot and ongoing effect is valid")
	var profile := Profile.new(_path("valid-choice-profile"))
	var session := Session.new(profile, ShopSave.new(good, _path("valid-choice-shop")))
	check_eq(session.start(), OK, "configured choice event passes actual Session startup")
	var rules: ShopRules = session.rules
	if rules == null: return
	var before_gold := rules.gold
	var before_walk := rules.walk_speed(rules.workers[0])
	rules.trigger_event(event)
	check_eq(rules.gold, before_gold, "choice defers one-shot until accepted")
	check_eq(rules.walk_speed(rules.workers[0]), before_walk, "choice defers ongoing modifier until accepted")
	check_eq(rules.answer_event(0), "", "actual configured choice accepts")
	check_eq(rules.gold, before_gold - 5 + 200, "choice cost and grant are both effective")
	check_eq(rules.walk_speed(rules.workers[0]), before_walk * 2.0, "choice applies ongoing staff modifier")
	var tea: SpecShop = TEA.duplicate(true)
	var track: SpecUpgradeTrack = null
	for candidate in tea.staff.tracks:
		if candidate.id == "front": track = candidate
	check(track != null, "fixture has zoned staff upgrade")
	if track == null: return
	track.base_effects.append(SpecEffect.make("work", "mul", 2.0))
	check_eq(v.validate(tea), [], "staff track inherits its actual zone target")
	var baseline := ShopRules.new(TEA)
	var modified := ShopRules.new(tea)
	check_eq(modified.skill(modified.workers[0]), baseline.skill(baseline.workers[0]) * 2.0, "implicit staff track zone changes actual skill")

func test_later_flavor_group_does_not_assume_a_preopened_stage_was_purchased() -> void:
	var bad: SpecShop = PANCAKE.duplicate(true)
	bad.station(bad.goals.opening_station).starts_unlocked = true
	var later_station: String = bad.stages[1].stations[0]
	for dish in bad.dishes:
		if dish.flavor_station.is_empty() or dish.topping_count <= 0: continue
		for step in dish.steps:
			if step.station != later_station and step.station not in bad.stages[0].stations: bad.stages[0].stations.append(step.station)
	for station in bad.stations:
		for material in station.materials:
			material.box_cost = 0
			material.track.requires_level = 1
	bad.stages[1].flavor_group = "later_flavors"
	bad.stages[1].flavor_fallback = ""
	bad.stages[1].order_weights["later_flavors"] = 1
	_bad(bad, "stages[1].flavor_fallback")
	_reject_before_io(bad)

func test_staff_regions_and_stage_slot_keys_reject_ignored_declarations_before_io() -> void:
	var bad: SpecShop = TEA.duplicate(true)
	bad.stages[0].staff_slots["front"] = 99
	_bad(bad, "stages[0].staff_slots.front")
	_reject_before_io(bad)
	bad = TEA.duplicate(true)
	bad.staff.zones.append("bar")
	bad.stages[0].staff_slots["bar"] = 99
	_bad(bad, "staff.zones[2]")
	_bad(bad, "stages[0].staff_slots.bar")
	_reject_before_io(bad)
	bad = TEA.duplicate(true)
	bad.stages[0].staff_slots[""] = 99
	_bad(bad, "stages[0].staff_slots.")
	_reject_before_io(bad)
	bad = TEA.duplicate(true)
	bad.staff.zones = ["front"]
	_bad(bad, "staff.zones")
	_reject_before_io(bad)
	bad = PANCAKE.duplicate(true)
	bad.stages[0].staff_slots["kitchen"] = 99
	_bad(bad, "stages[0].staff_slots.kitchen")
	_reject_before_io(bad)

func test_unzoned_front_base_capacity_controls_actual_counter_placement() -> void:
	for capacity in [1, 2]:
		var shop: SpecShop = PANCAKE.duplicate(true)
		shop.staff.can_drag = true
		shop.staff.front_base_slots = capacity
		shop.stages[0].staff_slots[""] = 2
		var profile := Profile.new(_path("counter-capacity-profile"))
		var session := Session.new(profile, ShopSave.new(shop, _path("counter-capacity-shop")))
		check_eq(session.start(), OK, "effective unzoned counter capacity passes Session schema gate")
		var rules: ShopRules = session.rules
		if rules == null: continue
		check_eq(rules.unlock(shop.goals.opening_station), "", "open configured unzoned shop")
		rules.gold = 10000
		check_eq(rules.hire(), "", "hire a second worker within unified capacity")
		check_eq(rules.staff_slots(), 2, "unified stage capacity remains independent of counter posts")
		check_eq(rules.workers.size(), 2, "two workers available for real placement")
		check_eq(rules.place_worker(rules.workers[0].id, rules.counter_id), "", "first counter placement succeeds")
		var second := rules.place_worker(rules.workers[1].id, rules.counter_id)
		check(second.is_empty() if capacity == 2 else not second.is_empty(), "second placement follows configured counter capacity")
		var owners := rules.workers.filter(func(worker): return worker.post == rules.counter_id)
		check_eq(owners.size(), capacity, "actual counter occupants match the configured front capacity")

func test_supported_staff_capacity_sources_change_real_session_limits() -> void:
	var single: SpecShop = PANCAKE.duplicate(true)
	single.stages[0].staff_slots[""] = 6
	var profile := Profile.new(_path("unified-capacity-profile"))
	var session := Session.new(profile, ShopSave.new(single, _path("unified-capacity-shop")))
	check_eq(session.start(), OK, "unified capacity config starts")
	if session.rules == null: return
	check_eq(session.rules.unlock(single.goals.opening_station), "", "open actual unified shop")
	check_eq(session.rules.staff_slots(), 6, "unzoned stage empty-key capacity changes actual limit")
	var zoned: SpecShop = TEA.duplicate(true)
	zoned.stages[0].staff_slots["kitchen"] = 4
	zoned.staff.front_base_slots = 3
	var event := _event_effect(zoned, SpecEffect.make("staff_slot", "add", 2, "front"))
	profile = Profile.new(_path("zoned-capacity-profile"))
	check_eq(profile.select_shop(zoned.id), OK, "select real zoned shop")
	session = Session.new(profile, ShopSave.new(zoned, _path("zoned-capacity-shop")))
	check_eq(session.start(), OK, "supported zoned capacity config starts")
	if session.rules == null: return
	check_eq(session.rules.kitchen_slots(), 4, "kitchen stage capacity changes actual limit")
	check_eq(session.rules.front_slots(), 3, "front base capacity changes actual limit")
	check_eq(session.rules.staff_slots(), 7, "total capacity uses implemented sources")
	session.rules.trigger_event(event)
	check_eq(session.rules.front_slots(), 5, "configured front modifier changes actual limit")
	check_eq(session.rules.staff_slots(), 9, "total capacity includes front modifier")
