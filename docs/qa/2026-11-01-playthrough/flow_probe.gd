extends SceneTree
const Shop = preload("res://game/tea_playtest/tea_shop_sim.gd")
func _initialize():
	call_deferred("_run")
func _run():
	var sim = Shop.new()
	sim.unlock_station("lemonade")
	sim.gold = 20000
	sim.revenue = 2000
	for id in ["boil", "mix", "topping"]: sim.unlock_station(id)
	sim.upgrade_station("topping")
	sim.upgrade_station("mix")
	sim.upgrade_material("supply", "tea_leaf")
	var row: Dictionary = sim.station_info("topping").materials[0]
	print("PRICE_BEFORE ", JSON.stringify({"panel_base":row.base_price,"panel_bonus":row.bonus,"panel_next_bonus":row.next_bonus,"panel_now":roundi(row.base_price*row.bonus),"panel_next":roundi(row.base_price*row.next_bonus),"actual_now":sim._dish_price("pearl_milk_tea")}))
	sim.upgrade_material("topping", "pearl")
	print("PRICE_AFTER actual=",sim._dish_price("pearl_milk_tea"))
	for scenario in ["one_mobile", "three_mobile", "two_seated_one_mobile"]:
		sim = Shop.new()
		sim.unlock_station("lemonade")
		var milestones := []
		var first_sales := {}
		var tasks_done := -1.0
		var last_sold := 0
		var last_sale := 0.0
		for tick in 36000:
			if tick % 10 == 0:
				for id in ["boil", "mix", "topping"]:
					if not sim.station_unlocked(id) and sim.station_info(id).unlock_error.is_empty():
						sim.unlock_station(id)
						milestones.append({"unlock":id,"time":snappedf(sim.elapsed,0.1),"gold":sim.gold})
				if scenario != "one_mobile" and sim.stage_index > 0 and sim.roster.size() < 3 and sim.gold >= sim.hire_cost():
					sim.hire()
					for worker in sim.roster:
						if not worker.deployed: sim.deploy_worker(worker.id)
				if scenario == "two_seated_one_mobile" and sim.workers.size() == 3:
					if sim.station_unlocked("boil") and sim.workers[1].post.is_empty(): sim.assign_post(2,"boil")
					if sim.station_unlocked("topping") and sim.workers[2].post.is_empty(): sim.assign_post(3,"topping")
				if sim.stage_index == 3 and sim.station_levels.topping < 4 and sim.station_info("topping").upgrade_error.is_empty(): sim.upgrade_station("topping")
			sim.advance(0.1)
			for dish in sim.sold_by_dish:
				if sim.sold_by_dish[dish]>0 and not first_sales.has(dish): first_sales[dish]=snappedf(sim.elapsed,0.1)
			if sim.sold != last_sold:
				last_sale=sim.elapsed
				last_sold=sim.sold
			if tick % 100 == 0:
				var audit: Dictionary = sim.audit()
				if not audit.valid:
					print("AUDIT_FAIL ",scenario," ",audit)
					break
				var copy = Shop.new()
				var load_error: String = copy.load_dict(sim.to_dict())
				if not load_error.is_empty():
					print("LOAD_FAIL ",scenario," time=",sim.elapsed," ",load_error)
					break
				if tasks_done<0 and sim.task_rows().all(func(r): return r.complete): tasks_done=snappedf(sim.elapsed,0.1)
				if tick % 6000==0: print("PROGRESS ",scenario," t=",roundi(sim.elapsed)," sold=",sim.sold," stage=",sim.stage_index)
		print("SCENARIO ", JSON.stringify({"name":scenario,"time":snappedf(sim.elapsed,0.1),"gold":sim.gold,"revenue":sim.revenue,"sold":sim.sold_by_dish,"orders_created":sim._next_order-1,"orders_left":sim._next_order-1-sim.sold-sim.orders.size(),"tasks":sim.task_rows(),"tasks_done_at":tasks_done,"last_sale_at":last_sale,"first_sales":first_sales,"milestones":milestones,"audit":sim.audit(),"stations":sim.stations}))
	quit()
