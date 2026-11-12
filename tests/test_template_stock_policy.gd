extends "res://tests/test_case.gd"
const Schema := preload("res://content/rules/spec_shop_template.gd")
const Runtime := preload("res://game/rules/template/runtime.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")
const Actors := preload("res://tests/fixtures/template_service.gd")

func _definition(base := 0, per_waiting := 1, low := 0) -> Resource:
	var template := Schema.new()
	template.places = {"stock_in":{"port":Vector2(300,100)}, "stock":{"port":Vector2(300,100),"capacity":8},
		"sink":{"port":Vector2(500,100),"capacity":16}, "work_in":{"port":Vector2(600,100)}, "work_out":{"port":Vector2(600,100)}}
	template.machines = {"pot":{"input":"stock_in","output":"stock","profile":{}},
		"work":{"input":"work_in","output":"work_out","profile":{"manual":true}}}
	var source := {"id":"stock", "capability":"source", "place":"stock", "item":"tea", "seconds":0.2}
	template.recipes = {"cup":{"nodes":[source], "output":{"node":"stock","item":"tea","count":1}},
		"drink":{"nodes":[source.duplicate(true), {"id":"mix","capability":"process","machine":"work",
			"consumes":{"tea":2},"produces":{"drink":1},"inputs":{"tea":"stock"},"seconds":1.0}],
			"output":{"node":"mix","item":"drink","count":1}}}
	template.restocks = {"stock":{"machine":"pot","produces":{"tea":2},"seconds":0.5,"stock_limit":8,
		"policy":{"mode":"demand","base":base,"per_waiting":per_waiting,"low":low}}}
	return template

func _runtime(template: Resource) -> RefCounted:
	var owner := Actors.owner()
	owner.workers[1].deployed = false
	var runtime := Runtime.new(owner,template)
	check_eq(runtime.last_error,"","valid public stock policy")
	return runtime if runtime.last_error.is_empty() else null

func _advance(runtime: RefCounted, ticks := 100) -> void:
	for tick in ticks: check_eq(runtime.step(0.1),"","shared stock runtime step")

func _demand(runtime: RefCounted) -> Dictionary:
	check(runtime.has_method("source_demand"),"public runtime derives source demand from real production and claims")
	return runtime.call("source_demand") if runtime.has_method("source_demand") else {}

func _withdraw(runtime: RefCounted, count: int, unit := -1) -> void:
	var worker: Dictionary = runtime.runner.owner.workers[0]
	check_eq(runtime.runner.transfer(worker.id,"stock","sink","tea",count,0.2,-1,unit),"","real stock withdrawal")
	for tick in 300:
		check_eq(runtime.step(0.1),"","physical stock pickup/drop")
		if runtime.runner.idle(worker.id): return
	check(false,"withdrawal completes through the shared actor actions")

func test_default_fill_policy_is_unchanged_and_explicit_base_stops_before_capacity() -> void:
	for mode in ["fill","base"]:
		var template := _definition(3)
		if mode == "fill": template.restocks.stock.erase("policy")
		var runtime := _runtime(template)
		if runtime == null: return
		_advance(runtime)
		check_eq(runtime.runner.inventory.quantity("stock","tea"),8 if mode == "fill" else 4,"whole batches obey the selected target")
		check_eq(runtime.runner.machines.snapshot().runs.size(),4 if mode == "fill" else 2,"base stock does not keep filling the physical container")
		check_eq(runtime.frame().draws,[],"stock policy cannot create loose world icons")

func test_demand_only_stock_waits_for_real_requests_and_pause_cannot_start_or_complete_a_batch() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	_advance(runtime)
	check_eq(runtime.runner.machines.snapshot().runs,[],"zero demand and zero base means no speculative batch")
	for index in 3: runtime.request_production("cup")
	var before: Dictionary = runtime.snapshot()
	check_eq(_demand(runtime),{"stock":{"tea":3}},"three real requested units need three source servings")
	check_eq(runtime.snapshot(),before,"demand is a detached read, not another mutable ledger")
	check_eq(runtime.step(100.0,true),"","pause")
	check_eq(runtime.snapshot(),before,"pause cannot even start a demanded batch")
	_advance(runtime)
	check_eq(runtime.runner.inventory.quantity("stock","tea"),4,"three requests require two whole two-serving batches")
	check_eq(runtime.runner.machines.snapshot().runs.size(),2,"no extra fill-to-capacity batch")

func test_source_output_delivery_proofs_prevent_restocking_already_fulfilled_units() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	var units: Array = []
	for index in 3: units.append(runtime.request_production("cup").id)
	_advance(runtime)
	for unit in units: _withdraw(runtime,1,unit)
	_advance(runtime)
	check_eq(_demand(runtime),{},"dropped claims remain proof after source stock is gone")
	check_eq(runtime.runner.inventory.quantity("stock","tea"),1,"only the unavoidable extra serving remains shared")
	check_eq(runtime.runner.inventory.quantity("sink","tea"),3,"all three units were physically carried and dropped")
	check_eq(runtime.runner.machines.snapshot().runs.size(),2,"fulfilled source-only units cannot keep requesting stock forever")
	check_eq(runtime.runner.inventory.audit(),[],"source fulfillment conserves ownership and physical goods")

func test_process_inputs_reserved_and_in_transit_are_not_counted_again_as_source_shortages() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	var unit: Dictionary = runtime.request_production("drink")
	check_eq(_demand(runtime),{"stock":{"tea":2}},"recipe input quantities drive the demand")
	var reserved := false
	var held := false
	for tick in 500:
		check_eq(runtime.step(0.1),"","process fed by shared demand stock")
		for task in runtime.runner.tasks.values():
			if task.kind != "transfer" or task.from != "stock": continue
			reserved = true
			held = held or runtime.runner.owner.worker_by_id(task.worker).carry_count > 0
			check_eq(_demand(runtime),{},"the same goods are covered while reserved and while held")
		if runtime.ready(unit.id): break
	check(reserved and held,"real worker reservation and pickup were observed")
	check(runtime.ready(unit.id),"the two servings reach and complete the real process")
	_advance(runtime)
	check_eq(runtime.runner.inventory.quantity("stock","tea"),0,"demand-only source is not refilled after processing")
	var runs := 0
	for run in runtime.runner.machines.snapshot().runs:
		if run.machine == "pot": runs += 1
	check_eq(runs,1,"one physical batch supplies the whole recipe")

func test_low_watermark_refills_only_after_a_real_stock_withdrawal() -> void:
	var template := _definition(0,0,3)
	template.places.stock.initial = {"tea":4}
	var runtime := _runtime(template)
	if runtime == null: return
	_advance(runtime)
	check_eq(runtime.runner.machines.snapshot().runs,[],"stock at or above the low watermark is left alone")
	_withdraw(runtime,2)
	_advance(runtime)
	check_eq(runtime.runner.inventory.quantity("stock","tea"),4,"a batch restores the low stock")
	check_eq(runtime.runner.machines.snapshot().runs.size(),1,"low watermark is a trigger, not fill-to-capacity")

func test_target_is_capped_and_a_whole_batch_never_overflows_or_splits_to_fit() -> void:
	var template := _definition(100)
	template.places.stock.initial = {"tea":7}
	var runtime := _runtime(template)
	if runtime == null: return
	_advance(runtime)
	check_eq(runtime.runner.machines.snapshot().runs,[],"one spare slot cannot accept a two-serving batch")
	_withdraw(runtime,1)
	_advance(runtime)
	check_eq(runtime.runner.inventory.quantity("stock","tea"),8,"freeing a complete batch of space allows refill to the hard limit")
	check_eq(runtime.runner.machines.snapshot().runs.size(),1,"no overflow, phantom discard or partial production")

func test_dynamic_stock_and_real_machine_stages_restore_without_an_extra_batch() -> void:
	var template := _definition()
	template.machines.pot.profile = {"load_seconds":0.4,"unload_seconds":0.4,"stir_points":[0.5],"stir_seconds":0.2}
	var runtime := _runtime(template)
	if runtime == null: return
	var unit: Dictionary = runtime.request_production("drink")
	var cooking := false
	for tick in 200:
		check_eq(runtime.step(0.1),"","start real manual stages")
		for run in runtime.runner.machines.snapshot().runs:
			if run.phase in ["cook","await_stir","stir"]: cooking = true
		if cooking: break
	check(cooking,"saved during an actual stock machine lifecycle")
	var reopened := _runtime(template)
	if reopened == null: return
	check_eq(reopened.restore(runtime.snapshot()),"","restore graph, stock, claims and machine references together")
	for tick in 300:
		check_eq(runtime.step(0.1),"","continuous demanded stock")
		check_eq(reopened.step(0.1),"","restored demanded stock")
	check_eq(reopened.snapshot(),runtime.snapshot(),"derived demand and future task allocation replay identically")
	check(runtime.ready(unit.id),"restored ingredients complete the requested product")
	check_eq(runtime.runner.inventory.audit(),[],"restored stock conserves goods")

func test_stock_policy_rejects_unknown_modes_bad_counts_callbacks_and_ambiguous_mixed_batches() -> void:
	for patch in [{"mode":"private"}, {"base":-1}, {"per_waiting":1.5}, {"low":"3"}, {"callback":"shop_specific"}, {"mixed":true}, {"limit":1}]:
		var template := _definition()
		if patch.has("mixed"): template.restocks.stock.produces["coffee"] = 1
		elif patch.has("limit"): template.restocks.stock.stock_limit = patch.limit
		else: template.restocks.stock.policy.merge(patch,true)
		var result := Compiler.compile(template)
		check(not result.errors.is_empty(),"unsupported policy cannot silently select a fallback")
		check(result.errors.any(func(error: Dictionary) -> bool: return String(error.path).begins_with("restocks.stock")),"stock policy retains a useful configuration path")

func test_counter_and_self_pickup_reuse_demand_stock_after_old_customers_finish_eating() -> void:
	for delivery in ["counter","self_pickup"]:
		var template := Actors.definition(delivery)
		var stock := _definition()
		template.places["stock_in"] = stock.places.stock_in
		template.places["stock"] = stock.places.stock
		template.machines["pot"] = stock.machines.pot
		template.restocks = stock.restocks
		template.recipes.drink = stock.recipes.cup
		var runtime := _runtime(template)
		if runtime == null: return
		for wave in 3:
			check_eq(runtime.arrive(Actors.request()).error,"","real mixed main/side order in " + delivery)
			for tick in 1500:
				check_eq(runtime.step(0.1),"","shared service with demand stock")
				if runtime.runner.owner.sold == (wave + 1) * 2 and runtime.service.customers.snapshot().customers.is_empty(): break
			check_eq(runtime.runner.owner.sold,(wave + 1) * 2,"both real order lines were served and settled")
		_advance(runtime)
		check_eq(_demand(runtime),{},"food consumption does not reopen the old production demand")
		check_eq(runtime.runner.inventory.quantity("stock","tea"),1,"three served cups require two batches and leave only one extra")
		var runs := 0
		for run in runtime.runner.machines.snapshot().runs:
			if run.machine == "pot": runs += 1
		check_eq(runs,2,"same capability does not refill served orders in " + delivery)
		check_eq(runtime.runner.inventory.audit(),[],"mixed service conserves all physical inventory")

func test_large_valid_demand_multiplier_saturates_at_the_stock_limit_without_integer_overflow() -> void:
	var runtime := _runtime(_definition(0,9223372036854775807))
	if runtime == null: return
	for index in 2: runtime.request_production("cup")
	_advance(runtime)
	check_eq(runtime.runner.inventory.quantity("stock","tea"),8,"the hard stock limit applies before multiplying enormous valid counts")

func test_cancelled_source_pickup_reopens_demand_and_returns_stock_without_an_extra_batch() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	var unit: Dictionary = runtime.request_production("cup")
	_advance(runtime)
	var worker: Dictionary = runtime.runner.owner.workers[0]
	check_eq(runtime.runner.transfer(worker.id,"stock","sink","tea",1,0.2,-1,unit.id),"","reserve final source output")
	check_eq(_demand(runtime),{},"active pickup covers its bound source demand")
	for tick in 300:
		check_eq(runtime.runner.step(0.1),"","physically pick up the stock")
		if worker.carry_count > 0: break
	check_eq(worker.carry_count,1,"real held material before recall")
	check_eq(runtime.runner.cancel(worker.id),"","recall returns goods through the normal inventory claim")
	check_eq(_demand(runtime),{"stock":{"tea":1}},"cancelled transfer cannot prove final fulfillment")
	check_eq(runtime.runner.inventory.quantity("stock","tea"),2,"cancel returns the source material and its ownership")
	_advance(runtime)
	check_eq(runtime.runner.machines.snapshot().runs.size(),1,"returned stock already covers the reopened demand")

func test_two_employees_cannot_claim_the_same_shared_output_while_another_order_line_is_processing() -> void:
	for delivery in ["counter","table"]:
		var template := Actors.definition(delivery,"employee")
		template.places["batch_in"] = {"port":Vector2(220,100)}
		template.places["batch_out"] = {"port":Vector2(220,100),"capacity":8}
		template.machines["batch"] = {"input":"batch_in","output":"batch_out","profile":{
			"load_seconds":0.2,"unload_seconds":0.2,"stir_points":[0.5],"stir_seconds":0.2}}
		template.restocks = {"stock":{"machine":"batch","produces":{"drink":2},"seconds":2.0,"stock_limit":8,
			"policy":{"mode":"demand","base":1,"per_waiting":1,"low":0}}}
		template.recipes.drink = {"nodes":[{"id":"stock","capability":"source","place":"batch_out","item":"drink","seconds":0.6}],
			"output":{"node":"stock","item":"drink","count":1}}
		template.dispatch = {"affinity":"prefer","hold_machine":true,"help_while_waiting":true}
		template.service["arrivals"] = {"pattern":"fixed","interval":12.0,"first_delay":1.0,"opening":1,
			"choices":[{"weight":1.0,"request":Actors.request()}]}
		var runtime := Runtime.new(Actors.owner(),template)
		check_eq(runtime.last_error,"","both real employees can use the shared capabilities")
		if not runtime.last_error.is_empty(): continue
		check_eq(runtime.set_service_open(true),"","start actual arrivals")
		for tick in 600:
			var error: String = runtime.step(0.1)
			check_eq(error,"","concurrent partial delivery cannot exceed one bound unit")
			if not error.is_empty(): break
			if not runtime.frame().orders.is_empty() and runtime.frame().orders[0].paid: break
		check(runtime.frame().orders[0].paid,"first complete mixed order settles in " + delivery)
		var first: Dictionary = runtime.frame().orders[0]
		for line in first.lines:
			check_eq(line.delivered,1,"only the requested serving reaches each line")
