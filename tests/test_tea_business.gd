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
	sim.unlock_station("press")
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
	check(not sim.unlock_station("boil").is_empty(), "the brewer needs the lemonade stand and its price")
	check_eq(sim.to_dict(), before, "rejected unlock is atomic")
	check_eq(sim.unlock_station("lemonade"), "", "lemonade unlocks")
	check_eq(sim.gold, 40, "configured opening cost charged")
	sim.advance(80)
	check(sim.revenue > 0 and sim.gold > 40, "real employee serves lemonade")
	check(sim.audit().valid, "lemonade is conserved")
	check(not sim.unlock_station("mix").is_empty(), "milk waits for the black tea line")
	sim.gold = sim.PROGRESSION.stages[1].line_cost
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
	check(sim._dish_unlocked("black_tea", false) and sim.pending_box().is_empty(), "black tea can be made once the box is in")
	check(sim.kitchen_staff() > 0 or not sim._dish_unlocked("black_tea"), "black tea is not ordered while nobody works the kitchen")
	check(not sim.unlock_box("milk").is_empty(), "the milk box waits for the milk machine")
	sim.revenue = 10000
	sim.gold = 10000
	check(not sim.unlock_station("mix").is_empty(), "milk machine waits for the sealer")
	check_eq(sim.unlock_station("seal"), "", "sealer unlocks on its own")
	check_eq(sim.unlock_station("mix"), "", "milk machine unlocks on its own")
	check_eq(sim.stage_index, 3, "milk tea stage reached")
	check(not sim._dish_unlocked("plain_milk_tea") and sim.pending_box() == "milk", "milk tea waits for the milk box")
	check_eq(sim.unlock_box("milk"), "", "milk box unlocks")
	check(sim._dish_unlocked("plain_milk_tea", false), "milk tea goes on sale")

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
	check_eq(sim.next_hire_art(), "gray_cat", "the new gray cat follows the original four animals")
	sim.gold = 110
	check(sim.hire(), "a fifth employee can be recruited")
	check_eq(sim.worker_by_id(5).art, "gray_cat", "fifth first-time recruit is the new gray cat")
	check_eq(sim.next_hire_art(), "cat", "after one of each, the cycle starts again")
	sim.gold = 135
	check(sim.hire(), "a sixth employee repeats the first animal")
	var second_cat: Dictionary = sim.worker_by_id(6)
	check(not second_cat.is_empty() and second_cat.art == "cat", "a repeat animal takes a fresh id")
	check_eq(sim.all_workers().size(), 6, "six employees can be owned")
	check_eq(sim.next_hire_art(), "raccoon", "repeats follow the animal order")
	check(sim.audit().valid, "five owned staff preserve simulation invariants")
	var copy = make_shop()
	check_eq(copy.load_dict(sim.to_dict()), "", "a roster with a repeat animal saves and loads")

func test_shop_slots_grow_with_each_production_line() -> void:
	var sim = make_shop()
	if sim == null: return
	sim.gold = 100000
	sim.revenue = 100000
	for unused in 7: sim.hire()
	check_eq(sim.staff_slots(), 1, "the lemonade shop runs on one front worker")
	check_eq(sim.workers[0].post, "counter", "who starts at the counter")
	var before: Dictionary = sim.to_dict()
	check(not sim.deploy_worker(2).is_empty(), "a kitchen hand waits for the first line")
	check(sim.deployment_error(2).contains("煮茶机"), "the refusal names the line that opens the kitchen")
	check_eq(sim.to_dict(), before, "blocked deployment is atomic")
	check_eq(sim.unlock_station("lemonade"), "", "open lemonade")
	var next_id := 2
	for line in ["boil", "seal", "mix", "press", "topping"]:
		var before_slots: int = sim.kitchen_slots()
		check_eq(sim.unlock_station(line), "", "open " + line)
		var added := 1
		check_eq(sim.kitchen_slots(), before_slots + added, "%s line adds %d kitchen slot(s)" % [line, added])
		for unused in added:
			check_eq(sim.deploy_worker(next_id), "", "the new slot takes one more employee")
			next_id += 1
		check(not sim.deploy_worker(next_id).is_empty(), "but no more than the slots")
	check_eq(sim.kitchen_staff(), 5, "a full kitchen runs five staff")
	check_eq(sim.deployment_error(next_id), "后厨最多 5 位员工", "the last line names no further unlock")
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
	check_eq(sim.deploy_at(extra.id, "counter", sim.Layout.POINTS.counter), "", "a second front worker takes the counter")
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
	check_eq(sim.all_workers()[-1].art, "rabbit", "the second rabbit takes a fresh id")
	check(not sim.all_workers()[-1].deployed, "the second rabbit starts in reserve")
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
	check(sim.task_rows().size() == 11, "all task goals exposed, including the star tasks")
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
	check_eq(sim.deploy_at(2, "", sim.Layout.POINTS.counter), "", "valid mobile drop deploys and places")
	check_eq(sim.worker_by_id(2).pos, sim.Layout.POINTS.counter, "physical actor starts at valid drop")

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

func test_price_bonuses_add_up_and_stars_jump() -> void:
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
	# Bonuses add up instead of multiplying: each level adds one step, each star adds (star - 1).
	check_eq(sim._dish_price("plain_milk_tea"), roundi(base * (1.0 + 4 * (step - 1.0) + star - 1.0)), "four price levels and one star")
	for level in range(5, 10): sim.upgrade_station("mix")
	check_eq(sim.stars("mix"), 2, "Lv10 earns the second star")
	check_eq(sim._dish_price("plain_milk_tea"), roundi(base * (1.0 + 9 * (step - 1.0) + 2 * (star - 1.0))), "nine levels and two stars")
	var lemonade: int = sim._dish_price("lemonade")
	var pour: float = sim._speed("lemonade")
	for level in range(1, 10): check_eq(sim.upgrade_station("lemonade"), "", "lemonade stand upgrades")
	check(not sim.upgrade_station("lemonade").is_empty(), "the lemonade stand stops at Lv10")
	check_eq(sim._dish_price("lemonade"), roundi(lemonade * (1.0 + 9 * (lemon_step - 1.0) + 2 * (lemon_star - 1.0))), "lemonade stays worth upgrading: ten levels and two stars")
	check(sim._speed("lemonade") > pour, "lemonade stand levels also pour faster")

func test_v4_save_refunds_lemonade_levels_above_the_new_cap() -> void:
	var sim = opened()
	if sim == null: return
	var old: Dictionary = sim.to_dict()
	old.version = 4
	old.station_levels.lemonade = 8
	old.stations.boil.capacity = 6
	var copy = make_shop()
	check_eq(copy.load_dict(old), "", "a v4 save loads")
	# The stand now goes to Lv10, so a v4 Lv8 stand is kept as it is.
	check_eq(copy.station_levels.lemonade, 8, "lemonade levels within the cap are kept")
	check_eq(copy.gold, old.gold, "nothing to refund")
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
		for id in ["boil", "seal", "mix", "press", "topping"]:
			if sim.station_info(id).unlock_error.is_empty(): sim.unlock_station(id)
		for material in ["tea_leaf", "milk"]:
			if sim.box_error(material).is_empty(): sim.unlock_box(material)
		if sim.stage_index > 0 and sim.roster.size() < sim.staff_slots() and sim.gold >= sim.hire_cost():
			sim.hire()
			for worker in sim.roster:
				if not worker.deployed: sim.deploy_worker(worker.id)
		if sim.stage_index == 5 and sim.station_levels.topping < 4 and sim.station_info("topping").upgrade_error.is_empty(): sim.upgrade_station("topping")
		for goal in [["lemonade", 5], ["boil", 5], ["seal", 5], ["mix", 10], ["press", 5]]:
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
			# The kitchen brews a fresh pot for the order and the front may serve walk-ins too, so allow two minutes.
			for tick in 1200:
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
	check_eq(capacity, 3, "the lemonade stage holds three in line (one row, no crowd at the door)")
	var caps: Array = sim.PROGRESSION.stages.map(func(stage) -> int: return stage.queue_capacity)
	check_eq(caps, [3, 4, 5, 7, 8, 8], "the line grows with each stage")

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
	check_eq(sim.gold, gold - 250, "segment charges its price")
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
	check_eq(sim.gold, gold + 250, "taking a segment back refunds it")
	check(sim.audit().valid, "removing a segment keeps cargo conserved")

func test_old_saves_get_their_belts_refunded() -> void:
	var sim = opened()
	if sim == null: return
	check(not sim.BELTS_IN_GAME, "the game no longer sells belts")
	check_eq(sim.buy_belt("seal_to_shelf"), "", "the sealer conveyor is still for sale")
	check_eq(sim.buy_belt("supply_to_boil"), "", "an old save could own another segment")
	for tick in 300: sim.advance(0.1)
	var gold: int = sim.gold
	check_eq(sim.retire_belts(), 50, "retiring refunds what the old segments cost")
	check_eq(sim.gold, gold + 50, "refund reaches the purse")
	check_eq(sim.belts.keys(), ["seal_to_shelf"], "only the conveyor the game sells remains")
	for tick in 300:
		sim.advance(0.1)
		if not sim.audit().valid:
			check(false, "cups in flight still arrive after retiring: %s" % sim.audit())
			return
	check(sim.belt_items.all(func(shipment): return shipment.route == "seal_to_shelf"), "cargo already on a retired segment finishes its trip")

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
	for line in ["lemonade", "boil", "seal", "mix", "press", "topping"]: sim.unlock_station(line)
	for material in ["tea_leaf", "milk"]: sim.unlock_box(material)
	# The task-pool rules (kept as a fallback) give the seat a whole segment.
	sim.follow_orders = false
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
	check(sim._source_point(job) != sim.Layout.POINTS.lemonade, "takeaway lemonade is picked up at the sealer, not the stand")
	job.src = "supply"
	check_eq(sim._source_point(job), sim.Layout.POINTS.lemonade, "dine-in lemonade is still poured at the stand")

func test_brewer_pauses_for_stirring_and_seated_brewer_runs_its_segment() -> void:
	var sim = make_shop()
	if sim == null: return
	sim.gold = 100000
	sim.revenue = 100000
	sim.hire()
	for line in ["lemonade", "boil"]: sim.unlock_station(line)
	sim.unlock_box("tea_leaf")
	sim.follow_orders = false
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
	check_eq(copy.stage_index, 5, "the old topping stage maps to the new last stage")
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
	check(is_equal_approx(sim._order_interval(), base), "flavors make cups dearer; they no longer bring customers faster")
	var info: Dictionary = sim.station_info("counter")
	check_eq(info.flyers, 1, "flyers start at Lv1")
	for level in range(2, 11): check_eq(sim.buy_flyers(), "", "flyers to Lv%d" % level)
	check(not sim.buy_flyers().is_empty(), "flyers stop at Lv10")
	check(is_equal_approx(sim._order_interval(), base / 1.9), "nine flyer levels bring customers 90% faster")
	var copy = make_shop()
	check_eq(copy.load_dict(sim.to_dict()), "", "flyer level saves")
	check_eq(copy.flyers, 10, "flyer level loads")

func test_star_tasks_finish_the_first_shop() -> void:
	var sim = opened()
	if sim == null: return
	check(not sim.shop_complete(), "an opened shop is not finished yet")
	var names: Array = sim.task_rows().map(func(row: Dictionary) -> String: return row.name)
	for name in ["柠檬水台升 1 星（Lv5）", "煮茶机升 1 星（Lv5）", "封口机升 1 星（Lv5）", "调奶台升 2 星（Lv10）"]:
		check(name in names, "star task listed: " + name)
	sim.gold = 100000
	sim.revenue = 100000
	check(not sim.shop_complete(), "the press table's tasks are still open")
	for goal in [["lemonade", 5], ["boil", 5], ["seal", 5], ["mix", 10], ["topping", 4], ["press", 5]]:
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

func _full_line(kitchen: int):
	var sim = make_shop()
	if sim == null: return null
	sim.gold = 100000
	sim.revenue = 100000
	for unused in kitchen: sim.hire()
	for line in ["lemonade", "boil", "seal", "mix", "press", "topping"]: sim.unlock_station(line)
	for material in ["tea_leaf", "milk"]: sim.unlock_box(material)
	for unused in 3: sim.upgrade_station("topping")
	for index in kitchen: check_eq(sim.deploy_worker(index + 2), "", "kitchen hand %d deployed" % (index + 2))
	return sim

func test_kitchen_staff_follow_an_order_from_the_pot_to_the_shelf() -> void:
	var sim = _full_line(3)
	if sim == null: return
	check(sim.follow_orders, "following orders is the default")
	var stages := {}
	var finished := 0
	var wrong_flavor := 0
	var made := {}
	for dish in sim.DISHES: made[dish] = sim.stations.topping.output.get(dish, 0)
	for tick in 4000:
		var before := {}
		var done_before := {}
		for worker in sim.workers:
			before[worker.id] = worker.ticket.duplicate()
			done_before[worker.id] = worker.completed
		sim.advance(0.1)
		for dish in made:
			var now: int = sim.stations.topping.output.get(dish, 0)
			if now > made[dish] and not sim.orders.any(func(order): return order.dish == dish): wrong_flavor += 1
			made[dish] = now
		for worker in sim.workers:
			var was: Dictionary = before[worker.id]
			if worker.ticket.is_empty() and not was.is_empty() and was.stage in ["topped", "topping"]: finished += 1
			if worker.ticket.is_empty(): continue
			stages[worker.ticket.stage] = true
			check(worker.post != "counter", "only kitchen staff follow orders")
			check(was.is_empty() or was.dish == worker.ticket.dish or worker.completed > done_before[worker.id], "a follower keeps its drink until it is done")
	check(stages.has("boil") and stages.has("mix") and stages.has("topping") and stages.has("topped"), "followers walk the whole route: %s" % [stages.keys()])
	check(finished > 5, "flavored cups are followed to the end (%d)" % finished)
	check_eq(wrong_flavor, 0, "the topping machine only makes flavors someone in line ordered")
	var flavors := 0
	for dish in ["pearl_milk_tea", "coconut_milk_tea", "redbean_milk_tea", "taro_milk_tea"]: flavors += 1 if sim.sold_by_dish[dish] > 0 else 0
	check(flavors >= 2, "several ordered flavors are sold")
	check(sim.audit().valid, "following orders keeps every cup accounted for: %s" % [sim.audit().errors])
	check_eq(make_shop().load_dict(sim.to_dict()), "", "a shop with followers on the way saves and loads")

func test_orders_next_to_each_other_for_the_same_drink_share_one_follower() -> void:
	var sim = _full_line(1)
	if sim == null: return
	sim.orders.clear()
	for unused in 3:
		sim.orders.append({"id": sim._next_order, "wait": 0.0, "reserved": false, "dish": "pearl_milk_tea", "takeaway": false})
		sim._next_order += 1
	sim.advance(0.1)
	var follower: Dictionary = sim.workers.filter(func(worker): return worker.post != "counter")[0]
	check_eq(follower.ticket.get("dish", ""), "pearl_milk_tea", "the oldest order is taken")
	check_eq(follower.ticket.get("count", 0), mini(3, sim._carry(follower)), "the same drink right behind it comes along")
	check(sim.open_orders().size() == 3 - follower.ticket.count, "those orders are no longer open")

func test_a_seated_brewer_keeps_the_pot_while_followers_carry_the_tea() -> void:
	var sim = make_shop()
	if sim == null: return
	sim.gold = 100000
	sim.revenue = 100000
	sim.hire()
	sim.hire()
	for line in ["lemonade", "boil", "seal"]: sim.unlock_station(line)
	sim.unlock_box("tea_leaf")
	sim.deploy_worker(2)
	sim.deploy_worker(3)
	check_eq(sim.assign_post(2, "boil"), "", "one worker keeps the pot")
	var seen := {}
	var stirred := false
	for tick in 3000:
		sim.advance(0.1)
		for worker in sim.workers:
			if worker.job.is_empty(): continue
			if worker.id == 2:
				check(worker.job.kind in ["load_boil", "brew_start", "stir", "brew_take"], "the seat only keeps the pot going")
				stirred = stirred or worker.job.kind == "stir"
			elif worker.id == 3: seen[worker.job.kind] = true
	check(stirred, "the pot still needs stirring")
	check(seen.has("carry_to_shelf") or seen.has("carry_to_seal"), "the follower carries the tea out")
	check(sim.sold_by_dish.black_tea > 0, "black tea reaches customers")
	check(sim.audit().valid, "pot keeping preserves simulation invariants")

func test_v7_save_loads_with_nobody_following_yet() -> void:
	var sim = _full_line(2)
	if sim == null: return
	for tick in 300: sim.advance(0.1)
	var old: Dictionary = sim.to_dict()
	old.version = 7
	for worker in old.roster: worker.erase("ticket")
	var copy = make_shop()
	check_eq(copy.load_dict(old), "", "a v7 save loads")
	check(copy.workers.all(func(worker): return worker.ticket.is_empty()), "nobody is following anything yet")
	for tick in 600: copy.advance(0.1)
	check(copy.audit().valid and copy.sold > old.sold, "the loaded shop keeps selling")

func test_cups_left_at_the_topping_machine_are_picked_up_by_the_next_follower() -> void:
	var sim = _full_line(1)
	if sim == null: return
	var follower: Dictionary = sim.workers.filter(func(worker): return worker.post != "counter")[0]
	var left := 0
	for tick in 3000:
		sim.advance(0.1)
		if follower.ticket.get("stage", "") == "topping":
			left = follower.ticket.count
			break
	check(left > 0, "a follower brings milk tea to the topping machine")
	check_eq(sim.recall_worker(follower.id), "", "and is called away before topping it")
	check_eq(sim.stations.topping.input.plain_milk_tea, left, "the cups stay at the machine")
	check_eq(sim.deploy_worker(follower.id), "", "someone comes back")
	var resumed := false
	for tick in 50:
		sim.advance(0.1)
		if follower.ticket.get("stage", "") in ["topping", "topped"] and sim.stations.topping.input.plain_milk_tea < left: resumed = true
		if resumed: break
	check(resumed, "the next follower tops the cups left behind instead of fetching new ones")
	check(sim.audit().valid, "picking up left cups keeps every cup accounted for")

# ---- Press table (fruit teas) and lemonade to go ----

func test_lemon_tea_is_pressed_at_the_front_from_a_lemonade() -> void:
	var sim = _full_line(2)
	if sim == null: return
	check(sim.station_unlocked("press"), "the front press opens before the topping machine")
	check(sim._dish_unlocked("lemon_tea", false), "lemon tea is on the menu once the press is open")
	sim.orders.clear()
	sim.orders.append({"id": 900, "dish": "lemon_tea", "wait": 0.0, "reserved": false, "takeaway": true})
	sim.orders.append({"id": 901, "dish": "lemon_tea", "wait": 0.0, "reserved": false, "takeaway": false})
	sim._next_order = 902
	var makers := {}
	for tick in 600:
		sim.advance(0.1)
		for worker in sim.workers:
			if not worker.job.is_empty() and worker.job.item == "lemon_tea":
				makers[worker.post] = true
				check_eq(worker.job.src, "supply", "lemon tea is made at the stand, never fetched from the kitchen")
		check_eq(sim.stations.seal.input.lemon_tea + sim.stations.seal.output.lemon_tea, 0, "lemon tea to go is not sealed")
		if sim.sold_by_dish.lemon_tea >= 2: break
	check_eq(sim.sold_by_dish.lemon_tea, 2, "both lemon teas reach their customers")
	check_eq(makers.keys(), ["counter"], "only the front makes lemon tea")
	var lemonade_seconds: float = sim._action_duration({"kind": "serve", "src": "supply", "item": "lemonade", "count": 1}, sim.workers[0])
	var tea_seconds: float = sim._action_duration({"kind": "serve", "src": "supply", "item": "lemon_tea", "count": 1}, sim.workers[0])
	check(tea_seconds > lemonade_seconds, "pressing lemon takes longer than pouring a lemonade")
	var price: int = sim._dish_price("lemon_tea")
	sim.upgrade_station("lemonade")
	check(sim._dish_price("lemon_tea") > price, "the lemonade stand's levels also raise the lemon tea price")
	check(sim.audit().valid, "lemon tea keeps every cup accounted for: %s" % [sim.audit().errors])
	check_eq(make_shop().load_dict(sim.to_dict()), "", "a shop with lemon tea saves and loads")
	var info: Dictionary = sim.station_info("press")
	check_eq(info.name, "手打台", "the machine card names the press")
	check(info.seconds > 0 and info.next_seconds > 0 and info.next_seconds < info.seconds, "upgrading presses faster")
	check_eq(info.materials.map(func(row): return row.id), ["lemon"], "one fruit: lemon")

func test_the_sealer_conveyor_carries_takeaway_cups_to_the_rack() -> void:
	var sim = _full_line(2)
	if sim == null: return
	check_eq(sim.buy_belt("seal_to_shelf"), "", "the conveyor is for sale once the milk station is open")
	var hand_carried := 0
	var shipped := 0
	for tick in 3000:
		sim.advance(0.1)
		for worker in sim.workers:
			if not worker.job.is_empty() and worker.job.kind == "carry_to_pickup": hand_carried += 1
		for shipment in sim.belt_items: if shipment.route == "seal_to_shelf": shipped += 1
		if tick % 50 == 0 and not sim.audit().valid:
			check(false, "belted takeaway conserves: %s" % [sim.audit().errors])
			return
	check(shipped > 0, "sealed cups ride the conveyor")
	# A cup on the conveyor still covers its order: nobody packs or makes a second one meanwhile.
	var need: int = sim._pack_need("black_tea")
	var supply: int = sim._kitchen_supply().black_tea
	sim.belt_items.append({"route": "seal_to_shelf", "item": "black_tea", "count": 1, "progress": 0.0, "duration": 3.0, "dst": "pickup"})
	check_eq(sim._pack_need("black_tea"), need - 1, "a cup on the conveyor counts as packed")
	check_eq(sim._kitchen_supply().black_tea, supply + 1, "a cup on the conveyor counts as made")
	sim.belt_items.pop_back()
	check_eq(hand_carried, 0, "nobody carries sealed cups to the rack by hand")
	check(sim.sold > 0 and sim.audit().valid, "the shop keeps selling")
	var copy = make_shop()
	check_eq(copy.load_dict(sim.to_dict()), "", "the conveyor saves and loads")
	check(copy.belts.has("seal_to_shelf"), "the conveyor is kept on load")

func test_lemonade_to_go_is_handed_over_without_the_sealer() -> void:
	var sim = make_shop()
	if sim == null: return
	sim.gold = 5000
	sim.revenue = 5000
	sim.unlock_station("lemonade")
	sim.unlock_station("boil")
	sim.unlock_station("seal")
	sim.orders.clear()
	sim.orders.append({"id": 950, "dish": "lemonade", "wait": 0.0, "reserved": false, "takeaway": true})
	sim._next_order = 951
	var seated: int = sim.diners.size()
	for tick in 400:
		sim.advance(0.1)
		check_eq(sim.stations.seal.input.lemonade + sim.stations.seal.output.lemonade, 0, "lemonade never goes to the sealer")
		if sim.sold_by_dish.lemonade > 0: break
	check(sim.sold_by_dish.lemonade > 0, "the takeaway lemonade is sold")
	check_eq(sim.diners.size(), seated, "a lemonade to go takes no seat")
	check_eq(sim.dish_name("lemonade"), "柠檬水", "the front drink is called lemonade (柠檬水)")
	check_eq(sim.dish_name("lemon_tea"), "柠檬茶", "lemon tea is the front's second drink")

## Takes the press table and fruit teas out of a save, as saves from before v9 had them.
func _strip_press(old: Dictionary) -> void:
	# Saves from then had sold no lemon tea.
	old.sold -= int(old.sold_by_dish.get("lemon_tea", 0))
	old.stations.erase("press")
	for key in ["shelf_stock", "sold_by_dish"]:
		for dish in ["lemon_tea", "banana_tea"]: old[key].erase(dish)
	for dish in ["lemon_tea", "banana_tea"]:
		old.stations.seal.input.erase(dish)
		old.stations.seal.output.erase(dish)
	old.station_levels.erase("press")
	old.unlocked_stations.erase("press")
	old.material_levels.erase("press")

func test_v6_save_without_the_press_table_still_loads() -> void:
	var sim = opened()
	if sim == null: return
	sim.advance(30)
	var old: Dictionary = sim.to_dict()
	old.version = 6
	old.erase("front_upgrades")
	old.erase("kitchen_upgrades")
	for worker in old.roster: worker.erase("ticket")
	_strip_press(old)
	old.stage_index = 4
	var copy = make_shop()
	check_eq(copy.load_dict(old), "", "a v6 save from before the press table loads")
	check(copy.station_unlocked("press") and copy.station_levels.press == 1, "past the topping machine it gets the front press at Lv1")

func test_v8_save_loads_with_the_press_table_still_locked() -> void:
	var sim = _full_line(2)
	if sim == null: return
	for tick in 300: sim.advance(0.1)
	var old: Dictionary = sim.to_dict()
	old.version = 8
	_strip_press(old)
	old.stage_index = 4
	var copy = make_shop()
	check_eq(copy.load_dict(old), "", "a v8 save loads")
	check(copy.station_unlocked("press") and copy.stage_index == 5, "past the topping machine it gets the front press")
	check_eq(copy.station_levels.press, 1, "at Lv1")
	for tick in 600: copy.advance(0.1)
	check(copy.audit().valid and copy.sold > old.sold, "the loaded shop keeps selling")

func test_new_dishes_and_takeaway_ease_in_over_a_dozen_customers() -> void:
	var sim = opened()
	if sim == null: return
	var full: Dictionary = sim.PROGRESSION.stages[sim.stage_index].order_weights
	var weights: Dictionary = sim.order_weights()
	check(is_equal_approx(weights.pearl_milk_tea, full.pearl_milk_tea * sim.RAMP_START), "a dish that just opened starts at a quarter of its weight")
	check(is_equal_approx(sim.takeaway_share(), sim.PROGRESSION.stages[sim.stage_index].takeaway_share * sim.RAMP_START), "takeaway starts low when the sealer opens")
	for i in sim.RAMP_ORDERS: sim._add_order()
	weights = sim.order_weights()
	check(is_equal_approx(weights.pearl_milk_tea, full.pearl_milk_tea), "after a dozen customers the dish has its full weight")
	check(is_equal_approx(sim.takeaway_share(), sim.PROGRESSION.stages[sim.stage_index].takeaway_share), "takeaway reaches its full share too")
	var copy = make_shop()
	check_eq(copy.load_dict(sim.to_dict()), "", "the ease-in counters save")
	check_eq(copy.order_ramp, sim.order_ramp, "the ease-in counters load")

func test_v9_save_counts_open_dishes_as_eased_in() -> void:
	var sim = opened()
	if sim == null: return
	var state: Dictionary = sim.to_dict()
	state.version = 9
	state.erase("order_ramp")
	# A v9 save in the milk stage: the topping machine not yet open.
	state.stage_index = 3
	for id in ["press", "topping"]: state.unlocked_stations[id] = false
	var copy = make_shop()
	check_eq(copy.load_dict(state), "", "a v9 save loads")
	check_eq(copy.order_ramp.plain_milk_tea, copy.RAMP_ORDERS, "dishes already sold keep their full weight")
	check_eq(copy.order_ramp.takeaway, copy.RAMP_ORDERS, "takeaway keeps its full share")
	check_eq(copy.order_ramp.pearl_milk_tea, 0, "a dish that opens later still eases in")

func test_dine_in_customers_sit_shorter_early_and_longer_later() -> void:
	var sim = make_shop()
	if sim == null: return
	check(sim.seat_seconds(0) < sim.seat_seconds(sim.PROGRESSION.stages.size() - 1), "early customers leave their seat sooner than late ones")
	check(is_equal_approx(sim.seat_seconds(), sim.seat_seconds(0)), "the current stage sets how long a customer sits")


## 2026-11-02 playtest: brewer bought with the last coins, no kitchen hand, and black tea orders filled
## the queue for good (customers never leave), so lemonade stopped selling and hiring was out of reach.
func test_kitchen_drinks_wait_for_a_kitchen_hand_so_lemonade_keeps_selling() -> void:
	var sim = make_shop()
	if sim == null: return
	sim.unlock_station("lemonade")
	sim.gold = sim.PROGRESSION.stages[1].line_cost + 20
	check_eq(sim.unlock_station("boil"), "", "brewer bought")
	check_eq(sim.unlock_box("tea_leaf"), "", "tea leaf box bought")
	check_eq(sim.kitchen_staff(), 0, "only the counter worker so far")
	sim.advance(600.0)
	check(sim.orders.all(func(order: Dictionary) -> bool: return order.dish == "lemonade"), "only lemonade is ordered without a kitchen hand")
	check(sim.gold >= sim.hire_cost(), "lemonade earns enough to hire the first kitchen hand")
	check(sim.hire(), "the kitchen hand can be hired")
	for worker in sim.all_workers():
		if not worker.deployed: sim.deploy_worker(worker.id)
	check(sim._dish_unlocked("black_tea"), "black tea goes on sale once someone works the kitchen")


## Item 16 (option B): the kitchen seals takeaway cups and puts them on the shelf's takeaway rack;
## the front picks up only at the shelf and the lemonade stand, never in the kitchen.
func test_sealed_takeaway_cups_go_to_the_shelf_rack_and_the_front_never_enters_the_kitchen() -> void:
	var sim = opened()
	if sim == null: return
	var wanted: int = sim._next_order
	sim.orders = [{"id": wanted, "dish": "plain_milk_tea", "wait": 0.0, "reserved": false, "takeaway": true}]
	sim._next_order += 1
	var racked := false
	var front_sources := {}
	for tick in 1500:
		sim.advance(0.1)
		for worker in sim.workers:
			if worker.job.is_empty(): continue
			if worker.post == "counter": front_sources[worker.job.src] = true
			if worker.job.kind == "carry_to_pickup":
				check(worker.post != "counter", "kitchen staff carry sealed cups to the rack")
				racked = true
		if not sim.orders.any(func(order: Dictionary) -> bool: return order.id == wanted): break
	check(racked, "the sealed cup was carried to the shelf's takeaway rack")
	check(not sim.orders.any(func(order: Dictionary) -> bool: return order.id == wanted), "the takeaway customer got their cup")
	check(not front_sources.has("seal"), "the front never fetches from the sealer")
	check(front_sources.has("pickup"), "the front picks the sealed cup up at the shelf")
	check_eq(sim._source_point({"kind": "serve", "src": "pickup", "dst": "counter", "item": "plain_milk_tea", "count": 1}), sim.Layout.POINTS.shelf, "the rack is where the shelf is")
	check(sim.audit().valid, "goods are conserved: %s" % [sim.audit().errors])
	var copy = make_shop()
	check_eq(copy.load_dict(sim.to_dict()), "", "the rack saves and loads")

func test_v10_save_gets_an_empty_takeaway_rack() -> void:
	var sim = opened()
	if sim == null: return
	sim.advance(30.0)
	var state: Dictionary = sim.to_dict()
	state.version = 10
	state.stations.erase("pickup")
	var copy = make_shop()
	check_eq(copy.load_dict(state), "", "a v10 save loads")
	check(copy.stations.has("pickup"), "the takeaway rack is added")
	check_eq(copy.stations.pickup.capacity, copy.PICKUP_CAPACITY, "with its normal size")

func test_v11_save_drops_the_kitchen_press_and_banana_tea() -> void:
	var sim = opened()
	if sim == null: return
	sim.advance(30.0)
	var state: Dictionary = sim.to_dict()
	# Shape of a v11 save at the old topping stage: kitchen press table locked, banana tea on the books.
	state.version = 11
	state.stage_index = 4
	state.unlocked_stations.press = false
	state.stations.press = {"input": {"tea": 1}, "output": {"lemon_tea": 0, "banana_tea": 1}, "phase": "idle", "progress": 0.0,
		"label": "press", "capacity": 6, "processing": 0, "remaining": 0.0, "duration": 0.0, "reserved_in": 0, "reserved_out": {},
		"work_reserved": false, "processing_item": ""}
	for key in ["shelf_stock", "order_ramp"]: state[key].banana_tea = 0
	state.sold_by_dish.banana_tea = 3
	state.sold += 3
	state.material_levels.press.banana = 2
	for key in ["input", "output"]:
		state.stations.seal[key].banana_tea = 0
	state.stations.pickup.output.banana_tea = 0
	var lemon_sold: int = state.sold_by_dish.lemon_tea
	var copy = make_shop()
	check_eq(copy.load_dict(state), "", "a v11 save loads")
	check_eq(copy.stage_index, 5, "the old topping stage is the new last stage")
	check(copy.station_unlocked("press") and copy.station_unlocked("topping"), "the front press comes with it")
	check(not copy.stations.has("press") and not copy.sold_by_dish.has("banana_tea"), "the kitchen press and banana tea are gone")
	check_eq(copy.sold_by_dish.lemon_tea, lemon_sold + 3, "banana teas sold count as lemon teas")
	check_eq(copy.sold, state.sold, "the sales total is kept")
	check(copy.audit().valid, "the migrated floor is consistent")
	for tick in 600: copy.advance(0.1)
	check(copy.audit().valid and copy.sold > state.sold, "the migrated shop keeps selling")
