extends "res://tests/test_case.gd"

const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
const PANCAKE: SpecShop = preload("res://content/shops/pancake/shop.tres")
const NOODLE: SpecShop = preload("res://tests/fixtures/noodle/shop.tres")
const Session := preload("res://game/app/shop_session.gd")
const Profile := preload("res://game/app/profile.gd")
var paths: Array[String] = []

func _path(label: String) -> String:
	var path := "user://presentation-%d-%d-%s.json" % [OS.get_process_id(), Time.get_ticks_usec(), label]
	paths.append(path)
	return path

func cleanup() -> void:
	for path in paths:
		for name in DirAccess.get_files_at(path.get_base_dir()):
			if name == path.get_file() or name.begins_with(path.get_file() + "."):
				DirAccess.remove_absolute(path.get_base_dir().path_join(name))

func _ready(definition: SpecShop) -> ShopRules:
	var rules := ShopRules.new(definition, 9)
	rules.gold = 1e8
	for stage in definition.stages:
		if not rules.station_unlocked(stage.stations[0]):
			check_eq(rules.execute_command("unlock", {"id": stage.stations[0]}).code, "ok", "fixture unlock")
	for key in rules.boxes:
		if not rules.boxes[key]: check_eq(rules.execute_command("unlock_box", {"material": key}).code, "ok", "fixture box")
	for unused in 2:
		if rules.execute_command("hire").code == "ok":
			var id: int = rules.roster.back().id
			rules.execute_command("deploy_worker", {"id": id})
	rules.execute_command("set_tuning", {"key": "walk", "value": 1.137})
	return rules

func _has_data_only(value: Variant) -> bool:
	if value is Object: return false
	if value is Dictionary:
		for key in value:
			if not _has_data_only(key) or not _has_data_only(value[key]): return false
	elif value is Array:
		for entry in value:
			if not _has_data_only(entry): return false
	return true

func _mutate(value: Variant) -> void:
	if value is Dictionary:
		for key in value:
			if value[key] is PackedVector2Array:
				var path: PackedVector2Array = value[key]
				if not path.is_empty(): path[0] = Vector2(-999, -999)
				path.append(Vector2(-999, -999))
				value[key] = path
			else: _mutate(value[key])
		value["_caller_probe"] = true
	elif value is Array:
		for entry in value: _mutate(entry)
		value.append("caller_probe")

func test_control_contract_and_atomic_validation() -> void:
	var rules := ShopRules.new(TEA, 9)
	var before := rules.to_dict()
	check_eq(rules.execute_command("set_paused", {"paused": true}).code, "ok", "canonical pause exists")
	check(rules.paused, "pause committed")
	if not rules.paused: return
	check_eq(rules.execute_command("set_paused", {"paused": false}).params, {"command": "set_paused", "paused": false, "previous": true, "value": false, "changed": true}, "pause outcome")
	check_eq(rules.execute_command("set_tuning", {"key": "work", "value": 1.137}).code, "ok", "raw tuning")
	check_eq(rules.tune.work, 1.137, "raw precision")
	check_eq(rules.execute_command("set_tuning", {"key": "work", "value": 1.137, "snap": true}).params.value, clampf(snappedf(1.137, 0.05), 0.25, 3.0), "exact slider normalization")
	for key in ["seat", "customer", "walk", "work", "price", TEA.stations[0].id]:
		check_eq(rules.execute_command("set_tuning", {"key": key, "value": 1}).code, "ok", "known key")
		check(rules.tune.has(key), "explicit default stored")
		check(not rules.execute_command("set_tuning", {"key": key, "value": 1}).params.changed, "same value unchanged")
	check_eq(rules.execute_command("set_tuning", {"key": "work", "value": -12}).params.value, 0.25, "lower clamp")
	check_eq(rules.execute_command("set_tuning", {"key": "work", "value": 99}).params.value, 3.0, "upper clamp")
	var stable := var_to_bytes(rules.to_dict())
	for args in [{}, {"paused": 1}, {"paused": true, "extra": 1}]:
		check_eq(rules.execute_command("set_paused", args).code, "invalid_argument", "invalid pause")
	for args in [{}, {"key": "work"}, {"key": "unknown", "value": 1}, {"key": "work", "value": true}, {"key": "work", "value": "1"}, {"key": 1, "value": 1}, {"key": "work", "value": NAN}, {"key": "work", "value": INF}, {"key": "work", "value": -INF}, {"key": "work", "value": 1, "snap": 1}, {"key": "work", "value": 1, "extra": 1}]:
		check_eq(rules.execute_command("set_tuning", args).code, "invalid_argument", "invalid tune")
	check_eq(var_to_bytes(rules.to_dict()), stable, "all rejected writes atomic")
	check_eq(rules.events.log, before.log, "controls add no events")
	check_eq(rules.clock, before.clock, "controls preserve clock")

func test_detached_reads_exist() -> void:
	var view := ShopView.new(ShopRules.new(TEA, 9))
	for method in ["render_snapshot", "roster_snapshot", "deployed_snapshot", "worker_snapshot", "customer_snapshot", "deployed_count", "is_deployed", "progress_snapshot", "activity_snapshot", "guide_snapshot", "staff_kind", "art_visible", "post_point", "navigation_point", "walkable", "tuning_limits"]:
		check(view.has_method(method), "read API " + method)

func test_session_dispatch_lifetime() -> void:
	var rules := ShopRules.new(PANCAKE, 9)
	var session := Session.new(null, null, rules)
	check(session.has_method("execute_command"), "session owner dispatch exists")
	if not session.has_method("execute_command"): return
	var before := var_to_bytes(rules.to_dict())
	check_eq(session.call("execute_command", "set_paused", {"paused": true}).code, "session_unavailable", "pre-start rejected")
	check_eq(var_to_bytes(rules.to_dict()), before, "inactive state untouched")
	check_eq(session.start(), ERR_INVALID_PARAMETER, "blocked start")
	check_eq(session.call("execute_command", "set_tuning", {"key": "work", "value": 2}).code, "session_unavailable", "failed start rejected")

func test_render_and_small_projections_detach_every_nested_container_in_three_shops() -> void:
	for definition in [TEA, PANCAKE, NOODLE]:
		var rules := _ready(definition)
		var view := ShopView.new(rules)
		if not view.has_method("render_snapshot"): return
		var work_seen := false
		var path_seen := false
		var queue_seen := false
		for unused in 1200:
			rules.step(0.1)
			queue_seen = queue_seen or rules.queue_size() > 0
			for worker in rules.workers:
				work_seen = work_seen or not worker.job.is_empty() or not worker.steps.is_empty()
				path_seen = path_seen or not worker.path.is_empty()
			if queue_seen and work_seen and path_seen: break
		check(queue_seen and work_seen and path_seen, definition.id + " nonempty queue, jobs/steps and paths")
		var live := var_to_bytes(rules.to_dict())
		var workers := rules.workers
		var worker: Dictionary = workers[0]
		var job: Dictionary = worker.job
		var stations := rules.stations
		var bus := rules.events
		var history := bus.log
		var rng_state := rules.rng.state
		var event_rng_state := rules.event_rng.state
		var frame: Dictionary = view.call("render_snapshot")
		for key in ["clock", "gold", "revenue", "sold", "lost", "paused", "stage_index", "completed_at", "shelf_count", "workers", "roster", "stations", "shelf_stock", "orders", "customers", "queue", "diners", "belts", "belt_items", "seats"]:
			var expected: Variant = rules.get(key)
			if key=="workers" and rules.movement_enabled():
				expected = expected.duplicate(true)
				for row: Dictionary in expected:
					if not row.deployed: continue
					row.speed = rules.walk_speed(row)/definition.layout.motion_units
					row.walking = row.walking and not row.path.is_empty()
			check_eq(frame[key], expected, definition.id + " frame field " + key)
		check_eq(frame.stage_queue_capacity, rules.current_stage().queue_capacity, "stage capacity excludes waiting seats")
		check_eq(frame.workers.map(func(row: Dictionary) -> int: return row.id), rules.workers.map(func(row: Dictionary) -> int: return row.id), "visual iteration order")
		check(not is_same(frame.workers[0], worker), "worker detached")
		check(not is_same(frame.workers[0].stats, worker.stats), "stats detached")
		check(not is_same(frame.workers[0].job, job), "job detached")
		check(not is_same(frame.workers[0].steps, worker.steps), "steps detached")
		check(not is_same(frame.stations, stations), "station map detached")
		var projections: Array = [frame, view.call("roster_snapshot"), view.call("deployed_snapshot"), view.call("worker_snapshot", worker.id), view.call("progress_snapshot"), view.call("activity_snapshot"), view.call("guide_snapshot"), view.call("staff_kind", worker.kind)]
		if not rules.customers.is_empty(): projections.append(view.call("customer_snapshot", rules.customers[0].id))
		for projection in projections:
			check(_has_data_only(projection), "projection contains no Objects")
			_mutate(projection)
		check_eq(var_to_bytes(rules.to_dict()), live, definition.id + " caller mutations leave all live bytes")
		check(is_same(workers, rules.workers) and is_same(worker, rules.workers[0]) and is_same(job, worker.job), "live worker identities retained")
		check(is_same(stations, rules.stations) and is_same(bus, rules.events) and is_same(history, bus.log), "live map/bus/log identities retained")
		check_eq(rules.rng.state, rng_state, "reads preserve simulation RNG")
		check_eq(rules.event_rng.state, event_rng_state, "reads preserve event RNG")
		check_eq(view.call("worker_snapshot", -999), {}, "missing worker")
		check_eq(view.call("customer_snapshot", -999), {}, "missing customer")
		check_eq(view.call("deployed_count"), rules.workers.size(), "deployed count")
		check_eq(view.call("is_deployed", worker.id), true, "known deployed")
		check_eq(view.call("is_deployed", -999), false, "missing undeployed")

func test_retained_snapshots_survive_real_steps_upgrades_and_reset() -> void:
	for definition in [TEA, PANCAKE, NOODLE]:
		var rules := _ready(definition)
		var view := ShopView.new(rules)
		if not view.has_method("render_snapshot"): return
		rules.run(10.0)
		var old: Dictionary = view.call("render_snapshot")
		var progress: Dictionary = view.call("progress_snapshot")
		var old_bytes := var_to_bytes(old)
		var progress_bytes := var_to_bytes(progress)
		rules.run(2.0)
		check(view.call("render_snapshot").clock > old.clock, "new frame sees actual step")
		var upgraded := false
		for key in rules.levels:
			if rules.execute_command("upgrade", {"key": key}).code == "ok":
				check(view.call("progress_snapshot").levels[key] != progress.levels[key], "new progress sees actual upgrade")
				upgraded = true
				break
		check(upgraded, "real upgrade fixture")
		rules.execute_command("set_tuning", {"key": "work", "value": 1.137})
		rules.reset(9)
		check_eq(view.call("render_snapshot").clock, 0.0, "fresh frame observes reset")
		check_eq(view.call("progress_snapshot").tune.work, 1.137, "fresh tuning retained by reset")
		check_eq(var_to_bytes(old), old_bytes, "old frame unchanged across actual mutations")
		check_eq(var_to_bytes(progress), progress_bytes, "old progress unchanged across actual mutations")
		var live := var_to_bytes(rules.to_dict())
		_mutate(old)
		_mutate(progress)
		check_eq(var_to_bytes(rules.to_dict()), live, "retained copies cannot reach replacement state")

func test_activity_guide_and_value_queries_match_actual_rules() -> void:
	for definition in [TEA, PANCAKE, NOODLE]:
		var rules := _ready(definition)
		rules.run(25.0)
		var view := ShopView.new(rules)
		if not view.has_method("activity_snapshot"): return
		for customer in rules.waiting_customers(): customer.wait = 10000.0
		var activity: Dictionary = view.call("activity_snapshot")
		for key in ["clock", "stage_index", "gold", "revenue", "sold", "lost"]: check_eq(activity[key], rules.get(key), "activity " + key)
		check_eq(activity.queue, rules.queue_size(), "actual queue")
		check_eq(activity.queue_capacity, rules.queue_capacity(), "actual capacity")
		check_eq(activity.angry_count, rules.angry_count(), "actual mood count")
		check_eq(activity.idle_count, rules.workers.filter(func(row: Dictionary) -> bool: return rules.worker_idle(row)).size(), "actual idle count")
		check_eq(activity.staff_count, rules.workers.size(), "actual staff count")
		check_eq(activity.seat_count, rules.seat_count(), "actual seat count")
		check_eq(activity.seats_used, rules.seats_used(), "actual seats used")
		check_eq(activity.customer_interval, rules.customer_interval(), "actual interval")
		check_eq(activity.machine_working.keys(), rules.pots + rules.autos, "actual machine IDs and order")
		for id in activity.machine_working: check_eq(activity.machine_working[id], rules.machine_working(id), "actual machine busy")
		var guide: Dictionary = view.call("guide_snapshot")
		check_eq(guide.any_angry, rules.angry_count() > 0, "guide current mood")
		check_eq(guide.staff_count, rules.workers.size(), "guide staff")
		check_eq(guide.lost, rules.lost, "guide lost")
		check(not String(guide.slow_machine).is_empty(), "slow machine fallback")
		var kind: Dictionary = view.call("staff_kind", "missing")
		check_eq(kind.id, definition.staff.kinds[0].id, "existing kind fallback")
		check_eq(kind.stats, definition.staff.kinds[0].stats, "kind stats")
		check_eq(view.call("tuning_limits"), {"min": 0.25, "max": 3.0, "step": 0.05}, "central metadata")
		check_eq(view.call("navigation_point", rules.counter_id), rules.nav.point(rules.counter_id), "nav point")
		check_eq(view.call("post_point", rules.counter_id), rules.nav.post(rules.counter_id), "post point")
		check_eq(view.call("navigation_point", "missing"), Vector2.ZERO, "missing point fallback")
		var point := rules.nav.point(rules.counter_id)
		check_eq(view.call("walkable", point, point), rules.nav.walkable(point, point), "walkable value")
		check_eq(view.call("art_visible", "always"), true, "always art")
		check_eq(view.call("art_visible", "box:missing"), false, "missing box art")
		check_eq(view.call("art_visible", "belt:missing"), false, "missing belt art")
		check_eq(view.call("art_visible", "flavor:missing"), false, "missing flavor art")
		check_eq(view.call("art_visible", "ingredient_box"), rules.boxes.values().has(true), "ingredient art")
		check_eq(view.call("art_visible", "wait_seats:1"), rules.wait_seats() >= 1, "waiting seat art")
		for station in definition.stations: check_eq(view.call("art_visible", station.id), rules.station_unlocked(station.id), "station art")

func test_controls_preserve_active_timing_and_legacy_entries() -> void:
	for definition in [TEA, PANCAKE, NOODLE]:
		var rules := _ready(definition)
		rules.run(10)
		rules.tune.legacy_saved_key = 1.123
		var before := rules.to_dict()
		if rules.execute_command("set_paused", {"paused": true}).code != "ok":
			check(false, "pause exists")
			return
		rules.step(20)
		check_eq(rules.clock, before.clock, "paused simulation does not advance")
		rules.execute_command("set_tuning", {"key": "work", "value": 1.137})
		rules.execute_command("set_paused", {"paused": false})
		var expected := before.duplicate(true)
		expected.tune.work = 1.137
		check_eq(rules.to_dict(), expected, "controls preserve every active timer/job/event and legacy key")
		rules.step(0.1)
		check(rules.clock > before.clock, "resume advances")

func test_active_session_commands_keep_diagnostics_and_sealed_sessions_reject() -> void:
	for departure in ["finish", "jump"]:
		var profile := Profile.new(_path(departure + "-profile"))
		var store := ShopSave.new(PANCAKE, _path(departure + "-shop"))
		var rules := ShopRules.new(PANCAKE, 9)
		var session := Session.new(profile, store, rules)
		if not session.has_method("execute_command"): return
		store.last_error = "retained startup warning"
		check_eq(session.start(), OK, "active start")
		check_eq(session.call("execute_command", "set_paused", {"paused": true}).code, "ok", "active pause")
		check_eq(session.last_error, "retained startup warning", "success preserves startup warning")
		check_eq(session.call("execute_command", "set_tuning", {"key": "work", "value": 1.137}).code, "ok", "active tune")
		check_eq(session.last_error, "retained startup warning", "tune preserves startup warning")
		check_eq(session.call("execute_command", "unlock", {"id": PANCAKE.goals.opening_station}).code, "ok", "business forwarding")
		check_eq(session.last_error, "retained startup warning", "business preserves warning")
		session.last_error = "retained persistence failure"
		check_eq(session.call("execute_command", "set_tuning", {"key": "price", "value": 1}).code, "ok", "command after failure")
		check_eq(session.last_error, "retained persistence failure", "successful command preserves persistence diagnostic")
		check_eq(session.restart(), OK, "restart")
		check(not rules.paused and rules.tune.work == 1.137, "restart resumes and keeps tuning")
		if departure == "finish": check_eq(session.finish({"shop": "pancake", "seconds": 1.0}), OK, "commit finish")
		else: check_eq(session.jump("tea"), OK, "commit jump")
		var before := var_to_bytes(rules.to_dict())
		for command in ["set_paused", "set_tuning", "hire"]:
			check_eq(session.call("execute_command", command).code, "session_unavailable", "departed owner rejects " + command)
		check_eq(var_to_bytes(rules.to_dict()), before, "departed rules unchanged")

func test_guide_preserves_seat_staff_machine_priorities_and_slow_order_selection() -> void:
	var single := _ready(PANCAKE)
	var view := ShopView.new(single)
	if not view.has_method("guide_snapshot"): return
	var group := single.buy_group()
	check(group != null and group.purpose == "wait", "single waiting-seat fixture")
	check_eq(view.call("guide_snapshot").seats_owned, single.seats[group.id], "owned seats uses purchased count")
	check_eq(view.call("guide_snapshot").angry_cause, "seats", "single seats have first priority")
	while single.seat_cost() >= 0: single.execute_command("buy_seat")
	single.workers.clear()
	check_eq(view.call("guide_snapshot").angry_cause, "staff", "single staff has next priority")
	while single.workers.size() < single.staff_slots(): single.workers.append(single.roster[0])
	check_eq(view.call("guide_snapshot").angry_cause, "machine", "single machine fallback")
	var dish := PANCAKE.dishes[0]
	single.customers = [{"id": 4242, "kind": dish.id, "wait": 0.0}]
	single.queue = [4242]
	var expected := single.counter_id
	for step in dish.steps:
		var station := PANCAKE.station(step.station)
		if station != null and not station.tracks.is_empty() and single.station_unlocked(station.id):
			expected = station.id
			break
	check_eq(view.call("guide_snapshot").slow_machine, expected, "single oldest queue first upgradeable step")
	var handoff := _ready(TEA)
	view = ShopView.new(handoff)
	handoff.orders.clear()
	check_eq(view.call("guide_snapshot").angry_cause, "", "handoff needs an angry order")
	var kitchen_dish: String = handoff.kitchen_dishes[0]
	handoff.orders = [{"id": 1, "dish": handoff.front_dishes[0], "wait": 1.0, "takeaway": true}, {"id": 2, "dish": kitchen_dish, "wait": 10000.0, "takeaway": false}]
	var dine := handoff.dine_group()
	check(dine != null, "dining fixture")
	handoff.seats[dine.id] = dine.start
	for index in handoff.seat_total(): handoff.diners.append({"seat": index})
	check_eq(view.call("guide_snapshot").angry_cause, "seats", "angry dine-in seats first")
	handoff.orders[1].takeaway = true
	handoff.workers.clear()
	check_eq(view.call("guide_snapshot").angry_cause, "staff", "handoff vacant staff next")
	while handoff.workers.size() < handoff.staff_slots(): handoff.workers.append(handoff.roster[0])
	check_eq(view.call("guide_snapshot").angry_cause, "machine", "handoff machine fallback")
	check_eq(view.call("guide_snapshot").slow_machine, handoff.chains[kitchen_dish][0], "oldest order selects first kitchen chain machine")

func test_session_rechecks_changed_configuration_before_dispatch() -> void:
	var profile := Profile.new(_path("recheck-profile"))
	var rules := ShopRules.new(PANCAKE, 9)
	var session := Session.new(profile, ShopSave.new(PANCAKE, _path("recheck-shop")), rules)
	if not session.has_method("execute_command"): return
	check_eq(session.start(), OK, "valid initial configuration")
	session.persist_tuning = true
	var before := var_to_bytes(rules.to_dict())
	check_eq(session.call("execute_command", "set_paused", {"paused": true}).code, "session_unavailable", "changed destination configuration blocks")
	check_eq(var_to_bytes(rules.to_dict()), before, "bad configuration cannot mutate rules")
	session.persist_tuning = false
	profile.shop = "tea"
	check_eq(session.call("execute_command", "set_tuning", {"key": "work", "value": 2}).code, "session_unavailable", "changed profile blocks")
	check_eq(var_to_bytes(rules.to_dict()), before, "mismatched owner cannot mutate rules")
