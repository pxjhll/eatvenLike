extends RefCounted
## One-time legacy serve adoption. Never called by normal movement ticks.
const Flow := preload("res://game/rules/serve_flow.gd")

static func _nearest(rules: ShopRules, at: Vector2, goal: Vector2, profile: String) -> Vector2:
	if rules.nav.can_stand(at,profile) and not rules.nav.path(at,goal,profile).is_empty(): return at
	# A valid authored port may fit between furniture even when no grid center
	# does. Include it so legacy coordinates cannot discard otherwise valid work.
	var candidates: Array = [{"point":goal,"distance":goal.distance_squared_to(at)}]
	var data := rules.shop.layout
	for y in data.grid_size.y:
		for x in data.grid_size.x:
			var point := (Vector2(x,y)+Vector2.ONE*0.5)*data.cell
			candidates.append({"point":point,"distance":point.distance_squared_to(at)})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if a.distance!=b.distance: return a.distance<b.distance
		if a.point.y!=b.point.y: return a.point.y<b.point.y
		return a.point.x<b.point.x)
	for row: Dictionary in candidates:
		if rules.nav.can_stand(row.point,profile) and not rules.nav.path(row.point,goal,profile).is_empty(): return row.point
	return Vector2.INF

static func workers(rules: ShopRules) -> String:
	for worker: Dictionary in rules.workers:
		var mode := rules.shop.fulfillment.handoff
		var role := Flow.role(rules,worker) if mode=="serve" else "staff"
		var profile := role if rules.shop.layout.actor_areas.has(role) else "staff"
		var job: Dictionary = Flow.job_of(rules,worker) if mode=="serve" else worker.job
		var goal := rules.nav.post(worker.post) if not String(worker.post).is_empty() else rules.nav.point(rules.shop.layout.spawn_point)
		var active: bool = not job.is_empty()
		if not job.is_empty():
			if mode=="serve":
				if job.stage=="home": goal = rules.nav.post(worker.post)
				else: goal = Flow._point(rules,String(job.to if job.stage in ["go_to","drop"] else job.from))
			else: goal = rules._destination_point(job) if worker.phase in ["walk_dropoff","dropoff"] else rules._source_point(job)
		elif mode=="single":
			active = worker.order>=0 or not worker.chore.is_empty() or worker.walking
			if not worker.chore.is_empty(): goal = rules.nav.point(worker.chore.get_slice(":",1))
			elif worker.order>=0: goal = rules.nav.point(worker.steps[worker.step].point)
			else: goal = rules.nav.point(rules.shop.staff.home_anchor)
		if not rules.nav.can_stand(goal,profile): return "movement adoption: current action port is not reachable"
		if not worker.walking and active:
			# Legacy hand timers are already running at the old authored port.
			worker.pos = goal
		else:
			var start := _nearest(rules,worker.pos,goal,profile)
			if not start.is_finite(): return "movement adoption: no legal position connects to the current action"
			worker.pos = start
		if worker.walking: rules.begin_move(worker,goal,worker.phase)
		else:
			worker.path = PackedVector2Array([worker.pos])
			worker.path_index = 1
	return ""
