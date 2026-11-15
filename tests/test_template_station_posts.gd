extends "res://tests/test_case.gd"
const Runtime := preload("res://game/rules/template/runtime.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")
const Production := preload("res://tests/fixtures/template_shop.gd")
const Actors := preload("res://tests/fixtures/template_service.gd")

func _definition() -> Resource:
	var template := Production.linear()
	template.dispatch = {"roles":{"staff":{"operate":["a"],"transfer_from":["pantry","a_out"],"transfer_to":["a_in","b_in"]}},
		"posts":{"boil":{"operate":["a"],"transfer_from":["pantry"],"transfer_to":["a_in"]}},
		"station_posts":{"a":{"post":"boil","feed":true}}}
	return template

func _runtime(posted := true) -> RefCounted:
	var owner := Actors.owner()
	if posted: owner.workers[1].post = "boil"
	var runtime := Runtime.new(owner,_definition())
	check_eq(runtime.last_error,"","station ownership is an explicit shared dispatch policy")
	return runtime if runtime.last_error.is_empty() else null

func test_posted_operator_owns_machine_across_completed_batches_and_direct_requests_cannot_bypass() -> void:
	var runtime := _runtime()
	if runtime==null: return
	var floating: int = runtime.runner.owner.workers[0].id
	var seated: int = runtime.runner.owner.workers[1].id
	for batch in 2:
		var run: Dictionary = runtime.runner.machines.start("a",{},{"done":1},0.5)
		check_eq(run.error,"","shared machine batch starts")
		var before: Dictionary = runtime.runner.inventory.snapshot()
		check(not runtime.runner.operate(floating,run.id,"a_in").is_empty(),"floating employee cannot claim posted machine")
		check_eq(runtime.runner.inventory.snapshot(),before,"denied operation changes no physical goods")
		check_eq(runtime.runner.operate(seated,run.id,"a_in"),"","posted employee executes ordinary public operation")
		for tick in 100:
			check_eq(runtime.step(0.1),"","complete actual posted batch")
			if runtime.runner.machines.run(run.id).phase=="completed": break
		check_eq(runtime.runner.machines.run(run.id).phase,"completed","same holder serves next batch without a shop-specific loop")
	check_eq(runtime.runner.inventory.quantity("a_out","done"),2,"two physical batches conserve output")

func test_optional_exclusive_feed_blocks_plain_and_bundle_transfer_but_keeps_other_logistics() -> void:
	var runtime := _runtime()
	if runtime==null: return
	var floating: int = runtime.runner.owner.workers[0].id
	var seated: int = runtime.runner.owner.workers[1].id
	var before: Dictionary = runtime.runner.inventory.snapshot()
	check(not runtime.runner.transfer(floating,"pantry","a_in","raw_a",1,0.6).is_empty(),"posted feed cannot be taken by a floating plain transfer")
	check(not runtime.runner.transfer_bundle(floating,[{"from":"pantry","to":"a_in","item":"raw_a","count":1}],0.6).is_empty(),"bundle does not bypass the same feed permission")
	check_eq(runtime.runner.inventory.snapshot(),before,"denied feed leaves no partial claims")
	check_eq(runtime.runner.transfer(seated,"pantry","a_in","raw_a",1,0.6),"","posted pot operator can fetch its own materials")
	check(runtime.runner.dispatcher.allowed(runtime.runner.owner.workers[0],{"kind":"transfer","from":"pantry","to":"b_in"}),"unrelated permitted logistics remain shared")

func test_machine_only_post_reserves_work_but_allows_floating_helpers_to_supply_material() -> void:
	var template := _definition()
	template.dispatch.station_posts.a.feed = false
	var owner := Actors.owner()
	owner.workers[1].post = "boil"
	var runtime := Runtime.new(owner,template)
	check_eq(runtime.last_error,"","work-only exclusivity can compose with shared feeding")
	if not runtime.last_error.is_empty(): return
	check(runtime.runner.dispatcher.allowed(owner.workers[0],{"kind":"transfer","from":"pantry","to":"a_in"}),"helpers still carry material to the occupied workbench")
	check(not runtime.runner.dispatcher.allowed(owner.workers[0],{"kind":"operate","machine":"a"}),"helpers do not take over actual processing")
	check(runtime.runner.dispatcher.allowed(owner.workers[1],{"kind":"operate","machine":"a"}),"station owner retains operation")

func test_post_handover_cancels_former_operator_before_advance_and_floating_work_returns_when_unoccupied() -> void:
	var runtime := _runtime()
	if runtime==null: return
	var first: Dictionary = runtime.runner.owner.workers[0]
	var previous: Dictionary = runtime.runner.owner.workers[1]
	var run: Dictionary = runtime.runner.machines.start("a",{},{"done":1},5.0)
	check_eq(runtime.runner.operate(previous.id,run.id,"a_in"),"","start actual operation at old post")
	for tick in 100:
		check_eq(runtime.step(0.1),"","reach working phase")
		if runtime.runner.machines.run(run.id).phase=="operate": break
	check_eq(runtime.runner.machines.run(run.id).phase,"operate","handover exercises an active manual clock")
	if runtime.runner.machines.run(run.id).phase!="operate": return
	previous.post = ""
	first.post = "boil"
	check_eq(runtime.step(0.1),"","new post facts revoke old worker through normal cancellation")
	check(runtime.runner.idle(previous.id),"old employee no longer operates the newly occupied station")
	check(not runtime.runner.dispatcher.allowed(previous,{"kind":"operate","machine":"a"}),"new post holder remains exclusive")
	first.post = ""
	check(runtime.runner.dispatcher.allowed(previous,{"kind":"operate","machine":"a"}),"unoccupied station returns to permitted floating employees")

func test_invalid_bindings_unknown_layout_post_and_duplicate_occupants_fail_before_advancing() -> void:
	for binding in [{"missing":{"post":"boil","feed":false}},{"a":{"post":"missing","feed":false}},{"a":{"post":"boil","feed":"yes"}},{"a":{"post":"boil","feed":false,"callback":"work"}}]:
		var template := _definition()
		template.dispatch.station_posts = binding
		check(not Compiler.compile(template).errors.is_empty(),"invalid machine/post binding rejected")
	var template := _definition()
	template.dispatch.posts["unknown"] = {"operate":["a"]}
	template.dispatch.station_posts.a.post = "unknown"
	check(not Runtime.new(Actors.owner(),template).last_error.is_empty(),"a declared permission row still needs a real post anchor")
	var runtime := _runtime()
	if runtime==null: return
	runtime.runner.owner.workers[0].post = "boil"
	var before: Dictionary = runtime.snapshot()
	check(not runtime.step(0.1).is_empty(),"duplicate physical post occupants are invalid context")
	check_eq(runtime.snapshot(),before,"bad outer ownership cannot partially advance actions or clocks")

func test_absent_binding_preserves_compiled_identity_and_no_second_post_lease_snapshot() -> void:
	var template := _definition()
	template.dispatch.erase("station_posts")
	var before: Dictionary = Compiler.compile(template).definition
	template.dispatch.station_posts = {}
	check_eq(Compiler.compile(template).definition,before,"empty capability adds no compiled policy fields")
	var runtime := _runtime()
	if runtime==null: return
	check(not runtime.runner.dispatcher.snapshot().has("station_posts"),"ownership derives from deployed staff, not another lease ledger")
