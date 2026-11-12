extends "res://tests/test_case.gd"
const Runtime := preload("res://game/rules/template/runtime.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")
const Production := preload("res://tests/fixtures/template_shop.gd")
const Service := preload("res://tests/fixtures/template_service.gd")
const Tea := preload("res://tests/fixtures/template_tea_production.gd")

func _terminal(template: Resource, recipe: String, destination := "pass", count := 1) -> Resource:
	if not template.places.has(destination): template.places[destination] = {"port":Vector2(500,100),"capacity":8}
	var graph: Dictionary = template.recipes[recipe]
	var output: Dictionary = graph.output
	graph.nodes.append({"id":"handoff","capability":"transfer","input":output.node,
		"place":destination,"item":output.item,"count":count,"seconds":1.2})
	graph.output = {"node":"handoff","item":output.item,"count":count}
	return template

func _runtime(template: Resource) -> RefCounted:
	var runtime := Runtime.new(Service.owner(),template)
	check_eq(runtime.last_error,"","explicit recipe transfer compiles through the public runtime")
	return runtime if runtime.last_error.is_empty() else null

func _advance(runtime: RefCounted, ticks := 500) -> void:
	for tick in ticks: check_eq(runtime.step(0.1),"","public graph transfer tick")

func _wait_claim(runtime: RefCounted, state: String) -> Dictionary:
	for tick in 1000:
		check_eq(runtime.step(0.1),"","wait for actual terminal transfer")
		for claim in runtime.runner.inventory.snapshot().claims:
			if claim.kind == "transfer" and claim.to == "pass" and claim.state == state: return claim
	check(false,"terminal transfer reaches " + state)
	return {}

func test_recipe_transfer_waits_for_actual_pickup_and_drop_without_manufacturing_another_product() -> void:
	var runtime := _runtime(_terminal(Production.definition(),"meal"))
	if runtime == null: return
	var unit: Dictionary = runtime.request_production("meal")
	var reserved := _wait_claim(runtime,"reserved")
	if reserved.is_empty(): return
	check("merge" in runtime.unit(unit.id).done,"both branches really merged before terminal pickup")
	check(not runtime.ready(unit.id),"reservation cannot complete the recipe")
	check_eq(runtime.frame().held,{},"unpicked output remains only in inventory UI")
	var held := _wait_claim(runtime,"held")
	if held.is_empty(): return
	check_eq(runtime.frame().held[held.worker].items,[{"item":"meal","count":1}],"real goods enter the employee hand")
	check(not runtime.ready(unit.id),"carried output has not reached its declared terminal")
	_advance(runtime)
	check(runtime.ready(unit.id),"recipe completes only after physical drop")
	check_eq(runtime.production_output(unit.id).place,"pass","consumer collects at declared destination")
	check_eq(runtime.runner.inventory.quantity("pass","meal",unit.id),1,"same owned product arrived")
	check_eq(runtime.runner.inventory.snapshot().created.meal,1,"transport does not manufacture a second meal")
	check_eq(runtime.runner.inventory.snapshot().consumed.get("meal",0),0,"transport does not consume the meal")
	check_eq(runtime.frame().held,{},"drop clears public held icons")
	check_eq(runtime.frame().draws,[],"terminal waiting stock does not create scene decorations")
	check_eq(runtime.runner.inventory.audit(),[],"graph transfer conserves goods")

func test_transfer_from_a_shared_source_is_owned_once_and_demand_stays_closed_after_delivery() -> void:
	var template := Production.linear()
	template.places.a_out.initial = {"drink":1}
	template.recipes.drink.nodes = [{"id":"ready","capability":"source","place":"a_out","item":"drink","seconds":0.6}]
	template.recipes.drink.output.node = "ready"
	var runtime := _runtime(_terminal(template,"drink"))
	if runtime == null: return
	var unit: Dictionary = runtime.request_production("drink")
	check_eq(runtime.source_demand(),{"a_out":{"drink":1}},"terminal movement declares one source demand")
	_advance(runtime)
	check(runtime.ready(unit.id),"shared source physically moved into owned output")
	check_eq(runtime.source_demand(),{},"completed transfer closes source demand")
	check_eq(runtime.runner.inventory.reserve_operation(0,"pass",{"drink":1},{},unit.id).error,"","consumer can consume owned output")
	var claim: Dictionary = runtime.runner.inventory.snapshot().claims.back()
	check_eq(runtime.runner.inventory.complete_operation(claim.id),"","real output consumed")
	_advance(runtime,30)
	check_eq(runtime.source_demand(),{},"eating or consuming output cannot reopen an old terminal")
	check_eq(runtime.runner.inventory.snapshot().created.drink,1,"source transfer never duplicates finite stock")

func test_multi_item_terminal_uses_atomic_bundle_admission_and_never_completes_a_partial_move() -> void:
	var template := Production.linear()
	template.recipes.drink.nodes[1].produces = {"drink":2}
	var runtime := _runtime(_terminal(template,"drink","pass",2))
	if runtime == null: return
	runtime.runner.owner.apply_effect("event","carry_limit",SpecEffect.make("carry","set",1.0))
	var unit: Dictionary = runtime.request_production("drink")
	_advance(runtime)
	check(not runtime.ready(unit.id),"capacity-one staff cannot claim a two-item graph transfer")
	check_eq(runtime.runner.inventory.quantity("a_out","drink",unit.id),2,"failed whole move leaves both goods at source")
	runtime.runner.owner.mods.remove("event","carry_limit")
	_advance(runtime)
	check(runtime.ready(unit.id),"capacity upgrade admits the whole terminal bundle")
	check_eq(runtime.runner.inventory.quantity("pass","drink",unit.id),2,"both real goods arrive")

func test_recall_of_a_held_terminal_returns_goods_and_retry_uses_a_new_claim() -> void:
	var runtime := _runtime(_terminal(Production.linear(),"drink"))
	if runtime == null: return
	var unit: Dictionary = runtime.request_production("drink")
	var held := _wait_claim(runtime,"held")
	if held.is_empty(): return
	check_eq(runtime.runner.cancel(held.worker),"","recall reuses public bundle cancellation")
	check_eq(runtime.runner.inventory.quantity("a_out","drink",unit.id),1,"recall returns actual source goods")
	check_eq(runtime.frame().held,{},"recall clears hands")
	_advance(runtime)
	check(runtime.ready(unit.id),"cancelled terminal can be claimed again")
	check_eq(runtime.runner.inventory.claim(held.id).state,"cancelled","old claim is not reused as completed proof")
	check_eq(runtime.runner.inventory.snapshot().created.drink,1,"retry cannot recreate product")

func test_terminal_restore_replays_reserved_held_and_completed_real_transfers() -> void:
	for state in ["reserved","held","dropped"]:
		var template := _terminal(Production.linear(),"drink")
		var runtime := _runtime(template)
		if runtime == null: return
		var unit: Dictionary = runtime.request_production("drink")
		if _wait_claim(runtime,state).is_empty(): return
		var reopened := _runtime(template)
		if reopened == null: return
		check_eq(reopened.restore(runtime.snapshot()),"","restore actual terminal at " + state)
		_advance(runtime)
		_advance(reopened)
		check(runtime.ready(unit.id) and reopened.ready(unit.id),"both terminals complete")
		check_eq(reopened.snapshot(),runtime.snapshot(),"all goods, claims, paths and clocks replay at " + state)

func test_forged_completion_or_reused_terminal_bundle_is_rejected_before_actor_adoption() -> void:
	var template := _terminal(Production.linear(),"drink")
	var second: Dictionary = template.recipes.drink.nodes.back().duplicate(true)
	second.id = "again"
	second.input = "handoff"
	second.place = "pass2"
	template.places["pass2"] = {"port":Vector2(600,100),"capacity":8}
	template.recipes.drink.nodes.append(second)
	template.recipes.drink.output.node = "again"
	var runtime := _runtime(template)
	if runtime == null: return
	runtime.request_production("drink")
	if _wait_claim(runtime,"held").is_empty(): return
	for patch in ["complete","duplicate","dependencies"]:
		var broken: Dictionary = runtime.snapshot()
		match patch:
			"complete": broken.units[0].done.append("handoff")
			"duplicate": broken.units[0].running.again = broken.units[0].running.handoff
			"dependencies": broken.units[0].done.erase("drink")
		var before: Dictionary = runtime.snapshot()
		check(not runtime.restore(broken).is_empty(),"forged graph transfer rejected: " + patch)
		check_eq(runtime.snapshot(),before,"rejected terminal state preserves actors and ledger")

func test_transfer_authoring_rejects_bad_bindings_same_container_and_private_fields() -> void:
	for patch in ["producer","item","same","count","callback"]:
		var template := _terminal(Production.linear(),"drink")
		var node: Dictionary = template.recipes.drink.nodes.back()
		match patch:
			"producer": node.input = "missing"
			"item": node.item = "missing"
			"same": node.place = "a_out"
			"count": node.count = 1.5
			"callback": node.callback = "private"
		check(not Compiler.compile(template).errors.is_empty(),"bad terminal is a precise authoring error: " + patch)

func test_service_in_all_three_combinations_waits_for_the_terminal_and_consumes_one_real_product() -> void:
	for delivery in ["counter","self_pickup","table"]:
		var template := _terminal(Service.definition(delivery),"drink","finish")
		var runtime := _runtime(template)
		if runtime == null: return
		check_eq(runtime.arrive([{ "dish":"lemonade","qty":1}]).error,"","real guest enters " + delivery)
		_advance(runtime,1500)
		check_eq(runtime.runner.owner.sold,1,"one sale after real terminal and fulfillment: " + delivery)
		check_eq(runtime.runner.inventory.snapshot().created.drink,1,"service cannot bypass or duplicate terminal product")
		check_eq(runtime.runner.inventory.audit(),[],"service/terminal inventories remain conserved")

func test_actual_milk_tea_moves_to_the_authored_pass_after_automatic_mixing() -> void:
	var template := Tea.definition()
	_terminal(template,"milk_tea")
	template.places.pass.port = Tea.TEA.layout.points.seal
	var runtime := Runtime.new(Tea.owner(),template)
	check_eq(runtime.last_error,"","real tea production and terminal share the runtime")
	if not runtime.last_error.is_empty(): return
	var unit: Dictionary = runtime.request_production("milk_tea")
	_advance(runtime,1800)
	check(runtime.ready(unit.id),"leaf, shared pot, actual tea transport, integrated milk, mixing and terminal all complete")
	check_eq(runtime.production_output(unit.id).place,"pass","milk tea ends at authored pickup coordinates")
	check_eq(runtime.runner.inventory.quantity("pass","plain_milk_tea",unit.id),1,"same drink reaches the real pass")
	check_eq(runtime.runner.inventory.snapshot().created.plain_milk_tea,1,"pass is a move, not a second production")

func test_internal_transfer_cannot_cover_a_separate_source_output_demand() -> void:
	var template := Production.linear()
	template.places.a_out.initial = {"drink":2}
	template.recipes.drink.nodes = [{"id":"ready","capability":"source","place":"a_out","item":"drink","seconds":0.6}]
	template.recipes.drink.output.node = "ready"
	_terminal(template,"drink")
	template.recipes.drink.output.node = "ready"
	var runtime := _runtime(template)
	if runtime == null: return
	runtime.request_production("drink")
	_advance(runtime)
	check_eq(runtime.source_demand(),{"a_out":{"drink":1}},"internal graph transport does not stand in for final customer collection")

func test_transfer_drop_timing_uses_shared_modifiers_once_and_pause_keeps_real_progress() -> void:
	var template := _terminal(Production.linear(),"drink")
	var node: Dictionary = template.recipes.drink.nodes.back()
	node.seconds = 2.0
	node.timing_target = "pass"
	var runtime := _runtime(template)
	if runtime == null: return
	runtime.runner.owner.tune["pass"] = 2.0
	runtime.runner.owner.apply_effect("event","faster_drop",SpecEffect.make("speed","mul",2.0,"pass"))
	runtime.runner.owner.apply_effect("event","faster_hands",SpecEffect.make("work","mul",2.0))
	runtime.request_production("drink")
	var reserved := _wait_claim(runtime,"reserved")
	if reserved.is_empty(): return
	check_eq(runtime.runner.tasks[reserved.worker].drop_seconds,1.0,"two seconds × tuning two ÷ target speed two ÷ staff speed two")
	var before: Dictionary = runtime.snapshot()
	check_eq(runtime.step(100.0,true),"","pause the physical handoff")
	check_eq(runtime.snapshot(),before,"paused transfer keeps path, time and reservation")

func test_public_post_permissions_block_terminal_transport_without_blocking_production() -> void:
	var template := _terminal(Production.linear(),"drink")
	template.dispatch = {"roles":{"staff":{"operate":["*"],"transfer_from":["*"],"transfer_to":["a_in"]}}}
	var runtime := _runtime(template)
	if runtime == null: return
	var unit: Dictionary = runtime.request_production("drink")
	_advance(runtime)
	check("drink" in runtime.unit(unit.id).done,"authorized staff finished actual production")
	check(not runtime.ready(unit.id),"unauthorized destination cannot be claimed by graph transport")
	check_eq(runtime.runner.inventory.quantity("a_out","drink",unit.id),1,"blocked terminal retains actual product")
	check(not runtime.runner.transfer_bundle(runtime.runner.owner.workers[0].id,[{"from":"a_out","to":"pass","item":"drink","count":1,"owner":unit.id,"allocate_owner":unit.id}],0.2).is_empty(),"direct bundle request cannot bypass the same policy")

func test_a_transfer_can_feed_another_common_process_without_a_special_finishing_loop() -> void:
	var template := _terminal(Production.linear(),"drink")
	template.places["packed"] = {"port":Vector2(500,100)}
	template.machines["pack"] = {"input":"pass","output":"packed","profile":{"manual":true}}
	template.recipes.drink.nodes.append({"id":"pack","capability":"process","machine":"pack","seconds":2.0,
		"consumes":{"drink":1},"produces":{"packed_drink":1},"inputs":{"drink":"handoff"}})
	template.recipes.drink.output = {"node":"pack","item":"packed_drink","count":1}
	var runtime := _runtime(template)
	if runtime == null: return
	var unit: Dictionary = runtime.request_production("drink")
	_advance(runtime)
	check(runtime.ready(unit.id),"normal processing starts after the transfer really commits")
	check_eq(runtime.runner.inventory.quantity("packed","packed_drink",unit.id),1,"explicit finish transforms the owned product")
	check_eq(runtime.runner.inventory.snapshot().consumed.drink,1,"finishing consumes exactly the delivered input")
