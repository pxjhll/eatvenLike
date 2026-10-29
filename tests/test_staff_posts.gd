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

func test_post_assignment_and_release_place_employee_immediately() -> void:
	var sim = session()
	check(sim.has_method("assign_post"), "simulation exposes post assignment")
	if not sim.has_method("assign_post"): return
	var worker: Dictionary = sim.workers[0]
	check_eq(sim.assign_post(worker.id, "topping"), "", "idle assignment accepted")
	check_eq(worker.pos, Vector2(190, 410), "drop immediately places employee at operation point")
	check(not worker.assignment_pending and not worker.walking, "drop has no deferred relocation")
	checked_run(sim, 15)
	check_eq(worker.pos, Layout.POST_POINTS.topping, "idle operator waits at its operation point")
	check_eq(worker.phase, "idle", "a sole seated operator cannot perform mobile hauling")
	var destination := Vector2(390, 750)
	check_eq(sim.assign_post(worker.id, "", destination), "", "mobile release accepted")
	check_eq(worker.pos, destination, "mobile drop immediately places employee at floor target")
	check_eq(worker.phase, "idle", "employee is ready to take fresh work at new location")
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

func test_carrying_assignment_returns_goods_and_places_employee() -> void:
	var sim = session(2)
	if not sim.has_method("assign_post"): return
	var worker: Dictionary = sim.workers[0]
	for unused in 300:
		sim.advance(0.1)
		if worker.carry_count > 0: break
	check(worker.carry_count > 0, "fixture uses a real carried batch")
	var job: Dictionary = worker.job.duplicate(true)
	var carried: int = worker.carry_count
	var completed: int = worker.completed
	var reserved_before: int = sim.stations.boil.reserved_in
	var before: Dictionary = worker.duplicate(true)
	check_eq(sim.assign_post(worker.id, "", Vector2(10, 10)), "blocked_ground", "invalid busy drop is rejected")
	check_eq(worker, before, "rejected drop preserves carrying worker and route")
	check(sim.audit().valid, "rejected busy drop preserves shared reservations")
	check_eq(sim.assign_post(worker.id, "topping"), "", "busy assignment accepted")
	check_eq(job.src, "supply", "fixture carries raw material from unlimited supply")
	check(carried > 0, "fixture has goods to return")
	check_eq(worker.job, {}, "delivery is interrupted immediately")
	check_eq(worker.pos, Vector2(190, 410), "carrying employee lands immediately at chosen post")
	check(not worker.assignment_pending, "no deferred handoff remains")
	check_eq(worker.carry_count, 0, "goods returned to source")
	check_eq(worker.completed, completed, "interruption earns no completed task")
	check_eq(sim.stations.boil.reserved_in, reserved_before - carried, "canceled delivery releases only this employee's destination space")
	check(sim.audit().valid, "return to unlimited supply conserves stock accounting")

func test_working_operator_leaves_inputs_and_releases_post_on_drop() -> void:
	var sim = session(2)
	if not sim.has_method("assign_post"): return
	sim.assign_post(2, "topping")
	var worker: Dictionary = sim.workers[1]
	for unused in 2000:
		sim.advance(0.1)
		if worker.phase == "work" and worker.job.kind == "topping": break
	check_eq(worker.phase, "work", "real topping batch is in progress")
	var input: int = sim.stations.topping.input.milk_tea
	var done: int = worker.completed
	sim.assign_post(worker.id, "", Vector2(390, 750))
	check_eq(worker.job, {}, "manual operation is interrupted")
	check_eq(worker.pos, Vector2(390, 750), "working employee lands on floor immediately")
	check_eq(worker.completed, done, "interrupted work does not complete a batch")
	check_eq(sim.stations.topping.input.milk_tea, input, "unfinished input stays at original station")
	check(not sim.stations.topping.work_reserved, "another worker can claim the abandoned operation")
	check(sim.stations.topping.phase != "working", "abandoned station stops displaying active work")
	check(sim.audit().valid, "operation cancellation preserves inventory and reservations")
	checked_run(sim, 180)
	check(sim.sold > 0, "production resumes after interruption")

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

func test_direct_placement_does_not_require_a_route_from_old_position() -> void:
	var sim = session()
	if not sim.has_method("assign_post"): return
	var worker: Dictionary = sim.workers[0]
	# Picking up an employee can rescue an old invalid position.
	worker.pos = Vector2(10, 10)
	check_eq(sim.assign_post(worker.id, "boil"), "", "direct placement only validates destination")
	check_eq(worker.pos, Vector2(270, 330), "employee is placed at legal operation point")

func test_isolated_floor_rejects_drop_without_interrupting_work() -> void:
	var sim = session()
	sim.advance(1.0)
	var before: Dictionary = sim.workers[0].duplicate(true)
	var isolated := Vector2(410, 1130)
	check_eq(Layout.drop_target(isolated).get("reason", ""), "unreachable", "customer-side floor is not a legal employee drop")
	check_eq(sim.assign_post(1, "", isolated), "unreachable", "simulation rejects floor disconnected from work area")
	check_eq(sim.workers[0], before, "rejected isolated drop preserves active work and cargo")
	check(sim.audit().valid, "rejected drop preserves inventory reservations")

func test_interrupt_every_task_phase_returns_stock_and_releases_reservations() -> void:
	for belts in [false, true]:
		var kinds := ["load_boil", "brew_start", "brew_take", "unload_boil", "transfer_to_topping", "topping", "serve"]
		kinds.append_array(["load_seal_belt", "load_shelf_belt"] if belts else ["carry_to_seal", "carry_to_shelf"])
		for kind in kinds:
			var phases := ["walk_pickup", "work"] if kind in ["brew_start", "brew_take", "topping"] else ["walk_pickup", "pickup", "walk_dropoff", "dropoff"]
			for phase in phases:
				var sim = session()
				sim.set_belts(belts)
				var worker: Dictionary = sim.workers[0]
				for unused in 6000:
					sim.advance(0.1)
					if worker.task_label == kind and worker.phase == phase: break
				check(worker.task_label == kind and worker.phase == phase, "real fixture reached %s/%s" % [kind, phase])
				if worker.task_label != kind or worker.phase != phase: continue
				var job: Dictionary = worker.job.duplicate(true)
				var carried: int = worker.carry_count
				var source_stock := 0
				if job.src == "shelf": source_stock = sim.shelf_count
				elif job.src != "supply": source_stock = sim._stock(sim.stations[job.src])
				var sold_before: int = sim.sold
				check_eq(sim.assign_post(worker.id, "", Vector2(390, 750)), "", "busy floor drop accepted")
				check_eq(worker.pos, Vector2(390, 750), "every task phase lands immediately")
				check(worker.job.is_empty() and not worker.walking and worker.path.is_empty(), "old task and movement are cleared")
				check_eq(worker.carry_count, 0, "no cargo remains after return")
				if kind in ["brew_start", "brew_take", "topping"]:
					check(not sim.stations[job.src].work_reserved, "abandoned manual operation is available again")
				if job.src == "shelf": check_eq(sim.shelf_count, source_stock + carried, "served cup returns to shelf")
				elif job.src != "supply": check_eq(sim._stock(sim.stations[job.src]), source_stock + carried, "cargo returns to source station")
				check(sim.audit().valid, "%s/%s cancellation preserves accounting: %s" % [kind, phase, sim.audit()])
				checked_run(sim, 180)
				check(sim.sold > sold_before, "fresh tasks resume after %s/%s cancellation" % [kind, phase])

func test_carried_goods_keep_source_capacity_available_for_return() -> void:
	for kind in ["unload_boil", "serve"]:
		var sim = session()
		var worker: Dictionary = sim.workers[0]
		for unused in 6000:
			sim.advance(0.1)
			if worker.task_label == kind and worker.phase == "pickup": break
		check_eq(worker.task_label, kind, "real pickup reached")
		var source: String = worker.job.src
		var free_before: int = sim._free(source)
		for unused in 20:
			sim.advance(0.1)
			if worker.carry_count > 0: break
		check(worker.carry_count > 0, "employee is carrying refundable stock")
		check_eq(sim._free(source), free_before, "pickup retains source slots until delivery or return")
		check_eq(sim.assign_post(worker.id, "", Vector2(390, 750)), "", "returning cargo succeeds")
		check(sim.audit().valid, "source capacity and stock remain valid after refund")

func test_repeated_busy_drops_preserve_other_workers_and_keep_selling() -> void:
	for belts in [false, true]:
		var sim = session(3)
		sim.set_belts(belts)
		for tick in 6000:
			sim.advance(0.1)
			if tick % 97 == 0:
				var index: int = (tick / 97) as int % 3
				var worker: Dictionary = sim.workers[index]
				var post: String = "" if index == 0 or not worker.post.is_empty() else ("boil" if index == 1 else "topping")
				check_eq(sim.assign_post(worker.id, post, Vector2(390, 750)), "", "repeated busy placement accepted")
				check(worker.job.is_empty() and worker.carry_count == 0, "each accepted drop cancels only its employee's task")
			if not sim.audit().valid:
				check(false, "repeated drops preserve shared inventory: %s" % sim.audit())
				break
		check(sim.sold > 3, "team still sells through repeated interrupted assignments")
