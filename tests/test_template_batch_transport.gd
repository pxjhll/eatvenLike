extends "res://tests/test_case.gd"
const Fixture := preload("res://tests/fixtures/template_shop.gd")
const Actors := preload("res://tests/fixtures/template_service.gd")
const Runtime := preload("res://game/rules/template/runtime.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")

func _template(terminal := false) -> Resource:
	var template := Fixture.linear()
	template.dispatch = {"batch_transfers":true}
	if terminal:
		template.places.a_out.initial = {"drink":3}
		template.places["pass"] = {"port":Vector2(450,100),"capacity":4}
		template.recipes.drink.nodes = [{"id":"stock","capability":"source","place":"a_out","item":"drink","seconds":0.6},
			{"id":"pass","capability":"transfer","input":"stock","place":"pass","item":"drink","count":1,"seconds":0.6}]
		template.recipes.drink.output.node = "pass"
	return template

func _runtime(template: Resource) -> RefCounted:
	var owner := Actors.owner()
	owner.workers[1].deployed = false
	var runtime := Runtime.new(owner,template)
	check_eq(runtime.last_error,"","cross-unit batching is a public optional policy")
	return runtime if runtime.last_error.is_empty() else null

func _two(runtime: RefCounted) -> void:
	runtime.request_production("drink")
	runtime.request_production("drink")
	check_eq(runtime.step(0.1),"","one allocation loop claims compatible production work")

func test_two_production_units_share_one_walk_but_keep_separate_owners() -> void:
	var runtime := _runtime(_template())
	if runtime==null: return
	_two(runtime)
	var worker: Dictionary = runtime.runner.owner.workers[0]
	var task: Dictionary = runtime.runner.tasks[worker.id]
	check_eq(task.kind,"bundle","two compatible input transfers share one transport")
	if task.kind!="bundle": return
	check_eq(task.picks.size(),2,"one child claim per production unit")
	check_eq(worker.carry_count,0,"reservation shows no carried goods")
	var owners: Array = []
	for pick in task.picks: owners.append(runtime.runner.inventory.claim(pick.claim).allocate_owner)
	check_eq(owners,[1,2],"orders retain individual input ownership")
	for tick in 200:
		check_eq(runtime.step(0.1),"","common pickup, transport, drop and process")
		if runtime.production_output(1).complete and runtime.production_output(2).complete: break
	check_eq(runtime.runner.inventory.quantity("a_out","drink",1),1,"first unit uses only its own input")
	check_eq(runtime.runner.inventory.quantity("a_out","drink",2),1,"second unit uses only its own input")
	check_eq(runtime.runner.inventory.audit(),[],"no second inventory or pooled owner")

func test_shared_terminal_bundle_records_each_graph_node_and_completes_after_real_drop() -> void:
	var runtime := _runtime(_template(true))
	if runtime==null: return
	_two(runtime)
	check_eq(runtime.unit(1).running.pass,runtime.unit(2).running.pass,"one batch supplies both explicit terminal nodes")
	check(not runtime.ready(1) and not runtime.ready(2),"reserved terminals remain unfinished")
	for tick in 200:
		check_eq(runtime.step(0.1),"","whole batch drop commits both graph nodes")
		if runtime.ready(1) and runtime.ready(2): break
	check(runtime.ready(1) and runtime.ready(2),"both terminals complete at physical destination")
	check_eq(runtime.runner.inventory.quantity("pass","drink",1),1,"first terminal identity")
	check_eq(runtime.runner.inventory.quantity("pass","drink",2),1,"second terminal identity")
	check_eq(runtime.runner.inventory.snapshot().created.drink,3,"finite source is never manufactured again")

func test_batch_restores_before_pickup_between_pickups_and_after_drop() -> void:
	for phase in ["reserved","partial","dropped"]:
		var template := _template(true)
		var runtime := _runtime(template)
		if runtime==null: return
		_two(runtime)
		var task: Dictionary = runtime.runner.tasks[runtime.runner.owner.workers[0].id]
		if task.kind!="bundle": check(false,"actual shared bundle required for restore"); return
		var bundle_id: int = task.bundle
		var reached: bool = phase=="reserved"
		for tick in (0 if reached else 200):
			check_eq(runtime.step(0.1),"","reach real batch save boundary")
			var states := {}
			for id in runtime.runner.inventory.bundle(bundle_id).claims: states[runtime.runner.inventory.claim(id).state] = true
			reached = states.has("held") and states.has("reserved") if phase=="partial" else states.has("dropped")
			if reached: break
		check(reached,"real save boundary reached: "+phase)
		var reopened := _runtime(template)
		check_eq(reopened.restore(runtime.snapshot()),"","restore shared graph-to-claim links: "+phase)
		for tick in 150:
			check_eq(runtime.step(0.1),"","continuous batch")
			check_eq(reopened.step(0.1),"","restored batch")
		check_eq(reopened.snapshot(),runtime.snapshot(),"same inventory, owners, cursor and clocks: "+phase)

func test_cancel_after_first_pickup_returns_all_children_and_both_units_can_retry() -> void:
	var runtime := _runtime(_template(true))
	if runtime==null: return
	_two(runtime)
	var worker: Dictionary = runtime.runner.owner.workers[0]
	for tick in 100:
		check_eq(runtime.step(0.1),"","reach actual first pickup")
		if worker.carry_count==1: break
	check_eq(worker.carry_count,1,"one child held while second remains reserved")
	check_eq(runtime.runner.cancel(worker.id),"","shared cancellation compensates every child")
	check_eq(runtime.runner.inventory.quantity("a_out","drink"),3,"all finite goods returned exactly once")
	for tick in 250:
		check_eq(runtime.step(0.1),"","both graph nodes retry after cancellation")
		if runtime.ready(1) and runtime.ready(2): break
	check(runtime.ready(1) and runtime.ready(2),"cancelled shared bundle does not strand either unit")
	check_eq(runtime.runner.inventory.snapshot().created.drink,3,"retry does not duplicate source goods")
	check_eq(runtime.runner.inventory.audit(),[],"partial pickup cancellation conserves stock")

func test_capacity_one_keeps_single_transfers_and_exclusive_following_keeps_orders_apart() -> void:
	for mode in ["capacity","exclusive"]:
		var template := _template()
		if mode=="exclusive": template.dispatch.affinity = "exclusive"
		var runtime := _runtime(template)
		if runtime==null: return
		if mode=="capacity": runtime.runner.owner.apply_effect("event","limit",SpecEffect.make("carry","set",1.0))
		_two(runtime)
		var task: Dictionary = runtime.runner.tasks[runtime.runner.owner.workers[0].id]
		check_eq(task.kind,"transfer","batch cannot bypass capacity or exclusive order scope: "+mode)
		check_eq(runtime.runner.inventory.claim(task.claim).count,1,"one genuine input remains allocated")

func test_batch_cannot_merge_distinct_physical_drop_ports_or_terminal_clocks() -> void:
	for mode in ["destination","clock"]:
		var template := _template(true)
		var second: Dictionary = template.recipes.drink.duplicate(true)
		if mode=="destination":
			template.places["other"] = {"port":Vector2(550,100),"capacity":4}
			second.nodes[1].place = "other"
		else: second.nodes[1].seconds = 1.2
		template.recipes["other"] = second
		var runtime := _runtime(template)
		if runtime==null: return
		runtime.request_production("drink")
		runtime.request_production("other")
		check_eq(runtime.step(0.1),"","allocate incompatible terminal routes")
		var task: Dictionary = runtime.runner.tasks[runtime.runner.owner.workers[0].id]
		check_eq(task.picks.size(),1,"different destination or drop clock requires separate transport: "+mode)
		check(not runtime.unit(2).running.has("pass"),"second terminal is not attached to incompatible first bundle")

func test_shared_finite_source_is_not_overreserved_by_batched_candidates() -> void:
	var template := _template(true)
	template.places.a_out.initial = {"drink":1}
	var runtime := _runtime(template)
	if runtime==null: return
	_two(runtime)
	var task: Dictionary = runtime.runner.tasks[runtime.runner.owner.workers[0].id]
	check_eq(task.picks.size(),1,"two requests cannot promise the same finite item")
	check(not runtime.unit(2).running.has("pass"),"unfunded unit remains pending")
	check_eq(runtime.runner.inventory.audit(),[],"batch planning made no phantom second reservation")

func test_same_order_main_and_addon_batch_under_exclusive_following_in_all_delivery_combinations() -> void:
	for delivery in ["counter","table","self_pickup"]:
		var template := Actors.definition(delivery)
		template.dispatch = {"batch_transfers":true,"affinity":"exclusive"}
		var runtime := _runtime(template)
		if runtime==null: return
		runtime.arrive(Actors.request())
		var saw_batch := false
		for tick in 2400:
			check_eq(runtime.step(0.1),"","same order combines production logistics: "+delivery)
			for task in runtime.runner.tasks.values():
				if task.kind=="bundle" and task.to=="a_in" and task.picks.size()==2: saw_batch = true
			if runtime.service.orders.guest(1).state=="gone": break
		check(saw_batch,"exclusive follows one order, allowing its distinct main/addon units to batch")
		check_eq(runtime.runner.owner.sold,2,"both owned products physically delivered and settled")
		check(runtime.service.orders.order(1).paid,"one whole-order payment")
		check_eq(runtime.runner.inventory.audit(),[],"same shared ledger for every delivery combination")

func test_forged_shared_terminal_links_and_duplicate_child_assignment_fail_atomically() -> void:
	var runtime := _runtime(_template(true))
	if runtime==null: return
	_two(runtime)
	for patch in ["owner","missing","duplicate"]:
		var saved: Dictionary = runtime.snapshot()
		match patch:
			"owner": saved.runner.inventory.claims[0].allocate_owner = 2
			"missing": saved.units[1].running.erase("pass")
			"duplicate": saved.units[1].running.pass = 999
		var before: Dictionary = runtime.snapshot()
		check(not runtime.restore(saved).is_empty(),"forged per-unit transport rejected: "+patch)
		check_eq(runtime.snapshot(),before,"failed restore preserves existing live batch")

func test_optional_batch_flag_rejects_unknown_values_and_absent_flag_preserves_definition() -> void:
	var template := _template()
	template.dispatch.batch_transfers = "yes"
	check(not Compiler.compile(template).errors.is_empty(),"batching needs an explicit boolean")
	template.dispatch.erase("batch_transfers")
	var before: Dictionary = Compiler.compile(template).definition
	template.dispatch.batch_transfers = false
	check_eq(Compiler.compile(template).definition,before,"disabled batching has no default identity impact")
