extends "res://tests/test_case.gd"
const Runtime := preload("res://game/rules/template/runtime.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")
const Production := preload("res://tests/fixtures/template_shop.gd")
const Actors := preload("res://tests/fixtures/template_service.gd")
const Stock := preload("res://game/rules/template/inventory.gd")
const Machines := preload("res://game/rules/template/machines.gd")
const View := preload("res://game/rules/template/view_frame.gd")

func _binding() -> Dictionary:
	return {"capability":"processing_item","items":["raw_a"],"points":[Vector2(210,80)],"host":"bench"}

func _definition() -> Resource:
	var template := Production.linear()
	template.machines.a["processing_display"] = _binding()
	return template

func _runtime(template: Resource) -> RefCounted:
	var runtime := Runtime.new(Actors.owner(),template)
	check_eq(runtime.last_error,"","explicit processing display compiles")
	return runtime if runtime.last_error.is_empty() else null

func _advance(runtime: RefCounted, ticks := 500) -> void:
	for tick in ticks: check_eq(runtime.step(0.1),"","shared processing/display step")

func _operate(runtime: RefCounted) -> Dictionary:
	for tick in 500:
		check_eq(runtime.step(0.1),"","wait for actual processing employee")
		for run in runtime.runner.machines.snapshot().runs:
			if run.phase == "operate": return run
	check(false,"real manual operation started")
	return {}

func _machine(profile: Dictionary = {}, ceiling := 1) -> Dictionary:
	var stock := Stock.new()
	stock.configure("bench",8)
	stock.configure("ready",8)
	stock.seed("bench","raw_a",6)
	var devices: RefCounted = Machines.new(stock)
	check_eq(devices.configure("a","bench","ready",profile),"","shared machine configuration")
	check(devices.has_method("track_slots"),"display positions need stable machine slot identities")
	if not devices.has_method("track_slots"): return {}
	check_eq(devices.track_slots("a",ceiling),"","enable bounded slot identities")
	var binding := _binding()
	binding.machine = "a"
	return {"stock":stock,"machines":devices,"binding":binding}

func test_only_real_deposited_processing_inputs_appear_at_explicit_ports() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	var unit: Dictionary = runtime.request_production("drink")
	check_eq(runtime.frame().draws,[],"demand cannot create a tabletop item")
	var carried := false
	for tick in 500:
		check_eq(runtime.step(0.1),"","real transport before processing")
		var frame: Dictionary = runtime.frame()
		if not frame.held.is_empty():
			carried = true
			check_eq(frame.draws,[],"carried raw material cannot also sit on the bench")
		if not frame.draws.is_empty():
			check(carried,"an employee actually carried the input before it was placed")
			check_eq(frame.held,{},"processing input is no longer in hands")
			check_eq(frame.draws[0].item,"raw_a","show actual reserved input, never future output")
			check_eq(frame.draws[0].pos,Vector2(210,80),"uses explicit tabletop port")
			check_eq(frame.draws[0].host,"bench","draw has an explicit sorting host")
			check_eq(runtime.runner.inventory.quantity("a_in","raw_a",unit.id),1,"shown input still exists in authoritative stock")
			break
	check(not runtime.frame().draws.is_empty(),"processing acquired a real display")
	_advance(runtime)
	check(runtime.ready(unit.id),"real production finished")
	check_eq(runtime.frame().draws,[],"finished waiting product is UI stock")
	check_eq(runtime.runner.inventory.snapshot().created.drink,1,"presentation cannot create another product")

func test_unassigned_stock_is_hidden_and_reserved_input_uses_its_real_count() -> void:
	var setup := _machine({"manual":true})
	if setup.is_empty(): return
	check_eq(View.build(setup.stock,setup.machines,[setup.binding]).draws,[],"waiting stock has no processing display")
	setup.machines.start("a",{"raw_a":2},{"meal":1},2.0)
	var frame: Dictionary = View.build(setup.stock,setup.machines,[setup.binding])
	check_eq(frame.draws.size(),1,"one run has one display slot")
	check_eq(frame.draws[0].count,2,"count derives from the actual reserved recipe")
	check_eq(frame.stock.bench.count,6,"display does not subtract or copy UI stock")
	check_eq(frame.stock.bench.reserved,2,"same inventory transaction reserves inputs")

func test_load_stir_unload_and_cancel_share_one_display_lifecycle() -> void:
	var setup := _machine({"load_seconds":0.2,"unload_seconds":0.2,"stir_points":[0.5],"stir_seconds":0.2})
	if setup.is_empty(): return
	var run: Dictionary = setup.machines.start("a",{"raw_a":1},{"meal":1},1.0)
	for stage in ["load","stir","unload"]:
		var frame: Dictionary = View.build(setup.stock,setup.machines,[setup.binding])
		check_eq(frame.draws.size(),1,"real input remains displayed while awaiting " + stage)
		check_eq(setup.machines.engage(run.id,1),"","shared stage assignment")
		setup.machines.advance(0.2)
		if stage != "unload": setup.machines.advance(0.5)
	check_eq(setup.stock.quantity("ready","meal"),1,"unload really commits output")
	check_eq(View.build(setup.stock,setup.machines,[setup.binding]).draws,[],"commit clears processing display immediately")
	run = setup.machines.start("a",{"raw_a":1},{"meal":1},1.0)
	check_eq(setup.machines.cancel(run.id),"","cancel real machine operation")
	check_eq(View.build(setup.stock,setup.machines,[setup.binding]).draws,[],"cancelled input returns to hidden UI stock")
	check_eq(setup.stock.audit(),[],"display lifecycle preserves material conservation")

func test_recall_keeps_placed_material_and_remaining_work_then_restore_finishes_once() -> void:
	var template := _definition()
	var runtime := _runtime(template)
	if runtime == null: return
	var unit: Dictionary = runtime.request_production("drink")
	var run := _operate(runtime)
	if run.is_empty(): return
	check_eq(runtime.runner.cancel(run.operator),"","recall uses shared employee release")
	check_eq(runtime.frame().draws.size(),1,"placed input stays on bench while awaiting replacement")
	var reopened := _runtime(template)
	if reopened == null: return
	check_eq(reopened.restore(runtime.snapshot()),"","restore reserved material and stable display slot")
	check_eq(reopened.frame(),runtime.frame(),"display is derived exactly after restore")
	_advance(runtime)
	_advance(reopened)
	check(runtime.ready(unit.id) and reopened.ready(unit.id),"both real operations finish")
	check_eq(reopened.snapshot(),runtime.snapshot(),"recall/restore does not duplicate production")
	check_eq(reopened.frame().draws,[],"finished bench clears after restored work")

func test_parallel_runs_keep_slots_when_another_completes_and_reuse_only_free_positions() -> void:
	var setup := _machine({"slots":2},3)
	if setup.is_empty(): return
	setup.binding.points = [Vector2(210,80),Vector2(240,80),Vector2(270,80)]
	var first: Dictionary = setup.machines.start("a",{"raw_a":1},{"meal":1},0.5)
	var second: Dictionary = setup.machines.start("a",{"raw_a":1},{"meal":1},4.0)
	check_eq(setup.machines.run(first.id).slot,0,"first operation owns slot zero")
	check_eq(setup.machines.run(second.id).slot,1,"parallel operation owns slot one")
	setup.machines.advance(0.5)
	var frame: Dictionary = View.build(setup.stock,setup.machines,[setup.binding])
	check_eq(frame.draws.size(),1,"completed neighboring run disappears")
	check_eq(frame.draws[0].pos,Vector2(240,80),"remaining food never shifts into the freed position")
	var third: Dictionary = setup.machines.start("a",{"raw_a":1},{"meal":1},4.0)
	check_eq(setup.machines.run(third.id).slot,0,"new operation reuses the actually free slot")
	setup.machines.cancel(third.id)
	setup.machines.set_slots_limit("a",1)
	check(not setup.machines.start("a",{"raw_a":1},{"meal":1},1.0).error.is_empty(),"shrunk count blocks new work while old slot remains")
	check_eq(View.build(setup.stock,setup.machines,[setup.binding]).draws[0].pos,Vector2(240,80),"shrinking count does not move a retained run")
	check_eq(setup.machines.audit(),[],"retained physical slot and numeric occupancy agree")

func test_corrupt_or_duplicated_slot_identity_cannot_be_adopted() -> void:
	var template := _definition()
	template.machines.a.profile = {"manual":false,"slots":2}
	template.machines.a.processing_display.points.append(Vector2(240,80))
	var runtime := _runtime(template)
	if runtime == null: return
	for index in 2: runtime.request_production("drink")
	for tick in 400:
		check_eq(runtime.step(0.1),"","reach actual parallel machine operations")
		if runtime.runner.machines.snapshot().runs.size() >= 2: break
	var before: Dictionary = runtime.snapshot()
	check_eq(before.runner.machines.runs.size(),2,"two real operations exist")
	for patch in ["duplicate","missing","range","definition"]:
		var broken: Dictionary = before.duplicate(true)
		match patch:
			"duplicate": broken.runner.machines.runs[1].slot = broken.runner.machines.runs[0].slot
			"missing": broken.runner.machines.runs[0].erase("slot")
			"range": broken.runner.machines.runs[0].slot = 2
			"definition": broken.runner.machines.definitions.a.slot_ceiling = 3
		check(not runtime.restore(broken).is_empty(),"forged display slot rejected: " + patch)
		check_eq(runtime.snapshot(),before,"invalid display state preserves real actors")

func test_processing_draws_exclude_the_same_reserved_units_from_stock_showcases_regardless_of_binding_order() -> void:
	var setup := _machine()
	if setup.is_empty(): return
	setup.machines.start("a",{"raw_a":2},{"meal":1},4.0)
	var showcase := {"capability":"stock_showcase","place":"bench","points":[Vector2(10,10),Vector2(20,10),Vector2(30,10),Vector2(40,10),Vector2(50,10),Vector2(60,10)]}
	for bindings in [[setup.binding,showcase],[showcase,setup.binding]]:
		var frame: Dictionary = View.build(setup.stock,setup.machines,bindings)
		check_eq(frame.error,"","showcase and processing display can share authoritative stock")
		check_eq(frame.draws.size(),5,"four waiting singles plus one count-two processing draw, not seven icons")
		check_eq(setup.stock.quantity("bench","raw_a"),6,"projection never edits actual quantity")

func test_invalid_display_definitions_are_authoring_errors_and_never_fall_back_to_machine_coordinates() -> void:
	for patch in ["points","item","duplicate","callback","infinite","slot_max","ambiguous"]:
		var template := _definition()
		match patch:
			"points": template.machines.a.processing_display.points = []
			"item": template.machines.a.processing_display.items = ["missing"]
			"duplicate": template.machines.a.processing_display.items = ["raw_a","raw_a"]
			"callback": template.machines.a.processing_display.callback = "draw"
			"infinite": template.places.a_in.infinite = ["raw_a"]
			"slot_max": template.machines.a.slots_binding = {"target":"a","max":2}
			"ambiguous":
				template.recipes.drink.nodes[1].consumes["milk"] = 1
				template.recipes.drink.nodes[1].inputs["milk"] = {"capability":"integrated"}
				template.places.a_in.infinite = ["milk"]
				template.machines.a.processing_display.items.append("milk")
		check(not Compiler.compile(template).errors.is_empty(),"bad processing display rejected: " + patch)

func test_projection_is_detached_and_conflicting_runtime_bindings_clear_all_draws() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	runtime.request_production("drink")
	if _operate(runtime).is_empty(): return
	var before: Dictionary = runtime.snapshot()
	var frame: Dictionary = runtime.frame()
	frame.draws[0].item = "forged"
	frame.draws[0].pos = Vector2.ZERO
	check_eq(runtime.snapshot(),before,"view cannot change stock, slots or progress")
	var conflicting := _binding()
	conflicting.machine = "a"
	frame = runtime.frame([conflicting])
	check(not frame.error.is_empty(),"cannot bind one machine processing display twice")
	check_eq(frame.draws,[],"invalid display combination fails without a fallback draw")

func test_the_same_display_capability_works_on_a_merged_recipe_and_ordinary_linear_recipe() -> void:
	for graph in ["linear","merged"]:
		var template := _definition() if graph=="linear" else Production.definition()
		if graph == "merged":
			template.machines.join["processing_display"] = {"capability":"processing_item","items":["a"],"points":[Vector2(410,80)],"host":"merge_bench"}
		var runtime := _runtime(template)
		if runtime == null: return
		var unit: Dictionary = runtime.request_production("drink" if graph=="linear" else "meal")
		var seen := false
		for tick in 800:
			check_eq(runtime.step(0.1),"","shared display composition")
			if not runtime.frame().draws.is_empty(): seen = true
			if runtime.ready(unit.id): break
		check(seen,"same public capability projects real inputs: " + graph)
		check(runtime.ready(unit.id),"production still completes through common graph")
		check_eq(runtime.frame().draws,[],"completed output returns to UI-only stock")

func test_slot_upgrade_shrink_pause_and_restore_keep_a_retained_high_slot_and_real_work() -> void:
	var template := _definition()
	template.machines.a.profile.manual = false
	template.machines.a.slots_binding = {"target":"a","max":2}
	template.machines.a.processing_display.points.append(Vector2(240,80))
	template.recipes.drink.nodes[1].seconds = 1.0
	template.recipes["slow"] = template.recipes.drink.duplicate(true)
	template.recipes.slow.nodes[1].seconds = 8.0
	var runtime := _runtime(template)
	if runtime == null: return
	runtime.runner.owner.apply_effect("event","two_slots",SpecEffect.make("process_slots","set",2.0,"a"))
	var fast: Dictionary = runtime.request_production("drink")
	var slow: Dictionary = runtime.request_production("slow")
	for tick in 500:
		check_eq(runtime.step(0.1),"","reach a retained higher slot")
		if runtime.ready(fast.id) and not runtime.ready(slow.id): break
	check(runtime.ready(fast.id) and not runtime.ready(slow.id),"short original operation finished before the slow operation")
	runtime.runner.owner.mods.remove("event","two_slots")
	check_eq(runtime.step(0.1),"","shrink while physical slot one is retained")
	check_eq(runtime.frame().limits.slots.a,{"target":1,"applied":1,"used":1},"numeric capacity remains one actual occupied operation")
	check_eq(runtime.frame().draws[0].pos,Vector2(240,80),"physical port identity is retained despite lower count")
	var paused: Dictionary = runtime.snapshot()
	check_eq(runtime.step(100.0,true),"","pause real operation")
	check_eq(runtime.snapshot(),paused,"pause preserves input, slot and remaining time")
	var reopened := _runtime(template)
	if reopened == null: return
	check_eq(reopened.restore(runtime.snapshot()),"","high retained slot restores within original port ceiling")
	check_eq(reopened.frame(),runtime.frame(),"restored draw has the same point and authoritative progress")
	_advance(runtime)
	_advance(reopened)
	check_eq(reopened.snapshot(),runtime.snapshot(),"upgraded/shrunk work replays identically")
	check_eq(reopened.frame().draws,[],"final completion clears retained display")

func test_finite_multi_input_ambiguity_and_missing_future_ports_are_errors_while_empty_binding_is_compatible() -> void:
	var template := Production.definition()
	template.machines.join["processing_display"] = {"capability":"processing_item","items":["a","b"],"points":[Vector2(410,80)]}
	check(not Compiler.compile(template).errors.is_empty(),"two finite merged inputs require an unambiguous display selection")
	template = Production.linear()
	var before: Dictionary = Compiler.compile(template)
	template.machines.a["processing_display"] = {}
	check_eq(Compiler.compile(template),before,"empty binding changes neither compiled definitions nor old signature")

func test_unselected_processing_inputs_stay_hidden_instead_of_showing_unrelated_waiting_material() -> void:
	var setup := _machine()
	if setup.is_empty(): return
	setup.stock.seed("bench","raw_b",1)
	setup.machines.start("a",{"raw_b":1},{"meal":1},2.0)
	var frame: Dictionary = View.build(setup.stock,setup.machines,[setup.binding])
	check_eq(frame.draws,[],"raw_a waiting nearby does not stand in for another recipe's input")
	check_eq(frame.stock.bench.items.raw_a.count,6,"unselected waiting raw material remains ordinary UI stock")

func test_slot_tracking_keeps_device_configuration_idempotent_and_blocks_undeclared_expansion() -> void:
	var setup := _machine()
	if setup.is_empty(): return
	var before: Dictionary = setup.machines.snapshot()
	check_eq(setup.machines.configure("a","bench","ready"),"","enabling display cannot break identical ordinary device registration")
	check_eq(setup.machines.track_slots("a",1),"","same tracked ceiling is idempotent")
	check(not setup.machines.track_slots("a",2).is_empty(),"physical port declaration cannot silently change")
	check(not setup.machines.set_slots_limit("a",2).is_empty(),"direct numeric request cannot exceed available display ports")
	check_eq(setup.machines.snapshot(),before,"failed expansion cannot modify the original device")
