extends "res://tests/test_case.gd"
const Fixture := preload("res://tests/fixtures/template_shop.gd")
const Actors := preload("res://tests/fixtures/template_service.gd")
const Runtime := preload("res://game/rules/template/runtime.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")

func _template() -> Resource:
	var template := Fixture.linear()
	check(template.get("transports")!=null,"automatic transports need a common state and inventory lifecycle")
	if template.get("transports")==null: return null
	template.places.a_out.initial = {"drink":2}
	template.places["pass"] = {"port":Vector2(450,100),"capacity":2}
	template.recipes.drink = {"nodes":[{"id":"stock","capability":"source","place":"a_out","item":"drink","seconds":0.6},
		{"id":"pass","capability":"transfer","input":"stock","place":"pass","item":"drink","count":1,"seconds":0.6,"transport":"lane"}],"output":{"node":"pass","item":"drink","count":1}}
	template.transports = {"lane":{"from":"a_out","to":"pass","connection":"lane","seconds":3.0,"interval":1.5,"capacity":1}}
	template.presentation = {"conveyors":{"lane":{"path":["Path/0","Path/1"],"host":"","height":52.0}}}
	return template

func _runtime(purchased := true, staff := false) -> RefCounted:
	var template := _template()
	if template==null: return null
	var owner := Actors.owner()
	var connection := SpecConnection.new()
	connection.id = "lane"; connection.from = "a_out"; connection.to = "pass"
	owner.shop.connections.append(connection)
	if purchased: owner.belts.lane = true
	if not staff:
		for worker in owner.workers: worker.deployed = false
	var runtime := Runtime.new(owner,template)
	check_eq(runtime.last_error,"","explicit route composes public runtime")
	return runtime if runtime.last_error.is_empty() else null

func test_purchased_route_moves_real_owned_stock_without_a_worker_or_fake_sprite() -> void:
	var runtime := _runtime()
	if runtime==null: return
	var unit: int = runtime.request_production("drink").id
	runtime.step(0.1)
	check_eq(runtime.frame().transports.size(),1,"one real flight")
	check_eq(runtime.runner.inventory.quantity("a_out","drink"),1,"actual pickup removes source stock")
	check_eq(runtime.runner.inventory.quantity("pass","drink"),0,"arrival cannot be committed early")
	check_eq(runtime.runner.tasks,{},"no employee action is invented")
	var view := ShopView.new(runtime.runner.owner)
	check_eq(view.bind_runtime(runtime,[],{"ports":{"Path/0":Vector2(200,100),"Path/1":Vector2(500,100)},"hosts":[]}),"","real transport display")
	runtime.step(1.5)
	var draws: Array = view.render_snapshot().draws
	check_eq(draws.size(),1,"flight alone authorizes one visible item")
	check_eq(draws[0].pos,Vector2(350,100),"position follows the authoritative half-complete clock")
	runtime.step(1.5)
	check(runtime.ready(unit),"actual drop completes the graph node")
	check_eq(runtime.frame().transports,[],"arrival removes in-flight display state")
	check_eq(runtime.runner.inventory.quantity("pass","drink",unit),1,"original owner survives physical arrival")
	check_eq(runtime.runner.inventory.audit(),[],"same conservation ledger")

func test_unpurchased_route_uses_existing_employee_transfer_and_owned_route_respects_interval() -> void:
	var runtime := _runtime(false,true)
	if runtime==null: return
	runtime.request_production("drink"); runtime.step(0.1)
	check(not runtime.runner.tasks.is_empty(),"unbought connection retains physical worker fallback")
	check_eq(runtime.frame().transports,[],"no unpurchased conveyor glyph")
	runtime = _runtime()
	runtime.request_production("drink"); runtime.request_production("drink")
	runtime.step(0.1)
	check_eq(runtime.frame().transports.size(),1,"one launch per interval")
	runtime.step(1.0)
	check_eq(runtime.frame().transports.size(),1,"cooldown holds the second unit")
	runtime.step(0.5)
	check_eq(runtime.frame().transports.size(),2,"second real flight after interval")

func test_pause_cancel_and_restore_reuse_stock_claims_and_frozen_remaining_time() -> void:
	var runtime := _runtime()
	if runtime==null: return
	runtime.request_production("drink"); runtime.step(0.1); runtime.step(1.0)
	var saved: Dictionary = runtime.snapshot()
	check_eq(runtime.step(5.0,true),"","pause transport")
	check_eq(runtime.snapshot(),saved,"pause freezes both route clock and stock")
	var resumed := _runtime()
	check_eq(resumed.restore(saved),"","adopt physical carrier and flight time")
	for tick in 40:
		runtime.step(0.1); resumed.step(0.1)
	check_eq(resumed.snapshot(),runtime.snapshot(),"same exactly-once drop after restore")
	runtime = _runtime()
	runtime.request_production("drink"); runtime.step(0.1)
	var bundle: int = runtime.frame().transports[0].bundle
	check_eq(runtime.cancel_transport(bundle),"","public cancellation returns the carried source")
	check_eq(runtime.cancel_transport(bundle),"","cancellation is idempotent")
	check_eq(runtime.runner.inventory.quantity("a_out","drink"),2,"all real goods return once")
	check_eq(runtime.frame().transports,[],"cancel clears physical display")
	check_eq(runtime.restore(runtime.snapshot()),"","cancelled graph can be resumed before retry")

func test_forged_flight_missing_owner_duplicate_bundle_or_invalid_time_is_rejected_atomically() -> void:
	var runtime := _runtime()
	if runtime==null: return
	runtime.request_production("drink"); runtime.step(0.1)
	for kind in ["missing","duplicate","time","node"]:
		var bad: Dictionary = runtime.snapshot()
		match kind:
			"missing": bad.transports.flights = []
			"duplicate": bad.transports.flights.append(bad.transports.flights[0].duplicate(true))
			"time": bad.transports.flights[0].left = -1.0
			"node": bad.units[0].running.erase("pass")
		var before: Dictionary = runtime.snapshot()
		check(not runtime.restore(bad).is_empty(),"reject malformed carrier linkage: "+kind)
		check_eq(runtime.snapshot(),before,"failed restore preserves all live state")

func test_invalid_routes_and_empty_disabled_definition_cannot_change_defaults() -> void:
	var template := _template()
	if template==null: return
	for field in ["from","capacity","callback"]:
		var bad := template.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
		if field=="from": bad.transports.lane.from = "missing"
		elif field=="capacity": bad.transports.lane.capacity = 0
		else: bad.transports.lane.callback = "custom"
		check(not Compiler.compile(bad).errors.is_empty(),"invalid route definition fails: "+field)
	var plain := Fixture.linear()
	var before: Dictionary = Compiler.compile(plain).definition
	plain.transports = {}
	check_eq(Compiler.compile(plain).definition,before,"unused transport preserves compiled identity")

func test_cancelled_carrier_history_remains_restorable_after_the_graph_retries() -> void:
	var runtime := _runtime()
	if runtime==null: return
	runtime.request_production("drink"); runtime.step(0.1)
	var bundle: int = runtime.frame().transports[0].bundle
	runtime.cancel_transport(bundle)
	for tick in 40: runtime.step(0.1)
	check_eq(runtime.restore(runtime.snapshot()),"","cancelled historical claim need not remain the node's current bundle")

func test_removed_connection_context_rejects_restore_and_step_before_any_state_change() -> void:
	var runtime := _runtime()
	if runtime==null: return
	runtime.request_production("drink"); runtime.step(0.1)
	var before: Dictionary = runtime.snapshot()
	runtime.runner.owner.shop.connections.clear()
	check(not runtime.restore(before).is_empty(),"missing authored route context cannot adopt a flight")
	check_eq(runtime.snapshot(),before,"failed restore keeps the carrier and clock")
	check(not runtime.step(0.1).is_empty(),"missing context cannot advance clocks or drop food")
	check_eq(runtime.snapshot(),before,"failed step is atomic")

func test_same_transport_capability_composes_with_both_linear_and_two_input_merge_production() -> void:
	for recipe in ["drink","meal"]:
		var template := Fixture.linear() if recipe=="drink" else Fixture.definition()
		if template.get("transports")==null: check(false,"shared transports exist"); return
		var graph: Dictionary = template.recipes[recipe]
		var output: Dictionary = graph.output.duplicate(true)
		var producer: Dictionary = graph.nodes.filter(func(node: Dictionary) -> bool: return node.id==output.node)[0]
		var source: String = template.machines[producer.machine].output
		template.places["pass"] = {"port":Vector2(500,100),"capacity":4}
		graph.nodes.append({"id":"route","capability":"transfer","input":output.node,"place":"pass","item":output.item,"count":1,"seconds":0.6,"transport":"lane"})
		graph.output.node = "route"
		template.transports = {"lane":{"from":source,"to":"pass","connection":"lane","seconds":3.0,"interval":1.5,"capacity":1}}
		var owner := Actors.owner()
		var connection := SpecConnection.new()
		connection.id = "lane"; connection.from = source; connection.to = "pass"
		owner.shop.connections.append(connection); owner.belts.lane = true
		var runtime := Runtime.new(owner,template)
		check_eq(runtime.last_error,"","same transport after "+recipe)
		var unit: int = runtime.request_production(recipe).id
		var saw_flight := false
		for tick in 1000:
			check_eq(runtime.step(0.1),"","real graph and physical transport")
			if not runtime.frame().transports.is_empty(): saw_flight = true
			if runtime.ready(unit): break
		check(saw_flight and runtime.ready(unit),"transport is actually reused after "+recipe)
		check_eq(runtime.runner.inventory.quantity("pass",output.item,unit),1,"same owned output")
