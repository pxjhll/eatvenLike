extends "res://tests/test_case.gd"
const Runtime := preload("res://game/rules/template/runtime.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")
const Fixture := preload("res://tests/fixtures/template_service.gd")
const Contract := preload("res://game/rules/shop_content_contract.gd")

func _definition(delivery := "table") -> Resource:
	var template := Fixture.definition(delivery)
	template.places["table2"] = {"port":Vector2(700,680)}
	template.service.seats["seat:dine/1"] = "table2"
	template.service.erase("eat_seconds")
	template.service["seating"] = {"group":"dine","order":["seat:dine/0","seat:dine/1"],
		"stages":[{"standing":1,"seconds":20.0},{"standing":2,"seconds":30.0}]}
	return template

func _owner() -> ShopRules:
	var owner := Fixture.owner()
	var group: SpecSeatGroup = owner.shop.seat_groups[0]
	group.start = 1
	group.step = 1
	group.steps.clear()
	group.costs.assign([10])
	owner.seats.dine = 1
	owner.unlocked.lemonade = true
	owner.shop.layout.customer_points["seat:dine/1"] = Vector2(700,700)
	return owner

func _runtime(template: Resource) -> RefCounted:
	var runtime := Runtime.new(_owner(),template)
	check_eq(runtime.last_error,"","purchased seat pool composes without custom customer loop")
	return runtime if runtime.last_error.is_empty() else null

func test_queue_capacity_follows_declared_stage_and_unpurchased_seats_cannot_admit() -> void:
	for delivery in ["table","self_pickup"]:
		var runtime := _runtime(_definition(delivery))
		if runtime==null: return
		check_eq(runtime.service.queue_capacity(),1,"initial stage queue bound")
		runtime.runner.owner.stage_index = 1
		check_eq(runtime.service.queue_capacity(),2,"next stage queue bound")
		for index in 2: check_eq(runtime.arrive([{"dish":"lemonade","qty":1}]).error,"","two actual visitors")
		for tick in 120:
			check_eq(runtime.step(0.1),"","one purchased seat is the only admission slot")
			check_eq(runtime.service.orders.guest(2).seat,"","unbought second seat cannot be assigned")
		check_eq(runtime.service.orders.guest(1).seat,"seat:dine/0","first visitor uses purchased seat")

func test_public_purchase_opens_next_declared_seat_and_stage_meal_clock() -> void:
	var runtime := _runtime(_definition())
	if runtime==null: return
	runtime.runner.owner.stage_index = 1
	for index in 2: runtime.arrive([{"dish":"lemonade","qty":1}])
	runtime.runner.owner.gold = 10000.0
	check_eq(runtime.runner.owner.buy_seat(),"","purchase actual extra seat")
	var saw_meal := false
	for tick in 700:
		check_eq(runtime.step(0.1),"","real service at two purchased seats")
		var guest: Dictionary = runtime.service.orders.guest(2)
		if guest.state=="eating":
			saw_meal = true
			check_eq(guest.seat,"seat:dine/1","second customer uses newly purchased seat")
			check(guest.meal_left<=30.0 and guest.meal_left>29.8,"current stage meal duration starts at actual arrival")
			break
	check(saw_meal,"second customer really received food and began meal")

func test_seat_context_and_duplicate_or_unowned_restore_fail_atomically() -> void:
	var template := _definition()
	var runtime := _runtime(template)
	if runtime==null: return
	runtime.arrive([{"dish":"lemonade","qty":1}])
	for tick in 100: check_eq(runtime.step(0.1),"","reach accepted first guest")
	var before: Dictionary = runtime.snapshot()
	var invalid: Dictionary = before.duplicate(true)
	invalid.service.orders.guests[0].seat = "seat:dine/1"
	check(not runtime.restore(invalid).is_empty(),"cannot lease unpurchased seat through save")
	check_eq(runtime.snapshot(),before,"restore failure changes no runtime facts")
	runtime.runner.owner.seats.dine = 99
	check(not runtime.step(0.1).is_empty(),"invalid outer purchase count fails before advancement")
	check_eq(runtime.snapshot(),before,"bad outer context does not move actors")

func test_seating_clocks_are_numeric_but_ports_and_queue_capacity_are_structural() -> void:
	var template := _definition()
	var before: Dictionary = Contract.describe_template(template)
	template.service.seating.stages[0].seconds = 25.0
	check_eq(Contract.describe_template(template).structure,before.structure,"meal clock is numeric")
	check(Contract.describe_template(template).gameplay!=before.gameplay,"full content identity records timing")
	template.service.seating.stages[0].standing = 2
	check(Contract.describe_template(template).structure!=before.structure,"queue capacity remains structural")

func test_seating_rejects_unused_ports_bad_stage_values_and_double_meal_configuration() -> void:
	for patch in [{"order":["seat:dine/0"]},{"stages":[{"standing":0,"seconds":20.0}]},{"callback":"seat_guest"}]:
		var template := _definition()
		for key in patch: template.service.seating[key] = patch[key]
		check(not Compiler.compile(template).errors.is_empty(),"invalid seating declaration")
	var template := _definition()
	template.service.eat_seconds = 10.0
	check(not Compiler.compile(template).errors.is_empty(),"one authoritative meal duration policy")
