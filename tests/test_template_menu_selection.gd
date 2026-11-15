extends "res://tests/test_case.gd"
const Runtime := preload("res://game/rules/template/runtime.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")
const Fixture := preload("res://tests/fixtures/template_service.gd")

func _selection() -> Dictionary:
	return {"order":["lemonade","black_tea"],
		"gates":{"lemonade":{"stations":["lemonade"]},"black_tea":{"stations":["boil"],"boxes":["tea_leaf"]}},
		"groups":[],"stages":[{"interval":10.0,"weights":{"lemonade":1.0}},{"interval":4.0,"weights":{"black_tea":1.0}}],
		"addon":{"dish":"lemonade","share":0.3}}

func _definition(delivery := "counter") -> Resource:
	var template := Fixture.definition(delivery)
	template.service["selection"] = _selection()
	template.service["arrivals"] = {"pattern":"fixed","first_delay":0.1}
	return template

func _runtime(template: Resource) -> RefCounted:
	var owner := Fixture.owner()
	owner.unlocked.lemonade = true
	owner.unlocked.boil = true
	owner.boxes.tea_leaf = true
	var runtime := Runtime.new(owner,template)
	check_eq(runtime.last_error,"","public menu selection compiles")
	return runtime if runtime.last_error.is_empty() else null

func test_closed_material_box_rejects_explicit_order_before_rng_or_state_changes() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	runtime.runner.owner.boxes.tea_leaf = false
	var before: Dictionary = runtime.snapshot()
	var rng_before: int = runtime.runner.owner.rng.state
	check(not runtime.arrive([{"dish":"black_tea","qty":1}]).error.is_empty(),"uninstalled ingredient cannot be sold")
	check_eq(runtime.snapshot(),before,"invalid order changes no queue, stock or loss count")
	check_eq(runtime.runner.owner.rng.state,rng_before,"invalid explicit order consumes no random draw")

func test_stage_change_updates_future_menu_and_interval_without_replacing_waiting_orders() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	check_eq(runtime.set_service_open(true),"","start common arrivals")
	check_eq(runtime.step(0.1),"","first stage arrival")
	check_eq(runtime.service.orders.guest(1).request[0].dish,"lemonade","initial stage actual choice")
	runtime.runner.owner.stage_index = 1
	for tick in 100: check_eq(runtime.step(0.1),"","wait out committed interval after stage change")
	check_eq(runtime.service.orders.guest(2).request[0].dish,"black_tea","next arrival uses the new stage")
	check_eq(runtime.service.orders.guest(1).request[0].dish,"lemonade","existing choice is frozen")
	check(absf(runtime.service.arrivals.snapshot().left-4.0)<0.000001,"next clock uses the stage's actual interval")

func test_weighted_primary_then_addon_use_exact_outer_rng_order() -> void:
	var template := _definition()
	template.service.selection.stages[0].weights = {"black_tea":1.0}
	var runtime := _runtime(template)
	if runtime == null: return
	var expected := RandomNumberGenerator.new()
	expected.state = runtime.runner.owner.rng.state
	expected.randf()
	var addon := expected.randf()<0.3
	check_eq(runtime.set_service_open(true),"","open")
	check_eq(runtime.step(0.1),"","one real automatic arrival")
	var rows: Array = runtime.service.orders.guest(1).request
	check_eq(rows[0].dish,"black_tea","primary stays first for pricing/customization")
	check_eq(rows.size(),2 if addon else 1,"addon follows one separate probability draw")
	check_eq(runtime.runner.owner.rng.state,expected.state,"primary then addon, fixed clock consumes no RNG")

func test_closed_or_duplicate_addon_does_not_draw_rng_or_create_an_unavailable_line() -> void:
	for closed in [false,true]:
		var template := _definition()
		template.service.selection.stages[0].weights = {"black_tea":1.0} if closed else {"lemonade":1.0}
		var runtime := _runtime(template)
		if runtime == null: return
		if closed: runtime.runner.owner.unlocked.lemonade = false
		var expected := RandomNumberGenerator.new()
		expected.state = runtime.runner.owner.rng.state
		expected.randf()
		runtime.set_service_open(true)
		check_eq(runtime.step(0.1),"","gated addon arrival")
		check_eq(runtime.service.orders.guest(1).request.size(),1,"no duplicate or locked addon")
		check_eq(runtime.runner.owner.rng.state,expected.state,"skipped addon consumes no RNG")

func test_empty_menu_and_full_queue_never_draw_unused_menu_rng() -> void:
	for full in [false,true]:
		var runtime := _runtime(_definition())
		if runtime == null: return
		if full:
			for index in 2: check_eq(runtime.arrive([{"dish":"lemonade","qty":1}]).error,"","fill queue")
		else: runtime.runner.owner.unlocked.lemonade = false
		var before: int = runtime.runner.owner.rng.state
		runtime.set_service_open(true)
		check_eq(runtime.step(0.1),"","full or empty availability")
		check_eq(runtime.runner.owner.rng.state,before,"no unused menu draw")
		check_eq(runtime.service.orders.snapshot().lost,1 if full else 0,"empty catalog is not a lost customer")

func test_group_share_falls_back_then_splits_only_between_open_levels() -> void:
	var template := _definition()
	template.service.selection.groups = [{"id":"flavors","dishes":["black_tea"],"fallback":"lemonade"}]
	template.service.selection.gates.black_tea.levels = {"boil":2}
	template.service.selection.stages[0].weights = {"flavors":1.0}
	var runtime := _runtime(template)
	if runtime == null: return
	runtime.set_service_open(true)
	check_eq(runtime.step(0.1),"","group fallback before upgrade")
	check_eq(runtime.service.orders.guest(1).request[0].dish,"lemonade","closed group maps to declared fallback")
	runtime.runner.owner.gold = 100000.0
	check_eq(runtime.runner.owner.upgrade("boil"),"","normal public machine upgrade opens next level")
	for tick in 100: check_eq(runtime.step(0.1),"","new menu after actual upgrade")
	check_eq(runtime.service.orders.guest(2).request[0].dish,"black_tea","group uses newly opened flavor")

func test_restore_preserves_choices_and_outer_rng_across_later_unlock_changes() -> void:
	var template := _definition("table")
	var runtime := _runtime(template)
	if runtime == null: return
	runtime.set_service_open(true)
	for tick in 80: check_eq(runtime.step(0.1),"","reach in-flight service")
	var reopened := _runtime(template)
	if reopened == null: return
	for owner in [runtime.runner.owner,reopened.runner.owner]:
		owner.unlocked.lemonade = false
		owner.stage_index = 1
	for key in ["gold","revenue","sold","sale_carry"]: reopened.runner.owner._sales.set(key,runtime.runner.owner._sales.get(key))
	reopened.runner.owner.sold_by_dish = runtime.runner.owner.sold_by_dish.duplicate(true)
	reopened.runner.owner.rng.state = runtime.runner.owner.rng.state
	check_eq(reopened.restore(runtime.snapshot()),"","closed menu cannot invalidate a previously frozen request")
	for tick in 200:
		check_eq(runtime.step(0.1),"","continue original")
		check_eq(reopened.step(0.1),"","continue restored")
	check_eq(reopened.snapshot(),runtime.snapshot(),"same menu, deliveries and clocks")
	check_eq(reopened.runner.owner.rng.state,runtime.runner.owner.rng.state,"same future menu RNG")

func test_invalid_selection_fields_and_unknown_runtime_requirements_fail_closed() -> void:
	for patch in [{"callback":"choose"},{"order":["lemonade"]},{"addon":{"dish":"missing","share":0.3}},{"stages":[{"interval":0.0,"weights":{"lemonade":1.0}}]},{"groups":[{"id":"flavors","dishes":["missing"],"fallback":"lemonade"}]}]:
		var template := _definition()
		for key in patch: template.service.selection[key] = patch[key]
		check(not Compiler.compile(template).errors.is_empty(),"bad menu definition is rejected")
	var unknown := _definition()
	unknown.service.selection.gates.lemonade.stations = ["missing"]
	check(not Runtime.new(Fixture.owner(),unknown).last_error.is_empty(),"unknown station requirement cannot be silently closed forever")
	var unused := _definition()
	unused.service.arrivals.interval = 3.0
	check(not Compiler.compile(unused).errors.is_empty(),"stage selection cannot silently ignore a second arrival interval")

func test_invalid_outer_stage_is_rejected_before_advancing_clock_rng_or_actors() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	runtime.runner.owner.stage_index = 99
	var before: Dictionary = runtime.snapshot()
	var rng_before: int = runtime.runner.owner.rng.state
	check(not runtime.step(0.1).is_empty(),"invalid external stage cannot index a menu or advance time")
	check_eq(runtime.snapshot(),before,"invalid context does not partially advance any subsystem")
	check_eq(runtime.runner.owner.rng.state,rng_before,"invalid stage consumes no RNG")

func test_whole_order_readiness_waits_for_both_actual_outputs_before_staff_delivery() -> void:
	for delivery in ["counter","table"]:
		var template := Fixture.definition(delivery)
		template.service["delivery_ready"] = "whole_order"
		var runtime := Runtime.new(Fixture.owner(),template)
		check_eq(runtime.last_error,"","whole-order readiness is a reusable service policy")
		if not runtime.last_error.is_empty(): return
		runtime.arrive(Fixture.request())
		var saw_only_one := false
		for tick in 1000:
			check_eq(runtime.step(0.1),"","actual two-line order")
			var order: Dictionary = runtime.service.orders.order(1)
			if order.is_empty(): continue
			var ready := 0
			for line in order.lines:
				for binding in line.units:
					if runtime.production_output(binding.unit).get("complete",false): ready += 1
			if ready == 1 and runtime.service.snapshot().deliveries.is_empty():
				saw_only_one = true
				for line in order.lines: check_eq(line.delivered,0,"cannot deliver only the first ready line")
			if not runtime.service.snapshot().deliveries.is_empty():
				var delivered := 0
				for line in order.lines: delivered += int(line.delivered)
				# A later partial trip may already have consumed one ready unit.
				if delivered == 0: check_eq(ready,2,"first delivery reserves goods only when the whole order is ready")
			if order.state == "delivered": break
		check(saw_only_one,"test actually exercised the one-output-ready boundary")
		check_eq(runtime.service.orders.order(1).state,"delivered","whole order still progresses to real payment")

func test_selection_numeric_projection_keeps_gates_order_and_groups_structural() -> void:
	var contract := preload("res://game/rules/shop_content_contract.gd")
	var template := _definition()
	var before: Dictionary = contract.describe_template(template)
	template.service.selection.stages[0].interval = 8.0
	template.service.selection.stages[0].weights.lemonade = 0.5
	template.service.selection.addon.share = 0.4
	var tuned: Dictionary = contract.describe_template(template)
	check_eq(tuned.structure,before.structure,"menu time, weight and addon probability are tuning values")
	check(tuned.gameplay!=before.gameplay,"numeric edits remain visible in full gameplay identity")
	template.service.selection.gates.lemonade.stations = ["boil"]
	check(contract.describe_template(template).structure!=before.structure,"unlock identity remains structural")

func test_addon_first_changes_real_production_order_without_changing_primary_pricing_identity() -> void:
	var template := _definition()
	template.service.selection.addon["first"] = true
	template.dispatch = {"affinity":"exclusive"}
	var runtime := _runtime(template)
	if runtime == null: return
	runtime.arrive([{"dish":"black_tea","qty":1},{"dish":"lemonade","qty":1}])
	for tick in 1000:
		check_eq(runtime.step(0.1),"","one follower produces addon before main")
		var runs: Array = runtime.runner.machines.snapshot().runs
		if not runs.is_empty():
			check_eq(runs[0].machine,"a","real addon recipe begins first")
			var lines: Array = runtime.service.orders.order(1).lines
			check_eq(lines[0].dish,"black_tea","primary line stays first for options and price")
			check_eq(lines[1].dish,"lemonade","addon remains the separate unmodified line")
			return
	check(false,"real addon process started")
