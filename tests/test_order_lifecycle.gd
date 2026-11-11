extends "res://tests/test_case.gd"
## Frozen v0 business regression; formal v1 coverage: test_first_shops_migration.

const MODULE := "res://game/rules/rule_orders.gd"
const TEA: SpecShop = preload("res://tests/fixtures/legacy_shops/tea.tres")
const PANCAKE: SpecShop = preload("res://tests/fixtures/legacy_shops/pancake.tres")
const FORWARDS := {"orders": "orders", "diners": "diners", "customers": "customers", "queue": "queue", "lost": "lost", "_next_order": "next_order", "_next_customer_id": "next_customer_id", "_order_clock": "order_clock", "_next_customer": "next_customer", "order_ramp": "order_ramp"}
const KEYS := ["clock", "gold", "revenue", "sold", "sold_by_dish", "lost", "stage_index", "unlocked", "levels", "boxes", "completed_at", "paused", "tune", "stations", "shelf_stock", "shelf_count", "shelf_reserved_in", "shelf_reserved_out", "generated", "orders", "diners", "roster", "hire_pool", "event_ready_at", "events_seen", "belts", "belt_clock", "belt_items", "order_ramp", "flyer_wave", "flyer_wait", "flyer_clock", "flyer_pending", "flyer_ready_at", "flyer_left", "flyer_timer", "seats", "_accumulator", "_order_clock", "_next_order", "_next_staff", "_sale_carry", "_next_customer", "_courier", "customers", "queue", "_next_customer_id", "full_seconds", "pot_busy", "side_idle", "serve"]

class ObserveRules extends ShopRules:
	var observations := []
	func _roll_options() -> Array:
		observations.append(["options", _next_customer_id, customers.size(), queue.duplicate()])
		return super._roll_options()
	func _order_steps(c: Dictionary) -> Array:
		observations.append(["steps", c.claimed, workers[0].order, queue.duplicate()])
		return super._order_steps(c)
	func _try_pot_chore(s: Dictionary, blocked: bool) -> bool:
		observations.append(["chore", customers[0].claimed if not customers.is_empty() else false])
		return super._try_pot_chore(s, blocked)
	func order_price_single(c: Dictionary) -> int:
		observations.append(["quote", queue.duplicate(), c.state, gold])
		return 17

class ReserveRules extends ShopRules:
	var observations := []
	func _walk(worker: Dictionary, destination: Vector2, phase: String) -> void:
		observations.append(["walk", shelf_reserved_out, orders[0].reserved, worker.job.kind])
		super._walk(worker, destination, phase)

func _owner() -> Variant:
	# Guard allows assertion RED on the complete suite before the new script exists.
	if not ResourceLoader.exists(MODULE):
		check_eq(null, {"id": 1, "state": "queue", "wait": 0.0}, "order owner cannot perform literal admission yet")
		return null
	return load(MODULE).new()

func _row(id: int, state := "queue", claimed := false, wait := 0.0) -> Dictionary:
	return {"id": id, "kind": "plain", "addon": false, "state": state, "wait": wait, "claimed": claimed, "paid": 0, "options": []}

func test_defaults_independent_containers_and_all_fields() -> void:
	var a = _owner()
	if a == null: return
	var b = _owner()
	check_eq([a.orders, a.diners, a.customers, a.queue, a.lost, a.next_order, a.next_customer_id, a.order_clock, a.next_customer, a.order_ramp], [[], [], [], [], 0, 1, 1, 0.0, 0.0, {}], "ten exact defaults")
	for field in ["orders", "diners", "customers", "queue"]:
		a.get(field).append({"test": true})
		check_eq(b.get(field), [], "independent " + field)
	a.order_ramp.x = 4
	check_eq(b.order_ramp, {}, "independent ramps")

func test_handoff_admission_keys_aliases_ramp_and_zero_limit() -> void:
	var s = _owner()
	if s == null: return
	s.order_ramp = {"old": 8, "a": 1, "takeaway": 2}
	var row: Dictionary = s.admit_handoff("a", 3, false, {"a": 0.5, "b": 2.0}, 2, true)
	check_eq(row, {"id": 1, "wait": 0.0, "reserved": false, "dish": "a", "takeaway": false, "seat": 3}, "literal handoff row")
	check_eq(row.keys(), ["id", "wait", "reserved", "dish", "takeaway", "seat"], "handoff key order")
	check(is_same(row, s.orders[0]), "original handoff alias")
	check_eq([s.next_order, s.order_ramp], [2, {"old": 8, "a": 2, "takeaway": 2, "b": 1}], "ramp limit and untouched key")
	s.admit_handoff("b", -1, true, {"a": 1.0}, 0, false)
	check_eq([s.order_ramp, s.next_order, s.orders[1].id], [{"old": 8, "a": 0, "takeaway": 2, "b": 1}, 3, 2], "zero ramp and closed takeaway")
	s.advance_handoff(0.25)
	check_eq([s.order_clock, s.orders[0].wait, s.orders[1].wait], [0.25, 0.25, 0.25], "clock and ordered waits")

func test_handoff_lookup_reserve_all_remove_first_and_fresh_misses() -> void:
	var s = _owner()
	if s == null: return
	var a := {"id": 7, "reserved": false}
	var b := {"id": 7, "reserved": false}
	var rows := [a, b, {"id": 8, "reserved": false}]
	s.orders = rows
	check(is_same(s.handoff_order(7), a), "first original lookup")
	var miss: Dictionary = s.handoff_order(-1)
	miss.x = 2
	check_eq(s.handoff_order(-1), {}, "fresh missing dictionary")
	s.set_handoff_reserved(7, true)
	check_eq([a.reserved, b.reserved, rows[2].reserved], [true, true, false], "reserve every duplicate id")
	s.set_handoff_reserved(7, false)
	s.remove_handoff(7)
	s.remove_handoff(-1)
	check(is_same(rows, s.orders) and is_same(rows[0], b), "remove first only, keep current array")
	check_eq([rows.size(), b.reserved], [2, false], "cancel reservation without normalization")

func test_diners_reverse_epsilon_and_original_history() -> void:
	var s = _owner()
	if s == null: return
	s.add_diner(2, "tea", 0.25)
	var first: Dictionary = s.diners[0]
	check_eq(first.keys(), ["seat", "dish", "left"], "diner key order")
	check_eq(first, {"seat": 2, "dish": "tea", "left": 0.25}, "literal diner")
	s.add_diner(3, "tea", 0.1000005)
	s.add_diner(4, "tea", 0.100002)
	var rows: Array = s.diners
	s.advance_diners(0.1)
	check(is_same(rows, s.diners) and is_same(rows[0], first), "diner aliases survive reverse removal")
	check_eq(rows.size(), 2, "epsilon removes adjacent ending row only")
	check(is_equal_approx(first.left, 0.15) and rows[1].left > 0.000001, "remaining history decremented once")
	s.advance_diners(1.0)
	check_eq(rows, [], "reverse loop removes every expired row")

func test_overflow_order_skip_and_nonpositive_budgets() -> void:
	var s = _owner()
	if s == null: return
	for budget in [1, 0, -2]:
		s.orders = [{"reserved": true, "takeaway": false, "seat": -1}, {"reserved": false, "takeaway": true, "seat": -1}, {"reserved": false, "takeaway": false, "seat": 2}, {"reserved": false, "takeaway": false, "seat": -1}, {"reserved": false, "takeaway": false, "seat": -1}]
		s.overflow_to_takeaway(budget)
		check_eq(s.orders.map(func(o: Dictionary) -> bool: return o.takeaway), [false, true, false, budget <= 0, true], "ordered overflow budget " + str(budget))

func test_single_literal_aliases_ids_fifo_and_dequeue() -> void:
	var s = _owner()
	if s == null: return
	var options := ["spicy"]
	var c: Dictionary = s.admit_single("dish", false, options)
	check_eq(c, {"id": 1, "kind": "dish", "addon": false, "state": "queue", "wait": 0.0, "claimed": false, "paid": 0, "options": ["spicy"]}, "literal single row")
	check_eq(c.keys(), ["id", "kind", "addon", "state", "wait", "claimed", "paid", "options"], "single key order")
	check(is_same(c, s.customers[0]) and is_same(options, c.options) and is_same(c, s.single_customer(1)), "original aliases")
	var d: Dictionary = s.admit_single("other", true, [])
	check_eq([s.next_customer_id, s.queue], [3, [1, 2]], "ids and queue order")
	check(is_same(s.claim_single(), c) and c.claimed, "claims original head")
	check_eq(s.claim_single(), {}, "claimed head blocks later row")
	check(not d.claimed, "no later search")
	var q: Array = s.queue
	s.dequeue_single(1)
	s.dequeue_single(99)
	check(is_same(q, s.queue) and is_same(s.claim_single(), d), "dequeue preserves array identity")
	s.dequeue_single(2)
	var miss: Dictionary = s.single_customer(99)
	miss.x = true
	check_eq(s.single_customer(99), {}, "fresh single misses")
	check_eq(s.claim_single(), {}, "empty FIFO")
	s.reject_single()
	check_eq([s.lost, s.next_customer_id, s.customers.size()], [1, 3, 2], "rejection increments only lost")

func test_single_strict_patience_event_boundary_and_reentrant_removal() -> void:
	var s = _owner()
	if s == null: return
	var c: Dictionary = s.admit_single("dish", false, [])
	check(not s.advance_single_customer(c, 1.0, 1.0), "exact patience retained")
	check(s.advance_single_customer(c, 0.1, 1.0), "strict excess leaves")
	check_eq([s.lost, s.queue, s.customers.size(), c.state], [1, [], 1, "leaving"], "callback boundary before removal")
	c.state = "paid"
	s.remove_leaving_single(c)
	check_eq(s.customers.size(), 1, "callback revival retained")
	c.state = "leaving"
	var old: Array = s.customers
	s.customers = [c, _row(9)]
	s.remove_leaving_single(c)
	check_eq([old.size(), s.customers.size(), s.customers[0].id], [1, 1, 9], "removal uses replaced current array")
	for test in [["queue", true, 0.1], ["queue", false, 0.0], ["queue", false, -1.0], ["paid", false, 0.1]]:
		var row := _row(8, test[0], test[1], 2.0)
		check(not s.advance_single_customer(row, 1.0, test[2]), "no timeout " + str(test))
		check_eq(row.wait, 3.0 if test[0] == "queue" else 2.0, "only queued wait advances")

func test_static_accept_and_leave_retain_unrelated_aliases() -> void:
	if _owner() == null: return
	var script = load(MODULE)
	var c := _row(3)
	var options: Array = c.options
	script.accept_single(c, 17)
	check_eq([c.paid, c.state, c.wait, c.claimed], [17, "paid", 0.0, false], "accept paid then state")
	script.leave_single(c)
	check_eq([c.paid, c.state], [17, "leaving"], "leave keeps paid")
	check(is_same(options, c.options), "static transitions keep references")

func test_rules_all_ten_forwarders_reset_load_reject_and_schema() -> void:
	# This is a behavior assertion as well as guarded literal coverage: live Rules
	# admission must be observable from the dedicated owner before any wiring exists.
	var r := ShopRules.new(PANCAKE, 42)
	r._spawn_single()
	var has_owner := false
	for p in r.get_property_list():
		if p.name == "_orders_state": has_owner = true
	check_eq(r.get("_orders_state").customers if has_owner else [], r.customers, "Rules admission must update owner records")
	if not has_owner: return
	var owner = r.get("_orders_state")
	var replacements := {"orders": [], "diners": [], "customers": [], "queue": [], "lost": 3, "_next_order": 7, "_next_customer_id": 8, "_order_clock": 0.25, "_next_customer": 0.5, "order_ramp": r.order_ramp.duplicate()}
	for key in replacements:
		r.set(key, replacements[key])
		check_eq(owner.get(FORWARDS[key]), replacements[key], "setter " + key)
		if replacements[key] is Array or replacements[key] is Dictionary:
			check(is_same(owner.get(FORWARDS[key]), replacements[key]), "replacement alias " + key)
	owner.lost = 4
	owner.next_order = 9
	check_eq([r.lost, r._next_order], [4, 9], "scalar getters")
	var saved := r.to_dict()
	check_eq(ShopRules.STATE_KEYS, KEYS, "saved field order unchanged")
	check_eq(ShopRules.BY_DATA_ID, ["sold_by_dish", "unlocked", "levels", "boxes", "stations", "shelf_stock", "order_ramp", "seats"], "data-id fields unchanged")
	check(not saved.has("_orders_state"), "no serialized owner")
	r.reset(42)
	check(is_same(r.get("_orders_state"), owner), "reset retains live owner")
	check_eq([r.orders, r.diners, r.customers, r.queue, r.lost, r._next_order, r._next_customer_id, r._order_clock, r._next_customer], [[], [], [], [], 0, 1, 1, 0.0, 2.0], "reset all forwarded values")
	check_eq(r.load_dict(saved), "", "candidate load accepted")
	check_eq(r.to_dict(), saved, "saved state restored")
	check(is_same(r.get("_orders_state"), owner), "load retains live owner")
	var invalid := saved.duplicate(true)
	invalid.lost = -1
	check(not r.load_dict(invalid).is_empty(), "invalid load rejected")
	check_eq(r.to_dict(), saved, "rejected candidate preserves owner")

func test_rules_lost_callback_per_row_revival_replacement_and_snapshot() -> void:
	var spec: SpecShop = PANCAKE.duplicate(true)
	spec.fulfillment.leave_after = 0.1
	var r := ShopRules.new(spec, 42)
	var a := _row(1, "queue", false, 0.1)
	var b := _row(2, "queue", false, 0.1)
	r.customers = [a, b]
	r.queue = [1, 2]
	var old: Array = r.customers
	var observed := []
	var listener := func(_event: Dictionary) -> void:
		observed.append([r.lost, r.queue.duplicate(), r.customers.map(func(c: Dictionary) -> String: return c.state)])
		if r.lost == 1:
			a.state = "paid"
			r.customers = [a, b, _row(3)]
			r.queue = [2, 3]
	r.events.on("lost", listener)
	r._customers_single()
	r.events.off("lost", listener)
	check_eq(observed, [[1, [2], ["leaving", "queue"]], [2, [3], ["paid", "leaving", "queue"]]], "callbacks see one transition before its removal")
	check_eq([r.customers.map(func(c: Dictionary) -> int: return c.id), r.customers[1].wait, old.size()], [[1, 3], 0.0, 2], "revival, current array, snapshot excludes new row")

func test_rules_lost_callback_reset_and_load_adopt_current_arrays() -> void:
	for action in ["reset", "load"]:
		var spec: SpecShop = PANCAKE.duplicate(true)
		spec.fulfillment.leave_after = 0.1
		var r := ShopRules.new(spec, 42)
		var saved := r.to_dict()
		var c := _row(1, "queue", false, 0.1)
		r.customers = [c]
		r.queue = [1]
		var observed := []
		var listener := func(_event: Dictionary) -> void:
			observed.append([r.customers.size(), r.queue.duplicate(), c.state, r.lost])
			if action == "reset": r.reset(42)
			else: check_eq(r.load_dict(saved), "", "callback load accepted")
		r.events.on("lost", listener)
		r._customers_single()
		r.events.off("lost", listener)
		check_eq(observed, [[1, [], "leaving", 1]], "callback before remove " + action)
		check_eq([r.customers, r.queue, r.lost], [[], [], 0], "cleanup respects adopted arrays " + action)

func _open_single(r: ShopRules) -> void:
	r.gold = 1000000.0
	check_eq(r.unlock("soy_milk"), "", "fixture opens soy")
	check_eq(r.unlock("rear_equipment"), "", "fixture opens griddle")
	check_eq(r.unlock_box("flour"), "", "fixture opens flour")

func _expected_single(r: ShopRules, oracle: RandomNumberGenerator) -> Dictionary:
	# Independent definition-order weighted sampler, never calls owner or _pick_dish.
	var weights := r.order_weights()
	var total := 0.0
	for value in weights.values(): total += value
	var sample := oracle.randf() * total
	var kind: String = weights.keys()[0] if not weights.is_empty() else ""
	for key in weights:
		sample -= weights[key]
		if sample <= 0.0:
			kind = key
			break
	var f := r.shop.fulfillment
	var addon: bool = kind == f.addon_dish or (not f.addon_dish.is_empty() and oracle.randf() < f.addon_chance)
	var options := []
	for option in r.shop.order_options:
		if r.station_unlocked(option.station) and oracle.randf() < option.share: options.append(option.id)
	return {"kind": kind, "addon": addon, "options": options}

func test_rules_single_rng_options_addon_rejection_and_arrived_boundary() -> void:
	for pair in [["plain", ""], ["plain", "plain"], ["plain", "soy"], ["soy", "soy"]]:
		var addon_dish: String = pair[1]
		var spec: SpecShop = PANCAKE.duplicate(true)
		spec.fulfillment.addon_dish = addon_dish
		for stage in spec.stages:
			stage.order_weights.clear()
			stage.order_weights[pair[0]] = 1.0
			stage.flavor_group = ""
		var r := ObserveRules.new(spec, 42)
		_open_single(r)
		var oracle := RandomNumberGenerator.new()
		oracle.state = r.rng.state
		for n in 3:
			var expected := _expected_single(r, oracle)
			var observed := []
			var listener := func(event: Dictionary) -> void: observed.append([event.dish, r._next_customer_id, r.customers.size(), r.queue.duplicate(), r.rng.state])
			r.events.on("arrived", listener)
			r._spawn_single()
			r.events.off("arrived", listener)
			var c: Dictionary = r.customers.back()
			check_eq([c.kind, c.addon, c.options, r.rng.state], [expected.kind, expected.addon, expected.options, oracle.state], "independent draw sequence " + addon_dish)
			check_eq(observed, [[expected.kind, n + 2, n + 1, range(1, n + 2), oracle.state]], "arrived follows admission")
			check_eq(r.observations.back(), ["options", n + 1, n, range(1, n + 1)], "options sees pre-admission ids/arrays")
		var rng_before := r.rng.state
		r.queue.resize(r.queue_capacity())
		var size_before := r.customers.size()
		r._spawn_single()
		check_eq([r.rng.state, r.customers.size(), r.lost], [rng_before, size_before, 1], "full queue rejects before every draw")

func test_rules_locked_options_skip_rng_and_open_options_definition_order() -> void:
	for open_option in [false, true]:
		var spec: SpecShop = PANCAKE.duplicate(true)
		var first := SpecOrderOption.new()
		first.id = "first"
		first.station = "front_counter"
		first.share = 0.5
		var locked := SpecOrderOption.new()
		locked.id = "locked"
		locked.station = "bag"
		locked.share = 1.0
		var last := SpecOrderOption.new()
		last.id = "last"
		last.station = "roll"
		last.share = 0.5
		spec.order_options.assign([first, locked, last])
		var r := ShopRules.new(spec, 42)
		_open_single(r)
		r.unlocked.bag = open_option
		var oracle := RandomNumberGenerator.new()
		oracle.state = r.rng.state
		for n in 3:
			var expected := _expected_single(r, oracle)
			r._spawn_single()
			check_eq([r.customers.back().options, r.rng.state], [expected.options, oracle.state], "option definition-order draws with locked station " + str(open_option))

func test_rules_fixed_exponential_and_flyer_first_rng() -> void:
	for mode in ["fixed", "exponential"]:
		var spec: SpecShop = PANCAKE.duplicate(true)
		spec.fulfillment.arrival = mode
		var r := ShopRules.new(spec, 42)
		_open_single(r)
		r._next_customer = 0.0
		r.flyer_left = 1
		r.flyer_timer = 0.0
		var oracle := RandomNumberGenerator.new()
		oracle.state = r.rng.state
		var flyer := _expected_single(r, oracle)
		var deadline := r.customer_interval()
		if mode == "exponential": deadline = -log(1.0 - oracle.randf() * 0.999) * deadline
		var normal := _expected_single(r, oracle)
		r._arrivals_single()
		check_eq([r.customers[0].kind, r.customers[0].addon, r.customers[0].options], [flyer.kind, flyer.addon, flyer.options], "flyer sampled first " + mode)
		check_eq([r.customers[1].kind, r.customers[1].addon, r.customers[1].options], [normal.kind, normal.addon, normal.options], "normal sampled after interval " + mode)
		check_eq([r._next_customer, r.rng.state, r.flyer_left, r.flyer_timer], [deadline, oracle.state, 0, spec.flyer.gap], "exact interval draw order " + mode)
		# Both arrivals reject, but exponential still consumes its interval draw.
		r.queue.resize(r.queue_capacity())
		r.flyer_left = 1
		r._next_customer = 0.0
		r.flyer_timer = 0.0
		if mode == "exponential": oracle.randf()
		r._arrivals_single()
		check_eq([r.rng.state, r.lost], [oracle.state, 2], "rejected arrival clock RNG " + mode)

func test_rules_handoff_closed_zero_weight_rng_and_admission_clock() -> void:
	var r := ShopRules.new(TEA, 42)
	var before := r.rng.state
	r._add_order()
	check_eq([r.orders, r.rng.state], [[], before], "closed handoff no draw")
	r.gold = 1000000.0
	r.unlock(r.next_unlock())
	var spec: SpecShop = TEA.duplicate(true)
	for stage in spec.stages: stage.order_weights.clear()
	var zero := ShopRules.new(spec, 42)
	zero.gold = 1000000.0
	zero.unlock(zero.next_unlock())
	var zero_rng := zero.rng.state
	zero._add_order()
	check_eq([zero.orders, zero.rng.state], [[], zero_rng], "zero weights reject without draw")
	var oracle := RandomNumberGenerator.new()
	oracle.state = r.rng.state
	# The first open tea stage has one defined dish; independent one sample.
	oracle.randf()
	var admitted := []
	var listener := func(event: Dictionary) -> void: admitted.append([event.dish, r.orders.size(), r._next_order, r.orders.back().wait, r.rng.state])
	r.events.on("arrived", listener)
	r._add_order()
	r.events.off("arrived", listener)
	check_eq(admitted, [["lemonade", 4, 5, 0.0, oracle.state]], "handoff admission precedes callback")
	r._order_clock = r._order_interval()
	r.orders.resize(r.queue_capacity())
	# Keep real rows for the wait loop and force only capacity rejection.
	for n in r.orders.size():
		if r.orders[n] == null: r.orders[n] = {"id": n + 10, "wait": 0.0, "reserved": true, "dish": "lemonade", "takeaway": false, "seat": -1}
	var state_before := r.rng.state
	r._tick_handoff()
	check_eq([r._order_clock, r.rng.state], [0.0, state_before], "deadline reset before full capacity check")

func test_rules_claim_before_steps_chore_and_take_quote_order() -> void:
	var r := ObserveRules.new(PANCAKE, 42)
	r.customers = [_row(17)]
	r.queue = [17]
	var w: Dictionary = r.workers[0]
	check(r._find_job_single(w), "real worker claims queue head")
	check_eq(r.observations[0], ["chore", false], "chores-first query before claim")
	check_eq(r.observations[1], ["steps", true, -1, [17]], "claim before recipe and worker assignment")
	w.steps = [{"action": "take"}, {"action": "hand"}]
	w.step = 0
	w.phase = "work"
	r._finish_work_single(w)
	check_eq(r.observations.back(), ["quote", [], "queue", float(PANCAKE.start_gold)], "take dequeues before price query")
	check_eq([r.customers[0].state, r.customers[0].paid], ["paid", 17], "real accept uses static transition")
	var spec: SpecShop = PANCAKE.duplicate(true)
	spec.dispatch.chores_first = true
	var chore := ObserveRules.new(spec, 42)
	chore.customers = [_row(1)]
	chore.queue = [1]
	chore._find_job_single(chore.workers[0])
	check_eq(chore.observations[0], ["chore", false], "chores query precedes claiming")

func test_rules_reserve_cancel_and_sale_callback_current_order_removal() -> void:
	var r := ReserveRules.new(TEA, 42)
	r.orders = [{"id": 17, "seat": 2, "takeaway": false, "reserved": false, "dish": "lemonade", "wait": 0.0}]
	var original: Dictionary = r.orders[0]
	r.shelf_stock.lemonade = 1
	r.shelf_count = 1
	var worker: Dictionary = r.workers[0]
	var job := {"kind": "serve", "item": "lemonade", "count": 1, "order_id": 17, "src": "shelf", "dst": "counter"}
	r._reserve(worker, job)
	check_eq(r.observations[0], ["walk", 1, true, "serve"], "inventory reserve then order reservation then assignment/walk")
	r._cancel_job(worker)
	check_eq([r.shelf_reserved_out, original.reserved, worker.job, worker.phase], [0, false, {}, "idle"], "cancel inventory and reservation before worker cleanup")
	worker.job = job
	worker.phase = "dropoff"
	worker.action_left = 0.05
	worker.carry_item = "lemonade"
	worker.carry_count = 1
	var replaced := [original.duplicate(), original.duplicate()]
	var observed := []
	var listener := func(_event: Dictionary) -> void:
		observed.append([r.orders.size(), worker.job.order_id, worker.carry_count])
		r.orders = replaced
	r.events.on("sale", listener)
	r._update_worker(worker)
	r.events.off("sale", listener)
	check_eq(observed, [[1, 17, 1]], "sale sees current order and worker before removal/cleanup")
	check_eq([replaced.size(), worker.job, worker.carry_count], [1, {}, 0], "remove first from callback-replaced array before cleanup")
