extends RefCounted
## Candidate arithmetic and selection; live queries and reservations belong to Rules.

static func transport_candidate(kind: String, source: String, destination: String, item: String,
		carry_count: int, available_count: int, free_count: int, priority: float, belt: String = "") -> Dictionary:
	var count := mini(carry_count, mini(available_count, free_count))
	if count <= 0: return {}
	return {"kind": kind, "src": source, "dst": destination, "item": item, "count": count, "priority": priority, "belt": belt, "order_id": -1}


static func serve_candidate(job: Dictionary, order: Dictionary, pour: String, dispatch: SpecDispatch) -> Dictionary:
	job.count = 1
	job.order_id = order.id
	job.pour = pour
	job.priority += wait_bonus(dispatch, order.wait)
	return job


static func exact_count(job: Dictionary, count: int) -> Dictionary:
	if job.is_empty() or job.count < count: return {}
	job.count = count
	return job


static func wait_bonus(dispatch: SpecDispatch, wait: float) -> float:
	return minf(dispatch.wait_bonus_cap, wait * dispatch.wait_bonus_per_second)


static func score(dispatch: SpecDispatch, worker: Dictionary, job: Dictionary, travel: float, work_time: float) -> float:
	var throughput: float = float(job.count) / maxf(0.1, travel + work_time)
	return (job.priority + throughput * dispatch.throughput_weight - travel * dispatch.travel_penalty) * (1.0 - worker.fatigue * dispatch.fatigue_weight)


static func consider(best: Dictionary, worker: Dictionary, job: Dictionary, value: float) -> void:
	if value > best.score:
		best.score = value
		best.worker = worker
		best.job = job


static func route_choice(options: Array, source: String, destination: String) -> Dictionary:
	var best: Dictionary = {}
	for job in options:
		if job.is_empty() or job.src != source or job.dst != destination: continue
		if best.is_empty() or job.priority > best.priority: best = job
	return best


static func fallback_pot_choice(options: Array) -> Dictionary:
	var best: Dictionary = {}
	for option in options:
		if not option.is_empty() and (best.is_empty() or option.priority > best.priority): best = option.duplicate()
	return best
