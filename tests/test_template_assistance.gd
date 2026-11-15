extends "res://tests/test_case.gd"
const Fixture := preload("res://tests/fixtures/template_service.gd")
const Runtime := preload("res://game/rules/template/runtime.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")

func _template() -> Resource:
	var template := Fixture.definition("table","employee")
	template.recipes["native"] = {"nodes":[{"id":"own","capability":"process","machine":"b","consumes":{},"produces":{"own":1},"inputs":{},"seconds":1.0}],"output":{"node":"own","item":"own","count":1}}
	template.dispatch = {"posts":{"counter":{"interact":["front"],"operate":["b"],"transfer_from":["b_out"],"transfer_to":["pass"]}},
		"assistance":{"posts":{"counter":{"transfer_from":["pantry","a_out"],"transfer_to":["a_in","pass"],"wait_for_admission":true}}}}
	return template

func _runtime() -> RefCounted:
	var owner := Fixture.owner()
	owner.workers[0].post = "counter"
	var runtime := Runtime.new(owner,_template())
	check_eq(runtime.last_error,"","compile explicit fallback transport policy")
	return runtime if runtime.last_error.is_empty() else null

func test_idle_front_can_help_transport_but_cannot_operate_kitchen() -> void:
	var runtime := _runtime()
	if runtime==null: return
	var worker: Dictionary = runtime.runner.owner.workers[0]
	check_eq(runtime.runner.transfer(worker.id,"pantry","a_in","raw_a",1,0.6),"","idle front uses ordinary inventory transfer")
	check_eq(worker.carry_count,0,"reservation never creates a carried icon")
	runtime.runner.cancel(worker.id)
	var run: Dictionary = runtime.runner.machines.start("a",{}, {"done":1},1.0)
	check(not runtime.runner.operate(worker.id,run.id,"a_in").is_empty(),"transport permission cannot grant kitchen processing")

func test_native_work_blocks_helper_candidates_and_direct_plain_or_bundle_requests() -> void:
	var runtime := _runtime()
	if runtime==null: return
	var worker: Dictionary = runtime.runner.owner.workers[0]
	runtime.request_production("drink")
	var unit_id: int = runtime.request_production("native").id
	runtime._start_ready_nodes()
	var run: Dictionary = runtime.runner.machines.run(runtime.unit(unit_id).running.own)
	var before: Dictionary = runtime.snapshot()
	var candidates: Array = runtime.candidates_for(worker.id)
	check(not candidates.is_empty(),"front has native machine work")
	for candidate in candidates: check_eq(candidate.kind,"operate","assistance is a fallback, regardless of score")
	check(not runtime.runner.transfer(worker.id,"pantry","a_in","raw_a",1,0.6).is_empty(),"direct transfer cannot skip native work")
	check(not runtime.runner.transfer_bundle(worker.id,[{"from":"pantry","to":"a_in","item":"raw_a","count":1}],0.6).is_empty(),"bundle shares priority authorization")
	check_eq(runtime.snapshot(),before,"denied helper requests leave inventory and actor unchanged")
	check_eq(runtime.runner.operate(worker.id,run.id,"b_in"),"","native operation remains available")

func test_approaching_guest_keeps_front_at_counter_before_admission_candidate_exists() -> void:
	var runtime := _runtime()
	if runtime==null: return
	var worker: Dictionary = runtime.runner.owner.workers[0]
	runtime.request_production("drink")
	runtime.arrive(Fixture.request())
	check(not runtime.service.customers.ready(1,"queue:0"),"guest still walking from entry")
	check_eq(runtime.candidates_for(worker.id),[],"front stays ready for approaching guest")
	check(not runtime.runner.transfer(worker.id,"pantry","a_in","raw_a",1,0.6).is_empty(),"direct request cannot abandon approaching guest")

func test_full_dining_room_does_not_hold_front_for_unadmittable_guest() -> void:
	var runtime := _runtime()
	if runtime==null: return
	var worker: Dictionary = runtime.runner.owner.workers[0]
	runtime.arrive(Fixture.request())
	for tick in 300:
		check_eq(runtime.step(0.1),"","admit first guest into actual dining seat")
		if runtime.service.orders.guest(1).order>0: break
	check_eq(runtime.service.orders.guest(1).seat,"seat:dine/0","existing guest owns only seat")
	runtime.runner.cancel(worker.id)
	runtime.arrive(Fixture.request())
	check_eq(runtime.runner.transfer(worker.id,"pantry","a_in","raw_a",1,0.6),"","no available seat means front may help")

func test_already_admitted_customer_retaining_queue_slot_does_not_hold_front_for_admission() -> void:
	var template := _template()
	template.service.delivery = "counter"
	template.service.handoff_port = "pass"
	template.service.seats = {}
	template.service.orders.queue_release = "after_delivery"
	var owner := Fixture.owner()
	owner.workers[0].post = "counter"
	var runtime := Runtime.new(owner,template)
	check_eq(runtime.last_error,"","counter may retain queue slot until delivery")
	if not runtime.last_error.is_empty(): return
	runtime.arrive(Fixture.request())
	for tick in 300:
		check_eq(runtime.step(0.1),"","complete actual admission")
		if runtime.service.orders.guest(1).order>0: break
	check_eq(runtime.service.orders.guest(1).state,"waiting","guest is waiting for food, not admission")
	check_eq(runtime.service.orders.queue(),[1],"customer deliberately retains its queue slot")
	if not runtime.runner.idle(owner.workers[0].id):
		check_eq(runtime.runner.tasks[owner.workers[0].id].kind,"transfer","scheduler may immediately start helping after admission")
		check_eq(runtime.runner.cancel(owner.workers[0].id),"","release that real helper before testing another direct request")
	check_eq(runtime.runner.transfer(owner.workers[0].id,"pantry","a_in","raw_a",1,0.6),"","food waiting cannot masquerade as pending admission")

func test_native_machine_already_claimed_by_colleague_does_not_block_idle_help() -> void:
	var runtime := _runtime()
	if runtime==null: return
	var worker: Dictionary = runtime.runner.owner.workers[0]
	var colleague: Dictionary = runtime.runner.owner.workers[1]
	colleague.post = "counter"
	var id: int = runtime.request_production("native").id
	runtime._start_ready_nodes()
	var run_id: int = runtime.unit(id).running.own
	check_eq(runtime.runner.operate(colleague.id,run_id,"b_in"),"","colleague owns the pending operation while walking there")
	check_eq(runtime.runner.transfer(worker.id,"pantry","a_in","raw_a",1,0.6),"","already claimed native work is not a competing task")

func test_unclaimable_native_bundle_does_not_block_feasible_help() -> void:
	var template := _template()
	template.places.b_out.initial = {"own":2}
	template.recipes.native = {"nodes":[{"id":"stock","capability":"source","place":"b_out","item":"own","seconds":0.6},
		{"id":"pass","capability":"transfer","input":"stock","place":"pass","item":"own","count":2,"seconds":0.6}],"output":{"node":"pass","item":"own","count":2}}
	var owner := Fixture.owner()
	owner.workers[0].post = "counter"
	owner.apply_effect("event","limit",SpecEffect.make("carry","set",1.0))
	var runtime := Runtime.new(owner,template)
	check_eq(runtime.last_error,"","whole native move exceeds actual carry capacity")
	if not runtime.last_error.is_empty(): return
	runtime.request_production("native")
	check_eq(runtime.runner.transfer(owner.workers[0].id,"pantry","a_in","raw_a",1,0.6),"","infeasible native move cannot strand a useful helper")

func test_help_in_progress_finishes_when_native_work_arrives_and_restores_without_second_ledger() -> void:
	var runtime := _runtime()
	if runtime==null: return
	var worker: Dictionary = runtime.runner.owner.workers[0]
	check_eq(runtime.runner.transfer(worker.id,"pantry","a_in","raw_a",1,0.6),"","start while idle")
	runtime.arrive(Fixture.request())
	var saved: Dictionary = runtime.snapshot()
	check_eq(runtime.restore(saved),"","later arrival does not invalidate already approved help")
	for tick in 200:
		check_eq(runtime.runner.step(0.1),"","complete accepted transport through common actions")
		if runtime.runner.idle(worker.id): break
	check_eq(runtime.runner.inventory.quantity("a_in","raw_a"),1,"transport commits once despite later native demand")
	check_eq(runtime.runner.inventory.audit(),[],"single inventory ledger remains consistent")

func test_reassignment_revokes_help_and_restore_cannot_regrant_removed_permissions() -> void:
	var runtime := _runtime()
	if runtime==null: return
	var worker: Dictionary = runtime.runner.owner.workers[0]
	runtime.runner.transfer(worker.id,"pantry","a_in","raw_a",1,0.6)
	var saved: Dictionary = runtime.snapshot()
	worker.post = "missing"
	check(not runtime.restore(saved).is_empty(),"new post cannot restore old help privilege")
	check_eq(runtime.runner.step(0.1),"","revoke before movement or pickup")
	check(runtime.runner.idle(worker.id),"removed helper has no action")
	check_eq(runtime.runner.inventory.quantity("a_in","raw_a"),0,"no revoked delivery")

func test_unknown_helper_profiles_permissions_and_guard_types_fail_compilation() -> void:
	for assistance in [{"roles":{"missing":{"transfer_from":["pantry"],"transfer_to":["a_in"]}}},
		{"posts":{"counter":{"operate":["a"]}}}, {"posts":{"counter":{"transfer_from":["unknown"]}}},
		{"posts":{"counter":{"wait_for_admission":"yes"}}}, {"callback":"custom"}]:
		var template := _template()
		template.dispatch.assistance = assistance
		check(not Compiler.compile(template).errors.is_empty(),"invalid assistance must fail explicitly")

func test_empty_assistance_preserves_existing_compiled_definition() -> void:
	var template := _template()
	template.dispatch.erase("assistance")
	var before: Dictionary = Compiler.compile(template).definition
	template.dispatch.assistance = {}
	check_eq(Compiler.compile(template).definition,before,"unconfigured assistance leaves default behavior and identity unchanged")
