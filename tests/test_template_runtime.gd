extends "res://tests/test_case.gd"
const Fixture := preload("res://tests/fixtures/template_shop.gd")
const Actors := preload("res://tests/fixtures/movement_shop.gd")
const PATH := "res://game/rules/template/runtime.gd"

func _runtime(template: Resource) -> RefCounted:
	check(ResourceLoader.exists(PATH), "templates must actually produce through the public runtime")
	if not ResourceLoader.exists(PATH): return null
	var shop := Actors.definition("handoff")
	shop.staff.starting.assign(["gray_cat", "gray_cat"])
	shop.staff.starting_posts.assign(["", ""])
	var rules := ShopRules.new(shop, 42)
	for worker in rules.workers: worker.pos = Vector2(100,100)
	return load(PATH).new(rules, template)

func test_parallel_recipe_runs_to_completion_without_a_shop_specific_executor() -> void:
	var runtime := _runtime(Fixture.definition())
	if runtime == null: return
	check_eq(runtime.last_error, "", "valid public template initializes")
	var request: Dictionary = runtime.request_production("meal")
	check_eq(request.error, "", "production demand accepted")
	var joined_after_both := false
	for tick in 1800:
		check_eq(runtime.step(0.1), "", "public runtime step")
		var unit: Dictionary = runtime.unit(request.id)
		if unit.running.has("merge"):
			joined_after_both = true
			check("a" in unit.done and "b" in unit.done, "join starts only after both branches complete")
		if runtime.ready(request.id): break
	check(joined_after_both, "real dependency join occurred")
	check(runtime.ready(request.id), "recipe completed through capabilities")
	check_eq(runtime.runner.inventory.quantity("join_out", "meal", request.id), 1, "one product belongs to the requested unit")
	check_eq(runtime.runner.inventory.audit(), [], "real production conserved all claims")
	check_eq(runtime.frame().draws, [], "finished product is UI inventory, not an automatic scene icon")

func test_linear_and_parallel_templates_use_the_same_runtime_and_can_run_multiple_orders() -> void:
	var runtime := _runtime(Fixture.linear())
	if runtime == null: return
	var first: Dictionary = runtime.request_production("drink")
	var second: Dictionary = runtime.request_production("drink")
	for tick in 1200:
		runtime.step(0.1)
		if runtime.ready(first.id) and runtime.ready(second.id): break
	check(runtime.ready(first.id) and runtime.ready(second.id), "same runtime handles independent requests")
	check_eq(runtime.runner.inventory.quantity("a_out", "drink", first.id), 1, "first order ownership")
	check_eq(runtime.runner.inventory.quantity("a_out", "drink", second.id), 1, "second order ownership")
	check_eq(runtime.runner.machines.audit(), [], "shared machine occupancy and stock")

func test_missing_branch_stock_waits_and_resumes_when_public_stock_is_added() -> void:
	var template := Fixture.definition()
	template.places.pantry.infinite = ["raw_a"]
	template.places.pantry.initial = {"raw_b":1}
	var runtime := _runtime(template)
	if runtime == null: return
	var first: Dictionary = runtime.request_production("meal")
	var second: Dictionary = runtime.request_production("meal")
	for tick in 1200: runtime.step(0.1)
	check(runtime.ready(first.id), "available stock completes the first request")
	check(not runtime.ready(second.id), "missing branch cannot be fabricated")
	check_eq(runtime.runner.inventory.seed("pantry", "raw_b", 1).error, "", "supply through public inventory")
	for tick in 1200:
		runtime.step(0.1)
		if runtime.ready(second.id): break
	check(runtime.ready(second.id), "blocked recipe resumes without a new executor")
	check_eq(runtime.runner.inventory.audit(), [], "missing-input wait preserves ownership")

func test_pause_preserves_real_actors_stock_and_processing_progress() -> void:
	var runtime := _runtime(Fixture.linear())
	if runtime == null: return
	var request: Dictionary = runtime.request_production("drink")
	for tick in 20: runtime.step(0.1)
	var before: Dictionary = runtime.frame()
	check_eq(runtime.step(60.0, true), "", "pause accepted")
	check_eq(runtime.frame(), before, "pause freezes the entire capability pipeline")
	for tick in 1200:
		runtime.step(0.1)
		if runtime.ready(request.id): break
	check(runtime.ready(request.id), "pipeline resumes after pause")

func test_invalid_template_and_unknown_recipe_cannot_select_a_legacy_fallback() -> void:
	var template := Fixture.linear()
	template.recipes.drink.nodes[1].capability = "private_tick"
	var runtime := _runtime(template)
	if runtime == null: return
	check(not runtime.last_error.is_empty(), "invalid content is rejected")
	check(not runtime.request_production("drink").error.is_empty(), "invalid template cannot run a partial order")
	check(not runtime.step(1.0).is_empty(), "no old mode is used as a fallback")
	runtime = _runtime(Fixture.linear())
	check(not runtime.request_production("missing").error.is_empty(), "unknown recipe reported")

func test_parallel_production_save_restores_branches_claims_and_actor_programs() -> void:
	var runtime := _runtime(Fixture.definition())
	if runtime == null: return
	var request: Dictionary = runtime.request_production("meal")
	for tick in 35: runtime.step(0.1)
	var saved: Dictionary = runtime.snapshot()
	var reopened := _runtime(Fixture.definition())
	check_eq(reopened.restore(saved), "", "restore the common runtime at an active production boundary")
	for tick in 1200:
		runtime.step(0.1)
		reopened.step(0.1)
		if runtime.ready(request.id) and reopened.ready(request.id): break
	check(runtime.ready(request.id) and reopened.ready(request.id), "both original and restored productions complete")
	check_eq(reopened.snapshot(), runtime.snapshot(), "replay agrees in clocks, programs, claims, goods and ownership")

func test_incompatible_graph_or_forged_completed_node_cannot_replace_live_state() -> void:
	var runtime := _runtime(Fixture.definition())
	if runtime == null: return
	runtime.request_production("meal")
	runtime.step(0.1)
	var original: Dictionary = runtime.snapshot()
	var broken: Dictionary = original.duplicate(true)
	broken.units[0].done.append("merge")
	check(not runtime.restore(broken).is_empty(), "a completed node needs a committed machine run")
	check_eq(runtime.snapshot(), original, "bad graph facts cannot mutate actors or stock")
	var changed := Fixture.definition()
	changed.recipes.meal.nodes[1].seconds = 3.0
	var other := _runtime(changed)
	var before: Dictionary = other.snapshot()
	check(not other.restore(original).is_empty(), "a new graph signature requires explicit content migration")
	check_eq(other.snapshot(), before, "incompatible state does not start an old executor")

func test_two_identical_recipe_steps_cannot_restore_using_the_same_machine_commit() -> void:
	var template := Fixture.linear()
	template.recipes.drink.nodes[1].produces = {"raw_a":1}
	var second: Dictionary = template.recipes.drink.nodes[1].duplicate(true)
	second.id = "second"
	second.inputs = {"raw_a":"drink"}
	template.recipes.drink.nodes.append(second)
	template.recipes.drink.output = {"node":"second","item":"raw_a","count":1}
	var runtime := _runtime(template)
	if runtime == null: return
	var request: Dictionary = runtime.request_production("drink")
	for tick in 600:
		runtime.step(0.1)
		if "drink" in runtime.unit(request.id).done: break
	var before: Dictionary = runtime.snapshot()
	check("drink" in before.units[0].done and "second" not in before.units[0].done, "first identical transform completed")
	var broken: Dictionary = before.duplicate(true)
	broken.units[0].running["second"] = broken.units[0].running.drink
	broken.units[0].done.append("second")
	check(not runtime.restore(broken).is_empty(), "each completed step needs its own committed operation")
	check_eq(runtime.snapshot(), before, "duplicate-commit forgery cannot skip a recipe step")

func test_machine_modifier_changes_the_actual_template_operation_duration() -> void:
	var runtime := _runtime(Fixture.linear())
	if runtime == null: return
	runtime.runner.owner.apply_effect("event", "template_machine_speed", SpecEffect.make("speed", "mul", 2.0, "a"))
	runtime.request_production("drink")
	for tick in 200:
		runtime.step(0.1)
		if not runtime.runner.machines.snapshot().runs.is_empty(): break
	check_eq(runtime.runner.machines.snapshot().runs[0].duration, 1.0, "template device consumes its shared upgrade modifiers even before formal scene integration")

func test_fixed_recipe_step_ignores_machine_speed_but_keeps_employee_work_rate() -> void:
	var template := Fixture.linear()
	template.recipes.drink.nodes[1].fixed = true
	var runtime := _runtime(template)
	if runtime == null: return
	check_eq(runtime.last_error, "", "fixed timing is an explicit public recipe capability")
	if not runtime.last_error.is_empty(): return
	runtime.runner.owner.apply_effect("event", "template_machine_speed", SpecEffect.make("speed", "mul", 2.0, "a"))
	runtime.runner.owner.apply_effect("event", "template_work_rate", SpecEffect.make("work", "mul", 2.0))
	runtime.request_production("drink")
	for tick in 200:
		runtime.step(0.1)
		if not runtime.runner.machines.snapshot().runs.is_empty() and runtime.runner.machines.snapshot().runs[0].operator > 0: break
	var run: Dictionary = runtime.runner.machines.snapshot().runs[0]
	check_eq(run.duration, 2.0, "fixed recipe duration ignores the machine speed upgrade")
	check_eq(run.operator_rate, 2.0, "global employee work modifier still applies")
