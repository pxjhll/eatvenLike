extends "res://tests/test_case.gd"
const LegacyRules := preload("res://tests/fixtures/legacy_shops/reference_rules.gd")
## Frozen v0 business regression; formal v1 coverage: test_first_shops_migration.

const MODULE := "res://game/rules/fulfillment_completion.gd"
const TEA: SpecShop = preload("res://tests/fixtures/legacy_shops/tea.tres")
const PANCAKE: SpecShop = preload("res://tests/fixtures/legacy_shops/pancake.tres")

class CompletionRules extends "res://tests/fixtures/legacy_shops/reference_rules.gd":
	var observations := []
	func _take(job: Dictionary) -> void:
		observations.append(["take", stations[job.src].phase, stations[job.src].processing])
	func pot_seconds(id: String) -> float:
		observations.append(["duration", stations[id].phase, stations[id].processing, workers[0].phase])
		return 13.0
	func pot_batch(id: String) -> int:
		observations.append(["batch", stations[id].phase, workers[0].phase])
		return 3
	func _finish(worker: Dictionary) -> void:
		observations.append(["finish", stations[worker.job.src].duplicate(true)])
		super._finish(worker)

func _kernel() -> Variant:
	if not ResourceLoader.exists(MODULE):
		check(false, "Completion kernel must exist")
		return null
	return load(MODULE)

func test_source_consumption_predicate() -> void:
	var kernel = _kernel()
	if kernel == null: return
	check_eq([kernel.consumes_handoff_source({"kind": "pot_start"}), kernel.consumes_handoff_source({"kind": "work"}), kernel.consumes_handoff_source({"kind": "stir"}), kernel.consumes_handoff_source({"kind": "pot_take"})], [true, true, false, false], "only loading and manual work consume source")

func test_pot_start_literal_and_unrelated_fields() -> void:
	var kernel = _kernel()
	if kernel == null: return
	var station := {"processing": 0, "duration": 2.0, "remaining": 7.0, "progress": 0.4, "phase": "waiting", "work_reserved": true, "output": {"tea": 2}, "history": ["keep"]}
	var job := {"kind": "pot_start", "count": 3, "item": "tea"}
	kernel.complete_handoff_work(station, job, 13.0)
	check_eq(station, {"processing": 3, "duration": 13.0, "remaining": 13.0, "progress": 0.0, "phase": "heating", "work_reserved": false, "output": {"tea": 2}, "history": ["keep"]}, "pot start initializes cooking only")
	check_eq(job, {"kind": "pot_start", "count": 3, "item": "tea"}, "job unchanged")

func test_stir_only_phase_and_reservation_change() -> void:
	var kernel = _kernel()
	if kernel == null: return
	var station := {"phase": "waiting", "work_reserved": true, "processing": 3, "duration": 9.0, "remaining": 7.0, "progress": 0.4}
	kernel.complete_handoff_work(station, {"kind": "stir"}, 0.0)
	check_eq(station, {"phase": "heating", "work_reserved": false, "processing": 3, "duration": 9.0, "remaining": 7.0, "progress": 0.4}, "stir preserves cooking history")

func test_pot_take_first_output_and_remaining_retained() -> void:
	var kernel = _kernel()
	if kernel == null: return
	var station := {"output": {"tea": 2, "other": 8}, "processing": 3, "phase": "waiting", "progress": 0.4, "work_reserved": true, "remaining": 7.0}
	kernel.complete_handoff_work(station, {"kind": "pot_take"}, 0.0)
	check_eq(station, {"output": {"tea": 5, "other": 8}, "processing": 0, "phase": "ready", "progress": 1.0, "work_reserved": false, "remaining": 7.0}, "only first output receives batch")

func test_topping_output_and_work_ready() -> void:
	var kernel = _kernel()
	if kernel == null: return
	var station := {"output": {"tea": 2}, "input": {"leaf": 9}, "processing_item": "tea", "phase": "working", "progress": 0.4, "work_reserved": true, "remaining": 7.0}
	kernel.complete_handoff_work(station, {"kind": "work", "count": 3, "item": "leaf"}, 0.0)
	check_eq(station, {"output": {"tea": 5}, "input": {"leaf": 9}, "processing_item": "", "phase": "ready", "progress": 1.0, "work_reserved": false, "remaining": 7.0}, "work completes output and clears reservation")

func test_topping_input_and_facade_preserve_phase() -> void:
	var kernel = _kernel()
	if kernel == null: return
	var station := {"output": {"tea": 2}, "input": {"leaf": 9}, "processing_item": "", "phase": "working", "history": [7]}
	kernel.complete_topping(station, {"item": "leaf", "count": 3})
	check_eq(station, {"output": {"tea": 2}, "input": {"leaf": 12}, "processing_item": "", "phase": "working", "history": [7]}, "direct topping adds input without phase changes")
	var rules := LegacyRules.new(TEA, 42)
	rules._complete_topping("unused", station, {"item": "leaf", "count": 2})
	check_eq(station, {"output": {"tea": 2}, "input": {"leaf": 14}, "processing_item": "", "phase": "working", "history": [7]}, "compatibility facade forwards")

func test_single_load_retains_stock_progress_and_history() -> void:
	var kernel = _kernel()
	if kernel == null: return
	var worker := {"chore": "load:pot", "step": 2, "carry_item": "tea"}
	var station := {"phase": "idle", "duration": 2.0, "remaining": 1.0, "stock": 4, "progress": 0.8, "user": 7}
	kernel.complete_single_chore(worker, station, true, 13.0, 0, 0)
	check_eq(station, {"phase": "cook", "duration": 13.0, "remaining": 13.0, "stock": 4, "progress": 0.8, "user": -1}, "load retains stock and history")
	check_eq(worker, {"chore": "", "step": 2, "carry_item": "tea"}, "load clears only chore")

func test_single_unload_cap_and_history() -> void:
	var kernel = _kernel()
	if kernel == null: return
	var worker := {"chore": "unload:pot", "step": 2}
	var station := {"phase": "done", "stock": 4, "duration": 13.0, "remaining": 0.0, "progress": 1.0, "user": 7}
	kernel.complete_single_chore(worker, station, false, 0.0, 3, 6)
	check_eq(station, {"phase": "idle", "stock": 6, "duration": 13.0, "remaining": 0.0, "progress": 1.0, "user": -1}, "unload caps stock, retains timing")
	check_eq(worker, {"chore": "", "step": 2}, "unload clears only chore")
	station.stock = 1
	kernel.complete_single_chore(worker, station, false, 0.0, 3, 6)
	check_eq(station.stock, 4, "below cap adds whole batch")

func test_adjacent_exclusive_step_keeps_user_and_sets_holds() -> void:
	var kernel = _kernel()
	if kernel == null: return
	var worker := {"step": 0, "steps": [{"action": "mix", "station": "pan", "holds": "batter"}, {"action": "cook", "station": "pan"}], "carry_item": "old", "carry_count": 2, "order": 17}
	var station := {"user": 7, "stock": 4}
	kernel.advance_single_step(worker, station, true)
	check_eq([worker.step, worker.carry_item, worker.carry_count, worker.order, station], [1, "batter", 1, 17, {"user": 7, "stock": 4}], "adjacent same station retains ownership")

func test_released_and_nonexclusive_steps_with_empty_holds() -> void:
	var kernel = _kernel()
	if kernel == null: return
	for exclusive in [true, false]:
		var worker := {"step": 0, "steps": [{"action": "cook", "station": "pan", "holds": ""}, {"action": "hand", "station": "counter"}], "carry_item": "old", "carry_count": 2}
		var station := {"user": 7, "stock": 4}
		kernel.advance_single_step(worker, station, exclusive)
		check_eq([worker.step, worker.carry_item, worker.carry_count, station], [1, "old", 2, {"user": -1 if exclusive else 7, "stock": 4}], "empty holds retains carry; only exclusive releases")
	var last := {"step": 0, "steps": [{"action": "cook", "station": "pan"}], "carry_item": "old", "carry_count": 2}
	var final_station := {"user": 7}
	kernel.advance_single_step(last, final_station, true)
	check_eq([last.step, final_station], [1, {"user": -1}], "last nonterminal recipe step releases without next index")

func test_take_is_index_only_even_with_holds_and_exclusive() -> void:
	var kernel = _kernel()
	if kernel == null: return
	var worker := {"step": 0, "steps": [{"action": "take", "holds": "ignored"}], "carry_item": "old", "carry_count": 2}
	var station := {"user": 7, "history": [1]}
	kernel.advance_single_step(worker, station, true)
	check_eq(worker, {"step": 1, "steps": [{"action": "take", "holds": "ignored"}], "carry_item": "old", "carry_count": 2}, "take changes only index and needs no station on step")
	check_eq(station, {"user": 7, "history": [1]}, "take never releases")

func test_rules_handoff_take_query_complete_finish_order() -> void:
	if _kernel() == null: return
	var rules := CompletionRules.new(TEA, 42)
	rules.stations.boil = {"processing": 0, "duration": 2.0, "remaining": 7.0, "progress": 0.4, "phase": "waiting", "work_reserved": true}
	var worker: Dictionary = rules.workers[0]
	worker.job = {"kind": "pot_start", "src": "boil", "count": 3}
	worker.phase = "work"
	worker.action_left = 0.05
	rules._update_worker(worker)
	check_eq(rules.observations, [["take", "waiting", 0], ["duration", "waiting", 0, "work"], ["finish", {"processing": 3, "duration": 13.0, "remaining": 13.0, "progress": 0.0, "phase": "heating", "work_reserved": false}]], "source before duration before completion before finish")
	check_eq([worker.phase, worker.job], ["idle", {}], "WorkerState cleanup follows completion")

func test_rules_chore_queries_only_used_arguments_and_work_finishes_first() -> void:
	if _kernel() == null: return
	var rules := CompletionRules.new(PANCAKE, 42)
	var id: String = rules.pots[0]
	var worker: Dictionary = rules.workers[0]
	worker.phase = "work"
	worker.chore = "load:" + id
	rules._finish_work_single(worker)
	check_eq(rules.observations, [["duration", "idle", 0, "idle"]], "load queries duration only, after work finish and before mutation")
	check_eq([worker.phase, worker.chore, rules.stations[id].phase, rules.stations[id].duration], ["idle", "", "cook", 13.0], "work finishes before chore effects")
	rules.observations.clear()
	rules.stations[id].phase = "done"
	worker.phase = "work"
	worker.chore = "unload:" + id
	rules._finish_work_single(worker)
	check_eq(rules.observations, [["batch", "done", "idle"]], "unload queries batch only, after work finish")

func test_rules_terminal_hand_settles_then_cleans_without_advancing() -> void:
	if _kernel() == null: return
	var rules := LegacyRules.new(PANCAKE, 42)
	var c := {"id": 17, "kind": "plain", "addon": false, "state": "paid", "paid": 6}
	rules.customers = [c]
	var worker: Dictionary = rules.workers[0]
	worker.order = 17
	worker.steps = [{"action": "hand"}]
	worker.step = 0
	worker.phase = "work"
	var observed := []
	var listener := func(event: Dictionary) -> void:
		observed.append([event.duplicate(), c.state, rules.sold, worker.phase, worker.order, worker.step])
	rules.events.on("sale", listener)
	rules._finish_work_single(worker)
	rules.events.off("sale", listener)
	check_eq(observed, [[{"dish": "plain", "income": 6}, "leaving", 1, "idle", 17, 0]], "sale sees finished work and unchanged terminal index")
	check_eq([worker.order, worker.steps, worker.step], [-1, [], 0], "terminal returns after existing cleanup")
