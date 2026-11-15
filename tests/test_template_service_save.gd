extends "res://tests/test_case.gd"
const Fixture := preload("res://tests/fixtures/template_service.gd")

func _runtime(delivery := "counter", admission := "automatic") -> RefCounted:
	var runtime := Fixture.runtime(delivery, admission)
	check(runtime.has_method("arrive"), "integrated service runtime exists")
	return runtime if runtime.has_method("arrive") else null

func _copy_outer_economy(source: RefCounted, destination: RefCounted) -> void:
	# The public runtime owns no second wallet. The outer session persists this
	# once; these tests explicitly restore it separately from service state.
	for key in ["gold", "revenue", "sold", "sale_carry"]: destination._sales.set(key, source._sales.get(key))
	destination.sold_by_dish = source.sold_by_dish.duplicate(true)

func _finish(runtime: RefCounted) -> void:
	for tick in 2400:
		check_eq(runtime.step(0.1), "", "complete restored public service")
		if runtime.frame().guests[0].state == "gone": break
	check_eq(runtime.frame().guests[0].state, "gone", "actual exit after restore")
	check_eq(runtime.runner.inventory.audit(), [], "no duplicated or lost goods after restore")

func test_service_save_resumes_admission_production_staff_collection_customer_carry_and_eating() -> void:
	for stage in ["admission", "production", "staff_collection", "customer_carry", "eating"]:
		var mode := "self_pickup" if stage in ["customer_carry", "eating"] else "counter"
		var admission := "employee" if stage == "admission" else "automatic"
		var runtime := _runtime(mode, admission)
		if runtime == null: return
		runtime.arrive(Fixture.request())
		var found := false
		for tick in 2000:
			runtime.step(0.1)
			var frame: Dictionary = runtime.frame()
			match stage:
				"admission":
					for task in runtime.runner.tasks.values():
						if task.kind == "interact": found = true
				"production": found = frame.units.size() > 0 and runtime.runner.inventory.quantity("a_in") > 0
				"staff_collection":
					for task in runtime.runner.tasks.values():
						if task.kind == "bundle" and runtime.runner.owner.worker_by_id(task.worker).carry_count > 0: found = true
				"customer_carry": found = frame.held.has("customer:1") and runtime.service.customers.record(1).walking
				"eating": found = frame.guests[0].state == "eating" and frame.guests[0].meal_left < 2.0
			if found: break
		check(found, "snapshot taken during " + stage)
		var saved: Dictionary = runtime.snapshot()
		var reopened := _runtime(mode, admission)
		_copy_outer_economy(runtime.runner.owner, reopened.runner.owner)
		var error: String = reopened.restore(saved)
		check_eq(error, "", "full service validates and adopts " + stage)
		if not error.is_empty(): continue
		check_eq(reopened.snapshot(), saved, "all service and actor state retained at " + stage)
		_finish(runtime)
		_finish(reopened)
		check_eq(reopened.snapshot(), runtime.snapshot(), "same remaining actions and timings at " + stage)
		check_eq(reopened.runner.owner._sales.gold, runtime.runner.owner._sales.gold, "no duplicate income at " + stage)
		check_eq(reopened.runner.owner.sold, 2, "no duplicate handoff count at " + stage)

func test_corrupt_customer_order_binding_or_carrier_reference_is_rejected_before_actor_adoption() -> void:
	var runtime := _runtime("self_pickup")
	if runtime == null: return
	runtime.arrive(Fixture.request())
	for tick in 2000:
		runtime.step(0.1)
		if runtime.frame().held.has("customer:1"): break
	var before: Dictionary = runtime.snapshot()
	check(not before.service.deliveries.is_empty(), "active real customer bundle")
	for corruption in ["unit", "target", "group", "missing_service", "missing_customer", "seat"]:
		var broken: Dictionary = before.duplicate(true)
		match corruption:
			"unit": broken.service.orders.orders[0].lines[0].units[0].unit = 999
			"target": broken.service.customers.customers[0].target = "exit"
			"group": broken.service.deliveries[0].bundle = 999
			"missing_service": broken.service = {}
			"missing_customer": broken.service.customers.customers.clear()
			"seat": broken.service.orders.guests[0].seat = "seat:unknown"
		check(not runtime.restore(broken).is_empty(), "reject inconsistent " + corruption)
		check_eq(runtime.snapshot(), before, "failed " + corruption + " adoption preserves every live service and actor")

func test_pause_freezes_orders_customer_motion_hands_meals_and_production_together() -> void:
	var runtime := _runtime("self_pickup")
	if runtime == null: return
	runtime.arrive(Fixture.request())
	for tick in 2000:
		runtime.step(0.1)
		if runtime.frame().held.has("customer:1"): break
	var saved: Dictionary = runtime.snapshot()
	check_eq(runtime.step(100.0, true), "", "one pause entry point")
	check_eq(runtime.snapshot(), saved, "no service clock runs behind pause")
