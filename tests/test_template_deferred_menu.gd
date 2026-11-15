extends "res://tests/test_case.gd"
const Runtime := preload("res://game/rules/template/runtime.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")
const Fixture := preload("res://tests/fixtures/template_service.gd")

func _definition(delivery := "table") -> Resource:
	var template := Fixture.definition(delivery,"employee")
	template.service.admission_seconds = 1.0
	template.service["selection"] = {"at":"admission","order":["lemonade","black_tea"],
		"gates":{"lemonade":{"stations":["lemonade"]},"black_tea":{"stations":["boil"]}},
		"stages":[{"interval":1000.0,"weights":{"lemonade":1.0}},{"interval":1000.0,"weights":{"black_tea":1.0}}]}
	template.service["arrivals"] = {"pattern":"fixed","first_delay":1000.0,"opening":1}
	return template

func _runtime(template: Resource = null) -> RefCounted:
	var owner := Fixture.owner()
	owner.unlocked.lemonade = true
	owner.unlocked.boil = true
	var runtime := Runtime.new(owner,_definition() if template==null else template)
	check_eq(runtime.last_error,"","selection timing is a common service capability")
	return runtime if runtime.last_error.is_empty() else null

func _advance(runtime: RefCounted, ticks: int) -> void:
	for tick in ticks: check_eq(runtime.step(0.1),"","advance shared admission and service")

func _take(runtime: RefCounted, id := 1) -> void:
	for tick in 1000:
		check_eq(runtime.step(0.1),"","wait for real admission completion")
		if runtime.service.orders.guest(id).order>0: return
	check(false,"actual employee finished admission")

func test_opening_and_manual_unselected_visitors_have_no_food_production_or_menu_rng() -> void:
	var runtime := _runtime()
	if runtime==null: return
	var before_rng: int = runtime.runner.owner.rng.state
	check_eq(runtime.set_service_open(true),"","opening wave enters queue")
	check_eq(runtime.arrive([]).error,"","explicit unselected visitor")
	for id in [1,2]:
		check_eq(runtime.service.orders.guest(id).request,[],"no invented dish while queueing")
		check_eq(runtime.service.orders.guest(id).order,-1,"no accepted order before employee work")
	check_eq(runtime.snapshot().units,[],"unselected guests cannot create production units")
	check_eq(runtime.runner.owner.rng.state,before_rng,"fixed arrival and queueing draw no menu RNG")

func test_selection_uses_stage_and_unlocks_at_completed_admission_not_task_claim() -> void:
	var runtime := _runtime()
	if runtime==null: return
	runtime.arrive([])
	var before_rng: int = runtime.runner.owner.rng.state
	var claimed := false
	for tick in 200:
		check_eq(runtime.step(0.1),"","reach claimed interaction")
		if runtime.service.orders.guest(1).claimed>0: claimed = true; break
	check(claimed,"real admission task claimed")
	check_eq(runtime.service.orders.guest(1).request,[],"claim does not prematurely select food")
	check_eq(runtime.runner.owner.rng.state,before_rng,"claim consumes no random draw")
	runtime.runner.owner.stage_index = 1
	var expected := RandomNumberGenerator.new()
	expected.state = before_rng
	expected.randf()
	_take(runtime)
	check_eq(runtime.service.orders.guest(1).request[0].dish,"black_tea","completed admission uses latest stage")
	check_eq(runtime.runner.owner.rng.state,expected.state,"one primary draw at completion")

func test_explicit_food_cannot_bypass_admission_time_sampling() -> void:
	var runtime := _runtime()
	if runtime==null: return
	var before: Dictionary = runtime.snapshot()
	check(not runtime.arrive([{"dish":"lemonade","qty":1}]).error.is_empty(),"late-selection template rejects early choice")
	check(not runtime.arrive([],[]).error.is_empty(),"option selection also belongs to completed admission")
	check_eq(runtime.snapshot(),before,"rejected early choice changes no queue or inventory")

func test_empty_menu_queues_without_rng_and_waits_for_real_qualification() -> void:
	var runtime := _runtime()
	if runtime==null: return
	runtime.runner.owner.unlocked.lemonade = false
	var before_rng: int = runtime.runner.owner.rng.state
	runtime.set_service_open(true)
	_advance(runtime,100)
	check_eq(runtime.service.orders.guest(1).request,[],"visitor can wait without a fabricated menu item")
	check_eq(runtime.service.orders.guest(1).claimed,-1,"no futile admission work with unavailable catalog")
	check_eq(runtime.runner.owner.rng.state,before_rng,"empty admission menu draws no unused choice")
	runtime.runner.owner.unlocked.lemonade = true
	_take(runtime)
	check_eq(runtime.service.orders.guest(1).request[0].dish,"lemonade","new qualification becomes selectable when work completes")

func test_gate_closing_during_employee_work_releases_claim_without_selecting_or_stalling() -> void:
	var runtime := _runtime()
	if runtime==null: return
	runtime.arrive([])
	for tick in 200:
		check_eq(runtime.step(0.1),"","reach active admission")
		if runtime.service.orders.guest(1).claimed>0: break
	var before_rng: int = runtime.runner.owner.rng.state
	runtime.runner.owner.unlocked.lemonade = false
	_advance(runtime,100)
	check_eq(runtime.service.orders.guest(1).request,[],"failed qualification does not freeze a stale dish")
	check_eq(runtime.service.orders.guest(1).claimed,-1,"completed empty-menu attempt returns claim")
	check_eq(runtime.runner.owner.rng.state,before_rng,"no choice draw for failed attempt")
	runtime.runner.owner.unlocked.lemonade = true
	_take(runtime)
	check(runtime.service.orders.guest(1).order>0,"customer progresses after reopening")

func test_full_queue_and_patience_departure_never_select_abandoned_food() -> void:
	var template := _definition()
	template.service.orders.patience = 0.2
	var runtime := _runtime(template)
	if runtime==null: return
	runtime.runner.owner.unlocked.lemonade = false
	for index in 2: runtime.arrive([])
	var before_rng: int = runtime.runner.owner.rng.state
	check_eq(runtime.arrive([]).error,"queue full","full unselected queue rejects visitor")
	_advance(runtime,10)
	for id in [1,2]:
		check_eq(runtime.service.orders.guest(id).request,[],"departing unclaimed guest still has no food")
		check_eq(runtime.service.orders.guest(id).order,-1,"no order was fabricated on departure")
	check_eq(runtime.runner.owner.rng.state,before_rng,"loss and patience draw no food RNG")
	check_eq(runtime.snapshot().units,[],"no abandoned production")

func test_selected_admission_restores_before_and_after_completion_in_table_and_self_pickup() -> void:
	for delivery in ["table","self_pickup"]:
		for accepted in [false,true]:
			var template := _definition(delivery)
			var runtime := _runtime(template)
			if runtime==null: return
			runtime.arrive([])
			if accepted: _take(runtime)
			else: _advance(runtime,45)
			var reopened := _runtime(template)
			if reopened==null: return
			for key in ["gold","revenue","sold","sale_carry"]: reopened.runner.owner._sales.set(key,runtime.runner.owner._sales.get(key))
			reopened.runner.owner.sold_by_dish = runtime.runner.owner.sold_by_dish.duplicate(true)
			reopened.runner.owner.rng.state = runtime.runner.owner.rng.state
			check_eq(reopened.restore(runtime.snapshot()),"","restore unresolved or frozen request and actual interaction")
			for tick in 300:
				check_eq(runtime.step(0.1),"","continuous late selection")
				check_eq(reopened.step(0.1),"","restored late selection")
			check_eq(reopened.snapshot(),runtime.snapshot(),"same selection, units, deliveries and motion")
			check_eq(reopened.runner.owner.rng.state,runtime.runner.owner.rng.state,"same future menu draws")

func test_flyers_admit_unselected_visitors_through_same_queue_when_menu_is_empty() -> void:
	var template := _definition()
	template.service.arrivals.opening = 0
	template.service["flyers"] = {"pattern":"gap","gap":1.0,"count":1,"cooldown":1.0,"when_full":"lost"}
	var runtime := _runtime(template)
	if runtime==null: return
	runtime.runner.owner.unlocked.lemonade = false
	var before_rng: int = runtime.runner.owner.rng.state
	runtime.set_service_open(true)
	runtime.send_flyers()
	var approved: int = runtime.frame().flyers.pending
	_advance(runtime,1)
	check_eq(runtime.service.orders.guest(1).request,[],"flyer visitor reaches same unresolved queue")
	check_eq(runtime.frame().flyers.pending,approved-1,"one flyer consumed by admission to queue; public flyer effects own approved count")
	check_eq(runtime.runner.owner.rng.state,before_rng,"no premature flyer menu draw")

func test_primary_specific_addon_skips_front_drink_without_drawing_probability() -> void:
	var template := _definition()
	template.service.selection["addon"] = {"dish":"black_tea","share":1.0,"with":["black_tea"]}
	var runtime := _runtime(template)
	if runtime==null: return
	var expected := RandomNumberGenerator.new()
	expected.state = runtime.runner.owner.rng.state
	expected.randf()
	runtime.arrive([])
	_take(runtime)
	check_eq(runtime.service.orders.guest(1).request.size(),1,"excluded front drink acquires no kitchen dependency")
	check_eq(runtime.runner.owner.rng.state,expected.state,"excluded primary skips addon draw")

func test_admission_ramp_grows_once_after_selection_and_not_for_queue_or_failed_attempts() -> void:
	var template := _definition()
	template.service.selection["ramp"] = {"start":0.25,"orders":12}
	var runtime := _runtime(template)
	if runtime==null: return
	runtime.arrive([])
	check_eq(runtime.service.snapshot().ramp.counts.lemonade,0,"queueing is not menu exposure before selection")
	_take(runtime)
	check_eq(runtime.service.snapshot().ramp.counts.lemonade,1,"one successful selected admission")
	_advance(runtime,10)
	check_eq(runtime.service.snapshot().ramp.counts.lemonade,1,"later production does not grow exposure again")

func test_tampered_early_frozen_or_missing_accepted_selection_is_rejected_atomically() -> void:
	var runtime := _runtime()
	if runtime==null: return
	runtime.arrive([])
	var before: Dictionary = runtime.snapshot()
	var invalid: Dictionary = before.duplicate(true)
	invalid.service.orders.guests[0].request = [{"dish":"lemonade","recipe":"drink","item":"drink","qty":1}]
	check(not runtime.restore(invalid).is_empty(),"unaccepted guest cannot contain an early frozen request")
	check_eq(runtime.snapshot(),before,"failed queue restore changes nothing")
	_take(runtime)
	before = runtime.snapshot()
	invalid = before.duplicate(true)
	invalid.service.orders.guests[0].request = []
	check(not runtime.restore(invalid).is_empty(),"accepted guest cannot lose its selected lines")
	check_eq(runtime.snapshot(),before,"failed accepted restore changes nothing")

func test_invalid_sampling_time_and_addon_members_are_authoring_errors() -> void:
	for patch in [{"at":"whenever"},{"addon":{"dish":"black_tea","share":0.4,"with":["missing"]}},{"addon":{"dish":"black_tea","share":0.4,"with":["lemonade","lemonade"]}}]:
		var template := _definition()
		for key in patch: template.service.selection[key] = patch[key]
		check(not Compiler.compile(template).errors.is_empty(),"invalid public sampling policy rejected")

func test_unselected_queue_cannot_restore_fake_admission_exposure() -> void:
	var template := _definition()
	template.service.selection["ramp"] = {"start":0.25,"orders":12}
	var runtime := _runtime(template)
	if runtime==null: return
	runtime.arrive([])
	var before: Dictionary = runtime.snapshot()
	var invalid: Dictionary = before.duplicate(true)
	invalid.service.ramp.counts.lemonade = 1
	check(not runtime.restore(invalid).is_empty(),"queue arrivals cannot prove selected-admission exposure")
	check_eq(runtime.snapshot(),before,"invalid exposure leaves unresolved visitor and RNG alone")

func test_unselected_customer_cannot_restore_an_eating_state_without_an_order() -> void:
	var runtime := _runtime()
	if runtime==null: return
	runtime.arrive([])
	var saved: Dictionary = runtime.service.orders.snapshot()
	saved.guests[0].state = "eating"
	saved.guests[0].queued = false
	saved.guests[0].meal_left = 1.0
	var orders := preload("res://game/rules/template/orders.gd").new(runtime.service.orders._policy)
	check(not orders.restore(saved,runtime.runner.inventory).is_empty(),"empty pending request cannot masquerade as an accepted eating customer")

func test_selected_admission_rolls_back_request_when_receipt_validation_fails() -> void:
	var runtime := _runtime()
	if runtime==null: return
	runtime.arrive([])
	var orders: RefCounted = runtime.service.orders
	var before: Dictionary = orders.snapshot()
	var rows := [{"dish":"lemonade","recipe":"drink","item":"drink","qty":1}]
	check(not orders.admit_selected(1,rows,{"lemonade":NAN}).error.is_empty(),"invalid quote fails before publishing any selected admission")
	check_eq(orders.snapshot(),before,"failed receipt cannot leave an early frozen request")
	check(not orders.admit(1,{"lemonade":12.0}).error.is_empty(),"unselected customer cannot make an empty order")
	check_eq(orders.snapshot(),before,"direct empty-admission bypass changes nothing")

func test_admission_primary_addon_then_customization_draw_in_shared_order_and_freeze() -> void:
	var template := _definition()
	template.service.orders.rounding = "order_round"
	template.service.selection["addon"] = {"dish":"black_tea","share":1.0,"with":["lemonade"]}
	var packed: Dictionary = template.recipes.drink.duplicate(true)
	packed.nodes[1].produces = {"packed_drink":1}
	packed.output.item = "packed_drink"
	template.recipes["packed"] = packed
	template.service["customization"] = {"options":[{"id":"bag","unlock":"seal","share":1.0,"price_mult":1.2}],
		"variants":{"lemonade":[{"options":["bag"],"recipe":"packed"}]}}
	var runtime := _runtime(template)
	if runtime==null: return
	runtime.runner.owner.unlocked.seal = true
	var expected := RandomNumberGenerator.new()
	expected.state = runtime.runner.owner.rng.state
	for draw in 3: expected.randf()
	runtime.arrive([])
	_take(runtime)
	var request: Array = runtime.service.orders.guest(1).request
	check_eq(request[0].recipe,"packed","primary option binds declared graph at completed admission")
	check_eq(request[0].options,["bag"],"option selection frozen once")
	check_eq(request[1].dish,"black_tea","addon remains separate uncustomized row")
	check_eq(runtime.runner.owner.rng.state,expected.state,"primary, addon and option consume exactly three draws")
	runtime.runner.owner.unlocked.seal = false
	check_eq(runtime.restore(runtime.snapshot()),"","frozen customization survives later qualification closure")
	check_eq(runtime.runner.owner.rng.state,expected.state,"restore does not sample options again")
