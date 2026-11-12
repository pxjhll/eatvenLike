extends "res://tests/test_case.gd"
const PATH := "res://content/shops/tea/shared_production.tres"
const Runtime := preload("res://game/rules/template/runtime.gd")
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")

func _template() -> Resource:
	check(ResourceLoader.exists(PATH),"milk-tea shop needs authored production data, not another toy recipe fixture")
	return load(PATH) if ResourceLoader.exists(PATH) else null

func _owner() -> ShopRules:
	var owner := ShopRules.new(TEA.copy_for_editing(),42)
	owner.gold = 100000.0
	for id in ["lemonade","boil","seal","mix","press","topping"]: check_eq(owner.unlock(id),"","prepare real milk-tea station through shared command: " + id)
	for id in ["tea_leaf","milk"]: check_eq(owner.unlock_box(id),"","install actual material box: " + id)
	for index in 3: check_eq(owner.upgrade("topping"),"","open actual topping flavors")
	check_eq(owner.hire(),"","recruit the actual kitchen employee instead of letting the sole front employee bypass its post")
	for worker in owner.roster:
		if not worker.deployed: check_eq(owner.deploy_worker(worker.id),"","deploy recruited kitchen employee through shared command")
	owner.nav.set_open(owner.unlocked)
	return owner

func _run(template: Resource) -> RefCounted:
	var runtime := Runtime.new(_owner(),template)
	check_eq(runtime.last_error,"","all authored milk-tea recipes compile on the common runtime")
	return runtime if runtime.last_error.is_empty() else null

func _finish(runtime: RefCounted, ids: Array, max_ticks := 6000) -> void:
	for tick in max_ticks:
		check_eq(runtime.step(0.1),"","formal milk-tea production tick")
		var ready := true
		for id in ids: ready = ready and runtime.ready(id)
		if ready: return
	check(false,"all requested real milk-tea products reach their final containers")

func test_all_eight_formal_dishes_and_six_sealed_variants_are_explicit_data() -> void:
	var template := _template()
	if template == null: return
	check_eq(Runtime.new(_owner(),template).last_error,"","authored shop uses only public capabilities")
	check_eq(template.recipes.size(),14,"eight normal products and six kitchen takeaway variants")
	for dish in TEA.dishes:
		check(template.recipes.has(dish.id),"formal menu product mapped: " + dish.id)
		if dish.takeaway_process: check(template.recipes.has(dish.id+":sealed"),"explicit sealed path: " + dish.id)
	check_eq(template.restocks.mix.batch,{"mode":"available","max":6},"automatic mixer processes physically arrived stock as a shared batch")
	check_eq(template.restocks.mix.seconds,4.0,"keeps real machine clock, not the zero-second recipe action")
	check_eq(template.restocks.boil.seconds,30.0,"real thirty-second shared pot")
	check_eq(template.restocks.boil.consumes,{"tea_leaf":1},"pot consumes actual transported tea leaves")
	check_eq(template.restocks.boil.produces,{"black_tea":1},"shared stock uses the real legacy output identity")
	check_eq(template.places.mix.capacity,6,"input/output use one physical quota")
	check_eq(template.places.mix.infinite,["milk"],"native milk supply is explicit")
	check_eq(template.places.boil.get("anchor"),"boil","production data references real scene ports instead of copied coordinates")
	check_eq(template.machines.boil.get("work_port"),"boil:work","pot operation keeps its separate legacy standing point")

func test_every_real_milk_tea_recipe_reaches_the_pass_using_original_navigation_and_staff() -> void:
	var template := _template()
	if template == null: return
	for dish in TEA.dishes:
		var runtime := _run(template)
		if runtime == null: return
		var request: Dictionary = runtime.request_production(dish.id)
		_finish(runtime,[request.id])
		check_eq(runtime.production_output(request.id).item,dish.item,"output retains actual dish identity")
		check_eq(runtime.runner.inventory.quantity(runtime.production_output(request.id).place,dish.item,request.id),1,"one real owned product reached pass: " + dish.id)
		check_eq(runtime.frame().draws,[],"ordinary milk-tea inventory remains UI-only")
		check_eq(runtime.runner.inventory.audit(),[],"real shop conserves input, hand and output")
		check_eq(runtime.runner.machines.audit(),[],"real shop devices agree with inventory")

func test_six_takeaway_recipes_really_seal_and_finish_on_the_shared_takeaway_rack() -> void:
	var template := _template()
	if template == null: return
	var runtime := _run(template)
	if runtime == null: return
	var ids: Array = []
	for dish in TEA.dishes:
		if dish.takeaway_process: ids.append(runtime.request_production(dish.id+":sealed").id)
	_finish(runtime,ids)
	for id in ids:
		var output: Dictionary = runtime.production_output(id)
		check_eq(output.place,"rack","sealed product physically arrives on the takeaway rack")
		check_eq(runtime.runner.inventory.quantity("rack",output.item,id),1,"rack contains actual owned output")
	var sealed := 0
	for run in runtime.runner.machines.snapshot().runs:
		if run.machine == "seal":
			check_eq(run.duration,9.0,"initial sealing clock is nine seconds")
			if run.phase == "completed": sealed += 1
	check_eq(sealed,6,"all six kitchen variants really used the same sealer")

func test_sealing_upgrade_keeps_legacy_rate_semantics_and_existing_work_duration_on_restore() -> void:
	var template := _template()
	if template == null: return
	var runtime := _run(template)
	if runtime == null: return
	runtime.runner.owner.apply_effect("event","seal_slots",SpecEffect.make("process_slots","set",3.0,"seal"))
	var request: Dictionary = runtime.request_production("plain_milk_tea:sealed")
	for tick in 3000:
		check_eq(runtime.step(0.1),"","reach actual sealing")
		if runtime.unit(request.id).running.has("seal"): break
	var run: Dictionary = runtime.runner.machines.run(runtime.unit(request.id).running.get("seal",-1))
	check(not run.is_empty(),"real sealing operation exists")
	if run.is_empty(): return
	check_eq(run.duration,3.0,"nine seconds divided by three legacy processing positions")
	check_eq(runtime.runner.machines.snapshot().definitions.seal.profile.slots,1,"legacy rate upgrade does not invent concurrent sealer clocks")
	var reopened := _run(template)
	if reopened == null: return
	check_eq(reopened.restore(runtime.snapshot()),"","in-flight upgraded sealer keeps committed time without requiring current modifier equality")
	_finish(runtime,[request.id])
	_finish(reopened,[request.id])
	check_eq(reopened.snapshot(),runtime.snapshot(),"real production save replays at the sealing boundary")

func test_formal_content_and_existing_scene_resources_are_not_mutated_by_shared_production() -> void:
	var template := _template()
	if template == null: return
	var contract := preload("res://game/rules/shop_content_contract.gd")
	var before: Dictionary = contract.describe(TEA)
	var runtime := _run(template)
	if runtime == null: return
	var request: Dictionary = runtime.request_production("pearl_milk_tea:sealed")
	_finish(runtime,[request.id])
	check_eq(contract.describe(TEA),before,"authored template never edits legacy shop, price, speed or customer definitions")

func test_full_real_menu_wave_restores_during_pot_stirring_and_shared_mixing() -> void:
	var template := _template()
	if template == null: return
	for checkpoint in ["stir","mix"]:
		var runtime := _run(template)
		if runtime == null: return
		var ids: Array = []
		for dish in TEA.dishes:
			ids.append(runtime.request_production(dish.id).id)
			if dish.takeaway_process: ids.append(runtime.request_production(dish.id+":sealed").id)
		var reached := false
		for tick in 3500:
			check_eq(runtime.step(0.1),"","reach a full-menu real production boundary")
			for run in runtime.runner.machines.snapshot().runs:
				if (checkpoint=="stir" and run.machine=="boil" and run.phase in ["await_stir","stir"]) or (checkpoint=="mix" and run.machine=="mix" and run.phase=="processing"): reached = true
			if reached: break
		check(reached,"actual menu reached " + checkpoint)
		if not reached: return
		var reopened := _run(template)
		if reopened == null: return
		check_eq(reopened.restore(runtime.snapshot()),"","restore full real menu at " + checkpoint)
		_finish(runtime,ids)
		_finish(reopened,ids)
		check_eq(reopened.snapshot(),runtime.snapshot(),"all fourteen paths, stocks and employees replay identically at " + checkpoint)
		check_eq(reopened.runner.inventory.quantity("rack"),6,"all takeaway products occupy the declared rack quota")

func test_original_front_employee_physically_collects_finished_drink_and_delivers_to_counter() -> void:
	var template := _template()
	if template == null: return
	var runtime := _run(template)
	if runtime == null: return
	var request: Dictionary = runtime.request_production("pearl_milk_tea:sealed")
	_finish(runtime,[request.id])
	var front: Dictionary = {}
	for worker in runtime.runner.owner.workers:
		if worker.post == "counter": front = worker
	check(not front.is_empty(),"use the original deployed front employee")
	if front.is_empty(): return
	var output: Dictionary = runtime.production_output(request.id)
	check_eq(runtime.runner.transfer(front.id,output.place,"counter",output.item,1,template.hop_seconds,request.id,request.id),"","front role may collect the actual finished output")
	check(not runtime.frame().held.has(front.id),"reservation cannot show a held cup")
	var carried := false
	for tick in 700:
		check_eq(runtime.step(0.1),"","front employee physically collects and delivers")
		if front.carry_count > 0:
			carried = true
			check_eq(runtime.frame().held[front.id].items,[{"item":"pearl_milk_tea","count":1}],"held icon comes from the real final drink")
		if runtime.runner.idle(front.id): break
	check(carried,"front employee actually carried the sealed product")
	check_eq(runtime.runner.inventory.quantity("counter","pearl_milk_tea",request.id),1,"same owned cup reaches the original counter coordinate")
	check(not runtime.frame().held.has(front.id),"counter drop clears the held item")
	check_eq(runtime.runner.inventory.audit(),[],"full production and front delivery conserve the same cup")
