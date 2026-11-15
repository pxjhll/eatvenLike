extends "res://tests/test_case.gd"
const Fixture := preload("res://tests/fixtures/template_service.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")

func _runtime(delivery := "counter", admission := "automatic") -> RefCounted:
	var runtime := Fixture.runtime(delivery, admission)
	check(runtime.has_method("arrive"), "production runtime must compose public customer/order/fulfillment capabilities")
	if not runtime.has_method("arrive"): return null
	check_eq(runtime.last_error, "", "valid service template")
	return runtime

func test_counter_service_runs_a_whole_order_from_arrival_through_production_receipt_and_real_exit() -> void:
	var runtime := _runtime()
	if runtime == null: return
	var owner: RefCounted = runtime.runner.owner
	var money := float(owner.gold)
	var receipt := floori(owner.dish_price("lemonade") + owner.dish_price("black_tea") + 0.0001)
	var guest: Dictionary = runtime.arrive(Fixture.request())
	check_eq(guest.error, "", "normal service arrival")
	check_eq(runtime.frame().orders, [], "cannot accept remotely at entrance")
	var produced := false
	for tick in 2400:
		check_eq(runtime.step(0.1), "", "one public runtime drives the entire service")
		if runtime.frame().units.size() == 2: produced = true
		if runtime.frame().guests[0].state == "gone": break
	check(produced, "order demand created real production units")
	check_eq(runtime.frame().guests[0].state, "gone", "guest leaves through actual exit")
	check_eq(runtime.frame().customers, [], "only exited actor is removed")
	check_eq(owner.sold, 2, "two actual deliveries counted")
	check_eq(owner.gold - money, float(receipt), "one shared sales receipt")
	check_eq(runtime.runner.inventory.quantity("guest:1"), 0, "sold takeaway accounts for its consumed goods")
	check_eq(runtime.runner.inventory.audit(), [], "full service conserves inventory")
	check_eq(runtime.frame().draws, [], "finished stock is UI inventory throughout the service")

func test_self_pickup_stages_main_and_side_then_customer_carries_both_to_the_seat_before_eating() -> void:
	var runtime := _runtime("self_pickup")
	if runtime == null: return
	var guest: Dictionary = runtime.arrive(Fixture.request())
	var carried := false
	var eating := false
	for tick in 2400:
		check_eq(runtime.step(0.1), "", "shared service step")
		var frame: Dictionary = runtime.frame()
		if not carried and frame.held.has("customer:" + str(guest.id)):
			carried = true
			check_eq(frame.held["customer:" + str(guest.id)].count, 2, "whole order picked together")
			check(runtime.service.customers.record(guest.id).pos.is_equal_approx(runtime.runner.owner.nav.layout.customer_points["pickup"]), "customer pickup happens at real pickup port")
			check_eq(runtime.runner.owner.sold, 0, "carrying is not a committed delivery")
		if frame.guests[0].state == "eating":
			eating = true
			check(runtime.service.customers.ready(guest.id, "seat:dine/0"), "eating begins only after actual seat arrival")
			check(not frame.held.has("customer:" + str(guest.id)), "drop clears customer hand")
		if frame.guests[0].state == "gone": break
	check(carried and eating, "shared customer carry and meal lifecycle ran")
	check_eq(runtime.runner.owner.sold, 2, "whole order delivered once")
	check_eq(runtime.runner.inventory.audit(), [], "self-pickup uses the same physical ledger")

func test_table_service_waits_for_actual_seating_and_delivers_to_declared_employee_table_port() -> void:
	var runtime := _runtime("table")
	if runtime == null: return
	var guest: Dictionary = runtime.arrive(Fixture.request())
	var delivered := false
	for tick in 2400:
		check_eq(runtime.step(0.1), "", "shared table service")
		if not delivered and runtime.runner.owner.sold > 0:
			delivered = true
			check(runtime.service.customers.ready(guest.id, "seat:dine/0"), "no delivery to a moving unseated guest")
			var found := false
			for worker in runtime.runner.owner.workers:
				if worker.pos.is_equal_approx(Vector2(500,680)): found = true
			check(found, "employee reaches its own table interaction port")
		if runtime.frame().guests[0].state == "gone": break
	check(delivered, "table service delivered real production")
	check_eq(runtime.runner.inventory.audit(), [], "table service shares inventory operations")

func test_employee_admission_waits_for_both_participants_and_cancel_does_not_accept_or_charge() -> void:
	var runtime := _runtime("counter", "employee")
	if runtime == null: return
	var guest: Dictionary = runtime.arrive(Fixture.request())
	var assigned := false
	for tick in 300:
		runtime.step(0.1)
		for task in runtime.runner.tasks.values():
			if task.kind != "interact": continue
			assigned = true
			check(runtime.service.customers.ready(guest.id, "queue:0"), "guest has reached front of queue")
			check_eq(runtime.frame().orders, [], "employee has not finished taking order")
			var worker: Dictionary = runtime.runner.owner.worker_by_id(task.worker)
			worker.deployed = false
			runtime.runner.cancel(worker.id)
			break
		if assigned: break
	runtime.step(0.1)
	check(assigned, "admission used standard employee interaction")
	check_eq(runtime.frame().orders, [], "cancelled admission creates no order")
	check_eq(runtime.runner.owner.sold, 0, "cancel does not sell anything")
	for tick in 2400:
		check_eq(runtime.step(0.1), "", "another employee may continue")
		if runtime.frame().guests[0].state == "gone": break
	check_eq(runtime.runner.owner.sold, 2, "reassigned admission and delivery complete once")

func test_full_seat_and_whole_pickup_capacity_are_explicit_wait_and_rejection_rules() -> void:
	var runtime := _runtime("table")
	if runtime == null: return
	runtime.arrive(Fixture.request())
	runtime.arrive(Fixture.request())
	var observed := false
	for tick in 2400:
		runtime.step(0.1)
		var guests: Array = runtime.frame().guests
		if guests[0].order > 0 and guests[0].state != "gone":
			observed = true
			check_eq(guests[1].order, -1, "one seat cannot admit two dine-in guests")
		if guests[1].state == "gone": break
	check(observed, "seat lease was exercised")
	check_eq(runtime.frame().guests[1].state, "gone", "seat is reusable after real departure")
	var self_pickup := _runtime("self_pickup")
	var before: Dictionary = self_pickup.snapshot()
	check(not self_pickup.arrive([{"dish":"lemonade", "qty":3}]).error.is_empty(), "oversized whole self-pickup order cannot silently stall")
	check_eq(self_pickup.snapshot(), before, "invalid order reserves neither customer nor production")

func test_service_compiler_rejects_private_callbacks_bad_menu_bindings_and_missing_required_ports() -> void:
	var runtime := _runtime()
	if runtime == null: return
	for patch in [{"callback":"custom_shop"}, {"menu":{"lemonade":"unknown"}}, {"delivery":"private_shop"}, {"handoff_port":"missing"}]:
		var template := Fixture.definition()
		for key in patch: template.service[key] = patch[key]
		check(not Compiler.compile(template).errors.is_empty(), "invalid service configuration cannot fall back to an old mode")
