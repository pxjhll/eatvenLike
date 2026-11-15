extends "res://tests/test_case.gd"
const Production := preload("res://tests/fixtures/template_shop.gd")
const Service := preload("res://tests/fixtures/template_service.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")
const Runtime := preload("res://game/rules/template/runtime.gd")

func _source() -> Dictionary:
	return {"id":"raw", "capability":"source", "place":"pantry", "item":"raw_a",
		"seconds":2.0, "timing_target":"supply", "fixed":false}

func _owner() -> ShopRules:
	var owner := Service.owner()
	owner.tune["supply"] = 2.0
	owner.apply_effect("event", "source_speed", SpecEffect.make("speed", "mul", 2.0, "supply"))
	owner.apply_effect("event", "source_duration", SpecEffect.make("duration", "mul", 3.0, "supply"))
	for worker in owner.workers: worker.stats.work = 2.0
	return owner

func test_source_clock_policy_is_compiled_and_invalid_targets_are_rejected() -> void:
	var template := Production.linear()
	template.recipes.drink.nodes[0] = _source()
	var compiled := Compiler.compile(template)
	check_eq(compiled.errors, [], "source clocks are declarative public data")
	if compiled.errors.is_empty():
		check_eq(compiled.definition.recipes.drink.nodes.raw.timing_target, "supply", "target survives compilation")
	for invalid in [null, 17, []]:
		template.recipes.drink.nodes[0].timing_target = invalid
		check(not Compiler.compile(template).errors.is_empty(), "invalid clock target cannot be coerced into an ID")

func test_source_timing_modifiers_change_real_production_pickup_before_applying_employee_rate_once() -> void:
	var template := Production.linear()
	template.recipes.drink.nodes[0] = _source()
	var runtime := Runtime.new(_owner(), template)
	check_eq(runtime.last_error, "", "clocked production compiles")
	if not runtime.last_error.is_empty(): return
	var unit: Dictionary = runtime.request_production("drink")
	check_eq(runtime.step(0.1), "", "common dispatcher assigns the source transfer")
	var worker: Dictionary = runtime.runner.owner.workers[0]
	check_eq(runtime.runner.tasks[worker.id].seconds, 3.0, "2 base × 3 duration ÷ 2 machine speed × 2 tuning ÷ 2 employee rate")
	var ticks := 0
	for tick in 500:
		if worker.phase == "pickup": ticks += 1
		check_eq(runtime.runner.step(0.1), "", "advance actual source action")
		if runtime.runner.idle(worker.id): break
	check_eq(ticks, 30, "the real pickup timer uses the same shared formula")
	check_eq(runtime.runner.inventory.quantity("a_in", "raw_a", unit.id), 1, "actual source material reaches its owned processing input")

func test_fixed_and_unconfigured_source_clocks_keep_distinct_public_semantics() -> void:
	for policy in ["fixed", "unconfigured"]:
		var template := Production.linear()
		var source := _source()
		if policy == "fixed": source.fixed = true
		else: source.erase("timing_target"); source.erase("fixed")
		template.recipes = {"raw":{"nodes":[source], "output":{"node":"raw", "item":"raw_a", "count":1}}}
		var runtime := Runtime.new(_owner(), template)
		check_eq(runtime.last_error, "", "source-only recipe compiles")
		if not runtime.last_error.is_empty(): continue
		var unit: Dictionary = runtime.request_production("raw")
		check_eq(runtime.production_output(unit.id).pickup_seconds, 4.0 if policy == "fixed" else 2.0,
			"fixed skips machine effects but keeps target tuning; unconfigured keeps literal clock")

func test_service_staging_and_direct_delivery_use_the_same_clocked_output_descriptor() -> void:
	for delivery in ["counter", "self_pickup"]:
		var template := Service.definition(delivery)
		template.recipes.drink = {"nodes":[_source()], "output":{"node":"raw", "item":"raw_a", "count":1}}
		var runtime := Runtime.new(_owner(), template)
		check_eq(runtime.last_error, "", "service compiles clocked source-only product")
		if not runtime.last_error.is_empty(): continue
		check_eq(runtime.arrive([{"dish":"lemonade", "qty":1}]).error, "", "customer enters common service")
		var found := false
		for tick in 1000:
			check_eq(runtime.step(0.1), "", "advance actual service")
			for task in runtime.runner.tasks.values():
				if task.kind == "transfer" and task.from == "pantry":
					found = true
					check_eq(task.seconds, 3.0, "self-pickup staging uses tuned source clock once")
				elif task.kind == "bundle" and task.picks[0].from == "pantry":
					found = true
					check_eq(task.picks[0].seconds, 3.0, "direct delivery uses tuned source clock once")
			if found: break
		check(found, "real employee request observed for " + delivery)
