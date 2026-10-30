extends "res://tests/test_case.gd"

func _run(intervals: Array) -> String:
	var sim = load("res://game/tea_playtest/tea_shop_sim.gd").new()
	var stages: Array = sim.PROGRESSION.stages
	var saved: Array = []
	for i in stages.size():
		saved.append(stages[i].customer_interval)
		stages[i].customer_interval = intervals[i]
	sim.unlock_station("lemonade")
	var rows := {}
	var stage := -1
	var row := {}
	for tick in 24000:
		for id in ["boil", "mix", "topping"]:
			if sim.station_info(id).unlock_error.is_empty(): sim.unlock_station(id)
		if sim.stage_index > 0 and sim.hire_cost() >= 0 and sim.gold >= sim.hire_cost():
			sim.hire()
			for worker in sim.roster:
				if not worker.deployed: sim.deploy_worker(worker.id)
		if sim.stage_index == 3 and sim.station_levels.topping < 4 and sim.station_info("topping").upgrade_error.is_empty(): sim.upgrade_station("topping")
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
	for i in stages.size(): stages[i].customer_interval = saved[i]
	var text := "intervals=%s revenue=%d |" % [intervals, sim.revenue]
	for key in rows:
		var r: Dictionary = rows[key]
		text += " S%d %d-%ds staff %d-%d arrived %d served %d lost %d |" % [key, r.start, r.end, r.staff, r.staff_end, r.arrived, r.served, r.lost]
	return text

func test_pace() -> void:
	for intervals in [[4.0, 3.0, 2.0, 1.5], [8.0, 6.0, 4.5, 3.5], [10.0, 7.0, 5.0, 4.0]]:
		print("PACE " + _run(intervals))
