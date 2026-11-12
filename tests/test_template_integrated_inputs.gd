extends "res://tests/test_case.gd"
const Compiler := preload("res://game/rules/template/compiler.gd")
const Runtime := preload("res://game/rules/template/runtime.gd")
const Production := preload("res://tests/fixtures/template_shop.gd")
const Actors := preload("res://tests/fixtures/template_service.gd")
const Tea := preload("res://tests/fixtures/template_tea_production.gd")

func _definition() -> Resource:
	var template := Production.linear()
	template.places.pantry.infinite = []
	template.places.pantry.initial = {"raw_a":1}
	template.places.a_in.infinite = ["milk"]
	template.recipes.drink.nodes[1].consumes["milk"] = 1
	template.recipes.drink.nodes[1].inputs["milk"] = {"capability":"integrated"}
	return template

func _runtime(template: Resource) -> RefCounted:
	var owner := Actors.owner()
	owner.workers[1].deployed = false
	var runtime := Runtime.new(owner,template)
	check_eq(runtime.last_error,"","explicit installed input compiles without a fictional source step")
	return runtime if runtime.last_error.is_empty() else null

func _finish(runtime: RefCounted, unit: int) -> void:
	for tick in 600:
		check_eq(runtime.step(0.1),"","actual mixed finite and integrated production")
		if runtime.ready(unit): return
	check(false,"production reaches a real owned output")

func _started(runtime: RefCounted, unit: int) -> int:
	for tick in 300:
		check_eq(runtime.step(0.1),"","physically supply and start operation")
		var state: Dictionary = runtime.unit(unit)
		if state.running.has("drink"): return int(state.running.drink)
	check(false,"real recipe operation started")
	return -1

func test_integrated_binding_has_no_fictional_dependency_and_needs_an_installed_input() -> void:
	var template := _definition()
	var result := Compiler.compile(template)
	check_eq(result.errors,[],"installed material is a named public input capability")
	if result.errors.is_empty():
		check_eq(result.definition.recipes.drink.nodes.drink.dependencies,["raw"],"only physically supplied raw ingredient adds a producer dependency")
		check_eq(result.definition.recipes.drink.nodes.drink.input_places.milk,"a_in","installed input resolves to this machine input")
	template.places.a_in.infinite = []
	check(not Compiler.compile(template).errors.is_empty(),"marker alone cannot conjure an uninstalled input")

func test_unknown_integrated_parameters_and_missing_bindings_are_not_silently_inferred() -> void:
	for binding in [{}, {"capability":"private"}, {"capability":"integrated","callback":"shop"}, null]:
		var template := _definition()
		template.recipes.drink.nodes[1].inputs.milk = binding
		check(not Compiler.compile(template).errors.is_empty(),"only the exact public binding shape is accepted")
	var template := _definition()
	template.recipes.drink.nodes[1].inputs.erase("milk")
	check(not Compiler.compile(template).errors.is_empty(),"installed supply still requires a deliberate recipe binding")

func test_only_finite_material_is_carried_and_integrated_consumption_commits_once_with_output() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	var unit: Dictionary = runtime.request_production("drink")
	check_eq(runtime.source_demand(),{"pantry":{"raw_a":1}},"installed input is excluded from real transport demand")
	var held := false
	for tick in 600:
		check_eq(runtime.step(0.1),"","real movement and recipe")
		for hand in runtime.frame().held.values():
			for item in hand.items:
				check_eq(item.item,"raw_a","employee only carries the physically supplied ingredient")
				held = true
		if runtime.ready(unit.id): break
	check(held,"employee did physically carry the finite input")
	var stock: Dictionary = runtime.runner.inventory.snapshot()
	check_eq(stock.created.get("milk",0),1,"installed supply generation commits with the successful operation")
	check_eq(stock.consumed.get("milk",0),1,"installed input is consumed exactly once")
	check_eq(runtime.runner.inventory.quantity("a_in","milk"),0,"no finite milk pile is invented")
	check_eq(runtime.source_demand(),{},"completed operation creates no new native-material shortage")
	check_eq(runtime.runner.inventory.audit(),[],"both sides of integrated supply remain accounted")

func test_cancelled_operation_does_not_consume_integrated_input_and_restart_is_once_only() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	var unit: Dictionary = runtime.request_production("drink")
	var run := _started(runtime,unit.id)
	if run < 0: return
	for worker in runtime.runner.tasks.keys(): runtime.runner.cancel(worker)
	check_eq(runtime.runner.machines.cancel(run),"","cancel ordinary operation claim")
	check_eq(runtime.runner.inventory.snapshot().created.get("milk",0),0,"cancel before completion cannot mint or consume installed material")
	_finish(runtime,unit.id)
	check_eq(runtime.runner.inventory.snapshot().consumed.get("milk",0),1,"restarted process uses exactly one serving")
	check_eq(runtime.runner.inventory.quantity("a_out","drink",unit.id),1,"restart yields only one final item")

func test_integrated_operation_restores_without_duplicating_material_or_output() -> void:
	var template := _definition()
	var runtime := _runtime(template)
	if runtime == null: return
	var unit: Dictionary = runtime.request_production("drink")
	_started(runtime,unit.id)
	var reopened := _runtime(template)
	if reopened == null: return
	check_eq(reopened.restore(runtime.snapshot()),"","installed input participates in the existing snapshot validation")
	for tick in 300:
		check_eq(runtime.step(0.1),"","continuous native process")
		check_eq(reopened.step(0.1),"","restored native process")
	check_eq(reopened.snapshot(),runtime.snapshot(),"no duplicate native generation after restore")
	check_eq(reopened.runner.inventory.snapshot().consumed.get("milk",0),1,"restored material consumed once")

func test_integrated_recipe_reuses_counter_and_self_pickup_service() -> void:
	for delivery in ["counter","self_pickup"]:
		var template := Actors.definition(delivery)
		template.places.a_in.infinite = ["milk"]
		template.recipes.drink.nodes[1].consumes["milk"] = 1
		template.recipes.drink.nodes[1].inputs["milk"] = {"capability":"integrated"}
		var runtime := _runtime(template)
		if runtime == null: return
		check_eq(runtime.arrive(Actors.request()).error,"","real mixed customer order")
		for tick in 1500:
			check_eq(runtime.step(0.1),"","service composed with integrated ingredient")
			if runtime.frame().guests[0].state == "gone": break
		check_eq(runtime.runner.owner.sold,2,"both order lines delivered using the same public service")
		check_eq(runtime.runner.inventory.snapshot().consumed.get("milk",0),1,"only the enabled recipe consumes installed milk")
		check_eq(runtime.runner.inventory.audit(),[],"service inventory remains conserved")

func test_installed_supply_also_reuses_scaled_shared_restock_without_a_fake_pickup() -> void:
	var template: Resource = preload("res://tests/test_template_restock.gd").new()._definition()
	template.places.pot_in.infinite = ["milk"]
	template.restocks.pot_stock.consumes = {"raw":1,"milk":1}
	template.restocks.pot_stock.produces = {"tea":1}
	template.restocks.pot_stock.batch = {"target":"pot","base":2,"max":4}
	var runtime := _runtime(template)
	if runtime == null: return
	for tick in 400: check_eq(runtime.step(0.1),"","batch native and physically supplied inputs")
	check_eq(runtime.runner.inventory.quantity("pot_out","tea"),4,"shared stock fills with two scaled batches")
	check_eq(runtime.runner.inventory.snapshot().consumed.get("milk",0),4,"native consumption scales with each committed batch")
	for claim in runtime.runner.inventory.snapshot().claims:
		if claim.kind == "transfer": check(claim.item != "milk","integrated batch input is not an employee transport")

func test_original_tea_pot_to_automatic_mixer_runs_with_explicit_integrated_milk() -> void:
	var runtime := Runtime.new(Tea.owner(),Tea.definition())
	check_eq(runtime.last_error,"","real tea production graph compiles using the public integrated binding")
	if not runtime.last_error.is_empty(): return
	var unit: Dictionary = runtime.request_production("milk_tea")
	for tick in 2400:
		check_eq(runtime.step(0.1),"","real tea shared pot and automatic mixer")
		runtime.source_demand()
		if runtime.ready(unit.id): break
	check(runtime.ready(unit.id),"real leaf → shared tea → physically moved tea + installed milk → original milk tea")
	check_eq(runtime.runner.inventory.quantity("mix_out","plain_milk_tea",unit.id),1,"original formal mix recipe produces one owned cup")
	check_eq(runtime.runner.inventory.snapshot().consumed.get("tea_leaf",0),2,"original two-serving kettle uses two real raw ingredients")
	check_eq(runtime.runner.inventory.snapshot().consumed.get("milk",0),1,"original mix consumes one installed milk serving")
	var saw_mix := false
	for run in runtime.runner.machines.snapshot().runs:
		if run.machine == "mix":
			saw_mix = true
			check_eq(run.duration,4.0,"automatic mixer uses its four-second machine parameter")
	check(saw_mix,"a real automatic machine operation executed")
	check_eq(runtime.frame().draws,[],"stocks and native materials remain UI data")
	check_eq(runtime.runner.inventory.audit(),[],"formal production combination conserves all inputs and outputs")
