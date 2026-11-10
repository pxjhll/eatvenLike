extends "res://tests/test_case.gd"

const MODULE := "res://game/rules/dispatch_policy.gd"
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")

# Instrument real queries without replacing their values or swallowing errors.
class QueryRules extends ShopRules:
	var queries := []
	func carry(worker: Dictionary) -> int:
		queries.append("carry")
		return super.carry(worker)
	func _available(source: String, item: String) -> int:
		queries.append("available")
		return super._available(source, item)
	func _free(destination: String) -> int:
		queries.append("free")
		return super._free(destination)
	func _cup(item: String) -> String:
		queries.append("cup")
		return super._cup(item)
	func _shelf_item_free(item: String) -> int:
		queries.append("shelf")
		return super._shelf_item_free(item)

# Real inventory, navigation and reservation; controlled enumeration makes ties visible.
class GreedyRules extends ShopRules:
	var rounds := []
	var selections := []
	var offered := []
	var duration_queries := []
	var mode := "stock"
	func _jobs(worker: Dictionary) -> Array:
		rounds.append([worker.id, _available("boil", "tea")])
		if mode == "stock":
			var first := _candidate("transfer", "boil", "mix", "tea", worker, 50.0)
			var second := _candidate("transfer", "boil", "mix", "tea", worker, 50.0)
			if not first.is_empty(): first["tie"] = "first"
			if not second.is_empty(): second["tie"] = "second"
			offered.append(first)
			return [{}, first, second, _candidate("load", supply_id, "boil", station_input.boil, worker, 1.0)]
		var result := []
		for kind in ["work", "stir", "pot_start", "load", "serve"]:
			result.append({"kind": kind, "src": "lemonade", "dst": "lemonade", "item": "lemonade", "count": 1, "priority": 0.0, "belt": "", "order_id": -1})
		result.push_front({"kind": "work", "src": "unreachable", "dst": "unreachable", "item": "lemonade", "count": 1, "priority": 9999.0, "belt": "", "order_id": -1})
		return result
	func _source_point(job: Dictionary) -> Vector2:
		return Vector2(-100000, -100000) if job.src == "unreachable" else super._source_point(job)
	func _destination_point(job: Dictionary) -> Vector2:
		return Vector2(-100000, -100000) if job.dst == "unreachable" else super._destination_point(job)
	func _action_duration(job: Dictionary, worker: Dictionary) -> float:
		duration_queries.append([job.kind, job.src])
		return super._action_duration(job, worker)
	func _reserve(worker: Dictionary, job: Dictionary) -> void:
		selections.append({"worker": worker, "job": job})
		if mode == "stock": super._reserve(worker, job)
		else: worker.phase = "observed"

class BeltRules extends ShopRules:
	var observations := []
	var worker_reserves := 0
	func _append_pack_jobs(worker: Dictionary, result: Array) -> void:
		observations.append(["options", _courier, worker.courier, belt_clock[shop.connections[0].id]])
		super._append_pack_jobs(worker, result)
	func _reserve(worker: Dictionary, job: Dictionary) -> void:
		worker_reserves += 1
		super._reserve(worker, job)
	func _take(job: Dictionary) -> void:
		observations.append(["take", _courier, stations[job.src].reserved_out.get(job.item, 0), stations[job.src].output[job.item], belt_items.size()])
		super._take(job)

func _policy() -> Variant:
	if not ResourceLoader.exists(MODULE):
		check(false, "DispatchPolicy module must exist before behavioral assertions")
		return null
	return load(MODULE)

func _dispatch() -> SpecDispatch:
	var dispatch := SpecDispatch.new()
	dispatch.throughput_weight = 4.0
	dispatch.travel_penalty = 1.0
	dispatch.fatigue_weight = 0.4
	dispatch.wait_bonus_cap = 5.0
	dispatch.wait_bonus_per_second = 0.5
	return dispatch

func _open(rules: ShopRules) -> void:
	rules.gold = 1000000.0
	for unused in 30:
		var next := rules.next_unlock()
		if next.is_empty(): break
		check_eq(rules.execute_command("unlock", {"id": next}).code, "ok", "open real station")
	for material in rules.boxes:
		if not rules.boxes[material]: check_eq(rules.execute_command("unlock_box", {"material": material}).code, "ok", "open real box")
	for unused in 2:
		check_eq(rules.execute_command("hire").code, "ok", "hire real kitchen worker")
	for worker in rules.roster:
		if not worker.deployed: check_eq(rules.execute_command("deploy_worker", {"id": worker.id, "post": ""}).code, "ok", "deploy real kitchen worker")

func _worker(rules: ShopRules) -> Dictionary:
	for worker in rules.workers:
		if worker.post.is_empty(): return worker
	return {}

func test_transport_literal_fields_key_order_and_minimum() -> void:
	var policy = _policy()
	if policy == null: return
	var job: Dictionary = policy.transport_candidate("load", "supply", "pot", "raw", 4, 3, 2, 7.0)
	check_eq(job, {"kind": "load", "src": "supply", "dst": "pot", "item": "raw", "count": 2, "priority": 7.0, "belt": "", "order_id": -1}, "literal legacy transport")
	check_eq(job.keys(), ["kind", "src", "dst", "item", "count", "priority", "belt", "order_id"], "legacy insertion order")
	for limits in [[1, 3, 4], [4, 1, 3], [3, 4, 1]]:
		check_eq(policy.transport_candidate("k", "s", "d", "i", limits[0], limits[1], limits[2], -2.0, "belt").count, 1, "each cap independently limits")
	check_eq(policy.transport_candidate("k", "s", "shelf", "i", 9, 8, 7, -2.0, "b").count, 7, "factory has no shelf cap")

func test_transport_rejection_returns_independent_empty_results() -> void:
	var policy = _policy()
	if policy == null: return
	for limits in [[0, 2, 2], [2, -1, 2], [2, 2, 0]]:
		var first: Dictionary = policy.transport_candidate("k", "s", "d", "i", limits[0], limits[1], limits[2], 0.0)
		var second: Dictionary = policy.transport_candidate("k", "s", "d", "i", limits[0], limits[1], limits[2], 0.0)
		check(first.is_empty() and second.is_empty() and not is_same(first, second), "nonpositive cap produces fresh empty result")

func test_serve_enrichment_preserves_aliases_and_adds_capped_wait() -> void:
	var policy = _policy()
	if policy == null: return
	var dispatch := _dispatch()
	var job := {"count": 8, "priority": 7.0, "order_id": -1, "extra": [9], "belt": "b"}
	var order := {"id": 12, "wait": 30.0, "other": [3]}
	var saved_order := order.duplicate(true)
	var nested: Array = job.extra
	var result: Dictionary = policy.serve_candidate(job, order, "press", dispatch)
	check(is_same(result, job) and is_same(result.extra, nested), "enrichment returns original candidate and nested alias")
	check_eq(job, {"count": 1, "priority": 12.0, "order_id": 12, "extra": [9], "belt": "b", "pour": "press"}, "serve overwrites count/id/pour, adds bonus")
	check_eq(order, saved_order, "order unchanged")
	check_eq([dispatch.wait_bonus_cap, dispatch.wait_bonus_per_second], [5.0, 0.5], "definition unchanged")

func test_wait_bonus_has_no_lower_normalization() -> void:
	var policy = _policy()
	if policy == null: return
	var d := _dispatch()
	check_eq([policy.wait_bonus(d, 2.0), policy.wait_bonus(d, 30.0), policy.wait_bonus(d, -4.0)], [1.0, 5.0, -2.0], "linear, capped, negative literal bonuses")

func test_exact_count_rejection_identity_and_no_positivity_policy() -> void:
	var policy = _policy()
	if policy == null: return
	var job := {"count": 3, "extra": [4]}
	var rejected: Dictionary = policy.exact_count(job, 4)
	check(rejected.is_empty() and not is_same(rejected, job), "too small yields new empty result")
	check_eq(job.count, 3, "rejection does not mutate")
	check(is_same(policy.exact_count(job, 2), job), "success returns original dictionary")
	check_eq(job.count, 2, "success sets exact count")
	check(is_same(policy.exact_count(job, -2), job), "negative exact count not newly rejected")
	check_eq(job.count, -2, "negative exact value stored")
	var empty := {}
	check(not is_same(policy.exact_count(empty, 0), empty), "empty input yields fresh empty")

func test_score_literal_weights_denominator_fatigue_and_negative() -> void:
	var policy = _policy()
	if policy == null: return
	var d := _dispatch()
	var worker := {"fatigue": 0.25}
	var job := {"count": 3, "priority": 10.0}
	check_eq(policy.score(d, worker, job, 2.0, 4.0), 9.0, "independent weighted score")
	check_eq(policy.score(d, {"fatigue": 0.0}, {"count": 2, "priority": -1.0}, 0.0, 0.0), 79.0, "0.1 denominator")
	check_eq(policy.score(d, {"fatigue": 0.0}, {"count": 0, "priority": -3.0}, 2.0, 1.0), -5.0, "negative score retained")
	check_eq(policy.score(d, {"fatigue": 5.0}, {"count": 0, "priority": 3.0}, 0.0, 1.0), -3.0, "fatigue factor not clamped")
	check_eq([worker, job], [{"fatigue": 0.25}, {"count": 3, "priority": 10.0}], "scoring input unchanged")

func test_consider_strict_ties_original_references_and_minus_infinity() -> void:
	var policy = _policy()
	if policy == null: return
	var best := {"score": -INF, "worker": {}, "job": {}}
	var worker := {"id": 1}
	var job := {"count": 2}
	policy.consider(best, worker, job, -INF)
	check(best.job.is_empty() and best.worker.is_empty(), "minus infinity does not select")
	policy.consider(best, worker, job, -3.0)
	policy.consider(best, {"id": 2}, {"other": 1}, -3.0)
	check(is_same(best.worker, worker) and is_same(best.job, job), "first tie retains original references")
	policy.consider(best, {"id": 3}, {"count": 4}, -2.0)
	check_eq([best.score, best.worker.id, best.job.count], [-2.0, 3, 4], "strict improvement replaces selection")

func test_route_filters_first_tie_original_alias_and_initial_infinity() -> void:
	var policy = _policy()
	if policy == null: return
	var first := {"src": "s", "dst": "d", "priority": -INF, "extra": [9]}
	var tie := {"src": "s", "dst": "d", "priority": -INF}
	var result: Dictionary = policy.route_choice([{}, {"src": "x", "dst": "d", "priority": 999.0}, {"src": "s", "dst": "x", "priority": 999.0}, first, tie], "s", "d")
	check(is_same(result, first), "route selects first matching minus infinity by reference")
	var higher := {"src": "s", "dst": "d", "priority": -2.0}
	check(is_same(policy.route_choice([first, higher, higher.duplicate()], "s", "d"), higher), "higher priority wins with original reference")
	var empty: Dictionary = policy.route_choice([{}], "s", "d")
	check(empty.is_empty() and not is_same(empty, policy.route_choice([], "s", "d")), "no route returns fresh empty")

func test_fallback_shallow_copy_first_tie_and_top_level_independence() -> void:
	var policy = _policy()
	if policy == null: return
	var first := {"priority": -INF, "nested": [9]}
	var result: Dictionary = policy.fallback_pot_choice([{}, first, {"priority": -INF, "nested": [2]}])
	check(not is_same(result, first) and is_same(result.nested, first.nested), "fallback shallow copy shares only nested data")
	result.priority = 5.0
	result.ticket = {"count": 1}
	check_eq(first, {"priority": -INF, "nested": [9]}, "priority/ticket attachment leaves source untouched")
	var higher := {"priority": 7.0, "nested": [3]}
	check(is_same(policy.fallback_pot_choice([first, higher, {"priority": 7.0, "nested": [4]}]).nested, higher.nested), "higher and first tie preserved")
	check(policy.fallback_pot_choice([{}]).is_empty(), "empty fallback")

func test_rules_candidate_queries_and_late_shelf_second_cap() -> void:
	if _policy() == null: return
	var rules := QueryRules.new(TEA, 42)
	_open(rules)
	var worker := _worker(rules)
	worker.stats.carry = 8.0
	# Leave one per-dish slot while enough aggregate shelf slots remain.
	rules.shelf_stock.plain_milk_tea = rules.dish_cap() - 1
	rules.shelf_count = rules.dish_cap() - 1
	rules.stations.mix.output.plain_milk_tea = 9
	rules.queries.clear()
	var job := rules._candidate("carry_to_shelf", "mix", ShopRules.SHELF, "plain_milk_tea", worker, 7.0)
	check_eq(rules.queries.slice(0, 3), ["carry", "available", "free"], "carry then available then free")
	check_eq(rules.queries.slice(3, 5), ["cup", "shelf"], "only successful shelf candidate queries cup and per-dish cap")
	check_eq(job.count, 1, "second shelf cap applies after aggregate cap")
	rules.queries.clear()
	rules._candidate("transfer", "mix", "topping", "missing", worker, 1.0)
	check_eq(rules.queries, ["carry", "available", "free"], "non-shelf rejection has no shelf queries")
	rules.queries.clear()
	rules._candidate("carry_to_shelf", "mix", ShopRules.SHELF, "missing", worker, 1.0)
	check_eq(rules.queries, ["carry", "available", "free"], "empty shelf candidate has no late queries")

func test_rules_serve_seat_order_pour_and_additive_bonus() -> void:
	if _policy() == null: return
	var fixture: SpecShop = TEA.duplicate(true)
	fixture.dispatch = _dispatch()
	fixture.dispatch.base_scores = {"serve": 7.0}
	var rules := ShopRules.new(fixture, 42)
	_open(rules)
	for group in rules.seats: rules.seats[group] = 0
	rules.seats[rules.seats.keys()[0]] = 1
	rules.orders = [{"id": 10, "dish": "lemonade", "wait": 30.0, "reserved": false, "takeaway": false, "seat": -1}, {"id": 11, "dish": "lemonade", "wait": 30.0, "reserved": false, "takeaway": false, "seat": -1}, {"id": 12, "dish": "lemonade", "wait": 2.0, "reserved": false, "takeaway": true, "seat": -1}]
	var jobs := rules._jobs(rules.workers[0])
	check_eq(jobs.size(), 2, "first standing diner consumes the single seat, takeaway still eligible")
	check_eq([jobs[0].order_id, jobs[0].count, jobs[0].pour, jobs[0].priority], [10, 1, fixture.dish("lemonade").steps[0].station, 12.0], "serve is enriched after seat decision")
	check_eq([jobs[1].order_id, jobs[1].priority], [12, 8.0], "order traversal and uncapped additive wait")
	check(not rules.orders[0].reserved, "enumeration does not reserve orders")

func test_rules_exact_facade_preserves_identity() -> void:
	if _policy() == null: return
	var rules := ShopRules.new(TEA, 42)
	var job := {"count": 2}
	check(is_same(rules._exact(job, 1), job), "Rules exact forwards identity")
	check_eq(job.count, 1, "Rules exact applies count")
	check(rules._exact(job, 2).is_empty(), "Rules exact forwards rejection")

func test_rules_greedy_regenerates_after_real_scarce_stock_reservation() -> void:
	if _policy() == null: return
	var fixture: SpecShop = TEA.duplicate(true)
	fixture.dispatch.throughput_weight = 0.0
	fixture.dispatch.travel_penalty = 0.0
	fixture.dispatch.fatigue_weight = 0.0
	var rules := GreedyRules.new(fixture, 42)
	_open(rules)
	var first := _worker(rules)
	var second := rules._new_worker(first.kind)
	second.pos = first.pos
	second.deployed = true
	rules.workers = [first, second]
	rules.stations.boil.output.tea = 1
	rules._allocate()
	check_eq(rules.selections.size(), 2, "both greedy rounds make reservations")
	check(is_same(rules.selections[0].worker, first) and is_same(rules.selections[0].job, rules.offered[0]), "worker and job traversal first ties retain original references")
	check_eq([first.job.kind, first.job.tie, second.job.kind], ["transfer", "first", "load"], "scarce transfer disappears after first reserve; next round chooses load")
	check_eq(rules.rounds, [[first.id, 1], [second.id, 1], [second.id, 0]], "fresh enumeration observes changed inventory only next round")
	check_eq(rules.stations.boil.reserved_out.tea, 1, "scarce stock reserved exactly once")

func test_rules_unreachable_filter_and_work_only_duration_estimator() -> void:
	if _policy() == null: return
	var rules := GreedyRules.new(TEA, 42)
	_open(rules)
	var worker := _worker(rules)
	rules.workers = [worker]
	rules.mode = "estimator"
	check_eq(TEA.layout.nav, "grid", "fixture uses real reachability")
	rules._allocate()
	check_eq(rules.duration_queries, [["work", "lemonade"]], "only reachable work calls duration; stir/pot/load/serve retain hop estimate")
	check_eq(rules.selections.size(), 1, "reachable candidate selected")
	check(rules.selections[0].job.src != "unreachable", "unreachable highest priority filtered before scoring")

func test_rules_new_ticket_fallback_overwrites_priority_without_source_mutation() -> void:
	if _policy() == null: return
	var fixture: SpecShop = TEA.duplicate(true)
	fixture.dispatch = _dispatch()
	fixture.dispatch.base_scores = {"follow": 11.0, "follow_step": 99.0}
	var rules := ShopRules.new(fixture, 42)
	_open(rules)
	rules.orders = [{"id": 90, "dish": "plain_milk_tea", "wait": 30.0, "reserved": false, "takeaway": false, "seat": -1}]
	var option := {"kind": "load", "src": rules.supply_id, "dst": "boil", "item": rules.station_input.boil, "count": 1, "priority": -3.0, "belt": "", "order_id": -1, "nested": [8]}
	var tied := option.duplicate(true)
	tied.nested = [9]
	var job := rules._new_ticket_job(_worker(rules), [{}, option, tied])
	check_eq(job.priority, 16.0, "follow overwrites fallback priority then adds capped bonus")
	check_eq(job.ticket, {"dish": "plain_milk_tea", "count": 1, "at": 0, "phase": "carry", "wait": 0.0}, "same ticket shape and prefix count")
	check(not is_same(job, option) and is_same(job.nested, option.nested), "fallback is shallow copy of first tie")
	check_eq([option.priority, option.has("ticket")], [-3.0, false], "source candidate not enriched")
	# A later start with unavailable output cannot fall back to pot work.
	rules.stations.mix.input[rules.station_input.mix] = 1
	check(rules._new_ticket_job(_worker(rules), [option]).is_empty(), "fallback applies only at initial carry stage")
	var worker := _worker(rules)
	worker.stats.carry = 3.0
	rules.orders.append({"id": 91, "dish": "plain_milk_tea", "wait": 2.0, "reserved": false, "takeaway": false, "seat": -1})
	rules.orders.append({"id": 92, "dish": "pearl_milk_tea", "wait": 2.0, "reserved": false, "takeaway": false, "seat": -1})
	rules.stations.mix.output[rules.station_output["mix|plain_milk_tea"]] = 2
	var resumed := rules._new_ticket_job(worker, [option])
	check_eq([resumed.ticket.count, resumed.ticket.at, resumed.priority], [2, 1, 16.0], "successful resumed job keeps contiguous same-dish prefix and overwrites step priority")
	check(not resumed.has("nested"), "successful ticket job never uses fallback option")

func test_rules_belt_pipeline_reserve_take_ship_cooldown_without_worker_reserve() -> void:
	if _policy() == null: return
	var rules := BeltRules.new(TEA, 42)
	_open(rules)
	var connection: Resource
	for c in TEA.connections:
		if c.from == rules.pickup_id and c.to == ShopRules.RACK:
			connection = c
			break
	check(connection != null, "real packing belt exists")
	if connection == null: return
	# The observer reads this route's clock, independent of other connections.
	rules.shop = TEA.duplicate(true)
	rules.shop.connections = [connection]
	rules.belts = {connection.id: true}
	rules.belt_clock = {connection.id: 0.0}
	rules.stations[rules.pickup_id].output.lemonade = 1
	rules.stations[rules.pickup_id].output.lemon_tea = 1
	rules._run_belts()
	check_eq(rules.observations, [["options", true, true, 0.0], ["take", false, 1, 1, 0]], "courier flag window ends before reserve then take sees reservation and original stock before shipment")
	check_eq(rules.worker_reserves, 0, "belt does not enter worker reservation")
	check_eq(rules.belt_items, [{"route": connection.id, "item": "lemonade", "count": 1, "progress": 0.0, "duration": connection.seconds, "dst": ShopRules.RACK}], "first tied dish shipped")
	check_eq([rules.stations[rules.pickup_id].output.lemonade, rules.stations[rules.pickup_id].reserved_out.get("lemonade", 0), rules.belt_clock[connection.id]], [0, 0, connection.interval], "take consumes and clears reservation before cooldown reset")
	var before := rules.observations.size()
	rules._run_belts()
	check_eq([rules.observations.size(), rules.belt_items.size()], [before, 1], "positive cooldown skips option queries and shipment")
	check_eq(rules.belt_clock[connection.id], maxf(0.0, connection.interval - ShopRules.STEP), "cooldown decrements before guard")
