extends "res://tests/test_case.gd"

const Sim := preload("res://game/tea_playtest/tea_playtest_sim.gd")
const Layout := preload("res://content/tea/art_playtest_layout.gd")

func session(team: int = 1):
	var sim = Sim.new()
	sim.gold = 500
	for unused in team - 1: sim.hire()
	return sim

func checked_run(sim, seconds: float) -> void:
	for unused in int(seconds * 10):
		sim.advance(0.1)
		var report: Dictionary = sim.audit()
		if not report.valid:
			check(false, "assignment preserves inventory and reservations: %s" % report)
			return

func test_post_assignment_and_release_walk_without_teleporting() -> void:
	var sim = session()
	check(sim.has_method("assign_post"), "simulation exposes post assignment")
	if not sim.has_method("assign_post"): return
	var worker: Dictionary = sim.workers[0]
	var start: Vector2 = worker.pos
	check_eq(sim.assign_post(worker.id, "topping"), "", "idle assignment accepted")
	check_eq(worker.pos, start, "assignment never teleports")
	check(worker.assignment_pending and worker.walking, "assignment walks before becoming available")
	checked_run(sim, 15)
	check_eq(worker.pos, Layout.POST_POINTS.topping, "idle operator waits at its operation point")
	check_eq(worker.phase, "idle", "a sole seated operator cannot perform mobile hauling")
	var destination := Vector2(390, 750)
	check_eq(sim.assign_post(worker.id, "", destination), "", "mobile release accepted")
	check_eq(worker.pos, Layout.POST_POINTS.topping, "release does not teleport")
	check_eq(worker.task_label, "move_free", "release moves toward floor target")
	for unused in 200:
		sim.advance(0.1)
		if not worker.assignment_pending: break
	check_eq(worker.pos, destination, "release reaches requested floor before taking a job")
	check_eq(worker.post, "", "released worker joins mobile pool")

func test_invalid_and_occupied_assignment_preserve_previous_role() -> void:
	var sim = session(2)
	check(sim.has_method("assign_post"), "simulation exposes post assignment")
	if not sim.has_method("assign_post"): return
	check_eq(sim.assign_post(1, "boil"), "", "boil reserved immediately")
	check_eq(sim.post_owner("boil"), 1, "pending movement owns post")
	check_eq(sim.post_owner("boil", 1), -1, "owner exclusion supports same-worker drops")
	check_eq(sim.assign_post(2, "topping"), "", "other employee owns topping")
	var before: Dictionary = sim.workers[1].duplicate(true)
	check_eq(sim.assign_post(2, "boil"), "occupied_post", "occupied post rejects drop")
	check_eq(sim.assign_post(2, "mix"), "invalid_post", "automatic station rejects seating")
	check_eq(sim.assign_post(2, "", Vector2(10, 10)), "blocked_ground", "outside floor rejects release")
	check_eq(sim.assign_post(2, "", Vector2(NAN, 0)), "blocked_ground", "nonfinite floor rejects release")
	check_eq(sim.assign_post(999, "boil"), "invalid_worker", "missing worker rejected")
	check_eq(sim.workers[1], before, "invalid requests leave complete worker state intact")

func test_seated_manual_posts_work_and_mobile_logistics_continue() -> void:
	for belts in [false, true]:
		for post in ["boil", "topping"]:
			var sim = session(2)
			if not sim.has_method("assign_post"): return
			sim.set_belts(belts)
			check_eq(sim.assign_post(2, post), "", "manual post assignment accepted")
			var saw_operation := false
			for unused in 4000:
				sim.advance(0.1)
				var worker: Dictionary = sim.workers[1]
				if not worker.assignment_pending:
					check_eq(worker.pos, Layout.POST_POINTS[post], "seated employee never cross-station hauls")
					if not worker.job.is_empty():
						saw_operation = true
						check(worker.job.kind in (["brew_start", "brew_take"] if post == "boil" else ["topping"]), "only bound manual operations allowed")
				var mobile: Dictionary = sim.workers[0]
				if not mobile.job.is_empty():
					check(not mobile.job.kind in (["brew_start", "brew_take"] if post == "boil" else ["topping"]), "locked operation excluded before scoring")
				if not sim.audit().valid:
					check(false, "mixed team conservation: %s" % sim.audit())
					break
			check(saw_operation, "seated employee performs useful manual work")
			check(sim.sold > 5, "mixed team continues selling in each transport mode")

func test_three_workers_can_staff_both_posts() -> void:
	for belts in [false, true]:
		var sim = session(3)
		if not sim.has_method("assign_post"): return
		sim.set_belts(belts)
		sim.assign_post(2, "boil")
		sim.assign_post(3, "topping")
		checked_run(sim, 450)
		check(sim.sold > 5, "one courier and two operators complete production")
		check(sim.workers[1].completed > 0 and sim.workers[2].completed > 0, "both seated operators contribute")

func test_carrying_assignment_finishes_delivery_before_moving() -> void:
	var sim = session(2)
	if not sim.has_method("assign_post"): return
	var worker: Dictionary = sim.workers[0]
	for unused in 300:
		sim.advance(0.1)
		if worker.carry_count > 0: break
	check(worker.carry_count > 0, "fixture uses a real carried batch")
	var job: Dictionary = worker.job.duplicate(true)
	var position: Vector2 = worker.pos
	check_eq(sim.assign_post(worker.id, "topping"), "", "busy assignment accepted")
	check_eq(worker.job, job, "atomic delivery remains unchanged")
	check_eq(worker.pos, position, "carried assignment does not teleport")
	check(worker.assignment_pending, "handoff remains pending")
	check_eq(sim.post_owner("topping"), worker.id, "new lock takes effect before delivery finishes")
	for unused in 500:
		sim.advance(0.1)
		check(sim.audit().valid, "carried handoff conserves batch and reservations")
		if not worker.assignment_pending: break
	check_eq(worker.carry_count, 0, "carried batch was delivered before taking post")
	check_eq(worker.pos, Layout.POST_POINTS.topping, "worker physically reaches new post")

func test_working_operator_finishes_atomic_batch_before_release() -> void:
	var sim = session(2)
	if not sim.has_method("assign_post"): return
	sim.assign_post(2, "topping")
	var worker: Dictionary = sim.workers[1]
	for unused in 2000:
		sim.advance(0.1)
		if worker.phase == "work" and worker.job.kind == "topping": break
	check_eq(worker.phase, "work", "real topping batch is in progress")
	var job: Dictionary = worker.job.duplicate(true)
	var done: int = worker.completed
	sim.assign_post(worker.id, "", Vector2(390, 750))
	check_eq(worker.job, job, "active manual operation remains atomic")
	for unused in 100:
		sim.advance(0.1)
		check(sim.audit().valid, "work handoff preserves reservations")
		if worker.completed > done: break
	check_eq(worker.completed, done + 1, "pending release completes manual batch")
	check_eq(worker.task_label, "move_free", "release walks after operation completion")
	check(worker.assignment_pending, "movement remains pending until floor destination")

func test_boil_requires_manual_start_and_manual_take() -> void:
	var sim = session()
	# Separate direct fixture checks ensure raw delivery alone never starts a batch.
	var isolated = session()
	isolated.workers.clear()
	isolated.stations.boil.input.raw = 3
	isolated.advance(20)
	check_eq(isolated.stations.boil.input.raw, 3, "raw waits for manual brew_start")
	check_eq(isolated.stations.boil.processing, 0, "boil is not automatically started")
	isolated.stations.boil.input.raw = 0
	isolated.stations.boil.processing = 3
	isolated.stations.boil.duration = 7.0
	isolated.stations.boil.remaining = 1.0
	isolated.stations.boil.phase = "heating"
	isolated.advance(20)
	check_eq(isolated.stations.boil.processing, 3, "finished batch stays in pot until manual take")
	check_eq(isolated.stations.boil.output.tea, 0, "machine completion cannot bypass manual unload")
	check_eq(isolated.stations.boil.phase, "awaiting_take", "machine advertises pending manual unload")
	var saw_start := false
	var saw_take := false
	for unused in 2000:
		sim.advance(0.1)
		var worker: Dictionary = sim.workers[0]
		saw_start = saw_start or worker.task_label == "brew_start"
		saw_take = saw_take or worker.task_label == "brew_take"
	check(saw_start and saw_take, "mobile worker performs separate manual start and unload operations")
	check(sim.sold > 0 and sim.audit().valid, "single mobile employee retains full conserved workflow")

func test_soft_fatigue_never_unseats_and_full_line_stays_conserved() -> void:
	var sim = session(3)
	if not sim.has_method("assign_post"): return
	sim.assign_post(2, "boil")
	sim.assign_post(3, "topping")
	for worker in sim.workers: worker.fatigue = 1.0
	checked_run(sim, 120)
	check_eq(sim.post_owner("boil"), 2, "fatigue leaves boil lock intact")
	check_eq(sim.post_owner("topping"), 3, "fatigue leaves topping lock intact")
	checked_run(sim, 300)
	check(sim.sold > 0, "fatigued operators keep working")

func test_full_boil_output_waits_without_losing_goods_or_unseating() -> void:
	var sim = session()
	if not sim.has_method("assign_post"): return
	var worker: Dictionary = sim.workers[0]
	for unused in 1000:
		sim.advance(0.1)
		if worker.task_label == "brew_take" and worker.phase == "work": break
	check_eq(worker.task_label, "brew_take", "real completed batch is being unloaded")
	check_eq(sim.assign_post(worker.id, "boil"), "", "mobile operator can seat during manual unload")
	checked_run(sim, 120)
	check_eq(sim.stations.boil.output.tea, 6, "two finished batches wait in bounded output without courier")
	check_eq(worker.phase, "idle", "sole seated worker waits when line is backed up")
	check_eq(worker.pos, Layout.POST_POINTS.boil, "blocked output never moves seated operator elsewhere")
	check_eq(sim.post_owner("boil"), worker.id, "blocked line leaves chosen assignment intact")
	check_eq(sim.assign_post(worker.id, "", Vector2(390, 750)), "", "player can explicitly restore courier work")
	checked_run(sim, 180)
	check(sim.sold > 0, "explicit mobile release drains backed-up output and serves customers")

func test_unreachable_drop_does_not_mutate_assignment() -> void:
	var sim = session()
	if not sim.has_method("assign_post"): return
	var worker: Dictionary = sim.workers[0]
	# A stale position outside the navigable floor cannot reach an otherwise legal post.
	worker.pos = Vector2(10, 10)
	var before: Dictionary = worker.duplicate(true)
	check_eq(sim.assign_post(worker.id, "boil"), "unreachable", "valid destination without route is rejected")
	check_eq(worker, before, "unreachable assignment preserves all worker state")
