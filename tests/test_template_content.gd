extends "res://tests/test_case.gd"
const Contract := preload("res://game/rules/shop_content_contract.gd")
const Fixture := preload("res://tests/fixtures/template_shop.gd")
const Service := preload("res://tests/fixtures/template_service.gd")

func _describe(template: Resource) -> Dictionary:
	var contract: RefCounted = Contract.new()
	check(contract.has_method("describe_template"), "template graphs need explicit gameplay and structural fingerprints")
	if not contract.has_method("describe_template"): return {}
	return contract.call("describe_template", template)

func test_template_timing_changes_gameplay_without_erasing_graph_quantities_from_structure() -> void:
	var template := Fixture.definition()
	var base := _describe(template)
	if base.is_empty(): return
	var timed: Resource = template.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	timed.hop_seconds = 0.8
	timed.recipes.meal.nodes[1].seconds = 3.0
	var metadata := _describe(timed)
	check(metadata.gameplay != base.gameplay, "real timing affects gameplay fingerprint")
	check_eq(metadata.structure, base.structure, "timing alone does not change graph identity")
	var counted: Resource = template.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	counted.recipes.meal.nodes[0].consumes.a = 2
	counted.recipes.meal.nodes[1].produces.a = 2
	check(_describe(counted).structure != base.structure, "input and output quantities remain structural facts")
	counted = template.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	counted.recipes.meal.output.count = 2
	check(_describe(counted).structure != base.structure, "final output quantity remains structural")

func test_dependencies_ports_initial_quantities_and_processing_slots_are_structural() -> void:
	var template := Fixture.definition()
	var base := _describe(template)
	if base.is_empty(): return
	for patch in ["dependency", "port", "initial", "slots", "supply"]:
		var copy: Resource = template.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
		match patch:
			"dependency": copy.recipes.meal.nodes[2]["after"] = ["b"]
			"port": copy.places.pantry.port += Vector2(1,0)
			"initial": copy.places.a_in["initial"] = {"raw_a":1}
			"slots": copy.machines.a.profile["slots"] = 2
			"supply": copy.places.pantry.infinite = ["raw_a"]
		check(_describe(copy).structure != base.structure, patch + " changes structural identity")

func test_manual_stage_activation_is_structural_but_tuning_an_existing_stage_is_not() -> void:
	var template := Fixture.linear()
	var base := _describe(template)
	if base.is_empty(): return
	template.machines.a.profile["load_seconds"] = 0.2
	var loaded := _describe(template)
	check(loaded.structure != base.structure, "adding loading adds an actor stage")
	template.machines.a.profile.load_seconds = 0.4
	check_eq(_describe(template).structure, loaded.structure, "existing load duration is numeric tuning")
	template.machines.a.profile["stir_points"] = [0.5]
	check(_describe(template).structure != loaded.structure, "adding stirring alters machine program")

func test_only_authored_labels_are_presentation_and_items_named_seconds_still_have_structural_counts() -> void:
	var template := Fixture.linear()
	var base := _describe(template)
	if base.is_empty(): return
	template.recipes.drink.nodes[1]["label"] = "新的制作文案"
	check_eq(_describe(template), base, "step label does not alter content contract")
	template.recipes.drink.nodes[1].produces = {"seconds":1}
	template.recipes.drink.output.item = "seconds"
	base = _describe(template)
	template.recipes.drink.nodes[1].produces.seconds = 2
	check(_describe(template).structure != base.structure, "semantic item key is not mistaken for a timing field")

func test_service_weights_and_dispatch_scores_are_tunable_but_menu_request_counts_and_ownership_policy_are_structural() -> void:
	var template := Service.definition()
	template.service["arrivals"] = {"pattern":"fixed", "interval":8.0,
		"choices":[{"weight":1.0, "request":[{"dish":"lemonade", "qty":1}]}]}
	template.dispatch = {"affinity":"prefer", "scores":{"operate":200.0}}
	var base := _describe(template)
	if base.is_empty(): return
	var tuned: Resource = template.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	tuned.service.arrivals.interval = 6.0
	tuned.service.arrivals.choices[0].weight = 2.0
	tuned.dispatch.scores.operate = 300.0
	check_eq(_describe(tuned).structure, base.structure, "known weights and timings are tunable")
	check(_describe(tuned).gameplay != base.gameplay, "tuning remains gameplay content")
	tuned.service.arrivals.choices[0].request[0].qty = 2
	check(_describe(tuned).structure != base.structure, "order quantities are structural")
	tuned = template.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	tuned.dispatch.affinity = "exclusive"
	check(_describe(tuned).structure != base.structure, "ownership semantics are structural")

func test_template_fingerprints_are_detached_and_reject_unrecognized_resource_types() -> void:
	var template := Fixture.definition()
	var base := _describe(template)
	if base.is_empty(): return
	check_eq(base.version, 1, "versioned content contract")
	check_eq(base.gameplay.length(), 64, "SHA256 gameplay identity")
	check_eq(_describe(template.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)), base, "deep copies are stable")
	check_eq(Contract.new().call("describe_template", SpecStep.new()), {}, "another resource cannot pretend to be a template")
