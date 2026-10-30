extends "res://tests/test_case.gd"
## 临时：没有传送带、名额按阶段时的客流节奏模拟（分析用，合并前删除）

func _run(intervals: Array, slots: Array, seats: Array = [], per_cup := 2.0, exclusive := true, bonus := 1.0) -> String:
	var sim = load("res://game/tea_playtest/tea_shop_sim.gd").new()
	var topping = sim._definition("topping")
	var saved_cup: float = topping.art_seconds
	topping.art_seconds = per_cup
	var stages: Array = sim.PROGRESSION.stages
	var saved: Array = []
	for i in stages.size():
		saved.append([stages[i].customer_interval, stages[i].staff_slots])
		stages[i].customer_interval = intervals[i]
		stages[i].staff_slots = slots[i]
	sim.unlock_station("lemonade")
	var rows := {}
	var stage := -1
	var row := {}
	for tick in 24000:
		for id in ["boil", "mix", "topping"]:
			if sim.station_info(id).unlock_error.is_empty(): sim.unlock_station(id)
		if sim.roster.size() < sim.staff_slots() and sim.gold >= sim.hire_cost():
			sim.hire()
		for worker in sim.roster:
			if not worker.deployed and sim.deployment_error(worker.id).is_empty(): sim.deploy_worker(worker.id)
		if sim.stage_index == 3 and sim.station_levels.topping < 4 and sim.station_info("topping").upgrade_error.is_empty(): sim.upgrade_station("topping")
		if tick % 10 == 0:
			for post in seats:
				if sim.stage_index < (1 if post == "boil" else 3) or not sim.station_unlocked(post) or sim.post_owner(post) != -1: continue
				# From the topping stage on, seat the most skilled free worker at topping and anyone free at the counter.
				var best: Dictionary = {}
				for worker in sim.workers:
					if not worker.post.is_empty(): continue
					if best.is_empty() or (post == "topping" and worker.skill > best.skill): best = worker
				if not best.is_empty():
					sim.assign_post(best.id, post)
		if tick % 50 == 0 and sim.station_info("boil").upgrade_error.is_empty() and sim.gold >= 200: sim.upgrade_station("boil")
		if sim.stage_index != stage:
			stage = sim.stage_index
			row = {"start": int(sim.elapsed), "orders": sim._next_order, "sold": sim.sold, "lost": 0, "staff": sim.workers.size()}
			rows[stage] = row
		sim.events.clear()
		sim.advance(0.1)
		for event in sim.events:
			if event.kind == "customer_left": row.lost += 1
		row.arrived = sim._next_order - row.orders
		row.served = sim.sold - row.sold
		row.end = int(sim.elapsed)
		row.staff_end = sim.workers.size()
	for i in stages.size():
		stages[i].customer_interval = saved[i][0]
		stages[i].staff_slots = saved[i][1]
	topping.art_seconds = saved_cup
	var text := "cup=%.0fs seats=%s slots=%s intervals=%s revenue=%d brewer=%d |" % [per_cup, seats, slots, intervals, sim.revenue, sim.station_levels.get("boil", 1)]
	for key in rows:
		var r: Dictionary = rows[key]
		text += " S%d %d-%ds staff %d-%d arrived %d served %d lost %d |" % [key, r.start, r.end, r.staff, r.staff_end, r.arrived, r.served, r.lost]
	return text

func test_pace() -> void:
	for seats in [[], ["topping"], ["boil"], ["boil", "topping"]]:
		print("PACE " + _run([8.0, 7.0, 7.0, 6.0], [2, 3, 4, 5], seats))
