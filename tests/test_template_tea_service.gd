extends "res://tests/test_case.gd"
const TemplateOuter := preload("res://tests/fixtures/template_outer.gd")
const SHOP: SpecShop = preload("res://content/shops/tea/shop.tres")
const TEMPLATE := preload("res://content/shops/tea/shared_production.tres")
const Runtime := preload("res://game/rules/template/runtime.gd")
const Requirements := preload("res://game/rules/template/requirements.gd")

func _owner(full := true, kitchen := true) -> ShopRules:
	var owner := TemplateOuter.owner(SHOP.copy_for_editing(),42)
	owner.gold = 1000000.0
	check_eq(owner.unlock("lemonade"),"","open actual tea shop")
	if full:
		for id in ["boil","seal","mix","press","topping"]: check_eq(owner.unlock(id),"","unlock actual tea machine")
		for id in ["tea_leaf","milk"]: check_eq(owner.unlock_box(id),"","buy actual material box")
		for index in 3: check_eq(owner.upgrade("topping"),"","open all actual flavors")
	if full and kitchen:
		check_eq(owner.hire(),"","hire actual kitchen employee")
		for worker in owner.roster:
			if not worker.deployed: check_eq(owner.deploy_worker(worker.id),"","deploy kitchen employee")
	return owner

func _runtime(full := true, kitchen := true) -> RefCounted:
	var runtime := Runtime.new(_owner(full,kitchen),TEMPLATE)
	check_eq(runtime.last_error,"","real tea production composes public customer service")
	check(runtime.service!=null,"real tea template needs full service configuration")
	return runtime if runtime.last_error.is_empty() and runtime.service!=null else null

func _finish(runtime: RefCounted, ids: Array) -> void:
	for tick in 6000:
		check_eq(runtime.step(0.1),"","actual tea service tick")
		var done := true
		for id in ids:
			if runtime.service.orders.guest(id).state!="gone": done = false
		if done: return
	check(false,"all real tea customers left after actual receipt and meal")

func test_actual_tea_declares_all_menu_seats_stages_and_sealed_routes_without_changing_production_graphs() -> void:
	check(not TEMPLATE.service.is_empty(),"actual tea template must declare common service")
	if TEMPLATE.service.is_empty(): return
	check_eq(TEMPLATE.service.menu.size(),8,"eight original drinks")
	check_eq(TEMPLATE.recipes.size(),14,"existing production and sealing graphs retained")
	check_eq(TEMPLATE.service.dining.order.size(),8,"all eight purchasable seats explicitly ordered")
	check_eq(TEMPLATE.service.dining.stages.size(),6,"six real stages")
	check_eq(TEMPLATE.service.dining.takeaway.variants.size(),6,"only kitchen drinks require sealing")
	check_eq(TEMPLATE.service.selection.ramp,{"start":0.25,"orders":12},"original exposure curve")
	check_eq(TEMPLATE.service.arrivals.opening,3,"original opening wave")
	check_eq(TEMPLATE.service.handoff_port,"counter","front employee hands over at the original counter")

func test_opening_stage_produces_and_delivers_only_lemonade_without_running_closed_kitchen() -> void:
	var runtime := _runtime(false,false)
	if runtime==null: return
	check_eq(runtime.set_service_open(true),"","start common opening wave")
	check_eq(runtime.service.orders.snapshot().guests.size(),3,"same three opening visitors")
	check_eq(runtime.service.orders.guest(1).seat,"seat:dine/0","first diner uses original seat")
	check_eq(runtime.service.orders.guest(2).seat,"seat:dine/1","second diner uses original seat")
	check_eq(runtime.service.orders.guest(3).state,"queue","third visitor waits for an actual seat before takeaway opens")
	check_eq(runtime.set_service_open(false),"","freeze further arrivals for controlled three-customer completion")
	_finish(runtime,[1,2,3])
	check_eq(runtime.runner.owner.sold_by_dish.lemonade,3,"all three real drinks delivered through common inventory")
	for run in runtime.runner.machines.snapshot().runs: check_eq(run.machine,"lemonade","closed kitchen never starts speculative production")
	check_eq(runtime.runner.owner.sold,3,"no double-counted opening visitors")

func test_actual_two_diners_and_one_takeaway_use_shared_counter_service_and_one_real_sealer_run() -> void:
	var runtime := _runtime()
	if runtime==null: return
	for index in 3: check_eq(runtime.arrive([{"dish":"black_tea","qty":1}]).error,"","real black tea arrival")
	check_eq(runtime.service.orders.guest(1).request[0].recipe,"black_tea","first drink is unsealed dining")
	check_eq(runtime.service.orders.guest(2).request[0].recipe,"black_tea","second drink is unsealed dining")
	check_eq(runtime.service.orders.guest(3).request[0].recipe,"black_tea:sealed","full seats select authored sealing graph")
	_finish(runtime,[1,2,3])
	var sealed := 0
	for run in runtime.runner.machines.snapshot().runs:
		if run.machine=="seal": sealed += 1
	check_eq(sealed,1,"only actual takeaway passes through shared sealer")
	check_eq(runtime.runner.owner.sold_by_dish.black_tea,3,"same original sales identity across two routes")
	check_eq(runtime.runner.owner.revenue,3.0*runtime.runner.owner.dish_price("black_tea"),"original common quote and payment retained")
	check_eq(runtime.runner.inventory.audit(),[],"single inventory ledger remains valid")

func test_nonsealed_front_drinks_can_take_away_without_a_packaging_step() -> void:
	var runtime := _runtime()
	if runtime==null: return
	for index in 3: check_eq(runtime.arrive([{"dish":"lemon_tea","qty":1}]).error,"","actual front-made lemon tea")
	check_eq(runtime.service.orders.guest(3).request[0].recipe,"lemon_tea","declared takeaway fallback uses ordinary graph")
	_finish(runtime,[1,2,3])
	check_eq(runtime.runner.owner.sold_by_dish.lemon_tea,3,"all hand-pounded drinks really delivered")
	for run in runtime.runner.machines.snapshot().runs: check(run.machine!="seal","front takeaway never visits sealer")

func test_common_worker_gate_keeps_kitchen_menu_closed_until_real_employee_is_deployed() -> void:
	var runtime := _runtime(true,false)
	if runtime==null: return
	check(not runtime.arrive([{"dish":"black_tea","qty":1}]).error.is_empty(),"installed equipment alone does not permit an unstaffed kitchen order")
	check(runtime.service.menu_weights().has("lemonade"),"front drink remains available")
	check(not runtime.service.menu_weights().has("black_tea"),"unstaffed kitchen is absent from automatic menu")
	var owner: RefCounted = runtime.runner.owner
	check_eq(owner.hire(),"","hire through existing command")
	var id := -1
	for worker in owner.roster:
		if not worker.deployed: id = worker.id
	check(not runtime.service.menu_weights().has("black_tea"),"recruited but undeployed employee is insufficient")
	check_eq(owner.deploy_worker(id),"","public deployment opens the kitchen qualification")
	check(runtime.service.menu_weights().has("black_tea"),"same shared menu gate sees deployed non-counter employee")
	check_eq(runtime.arrive([{"dish":"black_tea","qty":1}]).error,"","new order can now use ordinary production graph")

func test_actual_menu_weights_and_flow_match_original_queries_in_each_stage() -> void:
	var runtime := _runtime()
	if runtime==null: return
	var owner: RefCounted = runtime.runner.owner
	for key in owner.order_ramp: owner.order_ramp[key] = 0
	for stage in 6:
		owner.stage_index = stage
		check_eq(runtime.service.menu_weights(),owner.order_weights(),"actual configured stage order/weight/qualification matches original")
		check_eq(runtime.service.flow_multiplier(),owner.flow_multiplier(),"actual flavor contribution matches original")

func test_worker_requirement_validates_shape_references_and_actual_deployed_post_facts() -> void:
	var compiled := Requirements.compile({"workers":{"minimum":1,"exclude_posts":["counter"]}})
	check_eq(compiled.error,"","staffing qualification is a shared requirement")
	if not compiled.error.is_empty(): return
	var owner := _owner(true,false)
	check_eq(Requirements.reference_error(compiled.definition,owner),"","known excluded post")
	check(not Requirements.met(compiled.definition,owner),"counter employee does not count as kitchen capacity")
	for bad in [{"minimum":0,"exclude_posts":[]},{"minimum":1.0,"exclude_posts":[]},{"minimum":1,"exclude_posts":["counter","counter"]},{"minimum":1,"exclude_posts":[],"callback":"staffed"}]:
		check(not Requirements.compile({"workers":bad}).error.is_empty(),"invalid authored worker requirement")
	compiled = Requirements.compile({"workers":{"minimum":1,"exclude_posts":["unknown"]}})
	check(not Requirements.reference_error(compiled.definition,owner).is_empty(),"unknown excluded post cannot silently open menu")

func test_real_posted_pot_employee_owns_manual_stages_while_floating_helper_moves_finished_tea() -> void:
	check(TEMPLATE.dispatch.has("station_posts"),"actual tea template needs declared pot and topping posts")
	if not TEMPLATE.dispatch.has("station_posts"): return
	var owner := _owner()
	var seated := -1
	for worker in owner.workers:
		if worker.post!="counter": seated = worker.id
	check_eq(owner.place_worker(seated,"boil"),"","seat original kitchen employee through shared command")
	check_eq(owner.hire(),"","add a floating logistics helper")
	for worker in owner.roster:
		if not worker.deployed: check_eq(owner.deploy_worker(worker.id),"","deploy helper")
	var runtime := Runtime.new(owner,TEMPLATE)
	check_eq(runtime.last_error,"","posted tea data composes common authority gate")
	if not runtime.last_error.is_empty(): return
	runtime.arrive([{"dish":"black_tea","qty":1}])
	var saw_stage := false
	for tick in 3000:
		check_eq(runtime.step(0.1),"","actual tea pot with seated operator and shared logistics")
		for task in runtime.runner.tasks.values():
			if task.kind=="operate" and runtime.runner.machines.run(task.run).machine=="boil":
				saw_stage = true
				check_eq(task.worker,seated,"only real posted employee handles pot stages")
		if runtime.service.orders.guest(1).state=="gone": break
	check(saw_stage,"real load/cook/stir/unload used the posted operator")
	check_eq(owner.sold_by_dish.black_tea,1,"floating helper and counter still complete delivery")
