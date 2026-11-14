extends "res://tests/test_case.gd"
const Fixture := preload("res://tests/fixtures/template_service.gd")
const Runtime := preload("res://game/rules/template/runtime.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")
const SAMPLING := "res://game/rules/rule_sampling.gd"

func _policy(pattern := "fixed") -> Dictionary:
	return {"pattern":pattern, "interval":4.0, "first_delay":1.0, "opening":0,
		"choices":[{"weight":3.0, "request":[{"dish":"lemonade", "qty":1}]},
			{"weight":1.0, "request":Fixture.request()}]}

func _runtime(delivery := "counter", pattern := "fixed", policy: Dictionary = {}) -> RefCounted:
	var template := Fixture.definition(delivery)
	template.service["arrivals"] = _policy(pattern) if policy.is_empty() else policy
	var runtime := Runtime.new(Fixture.owner(), template)
	check_eq(runtime.last_error, "", "common service compiles public arrival policy")
	return runtime if runtime.last_error.is_empty() else null

func _outer_copy(source: RefCounted, destination: RefCounted) -> void:
	for key in ["gold", "revenue", "sold", "sale_carry"]: destination._sales.set(key, source._sales.get(key))
	destination.sold_by_dish = source.sold_by_dish.duplicate(true)
	destination.rng.seed = source.rng.seed
	destination.rng.state = source.rng.state

func test_sampling_keeps_fixed_arrivals_rng_free_and_matches_existing_exponential_and_weighted_draw_order() -> void:
	check(ResourceLoader.exists(SAMPLING), "old and template arrivals must share public random sampling arithmetic")
	if not ResourceLoader.exists(SAMPLING): return
	var sampler: Script = load(SAMPLING)
	var actual := RandomNumberGenerator.new()
	var expected := RandomNumberGenerator.new()
	actual.seed = 42
	expected.seed = 42
	check_eq(sampler.interval("fixed", 4.0, actual), 4.0, "fixed interval")
	check_eq(actual.state, expected.state, "fixed interval uses no random draw")
	var weights := {"a":3.0, "b":1.0}
	for index in 20:
		var delay := -log(1.0 - expected.randf() * 0.999) * 4.0
		check_eq(sampler.interval("exponential", 4.0, actual), delay, "same legacy exponential formula")
		var choice := "a" if expected.randf() * 4.0 <= 3.0 else "b"
		check_eq(sampler.choose(weights, actual), choice, "weighted draw follows interval draw")
	check_eq(actual.state, expected.state, "same exact RNG consumption")

func test_closed_service_and_pause_freeze_arrival_timer_then_first_delay_and_fixed_schedule_run() -> void:
	var runtime := _runtime()
	if runtime == null: return
	var before: Dictionary = runtime.service.arrivals.snapshot()
	var state: int = runtime.runner.owner.rng.state
	runtime.step(5.0)
	check_eq(runtime.service.arrivals.snapshot(), before, "closed service does not advance arrivals")
	check_eq(runtime.runner.owner.rng.state, state, "closed service consumes no random draws")
	check_eq(runtime.set_service_open(true), "", "opening enables arrivals")
	before = runtime.snapshot()
	runtime.step(100.0, true)
	check_eq(runtime.snapshot(), before, "pause includes the entire arrival scheduler")
	for tick in 9: runtime.step(0.1)
	check_eq(runtime.frame().guests.size(), 0, "first customer waits full first delay")
	runtime.step(0.1)
	check_eq(runtime.frame().guests.size(), 1, "first automatic customer")
	check_eq(runtime.service.arrivals.snapshot().attempts, 1, "one attempt recorded")
	for tick in 40: runtime.step(0.1)
	check_eq(runtime.service.arrivals.snapshot().attempts, 2, "fixed interval produces the next attempt")

func test_opening_wave_runs_once_and_full_queue_counts_lost_without_drawing_an_unused_menu() -> void:
	var policy := _policy()
	policy.opening = 3
	var runtime := _runtime("counter", "fixed", policy)
	if runtime == null: return
	var expected := RandomNumberGenerator.new()
	expected.seed = runtime.runner.owner.rng.seed
	expected.state = runtime.runner.owner.rng.state
	expected.randf()
	expected.randf()
	check_eq(runtime.set_service_open(true), "", "opening wave")
	check_eq(runtime.frame().guests.size(), 2, "two authored queue ports")
	check_eq(runtime.frame().lost, 1, "third opening customer rejected exactly once")
	check_eq(runtime.runner.owner.rng.state, expected.state, "rejected arrival does not sample an unused menu")
	runtime.set_service_open(true)
	check_eq(runtime.frame().lost, 1, "repeated opening cannot replay wave")
	runtime.set_service_open(false)
	runtime.set_service_open(true)
	check_eq(runtime.service.arrivals.snapshot().attempts, 3, "reopening does not replay initial arrivals")

func test_shared_flow_upgrade_changes_the_next_real_arrival_interval() -> void:
	var runtime := _runtime()
	if runtime == null: return
	runtime.runner.owner.apply_effect("event", "template_arrival_flow", SpecEffect.make("flow", "mul", 2.0))
	runtime.set_service_open(true)
	for tick in 10: runtime.step(0.1)
	check(absf(float(runtime.service.arrivals.snapshot().left) - 2.0) < 0.000001, "flow upgrade halves the next effective interval")
	for tick in 20: runtime.step(0.1)
	check_eq(runtime.service.arrivals.snapshot().attempts, 2, "second real attempt uses upgraded interval")

func test_fixed_and_random_arrivals_restore_with_outer_rng_without_duplicating_wallet_or_random_state() -> void:
	for pattern in ["fixed", "exponential"]:
		var runtime := _runtime("table", pattern)
		if runtime == null: return
		runtime.set_service_open(true)
		for tick in 137: runtime.step(0.1)
		var saved: Dictionary = runtime.snapshot()
		check(not saved.service.arrivals.has("rng"), "shared outer RNG is persisted once by session")
		var reopened := _runtime("table", pattern)
		_outer_copy(runtime.runner.owner, reopened.runner.owner)
		check_eq(reopened.restore(saved), "", "restore arrival clock and service atomically")
		for tick in 400:
			check_eq(runtime.step(0.1), "", "continue original arrival stream")
			check_eq(reopened.step(0.1), "", "continue restored arrival stream")
		check_eq(reopened.snapshot(), runtime.snapshot(), "same customers, requests, timing, and physical production")
		check_eq(reopened.runner.owner.rng.state, runtime.runner.owner.rng.state, "same subsequent RNG draws")
		check_eq(reopened.runner.owner.gold, runtime.runner.owner.gold, "same receipts")

func test_invalid_arrival_definition_or_clock_restore_is_rejected_without_adopting_actors() -> void:
	var valid := _runtime()
	if valid == null: return
	for patch in [{"pattern":"custom_shop"}, {"interval":0.0}, {"opening":-1}, {"callback":"spawn"},
		{"choices":[{"weight":1.0, "request":[{"dish":"missing", "qty":1}]}]}]:
		var template := Fixture.definition()
		var policy := _policy()
		for key in patch: policy[key] = patch[key]
		template.service["arrivals"] = policy
		check(not Compiler.compile(template).errors.is_empty(), "invalid arrival capability is explicit")
	valid.set_service_open(true)
	for tick in 20: valid.step(0.1)
	var before: Dictionary = valid.snapshot()
	var broken: Dictionary = before.duplicate(true)
	broken.service.arrivals.left = NAN
	check(not valid.restore(broken).is_empty(), "invalid arrival clock cannot replace service")
	check_eq(valid.snapshot(), before, "failed adoption leaves all actors and clocks intact")

func test_disabled_arrival_capability_never_draws_rng_or_automatically_generates_customers() -> void:
	var runtime := Fixture.runtime()
	var before: int = runtime.runner.owner.rng.state
	for tick in 100: runtime.step(0.1)
	check_eq(runtime.frame().guests, [], "unconfigured template keeps explicit arrivals")
	check_eq(runtime.runner.owner.rng.state, before, "unconfigured capability consumes no random numbers")
