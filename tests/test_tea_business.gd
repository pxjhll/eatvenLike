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
	sim.unlock_box("tea_leaf")
	sim.unlock_station("seal")
	sim.unlock_station("mix")
	sim.unlock_box("milk")
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
	check(sim.station_unlocked("supply"), "the cabinet is furniture from the start")
	check_eq(sim.unlock_station("boil"), "", "brewer unlocks first")
	check(sim.station_unlocked("boil") and not sim.station_unlocked("seal"), "the brewer opens on its own")
	check(not sim.station_unlocked("mix"), "milk machine stays locked")
	check_eq(sim.gold, 0, "brewer charges its stage price")
	check_eq(sim.pending_box(), "tea_leaf", "the tea leaf box is offered next")
	check(not sim._dish_unlocked("black_tea"), "no black tea before the tea leaf box")
	check(not sim.unlock_box("tea_leaf").is_empty(), "the box still costs money")
	sim.gold = 20
	check_eq(sim.unlock_box("tea_leaf"), "", "tea leaf box unlocks")
	check(sim._dish_unlocked("black_tea") and sim.pending_box().is_empty(), "black tea goes on sale")
	check(not sim.unlock_box("milk").is_empty(), "the milk box waits for the milk machine")
	sim.revenue = 10000
	sim.gold = 10000
	check(not sim.unlock_station("mix").is_empty(), "milk machine waits for the sealer")
	check_eq(sim.unlock_station("seal"), "", "sealer unlocks on its own")
	check_eq(sim.unlock_station("mix"), "", "milk machine unlocks on its own")
	check_eq(sim.stage_index, 3, "milk tea stage reached")
	check(not sim._dish_unlocked("plain_milk_tea") and sim.pending_box() == "milk", "milk tea waits for the milk box")
	check_eq(sim.unlock_box("milk"), "", "milk box unlocks")
	check(sim._dish_unlocked("plain_milk_tea"), "milk tea goes on sale")

func test_black_tea_sells_before_the_milk_machine() -> void:
	var sim = make_shop()
	if sim == null: return
	sim.unlock_station("lemonade")
	sim.revenue = 100
	sim.gold = 100
	sim.unlock_station("boil")
	sim.gold = 20
	sim.unlock_box("tea_leaf")
	sim.gold = 35
	check(sim.hire(), "the brewer gets a kitchen hand")
	check_eq(sim.deploy_worker(2), "", "the kitchen hand starts work")
	for tick in 3000:
		sim.advance(0.1)
		if sim.sold_by_dish.black_tea >= 3: break
	check(sim.sold_by_dish.black_tea >= 3, "brewed tea is shelved and served to seated customers")
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
	check(sim.deployment_error(reserve.id).contains("煮茶机"), "no kitchen staff before the brewer")
	check(not sim.train(reserve.id), "per-worker training is gone")
	sim.unlock_station("lemonade")
	sim.revenue = 100
	sim.unlock_station("boil")
	sim.unlock_box("tea_leaf")
	check_eq(sim.deploy_worker(reserve.id), "", "owned reserve deploys to the kitchen")
	check(is_same(sim.worker_by_id(reserve.id), sim.workers[1]), "deployed employee shares the owned record")
	for tick in 600:
		sim.advance(0.1)
		if reserve.carry_count > 0: break
	check(reserve.carry_count > 0, "the kitchen hand carries goods")
	check_eq(sim.recall_worker(reserve.id), "", "busy employee recalls")
	check(sim.audit().valid, "busy recall returns cargo and reservations")
	sim.reset_shop()
	check_eq(sim.all_workers().size(), 2, "reset retains owned staff")
	check_eq(sim.gold, 50, "reset returns opening economy")
	check_eq(sim.workers.size(), 1, "reset deploys starter only")
	check_eq(sim.workers[0].post, "counter", "the starter opens at the counter")

func test_rabbit_is_fourth_paid_recruit_and_roster_keeps_growing() -> void:
	var sim = make_shop()
	if sim == null: return
	sim.gold = 180
	for expected in [[35, "raccoon", 2], [60, "fox", 3]]:
		check_eq(sim.hire_cost(), expected[0], "existing recruitment prices stay ordered")
		var before: int = sim.gold
		check(sim.hire(), "recruit existing employee")
		check_eq(sim.gold, before - expected[0], "recruitment deducts its full price")
		check_eq(sim.worker_by_id(expected[2]).art, expected[1], "existing employee ids remain stable")
	check_eq(sim.hire_cost(), 85, "rabbit is the next paid recruit")
	check_eq(sim.next_hire_art(), "rabbit", "the missing animal comes next")
	sim.gold = 84
	var before: Dictionary = sim.to_dict()
	check(not sim.hire(), "rabbit cannot be recruited with insufficient gold")
	check_eq(sim.to_dict(), before, "failed rabbit recruitment is atomic")
	sim.gold = 85
	check(sim.hire(), "fourth recruit succeeds at its full price")
	check_eq(sim.gold, 0, "rabbit recruitment spends 85 gold")
	check_eq(sim.workers.size(), 1, "recruits enter reserve")
	var rabbit: Dictionary = sim.worker_by_id(4)
	check(not rabbit.is_empty(), "rabbit has stable id four")
	if rabbit.is_empty(): return
	check_eq(rabbit.art, "rabbit", "fourth roster entry uses rabbit art")
	check_eq(rabbit.name, "小兔子", "recruited rabbit has its display name")
	check_eq(rabbit.role, "speed", "rabbit trains movement speed")
	check_eq(rabbit.speed, 104.0, "rabbit starts with its movement speed")
	check_eq(rabbit.capacity, 2, "rabbit starts with two carry slots")
	check_eq(rabbit.skill, 1.0, "rabbit starts with normal operation skill")
	check_eq(rabbit.source, "招募", "rabbit records paid recruitment source")
	check_eq(sim.hire_cost(), 110, "the roster has no size limit; the fifth recruit costs more")
	check_eq(sim.next_hire_art(), "cat", "after one of each, the cycle starts again")
	sim.gold = 110
	check(sim.hire(), "a fifth employee can be recruited")
	var second_cat: Dictionary = sim.worker_by_id(5)
	check(not second_cat.is_empty() and second_cat.art == "cat", "a repeat animal takes a fresh id")
	check_eq(sim.all_workers().size(), 5, "five employees can be owned")
	check_eq(sim.next_hire_art(), "raccoon", "repeats follow the animal order")
	check(sim.audit().valid, "five owned staff preserve simulation invariants")
	var copy = make_shop()
	check_eq(copy.load_dict(sim.to_dict()), "", "a roster with a repeat animal saves and loads")

func test_shop_slots_grow_with_each_production_line() -> void:
	var sim = make_shop()
	if sim == null: return
	sim.gold = 100000
	sim.revenue = 100000
	for unused in 6: sim.hire()
	check_eq(sim.staff_slots(), 1, "the lemonade shop runs on one front worker")
	check_eq(sim.workers[0].post, "counter", "who starts at the counter")
	var before: Dictionary = sim.to_dict()
	check(not sim.deploy_worker(2).is_empty(), "a kitchen hand waits for the first line")
	check(sim.deployment_error(2).contains("煮茶机"), "the refusal names the line that opens the kitchen")
	check_eq(sim.to_dict(), before, "blocked deployment is atomic")
	check_eq(sim.unlock_station("lemonade"), "", "open lemonade")
	var next_id := 2
	for line in ["boil", "seal", "mix", "topping"]:
		var before_slots: int = sim.kitchen_slots()
		check_eq(sim.unlock_station(line), "", "open " + line)
		check_eq(sim.kitchen_slots(), before_slots + 1, "%s line adds a kitchen slot" % line)
		check_eq(sim.deploy_worker(next_id), "", "the new slot takes one more employee")
		next_id += 1
		check(not sim.deploy_worker(next_id).is_empty(), "but no more than the slots")
	check_eq(sim.kitchen_staff(), 4, "a full kitchen runs four staff")
	check_eq(sim.deployment_error(next_id), "后厨最多 4 位员工", "the last line names no further unlock")
	check_eq(sim.front_staff(), 1, "the front still has one worker")
	for tick in 600: sim.advance(0.1)
	check(sim.audit().valid, "five deployed staff preserve simulation invariants")
	sim.reset_shop()
	check_eq(sim.workers.size(), 1, "reset deploys only the starter")
	check_eq(sim.staff_slots(), 1, "reset returns to the opening slots")

func test_front_and_kitchen_staff_have_their_own_duties_and_upgrade_lists() -> void:
	var sim = opened()
	if sim == null: return
	var front: Dictionary = sim.workers.filter(func(w): return w.post == "counter")[0]
	var kitchen: Dictionary = sim.workers.filter(func(w): return w.post != "counter")[0]
	var walk_front: float = sim._walk_speed(front)
	var walk_kitchen: float = sim._walk_speed(kitchen)
	var info: Dictionary = sim.staff_upgrade_info("front")
	check_eq(info.kind, sim.PROGRESSION.front_upgrade_kinds[0], "the front list starts with its first item")
	var gold: int = sim.gold
	check_eq(sim.buy_staff_upgrade("front"), "", "a front upgrade can be bought")
	check_eq(sim.gold, gold - info.cost, "it costs its listed price")
	if info.kind == "walk":
		check(is_equal_approx(sim._walk_speed(front), walk_front * (1.0 + sim.PROGRESSION.walk_step)), "front staff walk faster")
		check(is_equal_approx(sim._walk_speed(kitchen), walk_kitchen), "kitchen staff are not affected")
	# Buy the whole front list: it adds front slots.
	while sim.staff_upgrade_info("front").cost > 0: check_eq(sim.buy_staff_upgrade("front"), "", "front list item bought")
	check_eq(sim.front_slots(), 1 + sim.PROGRESSION.front_upgrade_kinds.count("slot"), "slot items open more front posts")
	check(not sim.buy_staff_upgrade("front").is_empty(), "a finished list cannot be bought again")
	var capacity: int = sim._carry(kitchen)
	while sim.staff_upgrade_info("kitchen").cost > 0: sim.buy_staff_upgrade("kitchen")
	check_eq(sim._carry(kitchen), capacity + sim.PROGRESSION.kitchen_upgrade_kinds.count("carry"), "kitchen carry items add cups per trip")
	check_eq(sim._carry(front), front.capacity, "front staff carry one customer's cup regardless")
	# A second front worker can take the counter once there is a slot.
	sim.gold = 1000
	sim.hire()
	var extra: Dictionary = sim.all_workers().back()
	check_eq(sim.deploy_at(extra.id, "counter", Vector2(410, 930)), "", "a second front worker takes the counter")
	check_eq(sim.front_staff(), 2, "two front staff serve")
	var copy = make_shop()
	check_eq(copy.load_dict(sim.to_dict()), "", "front and kitchen upgrades save")
	check_eq(copy.front_upgrades, sim.front_upgrades, "front upgrades load")
	check_eq(copy.kitchen_upgrades, sim.kitchen_upgrades, "kitchen upgrades load")
	for tick in 3000:
		sim.advance(0.1)
		for worker in sim.workers:
			if worker.job.is_empty(): continue
			if worker.post == "counter": check(worker.job.kind == "serve", "front staff only serve")
			else: check(worker.job.kind != "serve", "kitchen staff never serve")
	check(sim.audit().valid, "split duties conserve goods")

func test_acquired_rabbit_can_train_work_recall_and_survive_shop_reset() -> void:
	var sim = make_shop()
	if sim == null: return
	check_eq(sim.acquire_staff("rabbit", "活动奖励"), "", "rabbit supports the explicit acquisition path")
	var rabbit: Dictionary = sim.worker_by_id(4)
	if rabbit.is_empty(): return
	var before: Dictionary = sim.to_dict()
	check_eq(sim.acquire_staff("rabbit", "活动奖励"), "", "a second rabbit can be acquired")
	check_eq(sim.worker_by_id(5).art, "rabbit", "the second rabbit takes the next free id")
	check(not sim.worker_by_id(5).deployed, "the second rabbit starts in reserve")
	check_eq(sim.recall_worker(1), "", "starter recalled for rabbit service")
	check_eq(sim.deploy_worker(4), "", "acquired rabbit deploys")
	check_eq(sim.worker_by_id(4).post, "counter", "with no kitchen yet, the rabbit takes the empty counter")
	check_eq(sim.unlock_station("lemonade"), "", "open real service work")
	var saw_cargo := false
	for tick in 1000:
		sim.advance(0.1)
		if rabbit.carry_count > 0:
			saw_cargo = true
			break
	check(saw_cargo, "rabbit picks up physical stock")
	check_eq(sim.recall_worker(4), "", "busy rabbit can recall")
	check(sim.audit().valid, "rabbit recall returns stock and reservations")
	check_eq(sim.deploy_worker(4), "", "recalled rabbit can deploy again")
	sim.reset_shop()
	check_eq(sim.all_workers().size(), 3, "reset retains both acquired rabbits")
	check_eq(sim.worker_by_id(4).level, 1, "reset keeps the rabbit at its base level")
	check(is_equal_approx(sim.worker_by_id(4).speed, 104.0), "reset keeps rabbit speed")
	check_eq(sim.worker_by_id(4).capacity, 2, "reset retains rabbit carry progression")
	check_eq(sim.worker_by_id(4).source, "活动奖励", "reset retains rabbit acquisition source")
	check_eq(sim.workers.size(), 1, "reset deploys only the starter")
	check_eq(sim.workers[0].id, 1, "reset restores cat deployment")
	check(not sim.worker_by_id(4).deployed, "rabbit returns to reserve on reset")
	check_eq(sim.gold, 50, "reset restores starting economy")
	check(sim.audit().valid, "reset with rabbit preserves stock invariants")

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
	check(sim.task_rows().size() == 9, "all task goals exposed, including the star tasks")
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
	sim.unlock_station("lemonade")
	sim.revenue = 100
	sim.unlock_station("boil")
	var before: Dictionary = sim.to_dict()
	check(not sim.deploy_at(2, "topping", Vector2(190, 410)).is_empty(), "locked work post rejects deployment")
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
	sim.orders = [{"id": 1, "dish": "pearl_milk_tea", "wait": 0.0, "reserved": false, "takeaway": false}]
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
		check(sim.stations.boil.processing == sim.brew_batch() and sim.stations.mix.processing == 3, "real batches started")
		durations.append([sim.stations.boil.duration, sim.stations.mix.duration, sim._dish_price("plain_milk_tea"), sim._dish_price("black_tea")])
		check(sim.audit().valid, "upgraded cycles keep physical batch accounting")
	check(durations[1][0] < durations[0][0], "brewer upgrade accelerates actual brewing")
	check_eq(durations[1][1], durations[0][1], "ingredient upgrades do not change mixing time")
	var probe = opened()
	if probe == null: return
	var leaf: float = 1.0 + probe._definition("supply").materials.filter(func(m): return m.id == "tea_leaf")[0].art_price_step
	var milk: float = 1.0 + probe._definition("supply").materials.filter(func(m): return m.id == "milk")[0].art_price_step
	check_eq(durations[1][2], roundi(30 * leaf * milk), "tea leaf and milk each multiply the milk tea price")
	check_eq(durations[1][3], roundi(28 * leaf), "tea leaf multiplies the black tea price")

func test_brewer_pot_grows_on_odd_levels_and_speeds_up_on_even_levels() -> void:
	var sim = opened()
	if sim == null: return
	sim.gold = 100000
	var batches: Array = []
	var seconds: Array = []
	for level in range(1, 11):
		batches.append(sim.brew_batch())
		seconds.append(snappedf(sim._machine_duration("boil"), 0.01))
		if level < 10: check_eq(sim.upgrade_station("boil"), "", "brewer upgrades to Lv%d" % (level + 1))
	check_eq(batches, [2, 2, 3, 3, 4, 4, 5, 5, 6, 6], "the pot starts at two cups and odd levels add one")
	for level in range(1, 10):
		if level % 2 == 1: check(seconds[level] < seconds[level - 1], "even level Lv%d brews faster" % (level + 1))
		else: check_eq(seconds[level], seconds[level - 1], "odd level Lv%d adds a cup, not speed" % (level + 1))
	check(not sim.upgrade_station("boil").is_empty(), "the brewer stops at Lv10")
	check_eq(sim.station_info("boil").kind, "capacity", "the brewer is a capacity machine")

func test_sealer_levels_speed_up_and_stars_add_slots() -> void:
	var sim = opened()
	if sim == null: return
	sim.gold = 100000
	var info: Dictionary = sim.station_info("seal")
	check_eq(info.kind, "capacity", "the sealer is a capacity machine")
	check_eq(info.slots, 1, "the sealer starts with one slot")
	check(is_equal_approx(info.seconds, sim.PROGRESSION.seal_seconds), "Lv1 seals at the base time")
	var before: float = sim.seal_seconds()
	for level in range(1, 10):
		check_eq(sim.upgrade_station("seal"), "", "sealer upgrades to Lv%d" % (level + 1))
		check(sim.seal_seconds() < before, "each sealer level cuts the time per cup")
		before = sim.seal_seconds()
		if level + 1 == 5: check_eq(sim.seal_slots(), 2, "Lv5 star adds a second slot")
	check_eq(sim.seal_slots(), 3, "Lv10 star adds a third slot")
	check_eq(sim.stars("seal"), 2, "the sealer shows two stars at Lv10")
	check(not sim.upgrade_station("seal").is_empty(), "the sealer stops at Lv10")

func test_price_machines_multiply_and_stars_jump() -> void:
	var sim = opened()
	if sim == null: return
	sim.gold = 100000
	check_eq(sim.station_info("mix").kind, "price", "the milk machine is a price machine")
	var base: int = sim._dish_price("plain_milk_tea")
	var step: float = 1.0 + sim._definition("mix").art_price_step
	var star: float = sim._definition("mix").art_star_mult
	var lemon_step: float = 1.0 + sim._definition("lemonade").art_price_step
	var lemon_star: float = sim._definition("lemonade").art_star_mult
	for level in range(1, 4): sim.upgrade_station("mix")
	check(sim.station_info("mix").next_star, "Lv4 → Lv5 is a star upgrade")
	sim.upgrade_station("mix")
	check_eq(sim.stars("mix"), 1, "Lv5 earns the first star")
	check_eq(sim._dish_price("plain_milk_tea"), roundi(base * pow(step, 4) * star), "four price levels and one star")
	for level in range(5, 10): sim.upgrade_station("mix")
	check_eq(sim.stars("mix"), 2, "Lv10 earns the second star")
	check_eq(sim._dish_price("plain_milk_tea"), roundi(base * pow(step, 9) * star * star), "nine levels and two stars")
	var lemonade: int = sim._dish_price("lemonade")
	for level in range(1, 5): check_eq(sim.upgrade_station("lemonade"), "", "lemonade stand upgrades")
	check(not sim.upgrade_station("lemonade").is_empty(), "the lemonade stand stops at Lv5")
	check_eq(sim._dish_price("lemonade"), roundi(lemonade * pow(lemon_step, 4) * lemon_star), "the lemonade stand gets its one star at Lv5")

func test_v4_save_refunds_lemonade_levels_above_the_new_cap() -> void:
	var sim = opened()
	if sim == null: return
	var old: Dictionary = sim.to_dict()
	old.version = 4
	old.station_levels.lemonade = 8
	old.stations.boil.capacity = 6
	var copy = make_shop()
	check_eq(copy.load_dict(old), "", "a v4 save loads")
	check_eq(copy.station_levels.lemonade, 5, "the lemonade stand is capped at Lv5")
	check_eq(copy.gold, old.gold + 75 + 110 + 150, "levels 6 to 8 are refunded at their old prices")
	check_eq(copy.stations.boil.capacity, 12, "the brewer gets room for a six-cup pot")

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
		for id in ["boil", "seal", "mix", "topping"]:
			if sim.station_info(id).unlock_error.is_empty(): sim.unlock_station(id)
		for material in ["tea_leaf", "milk"]:
			if sim.box_error(material).is_empty(): sim.unlock_box(material)
		if sim.stage_index > 0 and sim.roster.size() < sim.staff_slots() and sim.gold >= sim.hire_cost():
			sim.hire()
			for worker in sim.roster:
				if not worker.deployed: sim.deploy_worker(worker.id)
		if sim.stage_index == 4 and sim.station_levels.topping < 4 and sim.station_info("topping").upgrade_error.is_empty(): sim.upgrade_station("topping")
		for goal in [["lemonade", 5], ["boil", 5], ["seal", 5], ["mix", 10]]:
			if sim.station_levels[goal[0]] < goal[1] and sim.station_info(goal[0]).upgrade_error.is_empty(): sim.upgrade_station(goal[0])
		sim.advance(0.1)
		var all_complete := true
		for row in sim.task_rows(): all_complete = all_complete and row.complete
		if all_complete: break
	var complete := true
	for row in sim.task_rows(): complete = complete and row.complete
	check(complete, "real opening sales pay for every line, staff, star upgrades and all task goals")
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
			for id in 3: sim.orders.append({"id": id + 1, "dish": requested, "wait": 0.0, "reserved": false, "takeaway": false})
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

func test_customers_never_leave_they_get_impatient_then_angry() -> void:
	var sim = opened()
	if sim == null: return
	for worker in sim.workers.duplicate(): sim.recall_worker(worker.id)
	sim.orders = [{"id": 1, "dish": "plain_milk_tea", "wait": 14.9, "reserved": false, "takeaway": false}]
	check_eq(sim.order_mood(sim.orders[0]), 0, "a fresh customer is calm")
	sim.advance(0.2)
	check_eq(sim.orders[0].id, 1, "the customer is still in the queue")
	check_eq(sim.order_mood(sim.orders[0]), 1, "after 15 s the customer is impatient")
	sim.advance(15.0)
	check_eq(sim.orders[0].id, 1, "nobody walks out")
	check_eq(sim.order_mood(sim.orders[0]), 2, "after 30 s the customer is angry")
	var active = opened()
	active.orders = [{"id": 1, "dish": "lemonade", "wait": 40.0, "reserved": false, "takeaway": false}]
	active.advance(0.1)
	check(active.orders[0].reserved, "an angry customer is still served")
	var restored = make_shop()
	check_eq(restored.load_dict(active.to_dict()), "", "angry reserved order resumes")
	for tick in 200:
		active.advance(0.1)
		restored.advance(0.1)
	check_eq(restored.to_dict(), active.to_dict(), "moods and reserved deliveries resume deterministically")
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
	sim.orders = [{"id": 1, "dish": "plain_milk_tea", "wait": 0.0, "reserved": false, "takeaway": false}]
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
	var capacity: int = sim.PROGRESSION.stages[0].queue_capacity
	var seconds: float = sim.PROGRESSION.stages[0].customer_interval * (capacity + 1)
	for tick in int(seconds * 10):
		for order in sim.orders: order.wait = 0.0
		sim.advance(0.1)
	check_eq(sim.orders.size(), capacity, "queue fills to the stage's capacity")
	check_eq(capacity, 4, "the lemonade stage holds four in line")
	var caps: Array = sim.PROGRESSION.stages.map(func(stage) -> int: return stage.queue_capacity)
	check_eq(caps, [4, 5, 6, 7, 8], "each stage lets the line grow by one")

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
	var shipped := {}
	var resumed = make_shop()
	for tick in 6000:
		sim.advance(0.1)
		for shipment in sim.belt_items: shipped[shipment.route] = true
		if not sim.audit().valid:
			check(false, "belted shop conserves goods: %s" % sim.audit())
			return
		if tick == 2500:
			check_eq(resumed.load_dict(sim.to_dict()), "", "state with belts in flight loads")
			check_eq(resumed.to_dict(), sim.to_dict(), "belts and their cargo restore exactly")
	# Belts are retired from the game (old saves are refunded); this only checks that a save with them still runs.
	check(shipped.has("supply_to_boil"), "belt actually carries goods: supply_to_boil")
	check(sim.sold_by_dish.pearl_milk_tea > 0, "belted line still sells topped tea")
	gold = sim.gold
	check_eq(sim.remove_belt("seal_to_shelf"), "", "segment can be taken back")
	check_eq(sim.gold, gold + 40, "taking a segment back refunds it")
	check(sim.audit().valid, "removing a segment keeps cargo conserved")

func test_old_saves_get_their_belts_refunded() -> void:
	var sim = opened()
	if sim == null: return
	check(not sim.BELTS_IN_GAME, "the game no longer sells belts")
	check_eq(sim.buy_belt("seal_to_shelf"), "", "an old save could own a segment")
	check_eq(sim.buy_belt("supply_to_boil"), "", "and another")
	for tick in 300: sim.advance(0.1)
	var gold: int = sim.gold
	check_eq(sim.retire_belts(), 90, "retiring refunds what the segments cost")
	check_eq(sim.gold, gold + 90, "refund reaches the purse")
	check(sim.belts.is_empty() and sim.belt_clock.is_empty(), "no segment remains")
	for tick in 300:
		sim.advance(0.1)
		if not sim.audit().valid:
			check(false, "cups in flight still arrive after retiring: %s" % sim.audit())
			return
	check(sim.belt_items.is_empty(), "cargo already on a segment finishes its trip")

func test_counter_post_holds_only_the_front_slots() -> void:
	var sim = opened()
	if sim == null: return
	var kitchen: Dictionary = sim.workers.filter(func(w): return w.post != "counter")[0]
	check(not sim.assign_post(kitchen.id, "counter").is_empty(), "the counter has one front post to start")
	var resumed = make_shop()
	check_eq(resumed.load_dict(sim.to_dict()), "", "counter post saves and loads")

func test_seated_topping_worker_runs_its_whole_segment() -> void:
	var sim = make_shop()
	if sim == null: return
	sim.gold = 100000
	sim.revenue = 100000
	for unused in 4: sim.hire()
	for line in ["lemonade", "boil", "seal", "mix", "topping"]: sim.unlock_station(line)
	for material in ["tea_leaf", "milk"]: sim.unlock_box(material)
	for id in [2, 3, 4, 5]: sim.deploy_worker(id)
	check_eq(sim.assign_post(5, "topping"), "", "one worker takes the topping seat")
	var seated: Dictionary = sim.workers.filter(func(w): return w.id == 5)[0]
	check(is_equal_approx(sim._walk_speed(seated), seated.speed * 1.3) and is_equal_approx(sim._skill(seated), seated.skill * 1.3), "the seat walks and works 30% faster")
	var seen := {}
	for tick in 3000:
		sim.advance(0.1)
		for worker in sim.workers:
			if worker.job.is_empty(): continue
			var segment: bool = worker.job.kind in ["transfer_to_topping", "topping"] or (worker.job.kind == "carry_to_shelf" and worker.job.src == "topping")
			if worker.id == 5:
				check(segment, "the seated worker stays on its segment")
				seen[worker.job.kind] = true
			else:
				check(not segment, "mobile staff leave the topping segment to the seat")
	check(seen.has("transfer_to_topping") and seen.has("topping") and seen.has("carry_to_shelf"), "the seat fetches, tops and shelves")
	check(sim.audit().valid, "segment ownership preserves simulation invariants")

func test_kitchen_packer_saves_and_takeaway_lemonade_is_fetched_at_the_sealer() -> void:
	var sim = opened()
	if sim == null: return
	sim.orders = [{"id": sim._next_order, "dish": "lemonade", "wait": 0.0, "reserved": false, "takeaway": true}]
	sim._next_order += 1
	var packing_saved := false
	for tick in 600:
		sim.advance(0.1)
		for worker in sim.workers:
			if not worker.job.is_empty() and worker.job.kind == "carry_to_seal" and not packing_saved:
				check(worker.post != "counter", "kitchen staff carry takeaway cups to the sealer")
				check_eq(make_shop().load_dict(sim.to_dict()), "", "a worker packing a cup can be saved")
				packing_saved = true
		if packing_saved: break
	check(packing_saved, "the kitchen packs takeaway cups")
	var job := {"kind": "serve", "src": "seal", "dst": "counter", "item": "lemonade", "count": 1}
	check(sim._source_point(job) != Vector2(330, 910), "takeaway lemonade is picked up at the sealer, not the stand")
	job.src = "supply"
	check_eq(sim._source_point(job), Vector2(330, 910), "dine-in lemonade is still poured at the stand")

func test_brewer_pauses_for_stirring_and_seated_brewer_runs_its_segment() -> void:
	var sim = make_shop()
	if sim == null: return
	sim.gold = 100000
	sim.revenue = 100000
	sim.hire()
	for line in ["lemonade", "boil"]: sim.unlock_station(line)
	sim.unlock_box("tea_leaf")
	sim.deploy_worker(2)
	check_eq(sim.assign_post(2, "boil"), "", "one worker takes the brewer seat")
	var paused_at: Array = []
	var seen := {}
	for tick in 3000:
		var was: String = sim.stations.boil.phase
		sim.advance(0.1)
		var station: Dictionary = sim.stations.boil
		if station.phase == "stir" and was != "stir": paused_at.append(snappedf(station.progress, 0.001))
		for worker in sim.workers:
			if worker.id != 2 or worker.job.is_empty(): continue
			seen[worker.job.kind] = true
			check(worker.job.kind in ["load_boil", "brew_start", "stir", "brew_take", "carry_to_shelf"], "the seated brewer stays on its segment")
	check(paused_at.size() >= 2 and is_equal_approx(paused_at[0], 0.333) and is_equal_approx(paused_at[1], 0.667), "each brew stops at one and two thirds: %s" % [paused_at])
	check(seen.has("stir") and seen.has("load_boil") and seen.has("brew_take"), "the seat loads, stirs and takes the tea")
	check(sim.sold_by_dish.black_tea > 0, "stirred tea still reaches customers")
	check(sim.audit().valid, "stirring preserves simulation invariants")

func test_v3_save_keeps_progress_on_the_new_unlock_order() -> void:
	var sim = opened()
	if sim == null: return
	sim.advance(30)
	var old: Dictionary = sim.to_dict()
	old.version = 3
	old.stage_index = 3
	for key in ["boxes", "seats", "diners"]: old.erase(key)
	old.belts = {"supply_to_boil": true}
	var copy = make_shop()
	check_eq(copy.load_dict(old), "", "a save from before the split loads")
	check_eq(copy.stage_index, 4, "the old topping stage maps to the new last stage")
	check(copy.boxes.tea_leaf and copy.boxes.milk, "boxes of lines already open are owned")
	check(copy.station_unlocked("seal") and copy.station_unlocked("topping"), "every machine the player had stays open")
	check_eq(copy.gold, old.gold + 50, "money is kept and the old belt is refunded")
	check(copy.belts.is_empty(), "no belt survives the migration")
	check_eq(copy.station_levels, old.station_levels, "machine levels are kept")
	check_eq(copy.all_workers().size(), sim.all_workers().size(), "the roster is kept")
	check(copy.audit().valid, "the migrated floor is consistent")
	for tick in 600: copy.advance(0.1)
	check(copy.audit().valid, "the migrated shop keeps running")

func test_dine_in_needs_a_seat_and_takeaway_goes_through_the_sealer() -> void:
	var sim = make_shop()
	if sim == null: return
	sim.unlock_station("lemonade")
	sim.gold = 10000
	check_eq(sim.seats, 3, "the shop opens with three seats")
	check_eq(sim.buy_seat(), "", "a seat can be bought")
	check_eq(sim.seats, 4, "the seat is added")
	sim.revenue = 10000
	for tick in 600: sim.advance(0.1)
	check(sim.sold_by_dish.lemonade > 0, "lemonade is served to seated customers")
	check(sim.diners.size() <= sim.seats, "never more diners than seats")
	for order in sim.orders: check(not order.takeaway, "no takeaway before the sealer")
	sim.unlock_station("boil")
	sim.unlock_box("tea_leaf")
	check_eq(sim.unlock_station("seal"), "", "sealer opens")
	sim.hire()
	sim.hire()
	for worker in sim.all_workers():
		if not worker.deployed: sim.deploy_worker(worker.id)
	var sealed := false
	var takeaway_seen := false
	for tick in 3000:
		sim.advance(0.1)
		for order in sim.orders: takeaway_seen = takeaway_seen or order.takeaway
		if sim.stations.seal.processing > 0: sealed = true
		if not sim.audit().valid:
			check(false, "takeaway keeps goods conserved: %s" % sim.audit())
			return
	check(takeaway_seen, "customers start asking for takeaway")
	check(sealed, "takeaway cups pass through the sealer")
	check(sim.diners.size() <= sim.seats, "seats still cap the diners")

func test_flyers_and_flavors_bring_customers_faster() -> void:
	var sim = opened()
	if sim == null: return
	sim.gold = 100000
	var base: float = sim.PROGRESSION.stages[sim.stage_index].customer_interval
	var flavors := 0
	for material in sim._definition("topping").materials:
		if sim._dish_unlocked(material.item_id): flavors += 1
	check(flavors > 0, "the opened shop sells topped flavors")
	check(is_equal_approx(sim._order_interval(), base / (1.0 + 0.05 * flavors)), "each flavor on the menu brings customers 5% faster")
	var info: Dictionary = sim.station_info("counter")
	check_eq(info.flyers, 1, "flyers start at Lv1")
	for level in range(2, 11): check_eq(sim.buy_flyers(), "", "flyers to Lv%d" % level)
	check(not sim.buy_flyers().is_empty(), "flyers stop at Lv10")
	check(is_equal_approx(sim._order_interval(), base / (1.0 + 0.05 * flavors) / 1.9), "nine flyer levels bring customers 90% faster")
	var copy = make_shop()
	check_eq(copy.load_dict(sim.to_dict()), "", "flyer level saves")
	check_eq(copy.flyers, 10, "flyer level loads")

func test_star_tasks_finish_the_first_shop() -> void:
	var sim = opened()
	if sim == null: return
	check(not sim.shop_complete(), "an opened shop is not finished yet")
	var names: Array = sim.task_rows().map(func(row: Dictionary) -> String: return row.name)
	for name in ["柠檬茶台升 1 星（Lv5）", "煮茶机升 1 星（Lv5）", "封口机升 1 星（Lv5）", "调奶台升 2 星（Lv10）"]:
		check(name in names, "star task listed: " + name)
	sim.gold = 100000
	for goal in [["lemonade", 5], ["boil", 5], ["seal", 5], ["mix", 10], ["topping", 4]]:
		while sim.station_levels[goal[0]] < goal[1]: sim.upgrade_station(goal[0])
	for dish in sim.sold_by_dish: sim.sold_by_dish[dish] = 100
	check(sim.shop_complete(), "with every task done the first shop is complete")
	check_eq(sim.stars("boil"), 1, "the brewer shows its star")

func test_v6_save_refunds_training_and_puts_someone_at_the_counter() -> void:
	var sim = opened()
	if sim == null: return
	sim.advance(30)
	var old: Dictionary = sim.to_dict()
	old.version = 6
	old.erase("front_upgrades")
	old.erase("kitchen_upgrades")
	# Under the old rules nobody had to stand at the counter, and workers carried their own training.
	for worker in old.roster:
		worker.post = ""
	old.roster[1].level = 3
	old.roster[1].speed *= 1.1025
	old.roster[1].capacity += 0
	var copy = make_shop()
	check_eq(copy.load_dict(old), "", "a v6 save loads")
	var refund: int = sim.PROGRESSION.train_costs[0] + sim.PROGRESSION.train_costs[1]
	check_eq(copy.gold, old.gold + refund, "training levels are refunded")
	check_eq(copy.worker_by_id(old.roster[1].id).level, 1, "training is undone")
	check_eq(copy.front_staff(), 1, "someone takes the counter")
	check_eq(copy.stage_index, old.stage_index, "progress is kept")
	check(copy.audit().valid, "the migrated floor is consistent")
	for tick in 600: copy.advance(0.1)
	check(copy.audit().valid and copy.sold > old.sold, "the migrated shop keeps selling")

func test_v6_save_over_the_new_role_limits_recalls_extras_and_refunds_belts() -> void:
	var sim = make_shop()
	if sim == null: return
	sim.gold = 20000
	sim.unlock_station("lemonade")
	sim.unlock_station("boil")
	sim.hire()
	sim.hire()
	var old: Dictionary = sim.to_dict()
	old.version = 6
	old.erase("front_upgrades")
	old.erase("kitchen_upgrades")
	# Under the shared cap all three could be out, and nobody had to stand at the counter.
	old.deployed = []
	for worker in old.roster:
		worker.post = "boil" if worker == old.roster[0] else "topping"
		worker.deployed = true
		old.deployed.append(worker.id)
	old.belts = {"seal_to_shelf": true}
	old.belt_clock = {"seal_to_shelf": 0.0}
	var belt_cost: int = sim._belt_def("seal_to_shelf").cost
	var copy = make_shop()
	check_eq(copy.load_dict(old), "", "a v6 save over the new limits still loads")
	check_eq(copy.front_staff(), 1, "a posted worker is moved to the counter when nobody else can serve")
	check_eq(copy.kitchen_staff(), copy.kitchen_slots(), "kitchen keeps only the seats this stage has")
	check_eq(copy.roster.size(), 3, "extra workers go back to the roster, not away")
	check_eq(copy.gold, old.gold + belt_cost, "owned belts are refunded")
	check(copy.belts.is_empty(), "belts are dropped")
	for tick in 600: copy.advance(0.1)
	check(copy.audit().valid and copy.sold > old.sold, "the migrated shop keeps selling")
