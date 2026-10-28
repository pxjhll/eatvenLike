extends "res://tests/test_case.gd"
## These tests exercise actual stock, routes and employee actions, without old saves.

func new_session():
	if not ResourceLoader.exists("res://game/tea_playtest/tea_playtest_sim.gd"):
		check(false, "playtest session simulation exists")
		return null
	return load("res://game/tea_playtest/tea_playtest_sim.gd").new()

func run_checked(sim, seconds: float, toggle: bool = false) -> void:
	for tick in int(seconds * 10):
		if toggle and tick % 113 == 0:
			sim.set_belts(not sim.use_belts)
		sim.advance(0.1)
		var report: Dictionary = sim.audit()
		if not report.valid:
			check(false, "stock and reservation invariants at %.1fs: %s" % [sim.elapsed, report])
			return

func test_one_worker_completes_the_real_chain_in_both_modes() -> void:
	for belts in [false, true]:
		var sim = new_session()
		if sim == null: return
		sim.set_belts(belts)
		var saw_carry := false
		var saw_belt := false
		for tick in 3000:
			sim.advance(0.1)
			saw_carry = saw_carry or sim.workers[0].carry_count > 0
			saw_belt = saw_belt or not sim.belt_items.is_empty()
			if sim.sold >= 2: break
		check(sim.sold >= 2, "one worker supplies, processes and serves cups")
		check(saw_carry, "cups exist in worker hands during walks")
		check_eq(saw_belt, belts, "belt mode produces visible in-flight goods")
		check_eq(sim.gold, 60 + sim.sold * 12, "only completed service earns gold")
		check(sim.audit().valid, "single-worker conservation")

func test_multiworker_stock_and_capacity_survive_route_toggles() -> void:
	for belts in [false, true]:
		var sim = new_session()
		if sim == null: return
		sim.gold = 500
		check(sim.hire() and sim.hire(), "two additional workers hired")
		sim.set_belts(belts)
		run_checked(sim, 600, true)
		check(sim.sold > 10, "three employees continue completing orders")
		for worker in sim.workers:
			check(worker.completed > 0, "every employee contributes")
		check_eq(sim.workers.size(), 3, "team remains capped")
		check(not sim.hire(), "fourth employee cannot be hired")

func test_training_changes_specialty_and_charges_gold() -> void:
	var sim = new_session()
	if sim == null: return
	var before: int = sim.gold
	var price: int = sim.hire_cost()
	check(sim.hire(), "initial cash hires second employee")
	check_eq(sim.gold, before - price, "hire charges displayed cost")
	sim.gold = 500
	check(sim.hire(), "third employee hired")
	for worker in sim.workers:
		var old_speed: float = worker.speed
		var old_capacity: int = worker.capacity
		var old_skill: float = worker.skill
		before = sim.gold
		price = sim.train_cost(worker.id)
		check(sim.train(worker.id), "training succeeds")
		check_eq(sim.gold, before - price, "training charges displayed cost")
		match worker.role:
			"speed": check(worker.speed > old_speed, "cat training increases real walking speed")
			"carry": check(worker.capacity > old_capacity, "raccoon training increases real carry batch")
			"skill": check(worker.skill > old_skill, "fox training increases actual work speed")
	check(not sim.train(999), "unknown employee is rejected")
	sim.gold = 0
	check(not sim.train(sim.workers[0].id), "training cannot spend unavailable money")

func test_soft_fatigue_keeps_real_speed_and_recovers_while_idle() -> void:
	var sim = new_session()
	if sim == null: return
	var worker: Dictionary = sim.workers[0]
	var original_speed: float = worker.speed
	var original_skill: float = worker.skill
	worker.fatigue = 1.0
	sim.advance(0.1)
	check(worker.phase != "idle", "fatigue never refuses single-worker tasks")
	check_eq(worker.speed, original_speed, "fatigue does not change speed stat")
	check_eq(worker.skill, original_skill, "fatigue does not change skill stat")
	var start: Vector2 = worker.pos
	sim.advance(0.1)
	check(absf(worker.pos.distance_to(start) - original_speed * 0.1) < 0.01,
		"fatigue does not slow real movement")
	# An idle staff member in a fully reserved/full line recovers naturally.
	var idle = new_session()
	idle.workers[0].fatigue = 0.8
	idle.stations.boil.input.raw = 3
	idle.stations.boil.processing = 3
	idle.stations.boil.remaining = 100.0
	idle.stations.boil.duration = 100.0
	idle.stations.boil.phase = "heating"
	idle.advance(1.0)
	check(idle.workers[0].fatigue < 0.8, "idle time recovers fatigue")

func test_pause_and_fixed_steps_preserve_session_state() -> void:
	var sim = new_session()
	if sim == null: return
	sim.paused = true
	sim.advance(30)
	check_eq(sim.elapsed, 0.0, "paused session does not advance")
	sim.paused = false
	sim.advance(0.04)
	check_eq(sim.elapsed, 0.0, "fractional time waits for fixed step")
	sim.advance(0.06)
	check(absf(sim.elapsed - 0.1) < 0.0001, "fractional calls combine into one fixed step")

func test_switching_modes_keeps_in_flight_belt_delivery() -> void:
	var sim = new_session()
	if sim == null: return
	sim.set_belts(true)
	for tick in 3000:
		sim.advance(0.1)
		if not sim.belt_items.is_empty(): break
	check(not sim.belt_items.is_empty(), "actual belt shipment created")
	sim.set_belts(false)
	run_checked(sim, 300)
	check(sim.sold > 0, "old belt shipment and later manual jobs complete")
	check(sim.belt_items.is_empty(), "no future belt jobs after manual mode drains")

func test_each_transport_mode_keeps_long_run_stock_and_reservations_valid() -> void:
	for belts in [false, true]:
		var sim = new_session()
		if sim == null: return
		sim.gold = 500
		sim.hire()
		sim.hire()
		sim.set_belts(belts)
		run_checked(sim, 900)
		check(sim.sold > 20, "long run stays productive in each logistics mode")

func test_toggling_before_pickup_does_not_rewrite_reserved_belt_job() -> void:
	var sim = new_session()
	if sim == null: return
	for tick in 3000:
		sim.advance(0.1)
		var job: Dictionary = sim.workers[0].job
		if not job.is_empty() and job.belt == "topping_to_seal": break
	var job: Dictionary = sim.workers[0].job
	check(not job.is_empty() and job.belt == "topping_to_seal", "worker reserved a conveyor route")
	sim.set_belts(false)
	var saw_committed_belt := false
	for tick in 300:
		sim.advance(0.1)
		saw_committed_belt = saw_committed_belt or not sim.belt_items.is_empty()
		check(sim.audit().valid, "route commitment keeps stock reserved")
	check(saw_committed_belt, "already assigned job still loads conveyor after toggle")

func test_training_changes_real_trip_batches_movement_and_work_duration() -> void:
	var sim = new_session()
	if sim == null: return
	sim.advance(0.1)
	var cat: Dictionary = sim.workers[0]
	var old_speed: float = cat.speed
	check(sim.train(cat.id), "cat trained during an actual walk")
	var start: Vector2 = cat.pos
	sim.advance(0.1)
	check(cat.pos.distance_to(start) > old_speed * 0.1, "trained speed affects an existing trip")
	var work_durations: Array = []
	var picked_batches: Array = []
	for training in [false, true]:
		var session = new_session()
		session.gold = 500
		session.hire()
		session.hire()
		var raccoon: Dictionary = session.workers[1]
		if training: session.train(raccoon.id)
		# Isolate one real worker to compare the same actual supply route.
		session.workers = [raccoon]
		for tick in 300:
			session.advance(0.1)
			if raccoon.carry_count > 0: break
		picked_batches.append(raccoon.carry_count)
		var prep = new_session()
		prep.gold = 500
		prep.hire()
		prep.hire()
		var fox: Dictionary = prep.workers[2]
		if training: prep.train(fox.id)
		prep.workers = [fox]
		# A controlled downstream fixture isolates actual manual topping time.
		prep.stations.topping.input.milk_tea = 2
		fox.pos = preload("res://content/tea/art_playtest_layout.gd").POINTS.topping
		for tick in 100:
			prep.advance(0.1)
			if fox.phase == "work": break
		var began: float = prep.elapsed
		for tick in 100:
			prep.advance(0.1)
			if fox.completed > 0: break
		work_durations.append(prep.elapsed - began)
	check_eq(picked_batches, [3, 4], "raccoon training carries four real units instead of three")
	check(work_durations[1] < work_durations[0], "fox training completes the same topping batch sooner")

func test_allocation_considers_path_and_soft_fatigue() -> void:
	for prefer_close in [true, false]:
		var sim = new_session()
		if sim == null: return
		sim.gold = 500
		sim.hire()
		var cat: Dictionary = sim.workers[0]
		var raccoon: Dictionary = sim.workers[1]
		cat.pos = preload("res://content/tea/art_playtest_layout.gd").POINTS.supply
		raccoon.pos = cat.pos if not prefer_close else preload("res://content/tea/art_playtest_layout.gd").POINTS.counter
		raccoon.speed = cat.speed
		raccoon.capacity = cat.capacity
		cat.fatigue = 0.0 if prefer_close else 1.0
		# Four occupied slots leave exactly one two-unit task to choose between staff.
		sim.stations.boil.input.raw = 4
		sim.advance(0.1)
		check_eq(cat.phase != "idle", prefer_close, "near staff wins route choice; rested staff wins equal routes")
		check_eq(raccoon.phase != "idle", not prefer_close, "allocation shares one atomic task without duplicate pickup")

func test_empty_topping_clears_ready_after_real_pickup_and_preserves_work_phase() -> void:
	var sim = new_session()
	if sim == null: return
	var saw_work := false
	var saw_empty_pickup := false
	for tick in 1500:
		sim.advance(0.1)
		var station: Dictionary = sim.stations.topping
		var worker: Dictionary = sim.workers[0]
		check(sim.audit().valid, "actual production and pickup retain stock reservations")
		if worker.phase == "work":
			saw_work = true
			check_eq(station.phase, "working", "active manual topping retains working phase")
		if worker.carry_item == "topped" and worker.carry_count > 0 and station.input.milk_tea == 0 and station.output.topped == 0:
			saw_empty_pickup = true
			check_eq(station.phase, "idle", "picking the final prepared cups clears empty topping readiness")
			check_eq(station.progress, 0.0, "empty station does not retain completed work progress")
			break
	check(saw_work, "single worker actually performed manual topping")
	check(saw_empty_pickup, "single worker actually removed the final prepared cups")
