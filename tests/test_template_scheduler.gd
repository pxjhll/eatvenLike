extends "res://tests/test_case.gd"
const Fixture := preload("res://tests/fixtures/template_service.gd")
const Production := preload("res://tests/fixtures/template_shop.gd")
const Runtime := preload("res://game/rules/template/runtime.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")

func _runtime(template: Resource) -> RefCounted:
	var runtime := Runtime.new(Fixture.owner(), template)
	check(runtime.has_method("candidates_for"), "production, service and replenishment must use one ranked candidate pool")
	if not runtime.has_method("candidates_for"): return null
	check_eq(runtime.last_error, "", "strict shared scheduling definition")
	return runtime if runtime.last_error.is_empty() else null

func test_configured_priority_selects_real_production_or_admission_from_the_same_pool() -> void:
	for admit_first in [false, true]:
		var template := Fixture.definition("counter", "employee")
		template.dispatch = {"scores":{"admit":1000.0 if admit_first else 0.0, "transfer":0.0 if admit_first else 1000.0}}
		var runtime := _runtime(template)
		if runtime == null: return
		for worker in runtime.runner.owner.workers: worker.deployed = false
		runtime.request_production("drink")
		runtime.arrive([{"dish":"lemonade", "qty":1}])
		for tick in 100:
			runtime.step(0.1)
			if runtime.service.customers.ready(1, "queue:0"): break
		check(runtime.service.customers.ready(1, "queue:0"), "actual customer arrival")
		var worker: Dictionary = runtime.runner.owner.workers[0]
		worker.deployed = true
		var candidates: Array = runtime.candidates_for(worker.id)
		var kinds: Array = []
		for candidate in candidates: kinds.append(String(candidate.kind))
		check("interact" in kinds and "transfer" in kinds, "both service and production are in the same real pool")
		runtime.step(0.1)
		check_eq(runtime.runner.tasks[worker.id].kind, "interact" if admit_first else "transfer", "configured score determines actual assignment")

func test_equal_scores_are_stable_and_querying_candidates_cannot_change_authoritative_state() -> void:
	var runtime := _runtime(Production.linear())
	if runtime == null: return
	var first: Dictionary = runtime.request_production("drink")
	runtime.request_production("drink")
	var before: Dictionary = runtime.snapshot()
	var candidates: Array = runtime.candidates_for(runtime.runner.owner.workers[0].id)
	check_eq(candidates[0].unit, first.id, "equal scores preserve original demand order")
	check_eq(runtime.candidates_for(runtime.runner.owner.workers[0].id), candidates, "same facts give same ordering without RNG")
	candidates[0].count = 999
	check_eq(runtime.snapshot(), before, "detached candidate query cannot mutate demand or reservations")

func test_route_cost_can_prioritize_nearby_work_and_does_not_choose_unreachable_work() -> void:
	for unreachable in [false, true]:
		var template := Production.linear()
		template.places["far"] = {"port":Vector2(3000,3000) if unreachable else Vector2(900,100), "infinite":["raw_a"]}
		var recipe: Dictionary = template.recipes.drink.duplicate(true)
		recipe.nodes[0].place = "far"
		template.recipes["far_drink"] = recipe
		template.dispatch = {"travel_penalty":1.0}
		var runtime := _runtime(template)
		if runtime == null: return
		runtime.runner.owner.workers[0].pos = Vector2(100,100)
		runtime.request_production("far_drink")
		var near: Dictionary = runtime.request_production("drink")
		var candidates: Array = runtime.candidates_for(runtime.runner.owner.workers[0].id)
		check_eq(candidates[0].unit, near.id, "actual route cost favors nearby reachable source")
		if unreachable: check_eq(candidates.size(), 1, "unreachable candidate cannot trap the scheduler or cause remote pickup")

func test_continuation_bonus_prefers_existing_work_over_starting_another_order() -> void:
	var template := Production.definition()
	template.dispatch = {"scores":{"operate":0.0, "transfer":100.0}, "continuation_bonus":500.0}
	var runtime := _runtime(template)
	if runtime == null: return
	var first: Dictionary = runtime.request_production("meal")
	for tick in 200:
		runtime.step(0.1)
		if not runtime.unit(first.id).done.is_empty(): break
	check(not runtime.unit(first.id).done.is_empty(), "first production unit has real completed work")
	for worker in runtime.runner.owner.workers: runtime.runner.cancel(worker.id)
	runtime.request_production("meal")
	var candidates: Array = runtime.candidates_for(runtime.runner.owner.workers[0].id)
	check_eq(candidates[0].unit, first.id, "continuation score uses actual completed production nodes")

func test_invalid_score_keys_nonfinite_costs_and_callbacks_are_rejected() -> void:
	var runtime := _runtime(Production.linear())
	if runtime == null: return
	for policy in [{"scores":{"private_shop":100.0}}, {"travel_penalty":-1.0},
		{"continuation_bonus":NAN}, {"scores":{"operate":"fast"}}, {"rank_callback":"custom"}]:
		var template := Production.linear()
		template.dispatch = policy
		check(not Compiler.compile(template).errors.is_empty(), "unsupported or invalid scheduling policy cannot be ignored")
