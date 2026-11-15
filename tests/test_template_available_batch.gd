extends "res://tests/test_case.gd"
const Runtime := preload("res://game/rules/template/runtime.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")
const Schema := preload("res://content/rules/spec_shop_template.gd")
const Actors := preload("res://tests/fixtures/template_service.gd")
const Linear := preload("res://tests/fixtures/template_shop.gd")

func _definition(initial := 2) -> Resource:
	var template := Schema.new()
	template.places = {"raw":{"port":Vector2(100,100),"infinite":["tea"]},
		"mix":{"port":Vector2(250,100),"capacity":6,"infinite":["milk"],"initial":{"tea":initial} if initial>0 else {}}}
	template.machines = {"mix":{"input":"mix","output":"mix","profile":{}}}
	template.restocks = {"mix":{"machine":"mix","consumes":{"tea":1,"milk":1},"produces":{"drink":1},"sources":{"tea":"raw"},
		"seconds":4.0,"stock_limit":6,"batch":{"mode":"available","max":6},"policy":{"mode":"demand","base":0,"per_waiting":1}}}
	template.recipes = {"drink":{"nodes":[{"id":"ready","capability":"source","place":"mix","item":"drink"}],"output":{"node":"ready","item":"drink","count":1}}}
	return template

func _runtime(template: Resource) -> RefCounted:
	var runtime := Runtime.new(Actors.owner(),template)
	check_eq(runtime.last_error,"","available-stock batch is an explicit public capability")
	return runtime if runtime.last_error.is_empty() else null

func _tick(runtime: RefCounted, count := 1) -> void:
	for tick in count: check_eq(runtime.step(0.1),"","shared available-batch tick")

func test_available_inputs_form_one_shared_batch_without_waiting_for_the_maximum() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	_tick(runtime)
	var state: Dictionary = runtime.snapshot()
	check_eq(state.runner.machines.runs.size(),1,"ready finite input starts even without new demand")
	var claim: Dictionary = runtime.runner.inventory.claim(state.runner.machines.runs[0].claim)
	check_eq(claim.consumes,{"tea":2,"milk":2},"actual two arrived portions use both declared ingredients")
	check_eq(claim.produces,{"drink":2},"one shared automatic operation owns both outputs")
	check_eq(state.runner.machines.runs[0].duration,4.0,"batch is four seconds total")
	_tick(runtime,45)
	check_eq(runtime.runner.inventory.quantity("mix","drink"),2,"both drinks really finish")
	check_eq(runtime.runner.inventory.snapshot().consumed.milk,2,"native supply is accounted once")

func test_new_raw_stock_can_arrive_during_processing_without_changing_the_old_batch() -> void:
	var runtime := _runtime(_definition(1))
	if runtime == null: return
	for index in 2: runtime.request_production("drink")
	_tick(runtime)
	var first: Dictionary = runtime.runner.machines.snapshot().runs[0]
	var saw_prefetch := false
	for tick in 35:
		_tick(runtime)
		for claim in runtime.runner.inventory.snapshot().claims:
			if claim.kind == "transfer" and claim.from == "raw" and claim.to == "mix": saw_prefetch = true
	check(saw_prefetch,"same public transport feeds an automatic machine while its current batch cooks")
	check_eq(runtime.runner.inventory.claim(first.claim).produces,{"drink":1},"arriving stock cannot enlarge an already committed batch")
	_tick(runtime,90)
	check_eq(runtime.runner.inventory.quantity("mix","drink"),2,"the later portion forms the next physical batch")
	check_eq(runtime.runner.inventory.snapshot().consumed.tea,2,"no extra batch or duplicate raw stock")

func test_available_batch_save_restores_its_committed_recipe_and_remaining_clock() -> void:
	var template := _definition()
	var runtime := _runtime(template)
	if runtime == null: return
	_tick(runtime,17)
	var reopened := _runtime(template)
	if reopened == null: return
	check_eq(reopened.restore(runtime.snapshot()),"","available input count is restored from operation claim")
	_tick(runtime,35)
	_tick(reopened,35)
	check_eq(reopened.snapshot(),runtime.snapshot(),"automatic shared batch replays with one inventory commit")

func test_available_batch_uses_only_the_output_space_that_can_really_be_reserved() -> void:
	var template := _definition(4)
	template.places["out"] = {"port":Vector2(250,100),"capacity":2,"initial":{"drink":1}}
	template.machines.mix.output = "out"
	template.restocks.mix.stock_limit = 2
	template.restocks.mix.batch.max = 2
	var runtime := _runtime(template)
	if runtime == null: return
	_tick(runtime)
	var run: Dictionary = runtime.runner.machines.snapshot().runs[0]
	check_eq(runtime.runner.inventory.claim(run.claim).produces,{"drink":1},"partial available batch uses the one free output position")
	_tick(runtime,45)
	check_eq(runtime.runner.inventory.quantity("out","drink"),2,"real capacity remains the hard limit")

func test_available_batch_rejects_unbounded_or_native_only_input_and_private_fields() -> void:
	for patch in ["maximum","target","native","mode"]:
		var template := _definition()
		match patch:
			"maximum": template.restocks.mix.batch.max = 7
			"target": template.restocks.mix.batch.target = "private"
			"native":
				template.restocks.mix.consumes = {"milk":1}
				template.restocks.mix.sources = {}
			"mode": template.restocks.mix.batch.mode = "callback"
		check(not Compiler.compile(template).errors.is_empty(),"unsafe available batch rejected: " + patch)

func test_explicit_slot_rate_changes_time_without_adding_parallel_clocks_or_reapplying_duration() -> void:
	var template := Linear.linear()
	template.recipes.drink.nodes[1].seconds = 4.0
	template.recipes.drink.nodes[1]["slot_rate"] = {"target":"a","base":1,"max":4,"ignore_duration":true}
	var runtime := _runtime(template)
	if runtime == null: return
	runtime.runner.owner.tune["a"] = 2.0
	runtime.runner.owner.apply_effect("event","slots",SpecEffect.make("process_slots","set",2.0,"a"))
	runtime.runner.owner.apply_effect("event","speed",SpecEffect.make("speed","mul",2.0,"a"))
	runtime.runner.owner.apply_effect("event","duration",SpecEffect.make("duration","mul",3.0,"a"))
	runtime.request_production("drink")
	for tick in 400:
		_tick(runtime)
		if not runtime.runner.machines.snapshot().runs.is_empty(): break
	check_eq(runtime.runner.machines.snapshot().runs[0].duration,2.0,"four × tuning two ÷ speed two ÷ rate two")
	check_eq(runtime.runner.machines.snapshot().definitions.a.profile.slots,1,"rate semantics keep a single machine clock")

func test_bad_slot_rate_is_rejected_before_time_stock_or_actor_mutation() -> void:
	var template := Linear.linear()
	template.recipes.drink.nodes[1]["slot_rate"] = {"target":"a","base":1,"max":4}
	var runtime := _runtime(template)
	if runtime == null: return
	runtime.runner.owner.apply_effect("event","slots",SpecEffect.make("process_slots","set",0.5,"a"))
	var before: Dictionary = runtime.snapshot()
	check(not runtime.step(0.1).is_empty(),"fractional processing count is a numeric configuration error")
	check_eq(runtime.snapshot(),before,"invalid rate cannot advance a partial production tick")

func test_named_scene_ports_rebind_without_copying_coordinates_and_unknown_ports_fail_closed() -> void:
	var template := Linear.linear()
	template.places.a_in.erase("port")
	template.places.a_in.anchor = "bench"
	var owner := Actors.owner()
	owner.nav.layout.points["bench"] = Vector2(280,100)
	var runtime := Runtime.new(owner,template)
	check_eq(runtime.last_error,"","named scene anchor is resolved before shared compilation")
	if not runtime.last_error.is_empty(): return
	check_eq(runtime.runner.ports.a_in,Vector2(280,100),"actual layout supplies the coordinate")
	owner = Actors.owner()
	owner.nav.layout.points["bench"] = Vector2(320,100)
	runtime = Runtime.new(owner,template)
	check_eq(runtime.runner.ports.a_in,Vector2(320,100),"same recipe follows a new scene layout")
	check(not Runtime.new(Actors.owner(),template).last_error.is_empty(),"missing anchor cannot become origin or a straight-line fallback")
	template.places.a_in.port = Vector2(200,100)
	check(not Runtime.new(owner,template).last_error.is_empty(),"ambiguous literal and named position is rejected")

func test_manual_machine_uses_its_declared_work_port_while_materials_keep_their_own_container() -> void:
	var template := Linear.linear()
	template.places["work"] = {"port":Vector2(260,140),"capacity":0}
	template.machines.a["work_port"] = "work"
	var runtime := _runtime(template)
	if runtime == null: return
	runtime.request_production("drink")
	var working: Dictionary = {}
	for tick in 400:
		_tick(runtime)
		for run in runtime.runner.machines.snapshot().runs:
			if run.phase == "operate": working = run
		if not working.is_empty(): break
	check(not working.is_empty(),"manual operator reached real work stage")
	if working.is_empty(): return
	check_eq(runtime.runner.owner.worker_by_id(working.operator).pos,Vector2(260,140),"employee works at declared post instead of material drop point")
	check_eq(runtime.runner.inventory.quantity("a_in","raw_a"),1,"reserved input remains at its material container")
	var reopened := _runtime(template)
	if reopened == null: return
	check_eq(reopened.restore(runtime.snapshot()),"","separate work port is checked during actor restore")

func test_invalid_current_slot_rate_blocks_construction_and_restore_before_actor_adoption() -> void:
	var template := Linear.linear()
	template.recipes.drink.nodes[1]["slot_rate"] = {"target":"a","base":1,"max":4}
	var owner := Actors.owner()
	owner.apply_effect("event","bad",SpecEffect.make("process_slots","set",0.5,"a"))
	check(not Runtime.new(owner,template).last_error.is_empty(),"invalid initial rate cannot create a usable runtime")
	var runtime := _runtime(template)
	if runtime == null: return
	runtime.runner.owner.apply_effect("event","bad",SpecEffect.make("process_slots","set",0.5,"a"))
	var before: Dictionary = runtime.snapshot()
	check(not runtime.restore(before).is_empty(),"restore validates current outer numeric policy before adoption")
	check_eq(runtime.snapshot(),before,"bad current rate preserves every live actor and inventory claim")
