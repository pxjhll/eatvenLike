extends "res://tests/test_case.gd"
const Schema := preload("res://content/rules/spec_shop_template.gd")
const Runtime := preload("res://game/rules/template/runtime.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")
const Actors := preload("res://tests/fixtures/template_service.gd")
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")

func _definition() -> Resource:
	var template := Schema.new()
	template.places = {"raw":{"port":Vector2(100,100),"infinite":["leaf"]},
		"in":{"port":Vector2(300,100),"capacity":8},"out":{"port":Vector2(300,100),"capacity":8}}
	template.machines = {"pot":{"input":"in","output":"out","profile":{"load_seconds":0.2,"unload_seconds":0.2,"stir_points":[0.5],"stir_seconds":0.2}}}
	template.recipes = {"cup":{"nodes":[{"id":"stock","capability":"source","place":"out","item":"tea"}],"output":{"node":"stock","item":"tea","count":1}}}
	template.restocks = {"stock":{"machine":"pot","consumes":{"leaf":1},"produces":{"tea":1},"sources":{"leaf":"raw"},
		"seconds":2.0,"fetch_seconds":0.2,"stock_limit":8,"policy":{"mode":"demand","base":1,"per_waiting":1},
		"batch":{"target":"pot","base":3,"max":8}}}
	return template

func _runtime(template: Resource) -> RefCounted:
	var owner := Actors.owner()
	owner.workers[1].deployed = false
	owner.workers[0].pos = Vector2(100,100)
	var runtime := Runtime.new(owner,template)
	check_eq(runtime.last_error,"","valid explicit per-serving recipe and batch binding")
	return runtime if runtime.last_error.is_empty() else null

func _advance(runtime: RefCounted, ticks := 300) -> void:
	for tick in ticks: check_eq(runtime.step(0.1),"","shared batch runtime")

func _cooking(runtime: RefCounted) -> void:
	for tick in 400:
		check_eq(runtime.step(0.1),"","collect a whole batch and begin cooking")
		for run in runtime.runner.machines.snapshot().runs:
			if run.phase in ["processing","stir","await_stir"]: return
	check(false,"a real batch reached cooking")

func test_whole_batch_inputs_use_real_employee_capacity_and_cannot_start_after_only_one_trip() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	var saw_partial := false
	for tick in 500:
		check_eq(runtime.step(0.1),"","carry and cook the complete batch")
		var available: int = runtime.runner.inventory.quantity("in","leaf")
		if available == 2 and runtime.runner.machines.snapshot().runs.is_empty(): saw_partial = true
		if runtime.runner.inventory.quantity("out","tea") == 3: break
	check(saw_partial,"capacity-two employee must make another trip for the third ingredient")
	check_eq(runtime.runner.inventory.quantity("out","tea"),3,"three real ingredients yield exactly three servings")
	check_eq(runtime.runner.inventory.quantity("in","leaf"),0,"the entire batch is consumed once")
	check_eq(runtime.runner.inventory.snapshot().consumed.get("leaf",0),3,"no virtual ingredient bypass")
	check_eq(runtime.runner.inventory.audit(),[],"batch uses the existing authoritative ledger")

func test_batch_upgrade_before_loading_changes_actual_input_and_output_quantities() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	runtime.runner.owner.apply_effect("event","larger_batch",SpecEffect.make("batch","set",4.0,"pot"))
	_advance(runtime)
	check_eq(runtime.runner.inventory.quantity("out","tea"),4,"upgraded batch produces four real servings")
	check_eq(runtime.runner.inventory.snapshot().consumed.get("leaf",0),4,"upgraded batch also requires four real inputs")

func test_upgrade_during_cooking_preserves_the_committed_batch_and_restores_with_the_new_modifier() -> void:
	var template := _definition()
	var runtime := _runtime(template)
	if runtime == null: return
	_cooking(runtime)
	runtime.runner.owner.apply_effect("event","larger_batch",SpecEffect.make("batch","set",4.0,"pot"))
	var reopened := _runtime(template)
	if reopened == null: return
	reopened.runner.owner.apply_effect("event","larger_batch",SpecEffect.make("batch","set",4.0,"pot"))
	check_eq(reopened.restore(runtime.snapshot()),"","already committed size three remains valid after upgrading to four")
	for tick in 250:
		check_eq(runtime.step(0.1),"","finish original batch")
		check_eq(reopened.step(0.1),"","finish restored original batch")
	check_eq(reopened.snapshot(),runtime.snapshot(),"restore preserves original inputs, output and remaining stages")
	check_eq(runtime.runner.inventory.quantity("out","tea"),3,"an in-flight upgrade cannot add an unearned fourth serving")
	for index in 4: runtime.request_production("cup")
	_advance(runtime)
	check_eq(runtime.runner.inventory.quantity("out","tea"),7,"only the next batch uses size four")
	check_eq(runtime.runner.inventory.snapshot().consumed.get("leaf",0),7,"both batches conserve their own input quantities")

func test_restock_fetch_target_uses_public_machine_tuning_then_employee_rate_once() -> void:
	var template := _definition()
	template.restocks.stock.fetch_seconds = 2.0
	template.restocks.stock.fetch_timing_target = "supply"
	var runtime := _runtime(template)
	if runtime == null: return
	var owner: RefCounted = runtime.runner.owner
	owner.tune["supply"] = 2.0
	owner.workers[0].stats.work = 2.0
	owner.apply_effect("event","supply_speed",SpecEffect.make("speed","mul",2.0,"supply"))
	owner.apply_effect("event","supply_duration",SpecEffect.make("duration","mul",3.0,"supply"))
	check_eq(runtime.step(0.1),"","assign real raw-material pickup")
	check_eq(runtime.runner.tasks[owner.workers[0].id].seconds,3.0,"2 base × 3 duration ÷ 2 speed × 2 tuning ÷ 2 employee rate")

func test_bad_batch_shape_and_impossible_maximums_are_authoring_errors() -> void:
	for patch in [{"base":0},{"max":2},{"max":9},{"target":17},{"callback":"private"}]:
		var template := _definition()
		template.restocks.stock.batch.merge(patch,true)
		var compiled := Compiler.compile(template)
		check(not compiled.errors.is_empty(),"invalid or physically impossible batch binding is rejected")
		check(compiled.errors.any(func(error: Dictionary) -> bool: return String(error.path).begins_with("restocks.stock")),"batch authoring error includes its rule path")

func test_invalid_effective_batch_does_not_reserve_a_partial_operation_or_move_material() -> void:
	for size in [0.0,2.5,9.0,INF]:
		var runtime := _runtime(_definition())
		if runtime == null: return
		runtime.runner.owner.apply_effect("event","invalid_batch",SpecEffect.make("batch","set",size,"pot"))
		var before: Dictionary = runtime.runner.inventory.snapshot()
		check(not runtime.step(0.1).is_empty(),"invalid effective batch has an explicit runtime error")
		check_eq(runtime.runner.inventory.snapshot(),before,"invalid batch cannot reserve half its inputs or outputs")
		check_eq(runtime.runner.tasks,{},"invalid batch cannot assign raw-material transport")

func test_restored_batch_cannot_change_only_output_ratio_or_exceed_its_declared_range() -> void:
	var template := _definition()
	var runtime := _runtime(template)
	if runtime == null: return
	_cooking(runtime)
	var saved: Dictionary = runtime.snapshot()
	var claim_id: int = saved.runner.machines.runs[0].claim
	for claim in saved.runner.inventory.claims:
		if claim.id == claim_id: claim.produces.tea = 4
	var reopened := _runtime(template)
	if reopened == null: return
	var before: Dictionary = reopened.snapshot()
	check(not reopened.restore(saved).is_empty(),"one extra output without the corresponding input is rejected")
	check_eq(reopened.snapshot(),before,"failed adoption preserves original actors and inventory")

func test_batch_count_boundaries_reject_zero_scaling_and_inexact_modifier_ranges() -> void:
	var helper: Script = load("res://game/rules/template/batch_recipe.gd")
	check(not helper.scale({"leaf":1},0).error.is_empty(),"zero multiplier is a structured error, not division by zero")
	var template := _definition()
	template.places["in"].capacity = -1
	template.places.out.capacity = -1
	template.restocks.stock.stock_limit = 9223372036854775807
	template.restocks.stock.batch.max = 9007199254740992
	check(not Compiler.compile(template).errors.is_empty(),"batch modifiers use floating numbers and cannot declare an inexact integer range")
	var unused := _definition()
	unused.restocks.stock.fetch_fixed = true
	check(not Compiler.compile(unused).errors.is_empty(),"fixed fetch policy needs an explicit numeric target instead of being silently unused")

func test_fixed_restock_fetch_skips_machine_effects_but_keeps_target_tuning_and_employee_rate() -> void:
	var template := _definition()
	template.restocks.stock.fetch_seconds = 2.0
	template.restocks.stock.fetch_timing_target = "supply"
	template.restocks.stock.fetch_fixed = true
	var runtime := _runtime(template)
	if runtime == null: return
	var owner: RefCounted = runtime.runner.owner
	owner.tune["supply"] = 2.0
	owner.workers[0].stats.work = 2.0
	owner.apply_effect("event","supply_speed",SpecEffect.make("speed","mul",5.0,"supply"))
	check_eq(runtime.step(0.1),"","assign fixed raw-material pickup")
	check_eq(runtime.runner.tasks[owner.workers[0].id].seconds,2.0,"fixed skips machine speed but preserves 2 × 2 tuning ÷ 2 employee rate")

func test_real_milk_tea_pot_uses_original_navigation_stirring_and_employee_actions_for_two_batch_sizes() -> void:
	var shop: SpecShop = TEA.copy_for_editing()
	var pot := shop.station("boil")
	var template := Schema.new()
	template.places = {"raw":{"port":shop.layout.points.supply,"infinite":["tea_leaf"]},
		"in":{"port":shop.layout.points.boil,"capacity":12},"out":{"port":shop.layout.points.boil,"capacity":12},
		"received":{"port":shop.layout.points.shelf,"capacity":4}}
	template.machines = {"boil":{"input":"in","output":"out","profile":{
		"load_seconds":pot.params.load_seconds,"unload_seconds":shop.dispatch.hop_seconds,
		"stir_points":pot.params.stir_points.duplicate(),"stir_seconds":pot.params.stir_seconds}}}
	template.restocks = {"stock":{"machine":"boil","consumes":{"tea_leaf":1},"produces":{"tea":1},"sources":{"tea_leaf":"raw"},
		"seconds":pot.params.cook_seconds,"fetch_seconds":shop.station("supply").params.fetch_seconds,"fetch_timing_target":"supply",
		"stock_limit":12,"policy":{"mode":"demand","base":1,"per_waiting":1},"batch":{"target":"boil","base":3,"max":12}}}
	template.recipes = {"cup":{"nodes":[{"id":"stock","capability":"source","place":"out","item":"tea","seconds":shop.dispatch.hop_seconds}],
		"output":{"node":"stock","item":"tea","count":1}}}
	var owner := ShopRules.new(shop,42)
	check_eq(owner.pot_batch("boil"),2,"formal base effects set the initial batch to two despite the fallback base of three")
	for station in shop.stations: owner.unlocked[station.id] = true
	owner.nav.set_open(owner.unlocked)
	var runtime := Runtime.new(owner,template)
	check_eq(runtime.last_error,"","original milk-tea navigation and machine parameters compose with the same public batch runtime")
	if not runtime.last_error.is_empty(): return
	var unit: Dictionary = runtime.request_production("cup")
	for tick in 2400:
		check_eq(runtime.step(0.1),"","real milk-tea shared pot")
		if runtime.ready(unit.id): break
	check(runtime.ready(unit.id),"staff carried the real inputs and completed all machine stages")
	check_eq(runtime.runner.inventory.quantity("out","tea"),2,"original base effect produces a two-serving first batch")
	var run: Dictionary = runtime.runner.machines.snapshot().runs[0]
	check_eq(run.duration,30.0,"actual pot keeps the formal thirty-second cooking clock")
	check_eq(run.stir_index,2,"both formal stirring points were executed")
	var worker: Dictionary = {}
	for candidate in owner.workers:
		if candidate.deployed and runtime.runner.idle(candidate.id): worker = candidate; break
	check(not worker.is_empty(),"employee available to harvest the actual pot")
	if worker.is_empty(): return
	check_eq(runtime.runner.transfer(worker.id,"out","received","tea",1,shop.dispatch.hop_seconds,-1,unit.id),"","harvest uses normal physical pickup and drop")
	for tick in 600:
		check_eq(runtime.step(0.1),"","actual milk-tea receiving path")
		if runtime.runner.idle(worker.id): break
	check_eq(runtime.runner.inventory.quantity("received","tea",unit.id),1,"real tea reached the formal shelf coordinate")
	owner.apply_effect("event","larger_tea_batch",SpecEffect.make("batch","set",6.0,"boil"))
	for index in 3: runtime.request_production("cup")
	for tick in 2400:
		check_eq(runtime.step(0.1),"","upgraded formal pot through the same common capabilities")
		if runtime.runner.inventory.quantity("out","tea") == 7: break
	check_eq(runtime.runner.inventory.quantity("out","tea"),7,"one old serving plus the new six-serving batch")
	check_eq(runtime.runner.inventory.snapshot().consumed.get("tea_leaf",0),8,"two plus six real raw ingredients were consumed")
	check_eq(runtime.runner.inventory.audit(),[],"original navigation and upgraded production preserve inventory")
	check_eq(runtime.frame().draws,[],"waiting pot stock remains UI data")
