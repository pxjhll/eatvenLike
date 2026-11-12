extends "res://tests/test_case.gd"
const PATH := "res://content/shops/pancake/shared_production.tres"
const SHOP: SpecShop = preload("res://content/shops/pancake/shop.tres")
const Runtime := preload("res://game/rules/template/runtime.gd")

func _template() -> Resource:
	check(ResourceLoader.exists(PATH),"pancake needs authored production data for all real products")
	return load(PATH) if ResourceLoader.exists(PATH) else null

func _owner() -> ShopRules:
	var owner := ShopRules.new(SHOP.copy_for_editing(),42)
	owner.gold = 100000.0
	for id in ["soy_milk","rear_equipment","fryer","topping","bag"]: check_eq(owner.unlock(id),"","open actual station: "+id)
	check_eq(owner.unlock_box("flour"),"","buy actual flour box through public command")
	for index in 6: check_eq(owner.upgrade("topping"),"","open actual topping variants")
	owner.nav.set_open(owner.unlocked)
	return owner

func _runtime(template: Resource) -> RefCounted:
	var runtime := Runtime.new(_owner(),template)
	check_eq(runtime.last_error,"","pancake authored data uses only public capabilities")
	return runtime if runtime.last_error.is_empty() else null

func _finish(runtime: RefCounted, ids: Array, limit := 9000) -> void:
	for tick in limit:
		check_eq(runtime.step(0.1),"","real pancake production tick")
		var ready := true
		for id in ids: ready = ready and runtime.ready(id)
		if ready: return
	check(false,"all real products reach the pass")

func test_seven_dishes_and_seven_bagged_variants_are_explicit() -> void:
	var template := _template()
	if template == null: return
	check_eq(template.recipes.size(),14,"seven normal dishes and seven bag variants including soy")
	for dish in SHOP.dishes:
		check(template.recipes.has(dish.id),"real menu mapped: "+dish.id)
		check(template.recipes.has(dish.id+":bag"),"real option mapped: "+dish.id)
	check_eq(template.machines.rear_equipment.profile.load_seconds,1.0,"fixed batter preparation is a manual loading phase")
	check_eq(template.machines.rear_equipment.stage_ports,{"load":"mix:work","operate":"grill:work"},"two real positions share one continuously reserved device")
	check_eq(template.machines.rear_equipment.profile.slots,1,"one physical griddle cannot be shared mid-chain")
	check_eq(template.restocks.fryer.seconds,18.0,"keeps original frying clock")
	check_eq(template.restocks.fryer.produces,{"crisp":4},"real four-portion batch")
	check_eq(template.places.crisps.initial,{"crisp":4},"keeps original starting stock")

func test_every_real_recipe_and_bag_variant_conserves_flour_crisps_and_finished_goods() -> void:
	var template := _template()
	if template == null: return
	for dish in SHOP.dishes:
		for bag in [false,true]:
			var runtime := _runtime(template)
			if runtime == null: return
			var request: Dictionary = runtime.request_production(dish.id+(":bag" if bag else ""))
			_finish(runtime,[request.id])
			var output: Dictionary = runtime.production_output(request.id)
			check_eq(output.item,"bagged" if bag else dish.item,"actual product identity")
			check_eq(runtime.runner.inventory.quantity(output.place,output.item,request.id),1,"one real owned final product")
			var stock: Dictionary = runtime.runner.inventory.snapshot()
			check_eq(stock.consumed.get("flour",0),0 if dish.id=="soy" else 1,"one flour portion per real pancake")
			check_eq(stock.consumed.get("crisp",0),0 if dish.id in ["soy","plain"] else 1,"crisp joining also consumes the carried pancake")
			check_eq(runtime.runner.inventory.audit(),[],"real ingredients are conserved")
			check_eq(runtime.frame().draws,[],"waiting final products stay UI stock")

func test_griddle_retains_one_employee_while_walking_from_mixer_to_grill() -> void:
	var template := _template()
	if template == null: return
	var runtime := _runtime(template)
	if runtime == null: return
	var request: Dictionary = runtime.request_production("plain")
	var phases := {}
	var operator := -1
	for tick in 3000:
		check_eq(runtime.step(0.1),"","real preparation and grilling")
		for run in runtime.runner.machines.snapshot().runs:
			if run.machine != "rear_equipment" or run.phase not in ["load","operate"]: continue
			phases[run.phase] = true
			if operator < 0: operator = run.operator
			check_eq(run.operator,operator,"same employee holds both preparation stages")
			check_eq(runtime.runner.owner.worker_by_id(run.operator).pos,SHOP.layout.points["batter_mixer" if run.phase=="load" else "rear_equipment"],"real movement follows the authored stage anchor")
		if runtime.ready(request.id): break
	check_eq(phases.size(),2,"both manual stages occurred")
	check(runtime.ready(request.id),"same employee finishes the actual pancake")

func test_bag_and_roll_only_show_actual_processing_inputs_after_drop() -> void:
	var template := _template()
	if template == null: return
	var runtime := _runtime(template)
	if runtime == null: return
	var request: Dictionary = runtime.request_production("ham:bag")
	var seen := {}
	for tick in 5000:
		check_eq(runtime.step(0.1),"","real roll and bag display lifecycle")
		for draw in runtime.frame().draws:
			seen[draw.machine] = true
			check_eq(draw.item,"ham_top" if draw.machine=="roll" else "ham","display uses the real input, never future bagged output")
		if runtime.ready(request.id): break
	check_eq(seen,{"roll":true,"bag":true},"both explicit display abilities executed")
	check_eq(runtime.frame().draws,[],"completion clears processing display")

func test_actual_menu_restores_during_preparation_grilling_frying_and_bagging() -> void:
	var template := _template()
	if template == null: return
	for checkpoint in ["load","operate","fryer","bag"]:
		var runtime := _runtime(template)
		if runtime == null: return
		# Force a new four-portion batch through actual requests, not direct stock edits.
		var ids: Array = []
		for index in 6: ids.append(runtime.request_production("family:bag").id)
		var reached := false
		for tick in 7000:
			check_eq(runtime.step(0.1),"","reach actual production save boundary")
			for run in runtime.runner.machines.snapshot().runs:
				if (run.machine=="rear_equipment" and run.phase==checkpoint) or (run.machine==checkpoint and run.phase in ["processing","operate"]): reached = true
			if reached: break
		check(reached,"actual production reached "+checkpoint)
		if not reached: return
		var reopened := _runtime(template)
		if reopened == null: return
		check_eq(reopened.restore(runtime.snapshot()),"","restore actual pancake at "+checkpoint)
		_finish(runtime,ids)
		_finish(reopened,ids)
		check_eq(reopened.snapshot(),runtime.snapshot(),"all real claims and stage ports replay at "+checkpoint)
