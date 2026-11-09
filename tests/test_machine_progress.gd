extends "res://tests/test_case.gd"

const MODULE := "res://game/rules/machine_progress.gd"
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
const PANCAKE: SpecShop = preload("res://content/shops/pancake/shop.tres")

class ObservedRules extends ShopRules:
	var observations := []
	func _auto_output(id: String) -> String:
		var s: Dictionary = stations[id]
		observations.append(["output", id, s.input.duplicate(), s.processing, s.processing_item, s.phase, s.progress, s.remaining])
		return "tea"
	func machine_seconds(id: String) -> float:
		var s: Dictionary = stations[id]
		observations.append(["seconds", id, s.input.duplicate(), s.processing, s.processing_item, s.phase, s.progress, s.remaining])
		return 2.0

class OrderedSingleRules extends ShopRules:
	var observations := []
	func _arrivals_single() -> void:
		observations.append("arrivals")
	func _customers_single() -> void:
		observations.append(["customers", stations[pots[0]].phase])
	func _staff_tick(_worker: Dictionary) -> void:
		observations.append(["worker", stations[pots[0]].phase, stations[pots[0]].remaining])

func _kernel() -> Variant:
	if not ResourceLoader.exists(MODULE):
		check(false, "MachineProgress kernel must exist")
		return null
	return load(MODULE)

func _station() -> Dictionary:
	return {"input": {"raw": 0}, "output": {"tea": 0}, "phase": "working", "progress": 0.5,
		"remaining": 0.5, "duration": 1.0, "processing": 2, "processing_item": "tea",
		"work_reserved": true, "extra": [9]}

func test_completion_consumes_next_input_before_begin_timing() -> void:
	var kernel = _kernel()
	if kernel == null: return
	var station := {"input": {"raw": 3}, "output": {"tea": 1}, "phase": "working", "progress": 0.5,
		"remaining": 0.05, "duration": 1.0, "processing": 2, "processing_item": "tea", "work_reserved": true, "extra": 9}
	check_eq(kernel.advance_handoff(station, "combine", 0.1, []), "raw", "return first consumed input")
	check_eq(station.output, {"tea": 3}, "release previous output")
	check_eq([station.processing, station.input.raw, station.processing_item, station.phase, station.progress, station.remaining], [3, 0, "", "ready", 1.0, 0.0], "selection retains completed timing and phase")
	station.processing_item = "tea"
	kernel.begin_automatic(station, 2.0)
	check_eq([station.duration, station.remaining, station.progress, station.phase, station.extra, station.work_reserved], [2.0, 2.0, 0.0, "working", 9, true], "begin only timing after Rules binds output")

func test_stir_uses_first_crossed_point_in_unsorted_order() -> void:
	var kernel = _kernel()
	if kernel == null: return
	var s := _station()
	s.progress = 0.9
	s.duration = 10.0
	check(kernel.pause_for_stir(s, 0.1, [0.8, 0.2]), "crossed point pauses")
	check_eq([s.progress, s.remaining, s.phase], [0.8, 10.0 * (1.0 - 0.8), "stir"], "first listed crossed point wins without sorting")

func test_stir_exact_crossing_and_equal_before_are_distinct() -> void:
	var kernel = _kernel()
	if kernel == null: return
	var s := _station()
	check(kernel.pause_for_stir(s, 0.4, [0.5]), "exact new crossing pauses")
	check_eq([s.progress, s.remaining, s.phase], [0.5, 0.5, "stir"], "exact point retained")
	s.phase = "heating"
	s.progress = 0.8
	var saved := s.duplicate(true)
	check(not kernel.pause_for_stir(s, 0.5, [0.5, 0.9]), "equal previous point does not cross again")
	check_eq(s, saved, "no crossing is mutation free")
	check(not kernel.pause_for_stir(s, 0.1, []), "empty points do nothing")
	check_eq(s, saved, "empty points preserve fields")

func test_stir_overshoot_precedes_completion() -> void:
	var kernel = _kernel()
	if kernel == null: return
	var s := _station()
	s.phase = "heating"
	s.progress = 0.2
	s.remaining = 0.8
	check_eq(kernel.advance_handoff(s, "batch_pot", 2.0, [0.6]), "", "stir never starts automatic work")
	check_eq([s.phase, s.progress, s.remaining, s.processing, s.output], ["stir", 0.6, 0.4, 2, {"tea": 0}], "overshoot stops at stir before completion")

func test_pot_completion_retains_batch_and_has_no_output_effect() -> void:
	var kernel = _kernel()
	if kernel == null: return
	var s := _station()
	s.remaining = 0.05
	check_eq(kernel.advance_handoff(s, "batch_pot", 0.1, []), "", "pot awaits manual take")
	check_eq([s.phase, s.progress, s.remaining, s.processing, s.processing_item, s.output], ["awaiting_take", 1.0, 0.0, 2, "tea", {"tea": 0}], "pot completion preserves processing and output")

func test_awaiting_take_and_stir_block_progress() -> void:
	var kernel = _kernel()
	if kernel == null: return
	for phase in ["awaiting_take", "stir"]:
		for block in ["batch_pot", "combine"]:
			var s := _station()
			s.phase = phase
			s.input.raw = 4
			var saved := s.duplicate(true)
			check_eq(kernel.advance_handoff(s, block, 3.0, [0.6]), "", "blocked batch does not start")
			check_eq(s, saved, "blocked positive processing remains unchanged")

func test_handoff_clamps_and_uses_completion_epsilon() -> void:
	var kernel = _kernel()
	if kernel == null: return
	for remaining in [0.000001, 0.0000011]:
		var s := _station()
		s.remaining = remaining
		kernel.advance_handoff(s, "combine", 0.0, [])
		if remaining == 0.000001:
			check_eq([s.phase, s.processing, s.progress, s.remaining, s.output], ["ready", 0, 1.0, 0.000001, {"tea": 2}], "epsilon equality completes without zeroing positive remainder")
		else:
			check_eq([s.phase, s.processing, s.progress, s.remaining, s.output], ["working", 2, 1.0 - 0.0000011, 0.0000011, {"tea": 0}], "just outside epsilon remains processing")
	var s := _station()
	kernel.advance_handoff(s, "combine", 3.0, [])
	check_eq([s.remaining, s.progress, s.phase], [0.0, 1.0, "ready"], "overshoot clamps handoff remaining")

func test_running_recomputes_progress_without_start_or_queries() -> void:
	var kernel = _kernel()
	if kernel == null: return
	var s := _station()
	s.input.raw = 3
	check_eq(kernel.advance_handoff(s, "combine", 0.25, []), "", "running cannot consume next input")
	check_eq([s.remaining, s.progress, s.processing, s.input.raw, s.phase], [0.25, 0.75, 2, 3, "working"], "ongoing elapsed time only")

func test_pickup_consumes_one_and_combine_consumes_whole_first_positive() -> void:
	var kernel = _kernel()
	if kernel == null: return
	for block in ["pickup", "combine"]:
		var s := _station()
		s.processing = 0
		s.input = {"zero": 0, "negative": -1, "z_first": 3, "a_later": 5}
		check_eq(kernel.advance_handoff(s, block, 0.1, []), "z_first", "insertion order chooses first positive, never alphabetical")
		var amount := 1 if block == "pickup" else 3
		check_eq([s.processing, s.input, s.phase, s.progress, s.remaining, s.processing_item], [amount, {"zero": 0, "negative": -1, "z_first": 3 - amount, "a_later": 5}, "working", 0.5, 0.5, "tea"], "selection alone preserves historical fields and output binding")

func test_empty_idle_and_stock_ready_retention() -> void:
	var kernel = _kernel()
	if kernel == null: return
	var s := _station()
	s.processing = 0
	s.remaining = 7.0
	check_eq(kernel.advance_handoff(s, "combine", 0.1, []), "", "no input has no start")
	check_eq([s.phase, s.progress, s.remaining, s.processing_item], ["idle", 0.0, 7.0, "tea"], "empty stock resets only phase and progress")
	s.phase = "ready"
	s.progress = 0.7
	s.output.tea = 2
	var saved := s.duplicate(true)
	kernel.advance_handoff(s, "combine", 0.1, [])
	check_eq(s, saved, "stock retains existing ready phase and progress")
	s.phase = "idle"
	saved = s.duplicate(true)
	kernel.advance_handoff(s, "combine", 0.1, [])
	check_eq(s, saved, "stock does not normalize historical idle")

func test_empty_batch_pot_never_consumes_input_or_resets_history() -> void:
	var kernel = _kernel()
	if kernel == null: return
	var s := _station()
	s.processing = 0
	s.input.raw = 3
	var saved := s.duplicate(true)
	check_eq(kernel.advance_handoff(s, "batch_pot", 2.0, []), "", "pot input stays manual")
	check_eq(s, saved, "empty pot retains all history")

func test_aliases_and_unrelated_fields_survive_both_start_phases() -> void:
	var kernel = _kernel()
	if kernel == null: return
	var s := _station()
	s.remaining = 0.05
	s.input.raw = 3
	s.reserved_in = 7
	s.reserved_out = {"tea": 1}
	var input: Dictionary = s.input
	var output: Dictionary = s.output
	var reserved: Dictionary = s.reserved_out
	var history: Array = s.extra
	kernel.advance_handoff(s, "combine", 0.1, [])
	s.processing_item = "tea"
	kernel.begin_automatic(s, 2.0)
	check(is_same(input, s.input) and is_same(output, s.output) and is_same(reserved, s.reserved_out) and is_same(history, s.extra), "never replace nested containers")
	check_eq([input, output, reserved, history, s.reserved_in, s.work_reserved], [{"raw": 0}, {"tea": 2}, {"tea": 1}, [9], 7, true], "aliases observe only intended inventory effects")

func test_begin_automatic_has_no_new_duration_policy() -> void:
	var kernel = _kernel()
	if kernel == null: return
	var s := _station()
	var expected := s.duplicate(true)
	expected.duration = -2.0
	expected.remaining = -2.0
	expected.progress = 0.0
	expected.phase = "working"
	kernel.begin_automatic(s, -2.0)
	check_eq(s, expected, "begin stores supplied duration verbatim without eligibility or clamping")

func test_single_threshold_no_epsilon_clamp_progress_or_stock_effect() -> void:
	var kernel = _kernel()
	if kernel == null: return
	for remaining in [0.1, 0.05, 0.1000001]:
		var s := _station()
		s.phase = "cook"
		s.remaining = remaining
		s.stock = 4
		var expected := s.duplicate(true)
		expected.remaining = remaining - 0.1
		expected.phase = "done" if remaining <= 0.1 else "cook"
		kernel.advance_single(s, 0.1)
		check_eq(s, expected, "single subtracts raw time, with exact <=0 completion only")

func test_single_non_cook_is_fully_unchanged() -> void:
	var kernel = _kernel()
	if kernel == null: return
	for phase in ["idle", "done", "working", "stir", "awaiting_take"]:
		var s := _station()
		s.phase = phase
		var saved := s.duplicate(true)
		kernel.advance_single(s, 2.0)
		check_eq(s, saved, "only cook advances in single")

func test_rules_auto_output_then_duration_observe_consumed_input_old_phase() -> void:
	if _kernel() == null: return
	var rules := ObservedRules.new(TEA, 42)
	rules.unlocked.mix = true
	var s := _station()
	s.input.raw = 3
	s.remaining = 0.05
	rules.stations.mix = s
	rules._update_machines()
	check_eq(rules.observations, [["output", "mix", {"raw": 0}, 3, "", "ready", 1.0, 0.0], ["seconds", "mix", {"raw": 0}, 3, "tea", "ready", 1.0, 0.0]], "output sees consumed input; duration sees bound output; both see old timing")
	check_eq([s.phase, s.progress, s.duration, s.remaining, s.processing], ["working", 0.0, 2.0, 2.0, 3], "next batch gets no elapsed time on start tick")

func test_rules_pickup_skips_recipe_output_query() -> void:
	if _kernel() == null: return
	var rules := ObservedRules.new(TEA, 42)
	rules.unlocked[rules.pickup_id] = true
	var s := _station()
	s.processing = 0
	s.phase = "idle"
	s.input = {"black_tea": 3}
	rules.stations[rules.pickup_id] = s
	rules._update_machines()
	check_eq(rules.observations, [["seconds", rules.pickup_id, {"black_tea": 2}, 1, "black_tea", "idle", 0.5, 0.5]], "pickup binds input item before sole duration query")

func test_rules_station_order_and_filters_leave_ineligible_records_untouched() -> void:
	if _kernel() == null: return
	var fixture: SpecShop = TEA.duplicate(true)
	var secondary: SpecStation = fixture.station("seal").duplicate(true)
	secondary.id = "unused_pickup"
	fixture.stations.append(secondary)
	var rules := ObservedRules.new(fixture, 42)
	# Derivation selects the last pickup; pin the intended primary for this filter fixture.
	rules.pickup_id = "seal"
	for id in ["mix", rules.pickup_id, "unused_pickup", "lemonade"]:
		rules.unlocked[id] = true
		var s := _station()
		s.processing = 0
		s.input.raw = 3
		rules.stations[id] = s
	# The locked auto and manual station both have startable records.
	var locked := _station()
	locked.processing = 0
	locked.input.raw = 3
	rules.stations.mix2 = locked
	rules.autos.append("mix2")
	var locked_spec: SpecStation = secondary.duplicate(true)
	locked_spec.id = "mix2"
	locked_spec.block = "combine"
	fixture.stations.append(locked_spec)
	rules.unlocked.mix2 = false
	var ignored := [rules.stations.unused_pickup.duplicate(true), rules.stations.lemonade.duplicate(true), locked.duplicate(true)]
	rules._update_machines()
	check_eq(rules.observations.map(func(row: Array) -> String: return row[0] + "/" + row[1]), ["seconds/seal", "output/mix", "seconds/mix"], "shop declaration order controls start queries")
	check_eq([rules.stations.unused_pickup, rules.stations.lemonade, locked], ignored, "secondary pickup, nonautomatic station and locked auto untouched")

func test_rules_no_start_never_queries_output_or_duration() -> void:
	if _kernel() == null: return
	for phase in ["working", "stir", "awaiting_take", "ready", "idle"]:
		var rules := ObservedRules.new(TEA, 42)
		rules.unlocked.mix = true
		var s := _station()
		s.phase = phase
		if phase in ["ready", "idle"]: s.processing = 0
		rules.stations.mix = s
		rules._update_machines()
		check_eq(rules.observations, [], "no start means no recipe or duration query")

func test_rules_stir_facade_forwards_exact_station_points() -> void:
	if _kernel() == null: return
	var fixture: SpecShop = TEA.duplicate(true)
	fixture.station("boil").params.stir_points = [0.8, 0.2]
	var rules := ShopRules.new(fixture, 42)
	var s := _station()
	s.progress = 0.9
	check(rules._pause_for_stir("boil", s, 0.1), "compatibility facade returns crossing")
	check_eq([s.progress, s.remaining, s.phase], [0.8, 1.0 * (1.0 - 0.8), "stir"], "facade preserves original list order")

func test_single_customers_then_eligible_pots_then_workers() -> void:
	if _kernel() == null: return
	var rules := OrderedSingleRules.new(PANCAKE, 42)
	var id: String = rules.pots[0]
	rules.unlocked[id] = true
	rules.stations[id].phase = "cook"
	rules.stations[id].remaining = 0.05
	var ignored_id := ""
	for st in rules.shop.stations:
		if st.block != "batch_pot":
			ignored_id = st.id
			break
	rules.stations[ignored_id].phase = "cook"
	rules.stations[ignored_id].remaining = 0.05
	rules._tick_single()
	check_eq(rules.observations, [["customers", "cook"], ["worker", "done", -0.05]], "customers observe cook before pot; worker observes completion afterward")
	check_eq(rules.stations[ignored_id].remaining, 0.05, "non-pot skipped")
	rules.observations.clear()
	rules.unlocked[id] = false
	rules.stations[id].phase = "cook"
	rules.stations[id].remaining = 0.05
	rules._tick_single()
	check_eq(rules.stations[id].remaining, 0.05, "locked pot skipped")
