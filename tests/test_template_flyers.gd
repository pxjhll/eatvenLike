extends "res://tests/test_case.gd"
const Runtime := preload("res://game/rules/template/runtime.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")
const Fixture := preload("res://tests/fixtures/template_service.gd")

func _definition(pattern := "gap", delivery := "counter", full := "lost") -> Resource:
	var template := Fixture.definition(delivery)
	template.service["arrivals"] = {"pattern":"fixed","interval":10000.0,"first_delay":10000.0,
		"choices":[{"weight":1.0,"request":[{"dish":"lemonade","qty":1}]}]}
	template.service["flyers"] = {"pattern":pattern,"count":3,"cooldown":2.0,"when_full":full}
	if pattern == "gap": template.service.flyers.gap = 3.0
	else: template.service.flyers.seconds = 3.0
	return template

func _owner() -> ShopRules:
	var owner := Fixture.owner()
	owner.apply_effect("event","flyer_count",SpecEffect.make("flyer_customers","set",3.0))
	owner.apply_effect("event","flyer_cooldown",SpecEffect.make("flyer_cooldown","set",2.0))
	return owner

func _runtime(template: Resource) -> RefCounted:
	var runtime := Runtime.new(_owner(),template)
	check_eq(runtime.last_error,"","flyer clock composes with the common service")
	return runtime if runtime.last_error.is_empty() else null

func _advance(runtime: RefCounted, ticks: int) -> void:
	for tick in ticks: check_eq(runtime.step(0.1),"","advance actual flyer/customer service")

func test_gap_wave_uses_immediate_first_attempt_and_three_second_spacing_without_resetting_ordinary_arrivals() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	check_eq(runtime.set_service_open(true),"","open")
	var before_rng: int = runtime.runner.owner.rng.state
	check_eq(runtime.send_flyers(),"","send is a public free command")
	check_eq(runtime.runner.owner.rng.state,before_rng,"issuing flyers does not sample customer choices")
	check_eq(runtime.service.orders.snapshot().guests.size(),0,"first guest comes on next simulation tick")
	_advance(runtime,1)
	check_eq(runtime.service.orders.snapshot().guests.size(),1,"first staggered guest")
	_advance(runtime,29)
	check_eq(runtime.service.orders.snapshot().guests.size(),1,"not yet the next three-second attempt")
	_advance(runtime,1)
	check_eq(runtime.service.orders.snapshot().guests.size(),2,"second scheduled guest")
	_advance(runtime,30)
	check_eq(runtime.service.orders.snapshot().guests.size(),3,"third scheduled guest uses the same request/production path")
	check_eq(runtime.service.arrivals.snapshot().attempts,0,"flyers do not advance ordinary attempt counter")
	check(absf(runtime.service.arrivals.snapshot().left-9993.9)<0.000001,"ordinary clock was not reset")
	check_eq(runtime.runner.owner.flyer_left,0,"new clock never writes the legacy flyer execution state")

func test_full_queue_lost_policy_consumes_attempt_without_drawing_unused_menu_rng() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	for index in 2: runtime.arrive([{"dish":"lemonade","qty":1}])
	runtime.set_service_open(true)
	runtime.send_flyers()
	var rng_before: int = runtime.runner.owner.rng.state
	_advance(runtime,1)
	check_eq(runtime.service.orders.snapshot().lost,1,"full queue records exactly one lost flyer visitor")
	check_eq(runtime.frame().flyers.pending,2,"lost visitor consumes one scheduled visitor")
	check_eq(runtime.runner.owner.rng.state,rng_before,"no menu draw for a rejected visitor")

func test_spread_wave_waits_outside_full_queue_and_retries_when_space_really_opens() -> void:
	var runtime := _runtime(_definition("spread","counter","wait_outside"))
	if runtime == null: return
	for index in 2: runtime.arrive([{"dish":"lemonade","qty":1}])
	runtime.set_service_open(true)
	runtime.send_flyers()
	var rng_before: int = runtime.runner.owner.rng.state
	_advance(runtime,10)
	check_eq(runtime.frame().flyers.pending,3,"blocked wave remains outside")
	check_eq(runtime.service.orders.snapshot().lost,0,"waiting outside is not a lost order")
	check_eq(runtime.runner.owner.rng.state,rng_before,"outside visitor has no premature menu choice")
	_advance(runtime,40)
	check(runtime.frame().flyers.pending<3,"admission of queued guests eventually frees a real place")
	check_eq(runtime.service.orders.snapshot().lost,0,"retry does not double count a rejection")

func test_cooldown_and_spread_wave_gate_preserve_old_command_semantics() -> void:
	for pattern in ["gap","spread"]:
		var runtime := _runtime(_definition(pattern))
		if runtime == null: return
		check(not runtime.send_flyers().is_empty(),"closed service cannot send flyers")
		runtime.set_service_open(true)
		check_eq(runtime.send_flyers(),"","first wave")
		var before: Dictionary = runtime.snapshot()
		check(not runtime.send_flyers().is_empty(),"immediate duplicate is rejected")
		check_eq(runtime.snapshot(),before,"rejected command does not change wave or clocks")
		_advance(runtime,20)
		if pattern == "spread":
			check(not runtime.send_flyers().is_empty(),"spread wave remains active after cooldown ends")
			_advance(runtime,10)
		check_eq(runtime.send_flyers(),"","new wave after the policy's real gates clear")

func test_pause_freezes_every_flyer_clock_and_closure_preserves_pending_visitors() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	runtime.set_service_open(true)
	runtime.send_flyers()
	var before: Dictionary = runtime.snapshot()
	runtime.step(20.0,true)
	check_eq(runtime.snapshot(),before,"pause freezes cooldown and cadence")
	runtime.set_service_open(false)
	_advance(runtime,30)
	check_eq(runtime.frame().flyers.pending,3,"closed service holds all pending visitors")
	check_eq(runtime.frame().flyers.cooldown,0.0,"cooldown still passes with unpaused simulation time")
	runtime.set_service_open(true)
	_advance(runtime,1)
	check_eq(runtime.service.orders.snapshot().guests.size(),1,"reopen continues the existing wave once")

func test_shared_upgrade_changes_future_wave_size_but_not_committed_pending_count_or_cooldown() -> void:
	var template := _definition("spread")
	template.service.flyers.seconds = 6.0
	var runtime := _runtime(template)
	if runtime == null: return
	runtime.set_service_open(true)
	runtime.send_flyers()
	_advance(runtime,10)
	check_eq(runtime.frame().flyers.pending,3,"initial period is six seconds divided by three")
	runtime.runner.owner.apply_effect("event","flyer_count",SpecEffect.make("flyer_customers","set",6.0))
	runtime.runner.owner.apply_effect("event","flyer_cooldown",SpecEffect.make("flyer_cooldown","set",50.0))
	_advance(runtime,1)
	check_eq(runtime.frame().flyers.pending,2,"live upgraded spread cadence releases an existing visitor, does not append three new ones")
	check(absf(runtime.frame().flyers.cooldown-0.9)<0.000001,"old committed cooldown is not extended by upgrade")

func test_mid_wave_restore_keeps_rng_payment_and_pending_events_identical_in_two_combinations() -> void:
	for combination in [["gap","counter"],["spread","counter"],["spread","table"]]:
		var template := _definition(combination[0],combination[1],"wait_outside")
		var runtime := _runtime(template)
		if runtime == null: return
		runtime.set_service_open(true)
		runtime.send_flyers()
		_advance(runtime,13)
		var reopened := _runtime(template)
		if reopened == null: return
		for key in ["gold","revenue","sold","sale_carry"]: reopened.runner.owner._sales.set(key,runtime.runner.owner._sales.get(key))
		reopened.runner.owner.sold_by_dish = runtime.runner.owner.sold_by_dish.duplicate(true)
		reopened.runner.owner.rng.state = runtime.runner.owner.rng.state
		check_eq(reopened.restore(runtime.snapshot()),"","restore wave with actual pending customer work")
		for tick in 400:
			check_eq(runtime.step(0.1),"","continue wave")
			check_eq(reopened.step(0.1),"","continue restored wave")
		check_eq(reopened.snapshot(),runtime.snapshot(),"same guests, items and event schedule")
		check_eq(reopened.runner.owner.rng.state,runtime.runner.owner.rng.state,"same future randomness")
		check_eq(reopened.runner.owner.revenue,runtime.runner.owner.revenue,"same actual once-only income")

func test_invalid_flyer_values_and_restore_are_rejected_before_live_mutation() -> void:
	for patch in [{"callback":"spawn"},{"gap":0.0},{"pattern":"shop_loop"},{"when_full":"drop_silently"}]:
		var template := _definition()
		for key in patch: template.service.flyers[key] = patch[key]
		check(not Compiler.compile(template).errors.is_empty(),"invalid authored flyer policy")
	var runtime := _runtime(_definition())
	if runtime == null: return
	runtime.set_service_open(true)
	runtime.send_flyers()
	var before: Dictionary = runtime.snapshot()
	for patch in [{"pending":-1},{"elapsed":NAN},{"wave_left":1.0},{"custom":true}]:
		var invalid: Dictionary = before.duplicate(true)
		for key in patch: invalid.service.flyers[key] = patch[key]
		check(not runtime.restore(invalid).is_empty(),"invalid wave cannot be adopted")
		check_eq(runtime.snapshot(),before,"failed restore keeps actors and clocks")
	runtime.runner.owner.apply_effect("event","flyer_count",SpecEffect.make("flyer_customers","set",1.5))
	check(not runtime.step(0.1).is_empty(),"fractional effective visitor count is not truncated silently")
	check_eq(runtime.snapshot(),before,"bad modifier cannot advance clock, actor or wave")

func test_flyer_event_observes_committed_state_and_reentrant_send_cannot_duplicate_wave() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	runtime.set_service_open(true)
	var observed := {"pending":-1,"error":"","restore":""}
	var handler := func(_data: Dictionary) -> void:
		observed.pending = runtime.frame().flyers.pending
		observed.restore = runtime.restore(runtime.snapshot())
		observed.error = runtime.send_flyers()
	runtime.runner.owner.events.on("flyer",handler)
	check_eq(runtime.send_flyers(),"","public flyer event")
	check_eq(observed.pending,3,"event sees already committed wave")
	check_eq(observed.restore,"","event callback may save and adopt the already committed wave")
	check(not observed.error.is_empty(),"cooldown blocks a reentrant duplicate command")
	check_eq(runtime.frame().flyers.pending,3,"only one original wave remains")
	runtime.runner.owner.events.off("flyer",handler)

func test_flyer_attempt_precedes_an_ordinary_arrival_due_on_the_same_tick() -> void:
	var template := _definition()
	template.service.arrivals.first_delay = 0.1
	template.service.arrivals.choices = [{"weight":3.0,"request":[{"dish":"black_tea","qty":1}]},{"weight":1.0,"request":[{"dish":"lemonade","qty":1}]}]
	var runtime := _runtime(template)
	if runtime == null: return
	var expected := RandomNumberGenerator.new()
	expected.state = runtime.runner.owner.rng.state
	var first := "black_tea" if expected.randf()<0.75 else "lemonade"
	var second := "black_tea" if expected.randf()<0.75 else "lemonade"
	runtime.set_service_open(true)
	runtime.send_flyers()
	_advance(runtime,1)
	check_eq(runtime.service.orders.guest(1).request[0].dish,first,"flyer visitor uses first outer RNG choice")
	check_eq(runtime.service.orders.guest(2).request[0].dish,second,"ordinary visitor follows on same tick")
	check_eq(runtime.frame().flyers.pending,2,"one flyer visitor consumed")
	check_eq(runtime.service.arrivals.snapshot().attempts,1,"one independent ordinary attempt")
	check_eq(runtime.runner.owner.rng.state,expected.state,"exactly two menu draws")

func test_flyer_tuning_is_numeric_but_policy_and_disabled_capability_preserve_contracts() -> void:
	var contract := preload("res://game/rules/shop_content_contract.gd")
	var template := _definition()
	var before: Dictionary = contract.describe_template(template)
	template.service.flyers.count = 5
	template.service.flyers.cooldown = 100.0
	template.service.flyers.gap = 2.0
	var tuned: Dictionary = contract.describe_template(template)
	check_eq(tuned.structure,before.structure,"wave population and clocks are balance parameters")
	check(tuned.gameplay!=before.gameplay,"full content identity records tuning")
	template.service.flyers.when_full = "wait_outside"
	check(contract.describe_template(template).structure!=before.structure,"admission policy remains structural")
	template = Fixture.definition()
	var plain: Dictionary = Compiler.compile(template)
	template.service["flyers"] = {}
	check_eq(Compiler.compile(template),plain,"empty optional ability preserves old compiled signature")
