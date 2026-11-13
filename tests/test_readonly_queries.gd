extends "res://tests/test_case.gd"
const LegacyRules := preload("res://tests/fixtures/legacy_shops/reference_rules.gd")

const TEA: SpecShop = preload("res://tests/fixtures/legacy_shops/current/tea/shop.tres")
const PANCAKE: SpecShop = preload("res://tests/fixtures/legacy_shops/current/pancake/shop.tres")
const NOODLE: SpecShop = preload("res://tests/fixtures/noodle/shop.tres")

func ready_rules(definition: SpecShop) -> ShopRules:
	var rules := LegacyRules.new(definition, 9)
	rules.gold = 1e8
	rules.stage_index = definition.stages.size() - 1
	for station in definition.stations: rules.unlocked[station.id] = true
	for key in rules.boxes: rules.boxes[key] = true
	return rules

func test_preview_never_borrows_live_state() -> void:
	var rules := ready_rules(TEA)
	var bytes := var_to_bytes(rules.to_dict())
	var levels := rules.levels
	var mods := rules.mods
	var entries := rules.mods.entries
	var entry: Dictionary = entries[0]
	var entry_aliases := entries.duplicate()
	var dish_aliases: Array = []
	for modifier in entries: dish_aliases.append(modifier.dishes)
	var bus := rules.events
	var history := bus.log
	var rng := rules.rng
	var event_rng := rules.event_rng
	var workers := rules.workers
	var worker: Dictionary = workers[0]
	var roster := rules.roster
	var original_level := rules.level("boil")
	var result: Variant = rules.preview("boil", func(query: RefCounted = null) -> int:
		check(var_to_bytes(rules.to_dict()) == bytes, "Live serialized bytes stay unchanged inside evaluator")
		check_eq(rules.level("boil"), original_level, "Reentrant live level stays actual")
		check(is_same(rules.levels, levels), "Live level dictionary identity")
		check(is_same(rules.mods, mods), "Live modifiers identity")
		check(is_same(rules.mods.entries, entries), "Live entries array identity inside evaluator")
		check(is_same(rules.mods.entries[0], entry), "Live first entry identity inside evaluator")
		for index in entries.size():
			check(is_same(rules.mods.entries[index], entry_aliases[index]), "Live modifier dictionary identity inside evaluator")
			check(is_same(rules.mods.entries[index].dishes, dish_aliases[index]), "Live nested dish selector identity inside evaluator")
		check(is_same(rules.events, bus) and is_same(bus.log, history), "Live bus and history identities")
		check(is_same(rules.rng, rng) and is_same(rules.event_rng, event_rng), "Live RNG identities")
		check(is_same(rules.workers, workers) and is_same(rules.roster, roster), "Live worker arrays")
		check(is_same(rules.workers[0], worker) and is_same(rules.roster[0], worker), "Worker roster alias")
		if query != null: check_eq(query.level("boil"), original_level + 1, "Explicit context sees next level")
		return query.pot_batch("boil") if query != null else rules.pot_batch("boil"))
	check(result != null, "Evaluator returned value")
	check(var_to_bytes(rules.to_dict()) == bytes, "Live bytes after preview")
	check(is_same(rules.mods.entries, entries), "Live entries array identity after preview")
	for index in entries.size():
		check(is_same(rules.mods.entries[index], entry_aliases[index]), "Live modifier dictionary identity after preview")
		check(is_same(rules.mods.entries[index].dishes, dish_aliases[index]), "Live nested selector identity after preview")

func test_caps_keep_live_entries_identity() -> void:
	var rules := ready_rules(TEA)
	var entries := rules.mods.entries
	var bytes := var_to_bytes(rules.to_dict())
	var limits := rules.worker_stat_limits(rules.workers[0])
	check(limits.walk >= rules.walk_speed(rules.workers[0]), "Cap preserves current floor")
	check(is_same(rules.mods.entries, entries), "Caps retain live entries array identity")
	check(var_to_bytes(rules.to_dict()) == bytes, "Caps leave live bytes unchanged")

func _numbers(query: RefCounted, definition: SpecShop, workers: Array) -> Dictionary:
	var result := {"flyer_customers": query.flyer_customers(), "flyer_cooldown": query.flyer_cooldown()}
	for dish in definition.dishes:
		result["raw/" + dish.id] = query.raw_price(dish.id)
		result["price/" + dish.id] = query.dish_price(dish.id)
		result["quote/" + dish.id] = query.dish_quote(dish.id)
		var options: Array = []
		for option in definition.order_options: options.append(option.id)
		result["order/" + dish.id] = query.order_price_single({"kind": dish.id, "addon": not definition.fulfillment.addon_dish.is_empty(), "options": options})
	for station in definition.stations:
		result["timing/" + station.id] = query.station_timing(station.id)
		result["speed/" + station.id] = query.speed(station.id)
		result["duration/" + station.id] = query.duration_mult(station.id)
		result["batch/" + station.id] = query.pot_batch(station.id)
		result["slots/" + station.id] = query.process_slots(station.id)
		result["machine/" + station.id] = query.machine_seconds(station.id)
		result["manual/" + station.id] = query.manual_operation_seconds(station.id, 2.5, workers[0])
		result["fixed/" + station.id] = query.manual_operation_seconds(station.id, 2.5, workers[0], true)
	for worker in workers: result["worker/%d" % worker.id] = query.effective_worker_stats(worker)
	return result

func _set_conditions(rules: ShopRules) -> void:
	rules.tune.price = 1.125
	rules.tune.walk = 1.25
	rules.tune.work = 0.75
	for station in rules.shop.stations: rules.tune[station.id] = 1.375
	rules.mods.add("event", "permanent", "price", "mul", 1.125)
	rules.mods.add("event", "timed", "price", "add", 0.125, "", [], "", 45.0)
	rules.mods.add("event", "individual", "work", "mul", 1.375, "staff:%d" % rules.workers[0].id)

func test_previews_match_actual_upgrades_for_all_three_shops() -> void:
	for definition in [TEA, PANCAKE, NOODLE]:
		var template := ready_rules(definition)
		var changed := 0
		var compared := 0
		for key in template.levels:
			var virtual := ready_rules(definition)
			var actual := ready_rules(definition)
			_set_conditions(virtual)
			_set_conditions(actual)
			var track := actual.track_of(key)
			if track == null: continue
			if key.contains("/") and not key.begins_with("staff/"):
				var parent := String(key).get_slice("/", 0)
				while actual.level(parent) < track.requires_level:
					check_eq(actual.upgrade(parent), "", "Prepare actual required station level")
					check_eq(virtual.upgrade(parent), "", "Prepare virtual required station level")
			while actual.upgrade_cost(key) >= 0:
				var before := _numbers(actual, definition, actual.workers)
				var bytes := var_to_bytes(virtual.to_dict())
				var forecast: Dictionary = virtual.preview(key, func(query: RefCounted) -> Dictionary: return _numbers(query, definition, virtual.workers))
				check_eq(actual.upgrade(key), "", "Independent real upgrade succeeds: " + key)
				var after := _numbers(actual, definition, actual.workers)
				check_eq(forecast, after, "%s/%s actual upgrade equals forecast" % [definition.id, key])
				check(var_to_bytes(virtual.to_dict()) == bytes, "Preview leaves all live state unchanged")
				if before != after: changed += 1
				compared += 1
				check_eq(virtual.upgrade(key), "", "Advance virtual source with real command")
		check(compared >= 5, definition.id + " has multiple real progression comparisons")
		check(changed >= 5, definition.id + " has meaningful numeric upgrade changes")
		print("  %s: %d real upgrade comparisons, %d numeric changes" % [definition.id, compared, changed])

func test_nested_previews_and_retained_snapshots_are_isolated() -> void:
	var rules := ready_rules(TEA)
	rules.mods.add("event", "nested", "price", "mul", 1.125, "", ["lemonade"], "", 30.0)
	var context := rules.query_context()
	var snapshot := _numbers(context, TEA, rules.workers)
	var parent_level: int = context.level("lemonade")
	var returned: RefCounted = context.preview("lemonade", func(parent: RefCounted) -> RefCounted:
		check_eq(parent.level("lemonade"), parent_level + 1, "Parent virtual level")
		var child: RefCounted = parent.preview("lemonade", func(query: RefCounted) -> RefCounted: return query)
		check_eq(child.level("lemonade"), parent_level + 2, "Child derives from parent virtual level")
		check_eq(parent.level("lemonade"), parent_level + 1, "Child leaves parent level unchanged")
		return parent)
	var retained_price: float = returned.dish_price("lemonade")
	check_eq(context.level("lemonade"), parent_level, "Root snapshot level unchanged")
	check_eq(rules.upgrade("lemonade"), "", "Edit live level after retaining context")
	rules.tune.price = 3.0
	rules.mods.entries[-1].value = 8.0
	rules.mods.entries[-1].dishes.append("black_tea")
	rules.mods.tick(31.0)
	check_eq(_numbers(context, TEA, rules.workers), snapshot, "Retained snapshot ignores live levels tuning and nested modifiers")
	check_eq(returned.dish_price("lemonade"), retained_price, "Retained preview ignores later live edits")
	var child: RefCounted = context.query_context({"lemonade": parent_level + 2})
	check_eq(child.level("lemonade"), parent_level + 2, "Override derives from retained source")
	check_eq(child.tuned("price"), 1.0, "Override retains parent tuning")
	child.mods.entries[0].value = 900.0
	child.levels.lemonade = 77
	child.tune.price = 0.25
	check_eq(_numbers(context, TEA, rules.workers), snapshot, "Child mutable data never aliases parent")
	var quote: Dictionary = context.dish_quote("lemonade")
	quote.calculated = -1.0
	var timing: Dictionary = context.station_timing("lemonade")
	timing.seconds = -1.0
	var stats: Dictionary = context.effective_worker_stats(rules.workers[0])
	stats.walk = -1.0
	check_eq(_numbers(context, TEA, rules.workers), snapshot, "Returned dictionaries are fresh")

func test_missing_max_repeated_and_null_evaluators() -> void:
	var rules := ready_rules(TEA)
	var count := [0]
	var bytes := var_to_bytes(rules.to_dict())
	var result: Variant = rules.preview("missing", func(query: RefCounted) -> Variant:
		count[0] += 1
		check_eq(query.level("boil"), rules.level("boil"), "Missing track keeps level")
		return null)
	check_eq(result, null, "Null evaluator result preserved")
	check_eq(count[0], 1, "Missing track evaluates exactly once")
	for index in 4:
		rules.preview("boil", func(query: RefCounted) -> Variant:
			check_eq(query.level("boil"), 2, "Repeated preview keeps same next level")
			return null)
	check(var_to_bytes(rules.to_dict()) == bytes, "Repeated null calls do not change live bytes")
	while rules.upgrade_cost("boil") >= 0: check_eq(rules.upgrade("boil"), "", "Reach real maximum")
	var maximum := rules.level("boil")
	var batch := rules.pot_batch("boil")
	rules.preview("boil", func(query: RefCounted) -> Variant:
		check_eq(query.level("boil"), maximum + 1, "Maximum preview preserves historical level offset")
		check_eq(query.pot_batch("boil"), batch, "Maximum preview folds existing final effects only")
		return null)
	check_eq(rules.level("boil"), maximum, "Maximum preview leaves live level actual")
	check_eq(rules.query_context({"missing": 90}).level("missing"), 1, "Missing override ignored")

func test_event_precedence_and_newly_effect_bearing_source() -> void:
	for empty_base in [false, true]:
		var definition: SpecShop = TEA.duplicate(true)
		var track := definition.station("boil").track("level")
		if empty_base: track.base_effects.clear()
		track.levels[0].effects.assign([SpecEffect.make("batch", "set", 4.0)])
		var virtual := ready_rules(definition)
		var actual := ready_rules(definition)
		for rules in [virtual, actual]:
			rules.mods.add("event", "permanent", "batch", "set", 7.0, "boil")
			rules.mods.add("event", "timed", "batch", "set", 9.0, "boil", [], "", 60.0)
			rules.mods.add("event", "multiply", "batch", "mul", 2.0, "boil")
			rules.mods.add("event", "add", "batch", "add", 1.0, "boil")
		var before := virtual.pot_batch("boil")
		var preview: int = virtual.preview("boil", func(query: RefCounted) -> int: return query.pot_batch("boil"))
		check_eq(actual.upgrade("boil"), "", "Real upgrade for source placement")
		check_eq(preview, actual.pot_batch("boil"), "Virtual and actual source placement agree")
		check_eq(preview, 9 if empty_base else 19, "Preserve no-old-entry append and existing-entry precedence")
		check_eq(virtual.pot_batch("boil"), before, "Live event stack unchanged")

func test_one_shots_are_not_replayed_and_snapshot_has_no_simulation() -> void:
	var definition: SpecShop = TEA.duplicate(true)
	var track := definition.station("boil").track("level")
	for kind in ["grant_gold", "customer_wave", "unlock_staff_kind", "unlock_recipe", "shop_news", "open_flavor"]:
		track.levels[0].effects.append(SpecEffect.make(kind, "add", 99.0, "test_target"))
	var rules := ready_rules(definition)
	var before := var_to_bytes(rules.to_dict())
	var context: RefCounted = rules.preview("boil", func(query: RefCounted) -> RefCounted: return query)
	check(var_to_bytes(rules.to_dict()) == before, "No gold stock unlock events or commands change")
	for command in ["step", "run", "upgrade", "unlock", "send_flyers", "load_dict", "to_dict"]:
		check(not context.has_method(command), "Context exposes no simulation command: " + command)
	for property in context.get_property_list():
		if property.name in ["script", "shop", "levels", "mods", "tune", "RefCounted"]: continue
		var value: Variant = context.get(property.name)
		check(not value is ShopRules, "Context retains no live rules reference")

func test_worker_caps_match_real_full_cultivation_and_keep_floor() -> void:
	for definition in [TEA, PANCAKE, NOODLE]:
		var rules := ready_rules(definition)
		var actual := ready_rules(definition)
		_set_conditions(rules)
		_set_conditions(actual)
		for key in actual.levels:
			if not String(key).begins_with("staff/"): continue
			while actual.upgrade_cost(key) >= 0: check_eq(actual.upgrade(key), "", "Real maximum staff progression")
		var worker: Dictionary = rules.workers[0].duplicate(true)
		var posts: Array = ["", rules.counter_id]
		posts.append_array(rules.seatables)
		for post in posts:
			worker.post = post
			for courier in [false, true]:
				worker.courier = courier
				var before := var_to_bytes(rules.to_dict())
				var worker_before := worker.duplicate(true)
				var entries := rules.mods.entries
				var current := rules.effective_worker_stats(worker)
				var expected := actual.effective_worker_stats(worker)
				for name in current: expected[name] = maxf(float(current[name]), float(expected[name]))
				var limits := rules.worker_stat_limits(worker)
				for name in expected: check(is_equal_approx(float(limits[name]), float(expected[name])), "Regional seated mobile and courier caps equal real progression: " + name)
				check_eq(worker, worker_before, "Worker dictionary is read only")
				check(is_same(rules.mods.entries, entries), "Worker cap keeps array identity")
				check(var_to_bytes(rules.to_dict()) == before, "Worker cap preserves all live bytes")
		for key in rules.levels:
			if not String(key).begins_with("staff/"): continue
			while rules.upgrade_cost(key) >= 0: check_eq(rules.upgrade(key), "", "Reach cap before stronger current stats")
		worker.stats.walk = 1e6
		worker.stats.work = 1e6
		worker.stats.carry = 1000
		var limits := rules.worker_stat_limits(worker)
		var current := rules.effective_worker_stats(worker)
		for name in current: check(is_equal_approx(float(limits[name]), float(current[name])), "Maximum cap retains stronger effective current stats: " + name)
	var no_track: SpecShop = PANCAKE.duplicate(true)
	no_track.staff.tracks.clear()
	var rules := ready_rules(no_track)
	check_eq(rules.worker_stat_limits(rules.workers[0]), rules.effective_worker_stats(rules.workers[0]), "Missing staff track uses actual current stats")

func test_fractional_partial_prices_flyer_slots_and_fixed_timing_change() -> void:
	var tea := ready_rules(TEA)
	check_eq(tea.preview("supply/tea_leaf", func(query: RefCounted) -> float: return query.dish_price("plain_milk_tea")), 31.5, "Fractional material preview")
	var pancake := ready_rules(PANCAKE)
	var expected := ready_rules(PANCAKE)
	check_eq(expected.upgrade("topping"), "", "Real partial price upgrade")
	check_eq(pancake.preview("topping", func(query: RefCounted) -> Dictionary: return query.dish_quote("ham")), expected.dish_quote("ham"), "Partial price and integer receipt preview")
	check(expected.dish_price("ham") > pancake.dish_price("ham"), "Partial price upgrade actually changes amount")
	for pair in [[tea, "boil"], [tea, "mix"], [tea, "seal"], [pancake, "fryer"], [pancake, "rear_equipment"]]:
		var rules: ShopRules = pair[0]
		var id: String = pair[1]
		var clone := ready_rules(rules.shop)
		check_eq(clone.upgrade(id), "", "Real timing or slot upgrade")
		check_eq(rules.preview(id, func(query: RefCounted) -> Dictionary: return query.station_timing(id)), clone.station_timing(id), "Manual and automatic timing match real upgrade")
		if id == "fryer":
			check_eq(clone.manual_operation_seconds(id, 3.0), rules.manual_operation_seconds(id, 3.0), "Pot manual pickup ignores cooking upgrade")
		check_eq(clone.manual_operation_seconds(id, 3.0, {}, true), rules.manual_operation_seconds(id, 3.0, {}, true), "Fixed timing ignores machine upgrade")
	var flyer_before := tea.flyer_customers()
	check_eq(tea.upgrade("flyer"), "", "Real flyer upgrade")
	check(tea.flyer_customers() > flyer_before, "Flyer upgrade really changes customer count")

func test_cap_floor_when_future_cultivation_reduces_a_stat() -> void:
	var definition: SpecShop = PANCAKE.duplicate(true)
	var track := definition.staff.tracks[0]
	track.base_effects.clear()
	track.levels.resize(1)
	track.levels[0].effects.assign([SpecEffect.make("walk", "mul", 0.1), SpecEffect.make("work", "mul", 0.1), SpecEffect.make("carry", "add", -0.5)])
	var rules := ready_rules(definition)
	var actual := ready_rules(definition)
	var worker: Dictionary = rules.workers[0]
	var current := rules.effective_worker_stats(worker)
	check_eq(actual.upgrade("staff/"), "", "Real cultivation reducing stats")
	check(actual.walk_speed(worker) < current.walk and actual.skill(worker) < current.work and actual.carry(worker) < current.carry, "Fixture really lowers each future stat")
	var limits := rules.worker_stat_limits(worker)
	for name in current: check_eq(float(limits[name]), float(current[name]), "Current floor survives lower future stat: " + name)
