extends "res://tests/test_case.gd"

func _opened(id := "tea") -> ShopRules:
	var shop: SpecShop = load("res://content/shops/"+id+"/shop.tres")
	var owner := ShopRules.new(shop,42)
	owner.gold = maxf(owner.gold,float(shop.stages[0].cost))
	check_eq(owner.unlock(shop.sold_at(0)),"","open the actual first stage")
	return owner

func test_counter_finishes_first_drink_before_starting_a_second() -> void:
	var owner := _opened()
	var operations := {}
	for tick in 180:
		owner.step(0.1)
		check_eq(owner.runtime.last_error,"","formal opening runs without capability errors")
		if owner.sold>0: break
		for task in owner.runtime.runner.tasks.values():
			if task.kind=="operate": operations[task.run] = true
	check_eq(operations.size(),1,"completed drink continues to handoff before another drink starts")
	check(owner.sold>0 and owner.clock<=9.0,"first drink returns to the main opening cadence (main 8.1s)")

func test_at_port_operation_starts_without_an_empty_walking_tick() -> void:
	var owner := _opened()
	var worker: Dictionary = owner.workers[0]
	worker.pos = owner.runtime.runner.ports.lemonade
	owner.step(0.1)
	check_eq(worker.phase,"work","already at the real work port starts operating immediately")
	check(not worker.walking,"zero-distance move is not displayed as walking")
	check_eq(owner.runtime.restore(owner.runtime.snapshot()),"","fast-forwarded action keeps valid saved cursors")

func test_tiny_logistics_do_not_repeat_the_manufacturing_bar() -> void:
	var owner := _opened()
	var observed := {}
	for tick in 180:
		owner.step(0.1)
		var frame := ShopView.new(owner).render_snapshot()
		for worker in frame.workers:
			if worker.phase in ["pickup","dropoff"]:
				observed[worker.phase] = true
				check_eq(worker.display_progress,-1.0,"short hand movements do not show another work countdown")
				check(worker.get("display_working",false)==(worker.action.status!="blocked"),"only actual hand work animates")
		if owner.sold>0: break
	check(observed.has("pickup") and observed.has("dropoff"),"exercise actual inventory pickup and handoff")

func test_counter_guest_is_called_during_production_and_handoff_waits_for_arrival() -> void:
	var owner := _opened()
	var saw_work := false
	for tick in 180:
		owner.step(0.1)
		if owner.sold>0: break
		for task in owner.runtime.runner.tasks.values():
			if task.kind!="operate": continue
			if owner.worker_by_id(task.worker).phase!="work": continue
			saw_work = true
			var guest: Dictionary = owner.runtime.service.orders.guest(1)
			check_eq(owner.runtime.service.customers.record(1).target,"pickup","call the guest while their employee prepares the order")
			check_eq(guest.state,"waiting","calling is not an inventory handoff")
	check(saw_work,"exercise real manual preparation")
	check(owner.sold>0,"real guest arrival eventually allows delivery")

func test_early_call_and_previous_seat_target_both_restore_without_replaying_goods() -> void:
	var owner := _opened()
	owner.run(3.5)
	var current := owner.to_dict()
	check_eq(owner.runtime.service.customers.record(1).target,"pickup","active follower calls their actual guest")
	check_eq(owner.load_dict(current),"","new early-call save restores")
	var guest: Dictionary = owner.runtime.service.orders.guest(1)
	check_eq(owner.runtime.service.customers.request(1,guest.seat),"","reconstruct previous version's legal waiting route")
	var previous := owner.to_dict()
	check_eq(owner.load_dict(previous),"","previous valid seat target is accepted during earlier call adoption")
	owner.step(0.1)
	check_eq(owner.runtime.service.customers.record(1).target,"pickup","next normal step adopts current order routing")
	for tick in 140:
		owner.step(0.1)
		check_eq(owner.load_dict(owner.to_dict()),"","every inventory and action boundary roundtrips")
		if owner.sold>0: break
	check_eq(owner.sold,1,"resume commits the original sale exactly once")

func test_authored_long_counter_work_retains_its_timer_and_visible_progress() -> void:
	var shop: SpecShop = load("res://content/shops/tea/shop.tres").copy_for_editing()
	shop.runtime_template = shop.runtime_template.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	shop.runtime_template.recipes.lemonade.nodes[1].seconds = 2.0
	var owner := ShopRules.new(shop,42)
	owner.gold = 1000.0
	check_eq(owner.unlock(shop.sold_at(0)),"","open formal shop with an authored long finishing action")
	for tick in 180:
		owner.step(0.1)
		var frame := ShopView.new(owner).render_snapshot()
		for worker in frame.workers:
			var task: Dictionary = owner.runtime.runner.tasks.get(worker.id,{})
			if task.get("to","")!="counter:lemonade" or worker.phase!="dropoff": continue
			check_eq(task.drop_seconds,2.0,"coalescing bookkeeping does not discard authored long work")
			check(worker.display_progress>=0.0,"meaningful long counter work still displays progress")
			return
	check(false,"long finishing action was exercised")
