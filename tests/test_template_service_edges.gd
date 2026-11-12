extends "res://tests/test_case.gd"
const Fixture := preload("res://tests/fixtures/template_service.gd")
const Runtime := preload("res://game/rules/template/runtime.gd")

func _finish(runtime: RefCounted) -> void:
	for tick in 3000:
		check_eq(runtime.step(0.1), "", "shared service step")
		if runtime.frame().guests[0].state == "gone": break
	check_eq(runtime.frame().guests[0].state, "gone", "customer completes common lifecycle")
	check_eq(runtime.runner.inventory.audit(), [], "inventory remains conservative")

func test_source_already_at_pickup_needs_no_fictional_employee_trip_and_allocates_real_unit_ownership() -> void:
	var template := Fixture.definition("self_pickup")
	template.places["pass"].initial = {"drink":2}
	template.recipes["drink"] = {"nodes":[{"id":"ready", "capability":"source", "place":"pass", "item":"drink"}],
		"output":{"node":"ready", "item":"drink", "count":1}}
	var runtime := Runtime.new(Fixture.owner(), template)
	check_eq(runtime.last_error, "", "direct source is an ordinary public recipe")
	for worker in runtime.runner.owner.workers: worker.deployed = false
	runtime.arrive([{"dish":"lemonade", "qty":2}])
	_finish(runtime)
	check_eq(runtime.runner.owner.sold, 2, "shared source serves two separately bound recipe units")
	for claim in runtime.runner.inventory.snapshot().claims:
		if claim.kind == "transfer": check_eq(claim.actor, "customer:1", "no fake staff carrier at the same pickup container")

func test_declared_shared_staff_role_can_take_orders_and_deliver_without_a_shop_specific_zone() -> void:
	var template := Fixture.definition("counter", "employee")
	template.service.admission_roles = ["staff"]
	template.service.delivery_roles = ["staff"]
	var runtime := Runtime.new(Fixture.owner(), template)
	check_eq(runtime.last_error, "", "declared shared access profile is eligible")
	runtime.arrive(Fixture.request())
	_finish(runtime)
	check_eq(runtime.runner.owner.sold, 2, "profile eligibility applies to actual work")

func test_order_larger_than_employee_capacity_uses_multiple_physical_batches_and_one_receipt() -> void:
	var runtime := Fixture.runtime()
	runtime.arrive([{"dish":"lemonade", "qty":3}])
	_finish(runtime)
	check_eq(runtime.runner.owner.sold, 3, "all three bound units delivered with normal employee capacity")
	check_eq(runtime.frame().orders[0].lines[0].delivered, 3, "no unit lost across batches")
	check(runtime.frame().orders[0].paid, "one final receipt")

func test_prices_are_quoted_when_order_is_taken_and_not_frozen_at_customer_arrival() -> void:
	var runtime := Fixture.runtime()
	runtime.arrive([{"dish":"lemonade", "qty":1}])
	var owner: RefCounted = runtime.runner.owner
	var price := float(owner.dish_price("lemonade"))
	var effect := SpecEffect.make("price", "mul", 2.0)
	effect.dishes.assign(["lemonade"])
	owner.apply_effect("event", "service_quote", effect)
	var expected := float(owner.dish_price("lemonade"))
	check(expected > price, "shared price effect changed the quote while guest was walking")
	_finish(runtime)
	check_eq(runtime.frame().orders[0].quote, expected, "admission uses the current common price calculator")

func test_customer_already_carrying_a_whole_order_never_triggers_a_second_staging_from_infinite_supply() -> void:
	var template := Fixture.definition("self_pickup")
	template.places["pantry"].infinite.append("drink")
	template.recipes["drink"] = {"nodes":[{"id":"ready", "capability":"source", "place":"pantry", "item":"drink"}],
		"output":{"node":"ready", "item":"drink", "count":1}}
	var runtime := Runtime.new(Fixture.owner(), template)
	runtime.arrive([{"dish":"lemonade", "qty":2}])
	_finish(runtime)
	check_eq(runtime.runner.inventory.snapshot().created.get("drink", 0), 2, "only the two requested products are minted")
	check_eq(runtime.runner.inventory.quantity("pass", "drink"), 0, "no duplicate staging remains after customer pickup")

func test_front_source_fetch_uses_declared_capability_time_in_a_real_bundle_action() -> void:
	var template := Fixture.definition()
	template.places["pantry"].infinite.append("drink")
	template.recipes["drink"] = {"nodes":[{"id":"ready", "capability":"source", "place":"pantry", "item":"drink", "seconds":2.0}],
		"output":{"node":"ready", "item":"drink", "count":1}}
	var runtime := Runtime.new(Fixture.owner(), template)
	runtime.runner.owner.workers[1].deployed = false
	runtime.arrive([{"dish":"lemonade", "qty":1}])
	var found := false
	for tick in 300:
		runtime.step(0.1)
		var worker: Dictionary = runtime.runner.owner.workers[0]
		if worker.phase == "pickup":
			found = true
			check_eq(worker.action_left, 2.0, "source fetch time is distinct from shared handoff time")
			break
	check(found, "front source used real pickup action")

func test_shared_finite_source_is_not_counted_twice_when_selecting_a_delivery_batch() -> void:
	var template := Fixture.definition()
	template.places["pantry"].initial = {"drink":1}
	template.recipes["drink"] = {"nodes":[{"id":"ready", "capability":"source", "place":"pantry", "item":"drink"}],
		"output":{"node":"ready", "item":"drink", "count":1}}
	var runtime := Runtime.new(Fixture.owner(), template)
	runtime.arrive([{"dish":"lemonade", "qty":2}])
	for tick in 600:
		runtime.step(0.1)
		if runtime.runner.owner.sold > 0: break
	check_eq(runtime.runner.owner.sold, 1, "one available item can form a real partial delivery batch")
	check(not runtime.frame().orders[0].paid, "missing second unit prevents receipt")
	runtime.runner.inventory.seed("pantry", "drink", 1)
	_finish(runtime)
	check_eq(runtime.runner.owner.sold, 2, "replenishment completes the same order")
