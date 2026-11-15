extends "res://tests/test_case.gd"
const Runtime := preload("res://game/rules/template/runtime.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")
const Fixture := preload("res://tests/fixtures/template_service.gd")

func _definition(delivery := "counter") -> Resource:
	var template := Fixture.definition(delivery)
	template.service.orders.rounding = "order_round"
	template.places["pack_in"] = {"port":Vector2(400,100)}
	template.places["pack_out"] = {"port":Vector2(400,100)}
	template.machines["pack"] = {"input":"pack_in","output":"pack_out","profile":{"manual":true}}
	var packed: Dictionary = template.recipes.drink.duplicate(true)
	packed.nodes.append({"id":"pack","capability":"process","machine":"pack","seconds":2.0,
		"consumes":{"drink":1},"produces":{"packed_drink":1},"inputs":{"drink":"drink"}})
	packed.output = {"node":"pack","item":"packed_drink","count":1}
	template.recipes["packed"] = packed
	template.service["customization"] = {"options":[{"id":"bag","unlock":"seal","share":0.4,"price_mult":1.25}],
		"variants":{"lemonade":[{"options":["bag"],"recipe":"packed"}]}}
	return template

func _owner() -> ShopRules:
	var owner := Fixture.owner()
	owner.shop.dish("lemonade").price_parts = {"base":10.49}
	owner.shop.dish("black_tea").price_parts = {"base":2.49}
	owner.unlocked["seal"] = true
	return owner

func _runtime(template: Resource) -> RefCounted:
	var runtime := Runtime.new(_owner(),template)
	check_eq(runtime.last_error,"","declared order options compile through the public service")
	return runtime if runtime.last_error.is_empty() else null

func _advance(runtime: RefCounted, ticks := 1500) -> void:
	for tick in ticks: check_eq(runtime.step(0.1),"","shared service with selected recipe variant")

func _arrive(runtime: RefCounted, request: Array, selected: Variant = null) -> Dictionary:
	return runtime.arrive(request,selected)

func test_selected_option_changes_real_recipe_and_only_main_raw_price_before_whole_order_rounding() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	var state: int = runtime.runner.owner.rng.state
	check_eq(_arrive(runtime,Fixture.request(),["bag"]).error,"","explicit option selection is supported")
	check_eq(runtime.runner.owner.rng.state,state,"explicit selection never draws RNG")
	var request: Array = runtime.service.orders.guest(1).request
	check_eq(request[0].recipe,"packed","primary product uses selected graph")
	check_eq(request[0].item,"packed_drink","actual output item follows graph")
	check_eq(request[0].options,["bag"],"selection is frozen in authoritative request")
	check_eq(request[1].recipe,"side","addon keeps its ordinary recipe")
	_advance(runtime)
	var order: Dictionary = runtime.service.orders.order(1)
	check(absf(order.lines[0].price-13.1125)<0.000001,"10.49 × 1.25 stays unrounded until settlement")
	check_eq(order.lines[1].price,2.49,"addon price is not multiplied")
	check_eq(order.income,16,"round(10.49 × 1.25 + 2.49), not rounded solo prices")
	check_eq(runtime.runner.owner.sold,2,"physical main and addon each sell once")
	check_eq(runtime.runner.inventory.snapshot().created.packed_drink,1,"selected finish really ran")
	check_eq(runtime.runner.inventory.snapshot().consumed.drink,1,"finish consumes one real unwrapped input")

func test_repeated_dish_lines_keep_distinct_option_prices_and_physical_products() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	check_eq(_arrive(runtime,[{"dish":"lemonade","qty":1},{"dish":"lemonade","qty":1}],["bag"]).error,"","same dish may be primary and addon")
	_advance(runtime)
	var order: Dictionary = runtime.service.orders.order(1)
	check_eq(order.lines[0].recipe,"packed","only first line is customized")
	check_eq(order.lines[1].recipe,"drink","second line is plain even with same dish ID")
	check_eq(order.lines[1].price,10.49,"quotes are line-specific")
	check_eq(order.income,24,"round(13.1125 + 10.49)")

func test_automatic_option_roll_uses_one_outer_rng_draw_per_eligible_declared_option() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	var expected := RandomNumberGenerator.new()
	expected.state = runtime.runner.owner.rng.state
	var selected: Array = ["bag"] if expected.randf()<0.4 else []
	check_eq(_arrive(runtime,[{"dish":"lemonade","qty":1}]).error,"","eligible arrival rolls options")
	check_eq(runtime.service.orders.guest(1).request[0].options,selected,"selection follows declared probability")
	check_eq(runtime.runner.owner.rng.state,expected.state,"outer RNG advances exactly once")

func test_closed_or_inapplicable_options_and_full_queues_never_draw_option_rng() -> void:
	for scenario in ["closed","inapplicable","full"]:
		var runtime := _runtime(_definition())
		if runtime == null: return
		if scenario == "closed": runtime.runner.owner.unlocked.seal = false
		if scenario == "full":
			for index in 2: check_eq(_arrive(runtime,[{"dish":"lemonade","qty":1}],[]).error,"","fill actual queue")
		var before: int = runtime.runner.owner.rng.state
		var result := _arrive(runtime,[{"dish":"black_tea" if scenario=="inapplicable" else "lemonade","qty":1}])
		check_eq(result.error,"queue full" if scenario=="full" else "","arrival policy remains explicit")
		check_eq(runtime.runner.owner.rng.state,before,"no option RNG in " + scenario)
		if scenario != "full": check_eq(runtime.service.orders.guest(1).request[0].options,[],"ineligible primary has a frozen empty selection")

func test_invalid_explicit_selection_or_request_cannot_mutate_state_or_rng() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	for selected in [["unknown"],["bag","bag"],"bag",[1]]:
		var before: Dictionary = runtime.snapshot()
		var rng_before: int = runtime.runner.owner.rng.state
		check(not _arrive(runtime,[{"dish":"lemonade","qty":1}],selected).error.is_empty(),"invalid selection rejected")
		check_eq(runtime.snapshot(),before,"invalid selection leaves all actors and orders unchanged")
		check_eq(runtime.runner.owner.rng.state,rng_before,"invalid selection draws no RNG")
	check(not _arrive(runtime,[{"dish":"missing","qty":1}]).error.is_empty(),"invalid request rejected before rolling")
	runtime.runner.owner.unlocked.seal = false
	check(not _arrive(runtime,[{"dish":"lemonade","qty":1}],["bag"]).error.is_empty(),"explicit input cannot select a closed option")

func test_selection_stays_frozen_when_gate_closes_after_arrival_and_restore_never_rerolls() -> void:
	for checkpoint in ["queued","processing"]:
		var template := _definition()
		var runtime := _runtime(template)
		if runtime == null: return
		_arrive(runtime,Fixture.request(),["bag"])
		if checkpoint == "processing":
			for tick in 400:
				check_eq(runtime.step(0.1),"","reach real processing")
				if runtime.service.orders.guest(1).order > 0 and not runtime.runner.machines.snapshot().runs.is_empty(): break
		runtime.runner.owner.unlocked.seal = false
		var reopened := _runtime(template)
		if reopened == null: return
		reopened.runner.owner.unlocked.seal = false
		reopened.runner.owner.rng.state = runtime.runner.owner.rng.state
		var state: int = reopened.runner.owner.rng.state
		check_eq(reopened.restore(runtime.snapshot()),"","historical selection restores even after gate closes")
		check_eq(reopened.runner.owner.rng.state,state,"restore never resamples options")
		_advance(runtime)
		_advance(reopened)
		check_eq(reopened.snapshot(),runtime.snapshot(),"same selection, physical finish, receipt and actors after " + checkpoint)
		check_eq(reopened.service.orders.order(1).income,16,"frozen selected option keeps its price policy")

func test_restore_rejects_missing_or_forged_selection_and_recipe_binding_before_actor_adoption() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	_arrive(runtime,[{"dish":"lemonade","qty":1}],["bag"])
	for patch in ["missing","unknown","duplicate","recipe"]:
		var broken: Dictionary = runtime.snapshot()
		var row: Dictionary = broken.service.orders.guests[0].request[0]
		match patch:
			"missing": row.erase("options")
			"unknown": row.options = ["unknown"]
			"duplicate": row.options = ["bag","bag"]
			"recipe": row.recipe = "drink"; row.item = "drink"
		var before: Dictionary = runtime.snapshot()
		check(not runtime.restore(broken).is_empty(),"malformed selected request rejected: " + patch)
		check_eq(runtime.snapshot(),before,"bad option state cannot adopt actors")

func test_two_options_require_an_explicit_combination_recipe_and_canonical_selection_order() -> void:
	var template := _definition()
	template.service.customization.options.append({"id":"seal","unlock":"seal","share":1.0,"price_mult":1.1})
	template.service.customization.variants.lemonade.append({"options":["seal"],"recipe":"packed"})
	template.service.customization.variants.lemonade.append({"options":["seal","bag"],"recipe":"packed"})
	var runtime := _runtime(template)
	if runtime == null: return
	check_eq(_arrive(runtime,[{"dish":"lemonade","qty":1}],["seal","bag"]).error,"","explicit combination selects one authored graph")
	check_eq(runtime.service.orders.guest(1).request[0].options,["bag","seal"],"saved order follows declared option order")
	_advance(runtime)
	check_eq(runtime.service.orders.order(1).income,14,"round(10.49 × 1.25 × 1.1)")
	check_eq(runtime.runner.inventory.snapshot().created.packed_drink,1,"combined selection does not run finishing twice")

func test_customization_authoring_rejects_unknown_fields_bad_prices_missing_recipes_and_combinations() -> void:
	for patch in ["unknown","share","price","recipe","missing_combo","rounding","duplicate","empty","unused"]:
		var template := _definition()
		match patch:
			"unknown": template.service.customization.callback = "private"
			"share": template.service.customization.options[0].share = 1.1
			"price": template.service.customization.options[0].price_mult = INF
			"recipe": template.service.customization.variants.lemonade[0].recipe = "missing"
			"missing_combo": template.service.customization.options.append({"id":"seal","unlock":"seal","share":0.5,"price_mult":1.0})
			"rounding": template.service.orders.rounding = "dish_tenth_carry"
			"duplicate": template.service.customization.variants.lemonade.append({"options":["bag"],"recipe":"packed"})
			"empty": template.service.customization.options.clear()
			"unused": template.service.customization.options.append({"id":"unused","unlock":"seal","share":0.5,"price_mult":1.0})
		check(not Compiler.compile(template).errors.is_empty(),"unsupported option cannot be silently ignored: " + patch)

func test_chosen_variant_reuses_counter_self_pickup_and_table_fulfillment() -> void:
	for delivery in ["counter","self_pickup","table"]:
		var runtime := _runtime(_definition(delivery))
		if runtime == null: return
		check_eq(_arrive(runtime,Fixture.request(),["bag"]).error,"","variant accepted by " + delivery)
		_advance(runtime)
		check_eq(runtime.runner.owner.sold,2,"both main and addon physically delivered in " + delivery)
		check_eq(runtime.service.orders.order(1).income,16,"one rounded shared receipt")
		check_eq(runtime.runner.inventory.audit(),[],"variant production and fulfillment conserve stock")

func test_zero_and_one_probability_literals_are_valid_and_each_open_option_still_draws_once() -> void:
	for share in [0,1]:
		var template := _definition()
		template.service.customization.options[0].share = share
		template.service.customization.options[0].price_mult = 1
		var runtime := _runtime(template)
		if runtime == null: return
		var expected := RandomNumberGenerator.new()
		expected.state = runtime.runner.owner.rng.state
		expected.randf()
		check_eq(_arrive(runtime,[{"dish":"lemonade","qty":1}]).error,"","endpoint probabilities are explicit valid numbers")
		check_eq(runtime.runner.owner.rng.state,expected.state,"legacy eligible option consumes one draw even at endpoints")
		check_eq(runtime.service.orders.guest(1).request[0].options,["bag"] if share==1 else [],"endpoint choice matches configured probability")

func test_invalid_explicit_selection_in_a_full_queue_does_not_count_an_arrival_or_loss() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	for index in 2: _arrive(runtime,[{"dish":"lemonade","qty":1}],[])
	var before: Dictionary = runtime.snapshot()
	var state: int = runtime.runner.owner.rng.state
	check(not _arrive(runtime,[{"dish":"lemonade","qty":1}],["unknown"]).error.is_empty(),"invalid selection remains an input error")
	check_eq(runtime.snapshot(),before,"bad explicit options cannot increment queue-full losses")
	check_eq(runtime.runner.owner.rng.state,state,"bad input does not advance RNG")

func test_opening_arrival_rolls_menu_then_options_and_preserves_outer_rng_order() -> void:
	var template := _definition()
	template.service["arrivals"] = {"pattern":"fixed","interval":12.0,"opening":1,
		"choices":[{"weight":1.0,"request":Fixture.request()}]}
	var runtime := _runtime(template)
	if runtime == null: return
	var expected := RandomNumberGenerator.new()
	expected.state = runtime.runner.owner.rng.state
	expected.randf()
	var selected: Array = ["bag"] if expected.randf()<0.4 else []
	check_eq(runtime.set_service_open(true),"","opening wave uses the shared arrival path")
	check_eq(runtime.runner.owner.rng.state,expected.state,"menu draw precedes one eligible option draw")
	check_eq(runtime.service.orders.guest(1).request[0].options,selected,"automatic arrivals use the same variant selection")

func test_missing_gate_incomplete_combinations_and_multiplier_underflow_are_explicit_errors() -> void:
	var template := _definition()
	template.service.customization.options[0].unlock = "missing_station"
	check(not Runtime.new(_owner(),template).last_error.is_empty(),"missing gate cannot masquerade as a closed option")
	template = _definition()
	template.service.customization.options.append({"id":"seal","unlock":"seal","share":0.5,"price_mult":1.0})
	template.service.customization.variants.lemonade.append({"options":["bag","seal"],"recipe":"packed"})
	check(not Compiler.compile(template).errors.is_empty(),"combined variant cannot omit the seal-only branch")
	template.service.customization.variants.lemonade.append({"options":["seal"],"recipe":"packed"})
	template.service.customization.options[0].price_mult = 1e-300
	template.service.customization.options[1].price_mult = 1e-300
	check(not Compiler.compile(template).errors.is_empty(),"multipliers cannot silently underflow to a free order")

func test_accepted_line_selection_cannot_diverge_from_the_frozen_request_on_restore() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	_arrive(runtime,[{"dish":"lemonade","qty":1}],["bag"])
	for tick in 400:
		check_eq(runtime.step(0.1),"","wait for actual admission")
		if runtime.service.orders.guest(1).order > 0: break
	var before: Dictionary = runtime.snapshot()
	check(not before.service.orders.orders.is_empty(),"guest has a real accepted line")
	var broken: Dictionary = before.duplicate(true)
	broken.service.orders.orders[0].lines[0].options = []
	check(not runtime.restore(broken).is_empty(),"accepted line cannot drop the chosen price/recipe identity")
	check_eq(runtime.snapshot(),before,"invalid accepted selection does not adopt actors")

func test_option_probabilities_and_prices_are_tunable_but_variant_and_gate_bindings_are_structural() -> void:
	var contract := preload("res://game/rules/shop_content_contract.gd")
	var template := _definition()
	var base: Dictionary = contract.describe_template(template)
	template.service.customization.options[0].share = 0.7
	template.service.customization.options[0].price_mult = 1.3
	var tuned: Dictionary = contract.describe_template(template)
	check(tuned.gameplay != base.gameplay,"actual option numbers affect gameplay identity")
	check_eq(tuned.structure,base.structure,"tuning probability or price does not change production topology")
	template.service.customization.variants.lemonade[0].recipe = "drink"
	check(contract.describe_template(template).structure != base.structure,"selected recipe is still a structural binding")
