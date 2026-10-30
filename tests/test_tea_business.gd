extends "res://tests/test_case.gd"

func make_shop():
	var path := "res://game/tea_playtest/tea_shop_sim.gd"
	if not ResourceLoader.exists(path):
		check(false, "business simulator exists")
		return null
	return load(path).new()

func opened():
	var sim = make_shop()
	if sim == null: return null
	sim.unlock_station("lemonade")
	sim.gold = 20000
	sim.revenue = 2000
	sim.unlock_station("boil")
	sim.unlock_station("mix")
	sim.unlock_station("topping")
	sim.upgrade_station("topping")
	sim.upgrade_station("topping")
	sim.upgrade_station("topping")
	sim.hire()
	sim.hire()
	for worker in sim.all_workers():
		if not worker.deployed: sim.deploy_worker(worker.id)
	return sim

func test_opening_and_unlock_validation() -> void:
	var sim = make_shop()
	if sim == null: return
	check_eq(sim.gold, 50, "configured starting money")
	sim.advance(20)
	check_eq(sim.sold, 0, "locked shop cannot conjure income")
	var before: Dictionary = sim.to_dict()
	check(not sim.unlock_station("boil").is_empty(), "milk requires revenue")
	check_eq(sim.to_dict(), before, "rejected unlock is atomic")
	check_eq(sim.unlock_station("lemonade"), "", "lemonade unlocks")
	check_eq(sim.gold, 40, "configured opening cost charged")
	sim.advance(80)
	check(sim.revenue > 0 and sim.gold > 40, "real employee serves lemonade")
	check(sim.audit().valid, "lemonade is conserved")
	check(not sim.unlock_station("mix").is_empty(), "milk waits for the black tea line")
	sim.revenue = 100
	sim.gold = 100
	check_eq(sim.unlock_station("boil"), "", "black tea line unlocks first")
	check(sim.station_unlocked("boil") and sim.station_unlocked("supply") and sim.station_unlocked("seal"), "cabinet, brewer and sealer open together")
	check(not sim.station_unlocked("mix"), "milk machine stays locked")
	check_eq(sim.gold, 0, "black tea line charges its stage price")
	sim.revenue = 400
	sim.gold = 200
	check_eq(sim.unlock_station("mix"), "", "milk machine unlocks on its own")
	check_eq(sim.stage_index, 2, "milk tea stage reached")

func test_black_tea_sells_before_the_milk_machine() -> void:
	var sim = make_shop()
	if sim == null: return
	sim.unlock_station("lemonade")
	sim.revenue = 100
	sim.gold = 100
	sim.unlock_station("boil")
	for tick in 3000:
		sim.advance(0.1)
		if sim.sold_by_dish.black_tea >= 3: break
	check(sim.sold_by_dish.black_tea >= 3, "brewed tea is sealed, shelved and sold as black tea")
	check_eq(sim.sold_by_dish.plain_milk_tea, 0, "no milk tea without the milk machine")
	check(sim.audit().valid, "black tea is conserved")
	var state: Dictionary = sim.to_dict()
	var copy = make_shop()
	check_eq(copy.load_dict(state), "", "black tea stage saves and loads")

func test_collection_training_recall_and_reset() -> void:
	var sim = make_shop()
	if sim == null: return
	sim.gold = 500
	check(sim.hire(), "hire succeeds")
	check_eq(sim.workers.size(), 1, "new employee remains in reserve")
	var reserve: Dictionary = sim.all_workers()[1]
	check(sim.train(reserve.id), "reserve employee can train")
	check_eq(sim.deploy_worker(reserve.id), "", "owned reserve deploys")
	check(is_same(sim.worker_by_id(reserve.id), sim.workers[1]), "deployed employee shares the owned record")
	sim.unlock_station("lemonade")
	for tick in 400:
		sim.advance(0.1)
		if reserve.carry_count > 0: break
	check_eq(sim.recall_worker(reserve.id), "", "busy employee recalls")
	check(sim.audit().valid, "busy recall returns cargo and reservations")
	sim.reset_shop()
	check_eq(sim.all_workers().size(), 2, "reset retains owned staff")
	check_eq(sim.worker_by_id(reserve.id).level, 2, "reset retains training")
	check_eq(sim.gold, 50, "reset returns opening economy")
	check_eq(sim.workers.size(), 1, "reset deploys starter only")

func test_real_flavors_conservation_and_identical_resume() -> void:
	for belts in [false, true]:
		var sim = opened()
		if sim == null: return
		sim.set_belts(belts)
		var saw_flavors := {}
		var resumed = make_shop()
		for tick in 9000:
			sim.advance(0.1)
			var report: Dictionary = sim.audit()
			if not report.valid:
				check(false, "business conservation: %s" % report)
				return
			for item in sim.stations.topping.output:
				if sim.stations.topping.output[item] > 0: saw_flavors[item] = true
			if tick == 831:
				check_eq(resumed.load_dict(sim.to_dict()), "", "midflight state loads")
				check_eq(resumed.to_dict(), sim.to_dict(), "full state restored without conversion")
			if tick > 831:
				resumed.advance(0.1)
				if resumed.to_dict() != sim.to_dict():
					check(false, "continuation including RNG and pending work is identical")
					return
		check(saw_flavors.size() == 4, "production creates all four actual flavor ids")
		for dish in ["plain_milk_tea", "pearl_milk_tea", "coconut_milk_tea", "redbean_milk_tea", "taro_milk_tea"]:
			check(sim.sold_by_dish.get(dish, 0) > 0, "actual flavor sold: " + dish)

func test_upgrades_tasks_and_malformed_load_are_atomic() -> void:
	var sim = opened()
	if sim == null: return
	var price: int = sim.station_info("boil").upgrade_cost
	var previous: int = sim.gold
	check_eq(sim.upgrade_station("boil"), "", "machine upgrade succeeds")
	check_eq(sim.gold, previous - price, "resource machine price charged")
	check_eq(sim.upgrade_material("supply", "milk"), "", "milk material upgrades")
	check_eq(sim.upgrade_material("topping", "pearl"), "", "flavor price upgrades")
	check(sim.task_rows().size() == 5, "all task goals exposed, including the black tea stage")
	var before: Dictionary = sim.to_dict()
	check(not sim.upgrade_material("bad", "milk").is_empty(), "invalid material rejected")
	check_eq(sim.to_dict(), before, "invalid upgrade has no mutation")
	var malformed: Dictionary = before.duplicate(true)
	malformed.stations.seal.processing = -10
	check(not sim.load_dict(malformed).is_empty(), "malformed runtime rejected")
	check_eq(sim.to_dict(), before, "invalid load cannot partly mutate live shop")

func test_reserved_employee_drop_validates_before_deploying() -> void:
	var sim = make_shop()
	if sim == null: return
	sim.gold = 500
	sim.hire()
	var before: Dictionary = sim.to_dict()
	check(not sim.deploy_at(2, "boil", Vector2(270, 330)).is_empty(), "locked work post rejects deployment")
	check_eq(sim.to_dict(), before, "locked drop does not deploy or mutate roster")
	check(not sim.deploy_at(2, "", Vector2(-50, -50)).is_empty(), "blocked drop rejects deployment")
	check_eq(sim.to_dict(), before, "blocked drop preserves all state")
	check_eq(sim.deploy_at(2, "", Vector2(410, 930)), "", "valid mobile drop deploys and places")
	check_eq(sim.worker_by_id(2).pos, Vector2(410, 930), "physical actor starts at valid drop")

func test_exact_flavor_dispatch_and_upgraded_sale_price() -> void:
	var sim = opened()
	if sim == null: return
	# Isolate a real shelf dispatch; a coconut cup cannot serve a pearl order.
	for worker in sim.workers.duplicate():
		if worker.id != 1: sim.recall_worker(worker.id)
	sim.orders = [{"id": 1, "dish": "pearl_milk_tea", "wait": 0.0, "reserved": false}]
	sim.shelf_stock.coconut_milk_tea = 1
	sim.shelf_count = 1
	sim._generated = 1
	for job in sim._jobs(sim.workers[0]):
		check(job.is_empty() or job.kind != "serve", "wrong flavor never reserves this order")
	sim.shelf_stock.pearl_milk_tea = 1
	sim.shelf_count += 1
	sim._generated += 1
	sim.upgrade_material("topping", "pearl")
	var before: int = sim.revenue
	for tick in 1000:
		sim.advance(0.1)
		if sim.sold > 0: break
	check_eq(sim.sold_by_dish.pearl_milk_tea, 1, "exact physical flavor sold")
	check_eq(sim.shelf_stock.coconut_milk_tea, 1, "unrelated flavor stays on shelf")
	check_eq(sim.revenue - before, roundi(_base_price(sim, "pearl_milk_tea") * 1.08), "configured pearl bonus changes actual completed-sale income")
	check(sim.audit().valid, "exact-flavor dispatch conserves inventory")

func test_brewer_upgrades_speed_and_ingredient_upgrades_price() -> void:
	var durations: Array = []
	for upgraded in [false, true]:
		var sim = opened()
		if sim == null: return
		for worker in sim.workers.duplicate(): sim.recall_worker(worker.id)
		if upgraded:
			sim.upgrade_station("boil")
			sim.upgrade_material("supply", "tea_leaf")
			sim.upgrade_material("supply", "milk")
		sim.stations.boil.input.raw = 3
		sim.stations.mix.input.tea = 3
		sim._generated = 6
		sim.deploy_at(1, "boil", Vector2(270, 330))
		sim.advance(1.0)
		check(sim.stations.boil.processing == 3 and sim.stations.mix.processing == 3, "real batches started")
		durations.append([sim.stations.boil.duration, sim.stations.mix.duration, sim._dish_price("plain_milk_tea"), sim._dish_price("black_tea")])
		check(sim.audit().valid, "upgraded cycles keep physical batch accounting")
	check(durations[1][0] < durations[0][0], "brewer upgrade accelerates actual brewing")
	check_eq(durations[1][1], durations[0][1], "ingredient upgrades do not change mixing time")
	check_eq(durations[1][2], durations[0][2] + 4, "tea leaf + milk upgrades each add 6% of the milk tea base price")
	check_eq(durations[1][3], durations[0][3] + 2, "tea leaf upgrade adds 6% of the black tea base price")

func test_recalling_every_observed_job_phase_preserves_goods_and_reservations() -> void:
	var sim = opened()
	if sim == null: return
	var seen := {}
	for tick in 4000:
		sim.advance(0.1)
		for worker in sim.workers:
			if worker.job.is_empty(): continue
			var key: String = worker.job.kind + ":" + worker.phase
			if seen.has(key): continue
			seen[key] = true
			var copy = make_shop()
			var error: String = copy.load_dict(sim.to_dict())
			check_eq(error, "", "observed phase resumes: " + key)
			if not error.is_empty(): return
			check_eq(copy.recall_worker(worker.id), "", "busy recall succeeds: " + key)
			check(copy.audit().valid, "busy recall refunds and clears reservations: " + key)
	check(seen.size() >= 20, "recall covers operations, pickup, walking with cargo and dropoff")

func test_malformed_active_job_cannot_load_or_break_later_ticks() -> void:
	var sim = opened()
	if sim == null: return
	sim.advance(0.1)
	var before: Dictionary = sim.to_dict()
	var malformed: Dictionary = before.duplicate(true)
	malformed.roster[0].job.src = "mix"
	malformed.roster[0].job.item = "tea"
	malformed.roster[0].job.kind = "serve"
	malformed.roster[0].job.order_id = malformed.orders[0].id
	malformed.orders[0].reserved = true
	malformed.stations.mix.reserved_out.tea = 1
	malformed.stations.mix.input.tea = 1
	malformed.generated += 1
	check(not sim.load_dict(malformed).is_empty(), "incompatible source/item/operation rejected")
	check_eq(sim.to_dict(), before, "malformed active job cannot mutate live runtime")

func test_opening_income_funds_the_real_production_progression() -> void:
	var sim = make_shop()
	if sim == null: return
	sim.unlock_station("lemonade")
	for tick in 60000:
		for id in ["boil", "mix", "topping"]:
			if sim.station_info(id).unlock_error.is_empty(): sim.unlock_station(id)
		if sim.stage_index > 0 and sim.hire_cost() >= 0 and sim.gold >= sim.hire_cost():
			sim.hire()
			for worker in sim.roster:
				if not worker.deployed: sim.deploy_worker(worker.id)
		if sim.stage_index == 3 and sim.station_levels.topping < 4 and sim.station_info("topping").upgrade_error.is_empty(): sim.upgrade_station("topping")
		sim.advance(0.1)
		var all_complete := true
		for row in sim.task_rows(): all_complete = all_complete and row.complete
		if all_complete: break
	var complete := true
	for row in sim.task_rows(): complete = complete and row.complete
	check(complete, "real opening sales pay for milk, topping, staff and all original task goals")
	check(sim.audit().valid, "full natural progression conserves stock")

func test_corrupt_operation_phase_rejected_before_applying() -> void:
	var sim = opened()
	if sim == null: return
	sim.advance(0.1)
	var before: Dictionary = sim.to_dict()
	var malformed: Dictionary = before.duplicate(true)
	malformed.roster[0].phase = "work"
	malformed.roster[0].walking = false
	check(not sim.load_dict(malformed).is_empty(), "serve order cannot load as manual machine work")
	check_eq(sim.to_dict(), before, "invalid operation phase is atomic")

func test_full_other_flavors_do_not_block_the_requested_flavor() -> void:
	for belts in [false, true]:
		for requested in ["plain_milk_tea", "pearl_milk_tea"]:
			var sim = opened()
			if sim == null: return
			sim.set_belts(belts)
			if requested == "plain_milk_tea":
				for dish in ["pearl_milk_tea", "coconut_milk_tea", "redbean_milk_tea", "taro_milk_tea"]: sim.shelf_stock[dish] = 3
			else: sim.shelf_stock.plain_milk_tea = 12
			sim.shelf_count = 12
			sim.stations.seal.output[requested] = 1
			sim._generated = 13
			sim.workers[0].pos = Vector2(530, 430)
			sim.orders.clear()
			for id in 3: sim.orders.append({"id": id + 1, "dish": requested, "wait": 0.0, "reserved": false})
			for tick in 300:
				sim.advance(0.1)
				if not sim.audit().valid:
					check(false, "full other flavors conserve while requested flavor moves: %s" % sim.audit())
					return
				if sim.sold_by_dish[requested] > 0: break
			check(sim.sold_by_dish[requested] > 0, "twelve unrelated cups cannot block requested " + requested)

func test_shelf_capacity_is_per_flavor_and_reserves_in_flight_slots() -> void:
	var sim = opened()
	if sim == null: return
	sim.shelf_stock.plain_milk_tea = 11
	sim.shelf_count = 11
	sim.stations.seal.output.plain_milk_tea = 1
	sim.belt_items = [{"route": "seal_to_shelf", "item": "plain_milk_tea", "count": 1, "progress": 0.0, "duration": 4.0, "dst": "shelf"}]
	sim._shelf_reserved_in = 1
	sim._generated = 13
	var job: Dictionary = sim._candidate("carry_to_shelf", "seal", "shelf", "plain_milk_tea", sim.workers[0], 96)
	check(job.is_empty(), "incoming same flavor holds its final shelf slot")
	check_eq(sim.shelf_limit(), 72, "configured per-flavor capacity covers black tea and five milk flavors")
	check(sim.audit().valid, "per-flavor incoming reservation is conserved")

func test_unreserved_orders_leave_after_configured_patience_and_reserved_orders_finish() -> void:
	var sim = opened()
	if sim == null: return
	for worker in sim.workers.duplicate(): sim.recall_worker(worker.id)
	sim.orders = [{"id": 1, "dish": "plain_milk_tea", "wait": 23.9, "reserved": false}]
	sim.advance(0.2)
	var old_order_remains := false
	for order in sim.orders: old_order_remains = old_order_remains or order.id == 1
	check(not old_order_remains, "unreserved customer leaves after resource patience")
	var active = opened()
	active.orders = [{"id": 1, "dish": "lemonade", "wait": 23.9, "reserved": false}]
	active.advance(0.1)
	check(active.orders[0].reserved, "service reserves order before patience expires")
	active.advance(0.2)
	check(active.orders[0].id == 1 and active.orders[0].reserved, "reserved service survives patience threshold")
	var restored = make_shop()
	check_eq(restored.load_dict(active.to_dict()), "", "expired but reserved order resumes")
	for tick in 200:
		active.advance(0.1)
		restored.advance(0.1)
	check_eq(restored.to_dict(), active.to_dict(), "order departures and reserved deliveries resume deterministically")
	check(active.sold_by_dish.lemonade > 0, "reserved order earns income after actual delivery")

func test_carried_service_retains_its_flavor_slot_until_delivery_or_recall() -> void:
	var sim = opened()
	if sim == null: return
	for worker in sim.workers.duplicate():
		if worker.id != 1: sim.recall_worker(worker.id)
	sim.shelf_stock.plain_milk_tea = 12
	sim.shelf_count = 12
	sim.stations.seal.output.plain_milk_tea = 1
	sim._generated = 13
	sim.orders = [{"id": 1, "dish": "plain_milk_tea", "wait": 0.0, "reserved": false}]
	sim.workers[0].pos = Vector2(470, 670)
	for tick in 100:
		sim.advance(0.1)
		if sim.workers[0].carry_count > 0: break
	check_eq(sim.workers[0].carry_count, 1, "service cup is physically carried away from full flavor shelf")
	var candidate: Dictionary = sim._candidate("carry_to_shelf", "seal", "shelf", "plain_milk_tea", sim.workers[0], 96)
	check(candidate.is_empty(), "carried cup keeps its flavor slot reserved for refund")
	var restored = make_shop()
	check_eq(restored.load_dict(sim.to_dict()), "", "carried flavor slot resumes")
	check_eq(restored.recall_worker(1), "", "loaded busy courier can recall")
	check_eq(restored.shelf_stock.plain_milk_tea, 12, "recall restores exact flavor to its retained slot")
	check(restored.audit().valid, "busy recall does not exceed per-flavor capacity")

func test_customer_queue_uses_configured_capacity() -> void:
	var sim = make_shop()
	if sim == null: return
	sim.unlock_station("lemonade")
	for worker in sim.workers.duplicate(): sim.recall_worker(worker.id)
	# Keep everyone patient so only the queue cap limits arrivals, whatever the stage interval.
	var seconds: float = sim.PROGRESSION.stages[0].customer_interval * (sim.CONFIG.queue_capacity + 1)
	for tick in int(seconds * 10):
		for order in sim.orders: order.wait = 0.0
		sim.advance(0.1)
	check_eq(sim.orders.size(), sim.CONFIG.queue_capacity, "queue fills to the configured capacity, not a fixed 3")

func _base_price(sim, dish: String) -> int:
	for definition in sim.CONFIG.dishes:
		if definition.id == dish: return definition.price
	return -1

func test_price_preview_matches_the_price_after_upgrading() -> void:
	var sim = opened()
	if sim == null: return
	for unused in 2: sim.upgrade_station("mix")
	for unused in 3:
		var promised: int = sim.station_info("mix").price.next
		check_eq(sim.upgrade_station("mix"), "", "mixer price upgrade succeeds")
		check_eq(sim._dish_price("plain_milk_tea"), promised, "panel preview equals the real milk tea price")
	var row: Dictionary = sim.station_info("supply").materials[1]
	check_eq(sim.upgrade_material("supply", "milk"), "", "milk slot upgrade succeeds")
	check_eq(sim._dish_price("plain_milk_tea"), int(row.next), "slot preview equals the real milk tea price")

func test_belt_segments_are_bought_and_move_goods_without_staff() -> void:
	var fresh = make_shop()
	if fresh == null: return
	check(not fresh.buy_belt("seal_to_shelf").is_empty(), "belts wait for the black tea line")
	check(not fresh.buy_belt("nowhere").is_empty(), "unknown belt segment rejected")
	var sim = opened()
	var gold: int = sim.gold
	check_eq(sim.buy_belt("seal_to_shelf"), "", "belt segment bought")
	check_eq(sim.gold, gold - 40, "segment charges its price")
	check(not sim.buy_belt("seal_to_shelf").is_empty(), "segment cannot be bought twice")
	for row in sim.belt_rows():
		if row.id != "seal_to_shelf": check_eq(sim.buy_belt(row.id), "", "buy " + row.id)
	var hand_carried := {}
	var shipped := {}
	var resumed = make_shop()
	for tick in 6000:
		sim.advance(0.1)
		for worker in sim.workers:
			if not worker.job.is_empty() and worker.job.kind != "serve" and not sim._is_operation(worker.job):
				hand_carried[worker.job.src + ">" + worker.job.dst] = true
		for shipment in sim.belt_items: shipped[shipment.route] = true
		if not sim.audit().valid:
			check(false, "belted shop conserves goods: %s" % sim.audit())
			return
		if tick == 2500:
			check_eq(resumed.load_dict(sim.to_dict()), "", "state with belts in flight loads")
			check_eq(resumed.to_dict(), sim.to_dict(), "belts and their cargo restore exactly")
	check(hand_carried.is_empty(), "staff stop carrying on belted hops: %s" % hand_carried)
	for route in ["seal_to_shelf", "supply_to_boil", "boil_to_mix", "mix_to_topping", "topping_to_seal"]:
		check(shipped.has(route), "belt actually carries goods: " + route)
	check(sim.sold_by_dish.pearl_milk_tea > 0, "belted line still sells topped tea")
	gold = sim.gold
	check_eq(sim.remove_belt("seal_to_shelf"), "", "segment can be taken back")
	check_eq(sim.gold, gold + 40, "taking a segment back refunds it")
	check(sim.audit().valid, "removing a segment keeps cargo conserved")

func _run_front_split(front: bool) -> Dictionary:
	var sim = opened()
	if front: check_eq(sim.assign_post(sim.workers[0].id, "counter"), "", "worker staffs the counter")
	var lost := 0
	var mixed := false
	for tick in 18000:
		sim.events.clear()
		sim.advance(0.1)
		for event in sim.events:
			if event.kind == "customer_left": lost += 1
		for worker in sim.workers:
			if worker.job.is_empty(): continue
			if worker.post == "counter" and worker.job.kind != "serve": mixed = true
			if front and worker.post.is_empty() and worker.job.kind == "serve": mixed = true
		if tick % 500 == 0 and not sim.audit().valid:
			check(false, "front split conserves goods: %s" % sim.audit())
			break
	return {"lost": lost, "sold": sim.sold, "revenue": sim.revenue - 2000, "mixed": mixed, "milk": sim.sold - int(sim.sold_by_dish.get("lemonade", 0))}

func test_counter_post_splits_front_and_kitchen_duties() -> void:
	var sim = opened()
	if sim == null: return
	var shared := _run_front_split(false)
	var split := _run_front_split(true)
	print("FRONT SPLIT 30min shared=%s split=%s" % [shared, split])
	check(not split.mixed, "counter staff only serve and mobile staff leave serving to them")
	check(split.milk > 0, "kitchen staff keep the milk line running")
	check(split.lost <= shared.lost, "a dedicated counter loses no more customers: %s vs %s" % [split, shared])
	var resumed = make_shop()
	check_eq(sim.assign_post(sim.workers[0].id, "counter"), "", "counter post assigned")
	check_eq(resumed.load_dict(sim.to_dict()), "", "counter post saves and loads")
	check(not sim.assign_post(sim.workers[1].id, "counter").is_empty(), "counter has one front-of-house post")
