extends "res://tests/test_case.gd"
const Runtime := preload("res://game/rules/template/runtime.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")
const Fixture := preload("res://tests/fixtures/template_service.gd")
const Contract := preload("res://game/rules/shop_content_contract.gd")

func _definition(delivery := "counter") -> Resource:
	var template := Fixture.definition(delivery)
	template.service["selection"] = {"order":["lemonade","black_tea"],
		"gates":{"lemonade":{"stations":["lemonade"]},"black_tea":{"stations":["boil"],"boxes":["tea_leaf"]}},
		"stages":[{"interval":10.0,"weights":{"lemonade":0.65,"black_tea":0.35}},
			{"interval":5.0,"weights":{"lemonade":0.3,"black_tea":0.7}}],
		"ramp":{"start":0.25,"orders":4}}
	template.service["arrivals"] = {"pattern":"fixed","first_delay":0.1}
	return template

func _runtime(template: Resource) -> RefCounted:
	var owner := Fixture.owner()
	owner.unlocked.lemonade = true
	owner.unlocked.boil = true
	owner.boxes.tea_leaf = true
	var runtime := Runtime.new(owner,template)
	check_eq(runtime.last_error,"","shared ramp/flow policy compiles")
	return runtime if runtime.last_error.is_empty() else null

func _counts(runtime: RefCounted) -> Dictionary:
	return runtime.service.snapshot().ramp.counts

func test_successful_arrival_advances_every_available_weight_not_just_the_selected_dish() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	var before_rng: int = runtime.runner.owner.rng.state
	var legacy_before: Dictionary = runtime.runner.owner.order_ramp.duplicate(true)
	check_eq(runtime.service.menu_weights(),{"lemonade":0.65*0.25,"black_tea":0.35*0.25},"newly eligible dishes start at a quarter weight")
	check_eq(runtime.arrive([{"dish":"lemonade","qty":1}]).error,"","one real admitted visitor")
	check_eq(_counts(runtime),{"lemonade":1,"black_tea":1},"unselected eligible tea also gains one arrival")
	check_eq(runtime.service.menu_weights(),{"lemonade":0.65*0.4375,"black_tea":0.35*0.4375},"each eligible weight grows once")
	check_eq(runtime.runner.owner.rng.state,before_rng,"query and explicit arrival do not introduce RNG draws")
	check_eq(runtime.runner.owner.order_ramp,legacy_before,"legacy ramp state is never written")

func test_unlock_starts_a_new_ramp_without_resetting_existing_dishes_or_frozen_requests() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	runtime.runner.owner.boxes.tea_leaf = false
	runtime.arrive([{"dish":"lemonade","qty":1}])
	check_eq(_counts(runtime).black_tea,0,"closed ingredient earns no exposure")
	runtime.runner.owner.boxes.tea_leaf = true
	runtime.runner.owner.stage_index = 1
	check_eq(runtime.service.menu_weights(),{"lemonade":0.3*0.4375,"black_tea":0.7*0.25},"stage weights use independent accumulated exposure")
	check_eq(runtime.service.orders.guest(1).request[0].dish,"lemonade","waiting request remains frozen")

func test_group_share_is_not_scaled_but_its_available_members_still_gain_exposure() -> void:
	var template := _definition()
	template.service.selection["groups"] = [{"id":"flavors","dishes":["black_tea"],"fallback":"lemonade"}]
	template.service.selection.stages[0].weights = {"lemonade":0.2,"flavors":0.8}
	var runtime := _runtime(template)
	if runtime == null: return
	check_eq(runtime.service.menu_weights(),{"lemonade":0.05,"black_tea":0.8},"group share bypasses the direct-dish ramp")
	runtime.arrive([{"dish":"lemonade","qty":1}])
	check_eq(_counts(runtime).black_tea,1,"available group member gains exposure despite not being selected")
	runtime.runner.owner.stage_index = 1
	check_eq(runtime.service.menu_weights().black_tea,0.7*0.4375,"later direct weight reuses the member's exposure")
	runtime.runner.owner.stage_index = 0
	runtime.runner.owner.boxes.tea_leaf = false
	check_eq(runtime.service.menu_weights(),{"lemonade":0.2*0.4375+0.8},"group fallback is added after scaling the direct share")

func test_full_queue_invalid_request_and_empty_catalog_never_advance_ramp() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	check(not runtime.arrive([{"dish":"missing","qty":1}]).error.is_empty(),"invalid dish rejected")
	check_eq(_counts(runtime),{"lemonade":0,"black_tea":0},"failed validation creates no exposure")
	for index in 2: runtime.arrive([{"dish":"lemonade","qty":1}])
	var before := _counts(runtime)
	var rng_before: int = runtime.runner.owner.rng.state
	check_eq(runtime.arrive([{"dish":"black_tea","qty":1}]).error,"queue full","full queue rejects")
	runtime.set_service_open(true)
	runtime.step(0.1)
	check_eq(_counts(runtime),before,"neither manual nor automatic rejection grows exposure")
	check_eq(runtime.runner.owner.rng.state,rng_before,"rejected automatic visitor has no unused menu draw")
	var empty := _runtime(_definition())
	if empty == null: return
	empty.runner.owner.unlocked.lemonade = false
	empty.runner.owner.boxes.tea_leaf = false
	empty.set_service_open(true)
	empty.step(0.1)
	check_eq(_counts(empty),{"lemonade":0,"black_tea":0},"empty menu is not a successful arrival")

func test_opening_wave_and_flyer_arrivals_share_ramp_with_ordinary_service() -> void:
	var template := _definition()
	template.service.arrivals.opening = 1
	template.service.arrivals.first_delay = 10000.0
	template.service["flyers"] = {"pattern":"gap","count":1,"gap":1.0,"cooldown":1.0,"when_full":"lost"}
	var runtime := _runtime(template)
	if runtime == null: return
	runtime.set_service_open(true)
	check_eq(_counts(runtime),{"lemonade":1,"black_tea":1},"opening wave commits exposure immediately")
	runtime.send_flyers()
	runtime.step(0.1)
	check_eq(_counts(runtime),{"lemonade":2,"black_tea":2},"flyer admission uses the same ramp commit")

func test_automatic_selection_uses_pre_arrival_weights_and_exact_outer_rng() -> void:
	var template := _definition()
	var runtime := _runtime(template)
	if runtime == null: return
	runtime.runner.owner.boxes.tea_leaf = false
	runtime.arrive([{"dish":"lemonade","qty":1}])
	runtime.runner.owner.boxes.tea_leaf = true
	var expected := RandomNumberGenerator.new()
	expected.state = runtime.runner.owner.rng.state
	var weights := {"lemonade":0.65*0.4375,"black_tea":0.35*0.25}
	var dish := preload("res://game/rules/rule_sampling.gd").choose(weights,expected)
	runtime.set_service_open(true)
	check_eq(runtime.step(0.1),"","weighted automatic admission")
	check_eq(runtime.service.orders.guest(2).request[0].dish,dish,"sample before committing current visitor's exposure")
	check_eq(runtime.runner.owner.rng.state,expected.state,"ramp adds no random draw")

func test_ramp_caps_and_restore_continue_identically_in_counter_and_table_combinations() -> void:
	for delivery in ["counter","table"]:
		var template := _definition(delivery)
		var runtime := _runtime(template)
		if runtime == null: return
		runtime.set_service_open(true)
		for tick in 253: check_eq(runtime.step(0.1),"","reach in-flight menu ramp")
		var reopened := _runtime(template)
		if reopened == null: return
		for key in ["gold","revenue","sold","sale_carry"]: reopened.runner.owner._sales.set(key,runtime.runner.owner._sales.get(key))
		reopened.runner.owner.sold_by_dish = runtime.runner.owner.sold_by_dish.duplicate(true)
		reopened.runner.owner.rng.state = runtime.runner.owner.rng.state
		check_eq(reopened.restore(runtime.snapshot()),"","restore exposure with actual orders and inventory")
		for tick in 1000:
			check_eq(runtime.step(0.1),"","continue original service")
			check_eq(reopened.step(0.1),"","continue restored service")
		check_eq(_counts(runtime),{"lemonade":4,"black_tea":4},"exposure saturates at configured arrivals")
		check_eq(runtime.snapshot(),reopened.snapshot(),"all future physical service and ramp facts agree")
		check_eq(runtime.runner.owner.rng.state,reopened.runner.owner.rng.state,"same future randomness")
		check_eq(runtime.runner.owner.revenue,reopened.runner.owner.revenue,"same actual payment")

func test_tampered_ramp_restore_is_rejected_without_changing_live_runtime() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	runtime.arrive([{"dish":"lemonade","qty":1}])
	var before: Dictionary = runtime.snapshot()
	for counts in [{"lemonade":-1,"black_tea":1},{"lemonade":2,"black_tea":1},{"lemonade":1.0,"black_tea":1},{"lemonade":1},{"lemonade":1,"black_tea":1,"unknown":0}]:
		var invalid: Dictionary = before.duplicate(true)
		invalid.service.ramp.counts = counts
		check(not runtime.restore(invalid).is_empty(),"reject invalid key, count, type or impossible exposure")
		check_eq(runtime.snapshot(),before,"restore failure is atomic")

func _flow(template: Resource) -> void:
	template.service.selection["flow"] = {"flavors":["lemonade","black_tea"],"per_extra_flavor":0.12,"stations":["boil"],"per_level":0.05}

func test_flow_uses_declared_open_flavors_upgraded_stations_and_public_effect_once() -> void:
	var template := _definition()
	_flow(template)
	var runtime := _runtime(template)
	if runtime == null: return
	var owner: RefCounted = runtime.runner.owner
	owner.gold = 100000.0
	check_eq(owner.upgrade("boil"),"","public machine upgrade")
	owner.apply_effect("event","flow_test",SpecEffect.make("flow","mul",1.5))
	runtime.set_service_open(true)
	check_eq(runtime.step(0.1),"","schedule actual next arrival")
	check(absf(runtime.service.arrivals.snapshot().left-10.0/(1.12*1.05*1.5))<0.000001,"declared factors and modifier affect the one arrival clock")
	var frozen: float = runtime.service.arrivals.snapshot().left
	owner.boxes.tea_leaf = false
	owner.stage_index = 1
	check_eq(runtime.service.arrivals.snapshot().left,frozen,"unlock change does not reschedule a committed interval")
	check_eq(runtime.service.flow_multiplier(),1.05*1.5,"closed flavor no longer contributes to the next interval")
	owner.unlocked.boil = false
	check_eq(runtime.service.flow_multiplier(),1.5,"locked station level no longer contributes")

func test_flow_validation_rejects_unknown_references_and_invalid_effect_before_any_advance() -> void:
	var template := _definition()
	_flow(template)
	template.service.selection.flow.stations = ["unknown"]
	check(not Runtime.new(Fixture.owner(),template).last_error.is_empty(),"unmapped flow station cannot silently disappear")
	template = _definition()
	_flow(template)
	var runtime := _runtime(template)
	if runtime == null: return
	var before: Dictionary = runtime.snapshot()
	var before_rng: int = runtime.runner.owner.rng.state
	runtime.runner.owner.apply_effect("event","invalid_flow",SpecEffect.make("flow","set",-1.0))
	check(not runtime.step(0.1).is_empty(),"negative effective multiplier rejected")
	check_eq(runtime.snapshot(),before,"invalid flow does not partially advance actors or clocks")
	check_eq(runtime.runner.owner.rng.state,before_rng,"invalid flow consumes no random draw")

func test_invalid_authored_ramp_and_flow_are_rejected() -> void:
	for ramp in [{"start":0.0,"orders":4},{"start":1.1,"orders":4},{"start":NAN,"orders":4},{"start":0.25,"orders":-1},{"start":0.25,"orders":4.0},{"start":0.25,"orders":4,"callback":"tick"}]:
		var template := _definition()
		template.service.selection.ramp = ramp
		check(not Compiler.compile(template).errors.is_empty(),"invalid ramp cannot compile")
	for flow in [{"flavors":["unknown"],"per_extra_flavor":0.1},{"flavors":["lemonade","lemonade"],"per_extra_flavor":0.1},{"stations":["boil","boil"],"per_level":0.1},{"per_level":-1.0},{"per_level":INF},{"callback":"shop_flow"}]:
		var template := _definition()
		template.service.selection.flow = flow
		check(not Compiler.compile(template).errors.is_empty(),"invalid flow cannot compile")

func test_ramp_and_flow_numeric_projection_keeps_capability_membership_structural() -> void:
	var template := _definition()
	_flow(template)
	var before: Dictionary = Contract.describe_template(template)
	template.service.selection.ramp.start = 0.5
	template.service.selection.ramp.orders = 12
	template.service.selection.flow.per_extra_flavor = 0.2
	template.service.selection.flow.per_level = 0.1
	var tuned: Dictionary = Contract.describe_template(template)
	check_eq(tuned.structure,before.structure,"ramp curve and flow coefficients are numeric tuning")
	check(tuned.gameplay!=before.gameplay,"numeric tuning remains in full identity")
	template.service.selection.flow.flavors = ["lemonade"]
	check(Contract.describe_template(template).structure!=before.structure,"contributing menu identities remain structural")

func test_absent_ramp_leaves_service_snapshot_and_static_weights_unchanged() -> void:
	var template := _definition()
	template.service.selection.erase("ramp")
	var runtime := _runtime(template)
	if runtime == null: return
	check(not runtime.service.snapshot().has("ramp"),"disabled capability adds no serialized state")
	check(runtime.service.has_method("menu_weights"),"common service exposes its authoritative current menu")
	if not runtime.service.has_method("menu_weights"): return
	check_eq(runtime.service.menu_weights(),{"lemonade":0.65,"black_tea":0.35},"static menus keep their existing weights")
	runtime.arrive([{"dish":"lemonade","qty":1}])
	check_eq(runtime.service.menu_weights(),{"lemonade":0.65,"black_tea":0.35},"successful visitor cannot grow a static menu")

func test_zero_order_ramp_is_neutral_and_presentation_queries_are_detached() -> void:
	var template := _definition()
	template.service.selection.ramp.orders = 0
	var runtime := _runtime(template)
	if runtime == null: return
	check_eq(runtime.service.menu_weights(),{"lemonade":0.65,"black_tea":0.35},"zero exposure duration disables scaling")
	var frame: Dictionary = runtime.frame()
	frame.ramp.counts.lemonade = 999
	var weights: Dictionary = runtime.service.menu_weights()
	weights.lemonade = 999.0
	runtime.arrive([{"dish":"lemonade","qty":1}])
	check_eq(_counts(runtime),{"lemonade":0,"black_tea":0},"zero duration never creates out-of-range counts")
	check_eq(runtime.service.menu_weights(),{"lemonade":0.65,"black_tea":0.35},"mutating query results cannot alter the authoritative menu")

func test_ramp_underflow_cannot_turn_an_authored_positive_weight_into_zero() -> void:
	var template := _definition()
	template.service.selection.ramp.start = 1e-300
	template.service.selection.stages[0].weights.lemonade = 1e-300
	check(not Compiler.compile(template).errors.is_empty(),"reject positive coefficients whose product underflows before taking any RNG draw")

func test_flow_overflow_is_rejected_even_if_set_effect_hides_it() -> void:
	var template := _definition()
	_flow(template)
	template.service.selection.flow.per_extra_flavor = 1e308
	template.service.selection.flow.per_level = 1e308
	var runtime := _runtime(template)
	if runtime == null: return
	var owner: RefCounted = runtime.runner.owner
	owner.gold = 100000.0
	check_eq(owner.upgrade("boil"),"","real level now makes authored contributions overflow")
	owner.apply_effect("event","mask_overflow",SpecEffect.make("flow","set",1.0))
	var before: Dictionary = runtime.snapshot()
	check(not runtime.step(0.1).is_empty(),"set effect cannot conceal non-finite base arithmetic")
	check_eq(runtime.snapshot(),before,"overflow is found before actor, machine and clock advancement")

func test_finite_flow_must_also_produce_a_finite_positive_arrival_interval() -> void:
	for underflow in [true,false]:
		var template := _definition()
		_flow(template)
		template.service.selection.stages[0].interval = 1e-300 if underflow else 1e300
		var runtime := _runtime(template)
		if runtime == null: return
		runtime.runner.owner.apply_effect("event","extreme_flow",SpecEffect.make("flow","set",1e300 if underflow else 1e-300))
		var before: Dictionary = runtime.snapshot()
		check(not runtime.step(0.1).is_empty(),"finite multiplier cannot schedule zero or infinite interval")
		check_eq(runtime.snapshot(),before,"invalid derived interval is found before advancing any subsystem")

func test_actual_tea_six_stage_weights_exposure_and_rng_match_original_rule_queries() -> void:
	var selection := preload("res://game/rules/template/menu_selection.gd")
	var ramp_script := preload("res://game/rules/template/menu_ramp.gd")
	var tea: SpecShop = preload("res://content/shops/tea/shop.tres").copy_for_editing()
	# Controlled staffing only; this is a menu arithmetic comparison, not a
	# claim that the formal tea service or old saves have switched entry points.
	tea.staff.starting.assign(["gray_cat","gray_cat"])
	tea.staff.starting_posts.assign(["counter",""])
	var owner := ShopRules.new(tea,42)
	owner.gold = 1000000.0
	var raw := {"order":[],"gates":{
		"lemonade":{"stations":["lemonade"]},
		"black_tea":{"stations":["boil"],"boxes":["tea_leaf"]},
		"plain_milk_tea":{"stations":["boil","mix"],"boxes":["tea_leaf","milk"]},
		"lemon_tea":{"stations":["lemonade","press"]}},"stages":[],
		"ramp":{"start":tea.fulfillment.ramp_start,"orders":tea.fulfillment.ramp_orders},
		"flow":{"flavors":["pearl_milk_tea","coconut_milk_tea","redbean_milk_tea","taro_milk_tea"],
			"per_extra_flavor":tea.flavor_flow,"stations":["lemonade","boil","seal","mix","press","topping"],"per_level":tea.level_flow}}
	var menu := {}
	for dish in tea.dishes: raw.order.append(dish.id); menu[dish.id] = dish.id
	for index in 4:
		var dish: String = raw.flow.flavors[index]
		raw.gates[dish] = {"stations":["boil","mix","topping"],"boxes":["tea_leaf","milk"],"levels":{"topping":index+1}}
	for stage in tea.stages: raw.stages.append({"interval":stage.customer_interval,"weights":stage.order_weights.duplicate()})
	var compiled: Dictionary = selection.compile(raw,menu)
	check_eq(compiled.error,"","actual eight-dish, six-stage menu is expressed by generic selection data")
	if not compiled.error.is_empty(): return
	var definition: Dictionary = compiled.definition
	var ramp: RefCounted = ramp_script.new(definition.ramp,definition.order)
	var rng := RandomNumberGenerator.new()
	rng.state = owner.rng.state
	for stage_index in 6:
		owner.stage_index = stage_index
		for id in tea.stages[stage_index].stations: check_eq(owner.unlock(id),"","unlock actual stage station")
		if stage_index == 0:
			# The old opening command emits three old-loop customers. Exclude
			# those setup side effects from this pure menu comparison; public
			# opening-wave admission is covered by the real runtime test above.
			owner.orders = []
			for key in owner.order_ramp: owner.order_ramp[key] = 0
			rng.state = owner.rng.state
		if stage_index == 1: check_eq(owner.unlock_box("tea_leaf"),"","install tea leaf box")
		if stage_index == 3: check_eq(owner.unlock_box("milk"),"","install milk box")
		for arrival in 16:
			if stage_index==5 and arrival in [3,6,9]: check_eq(owner.upgrade("topping"),"","actual public level unlocks another flavor")
			var weights: Dictionary = selection.weights(definition,owner,ramp.counts())
			check_eq(weights,owner.order_weights(),"same original weights at each opening/upgrade/exposure boundary")
			check_eq(selection.flow_multiplier(definition,owner),owner.flow_multiplier(),"same declared flow with actual flavor unlocks")
			var expected := preload("res://game/rules/rule_sampling.gd").choose(owner.order_weights(),rng)
			var chosen: Array = selection.request(definition,owner,ramp.counts())
			check_eq(chosen[0].dish,expected,"same selected dish from exact weight order")
			check_eq(owner.rng.state,rng.state,"same one primary random draw")
			ramp.admitted(weights)
			owner._orders_state.admit_handoff(expected,-1,false,weights,tea.fulfillment.ramp_orders,owner.station_unlocked("seal"))
			for dish in definition.order: check_eq(ramp.counts()[dish],owner.order_ramp[dish],"same eligible-dish exposure; takeover routing is a later capability")
