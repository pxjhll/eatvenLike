extends RefCounted
## Local completion effects. Rules owns inventory, numeric queries and progression.

static func consumes_handoff_source(job: Dictionary) -> bool:
	return job.kind in ["pot_start", "work"]


static func complete_handoff_work(station: Dictionary, job: Dictionary, pot_seconds: float) -> void:
	match job.kind:
		"pot_start":
			station.processing = job.count
			station.duration = pot_seconds
			station.remaining = station.duration
			station.progress = 0.0
			station.phase = "heating"
		"stir":
			station.phase = "heating"
		"pot_take":
			var out: String = station.output.keys()[0]
			station.output[out] += station.processing
			station.processing = 0
			station.phase = "ready"
			station.progress = 1.0
		"work":
			complete_topping(station, job)
			station.phase = "ready"
			station.progress = 1.0
	station.work_reserved = false


static func complete_topping(station: Dictionary, job: Dictionary) -> void:
	if not station.processing_item.is_empty():
		station.output[station.processing_item] += job.count
		station.processing_item = ""
		return
	station.input[job.item] += job.count


static func complete_single_chore(worker: Dictionary, station: Dictionary, load: bool, duration: float, batch: int, capacity: int) -> void:
	if load:
		station.phase = "cook"
		station.duration = duration
		station.remaining = station.duration
	else:
		station.stock = mini(capacity, station.stock + batch)
		station.phase = "idle"
	station.user = -1
	worker.chore = ""


static func advance_single_step(worker: Dictionary, station: Dictionary, exclusive: bool) -> void:
	var step: Dictionary = worker.steps[worker.step]
	if step.action != "take":
		var next_same: bool = worker.step + 1 < worker.steps.size() and String(worker.steps[worker.step + 1].station) == String(step.station)
		if exclusive and not next_same: station.user = -1
		if not String(step.get("holds", "")).is_empty():
			worker.carry_item = step.holds
			worker.carry_count = 1
	worker.step += 1
