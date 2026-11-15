extends "res://tests/test_case.gd"
## Candidate tests use a short real order, not the historical long-session save.
## Observer tests hold that state and control only its observation clock; they
## test debounce/pause semantics, not a claim that normal dispatch stays idle.
const Hint := preload("res://game/rules/template/staff_operation_hint.gd")
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
const Fixture := preload("res://tests/fixtures/template_service.gd")
const Runtime := preload("res://game/rules/template/runtime.gd")

func _rules(request := true, mobile := 2) -> ShopRules:
	var rules := ShopRules.new(TEA,42)
	rules.gold = 1000000
	for id in ["lemonade","boil","seal","mix","press","topping"]: check_eq(rules.unlock(id),"","prepare real station")
	for id in ["tea_leaf","milk"]: check_eq(rules.unlock_box(id),"","prepare real material")
	for unused in mobile:
		check_eq(rules.hire(),"","recruit")
		for worker in rules.roster:
			if not worker.deployed: check_eq(rules.deploy_worker(worker.id),"","deploy")
	check_eq(rules.runtime.set_service_open(false),"","stop unrelated future arrivals")
	if request: check_eq(rules.runtime.arrive([{"dish":"black_tea","qty":1}]).error,"","real accepted drink request")
	return rules

func _waiting() -> ShopRules:
	var rules := _rules()
	for tick in 600:
		rules.step(0.1)
		if not Hint.candidates(rules.runtime).is_empty(): return rules
	check(false,"real shared replenishment reaches a staff-waiting shortage")
	return rules

func _is_hint(view: ShopView) -> bool:
	return view.bottleneck().get("key", "") == "hint_fixed_post"

func test_real_shortage_wait_requires_duration_and_is_read_only_without_full_queue() -> void:
	var rules := _waiting()
	var view := ShopView.new(rules)
	check(rules.full_seconds < ShopView.HINT_AFTER,"candidate does not require a full queue")
	var before := rules.to_dict()
	var random_before := rules.rng.state
	view.observe_bottlenecks()
	check(not _is_hint(view),"ordinary short wait is not a bottleneck warning")
	check_eq(rules.to_dict(),before,"observation does not mutate rules or dispatch")
	check_eq(rules.rng.state,random_before,"observation consumes no RNG")
	var first := rules.clock
	rules.clock = first + ShopView.HINT_AFTER - 0.1
	view.observe_bottlenecks()
	check(not _is_hint(view),"threshold is not reached early")
	rules.clock = first + ShopView.HINT_AFTER
	view.observe_bottlenecks()
	var hint := view.bottleneck()
	check(_is_hint(view),"continuous observed shortage reaches threshold")
	check_eq(hint.get("target"),"boil","real machine is highlighted")
	check_eq(hint.get("navigate"),"staff","advice opens staffing rather than selling an upgrade")
	check_eq(hint.get("quiet"),true,"low-interference warning does not auto-toast")
	check(String(hint.get("text","")).contains("保留流动"),"advice preserves transport staff")
	hint.clear()
	check(_is_hint(view),"returned hint is detached")

func test_pause_recovery_new_episode_and_runtime_restore_reset_the_observer() -> void:
	var rules := _waiting()
	var view := ShopView.new(rules)
	view.observe_bottlenecks()
	rules.paused = true
	for unused in 100:
		rules.step(0.1)
		view.observe_bottlenecks()
	rules.paused = false
	check(not _is_hint(view),"repeated paused frames do not age the wait")
	var checkpoint := rules.to_dict()
	rules.clock += ShopView.HINT_AFTER
	view.observe_bottlenecks()
	check(_is_hint(view),"controlled uninterrupted episode matures")
	# A real rule restore replaces the runtime: same machine identity cannot
	# inherit an old UI wait, even if it is still blocked.
	check_eq(rules.load_dict(checkpoint),"","checkpoint restores")
	view.observe_bottlenecks()
	check(not _is_hint(view),"restore starts fresh observation")
	var candidate: Dictionary = Hint.candidates(rules.runtime)[0]
	# Actual dispatch and work progression remove the condition, without
	# requiring the queue to empty or the player to dismiss a warning.
	var recovered := false
	for tick in 600:
		rules.step(0.1)
		view.observe_bottlenecks()
		if Hint.candidates(rules.runtime).is_empty(): recovered = true; break
	check(recovered,"real operation resumes")
	check(not _is_hint(view),"recovery immediately removes this advice")
	check(view._operation_wait.is_empty(),"recovery clears debounce history")
	check(not candidate.is_empty(),"recovery started from an actual candidate")

func test_no_order_and_early_staff_shortage_never_suggest_fixing_the_only_carrier() -> void:
	var reserve := _rules(false)
	var saw_wait := false
	for tick in 150:
		reserve.step(0.1)
		for run in reserve.runtime.runner.machines.active_snapshot().runs:
			if run.machine=="boil" and String(run.phase).begins_with("await_"): saw_wait = true
		check(Hint.candidates(reserve.runtime).is_empty(),"reserve replenishment without consumer demand is not a bottleneck")
	check(saw_wait,"negative test actually observed an awaiting reserve batch")
	var rules := _waiting()
	check_eq(rules.recall_worker(3),"","remove one of two eligible mobile workers")
	check(Hint.candidates(rules.runtime).is_empty(),"sole mobile operator must remain available to transport")
	check_eq(rules.recall_worker(2),"","remove last mobile employee")
	check(Hint.candidates(rules.runtime).is_empty(),"no kitchen employee needs recruitment, not fixed-post advice")

func test_fixed_holder_and_active_cooking_suppress_the_recommendation() -> void:
	var rules := _waiting()
	check_eq(rules.hire(),"","add a third mobile worker to isolate the occupied-post guard")
	for worker in rules.roster:
		if not worker.deployed: check_eq(rules.deploy_worker(worker.id),"","deploy extra mobile worker")
	check_eq(rules.place_worker(2,"boil"),"","player can choose fixed assignment")
	check(Hint.candidates(rules.runtime).is_empty(),"already staffed post needs no repeated recommendation")
	var cooking := _rules()
	var found := false
	for tick in 1000:
		cooking.step(0.1)
		if cooking.runtime.runner.machines.status("boil").get("phase","")=="processing":
			found = true
			check(Hint.candidates(cooking.runtime).is_empty(),"normal automatic cooking is not employee waiting")
			break
	check(found,"negative test reaches real automatic cooking")

func test_generic_machine_identity_and_owned_order_run_use_shared_capabilities() -> void:
	var owner := Fixture.owner()
	owner.gold = 1000000
	for id in ["lemonade","boil","seal","mix","press","topping"]: check_eq(owner.unlock(id),"","prepare fixture post")
	var template := Fixture.definition()
	template.dispatch = {"roles":{"staff":{"operate":["a"],"transfer_from":["*"],"transfer_to":["*"]}},
		"posts":{"boil":{"operate":["a"],"transfer_from":["*"],"transfer_to":["*"]}},
		"station_posts":{"a":{"post":"boil","feed":true}}}
	var runtime := Runtime.new(owner,template)
	check_eq(runtime.last_error,"","generic service composes")
	check_eq(runtime.arrive([{"dish":"lemonade","qty":1}]).error,"","generic order accepted")
	var run := {}
	for tick in 1000:
		check_eq(runtime.step(0.1),"","generic operation advances")
		for current in runtime.runner.machines.active_snapshot().runs:
			if current.machine=="a" and current.phase=="operate": run = current
		if not run.is_empty(): break
	check(not run.is_empty(),"owned production run exists")
	if run.is_empty(): return
	check_eq(runtime.runner.cancel(run.operator),"","ordinary cancellation releases the operator")
	var hints := Hint.candidates(runtime)
	check_eq(hints.size(),1,"generic owned production yields one candidate")
	if not hints.is_empty():
		check_eq(hints[0].target,"a","machine identity is not hardcoded to the tea pot")
		check_eq(hints[0].post,"boil","post comes from declarative station binding")
	runtime._definition.dispatch.station_posts.clear()
	check(Hint.candidates(runtime).is_empty(),"machine without a fixed-post capability is never recommended")

func test_available_output_removes_the_shortage_even_while_batch_waits() -> void:
	var rules := _waiting()
	var candidate: Dictionary = Hint.candidates(rules.runtime)[0]
	var stock: RefCounted = rules.runtime.runner.inventory
	var run: Dictionary = rules.runtime.runner.machines.run(candidate.run)
	var claim: Dictionary = stock.claim(run.claim)
	for item in claim.produces:
		check_eq(stock.seed(claim.to, item, int(claim.produces[item])).error,"","supply actual physical shared stock")
	check(String(rules.runtime.runner.machines.run(candidate.run).phase).begins_with("await_"),"batch still awaits staff")
	check(Hint.candidates(rules.runtime).is_empty(),"available output means this waiting batch is not blocking the consumer")

## End an observed shortage with a legal fixed assignment, then return that
## worker to mobile duty. This leaves the same real batch waiting so separate
## episodes can exercise repeated-key history without manufacturing a new run.
func _observe_gap(rules: ShopRules, view: ShopView, at: float) -> void:
	rules.clock = at
	check_eq(rules.place_worker(3,"boil"),"","temporarily cover the operation post")
	view.observe_bottlenecks()
	check(not _is_hint(view),"recovery hides advice immediately despite recent history")
	check_eq(rules.place_worker(3,""),"","return operator to floating duty")

func test_repeated_wait_needs_three_episodes_and_current_wait_then_expires() -> void:
	var rules := _waiting()
	var view := ShopView.new(rules)
	var start := rules.clock
	view.observe_bottlenecks()
	# First two waits each last nine seconds. Neither a brief pause nor merely
	# two recurrent shortages is sufficient for fixed-staff advice.
	rules.clock = start + 9.0
	view.observe_bottlenecks()
	check(not _is_hint(view),"one subthreshold episode stays quiet")
	_observe_gap(rules,view,start+9.1)
	rules.clock = start + 10.0
	view.observe_bottlenecks()
	rules.clock = start + 19.0
	view.observe_bottlenecks()
	check(not _is_hint(view),"two episodes stay quiet")
	var first_end: float = view._operation_recent.boil[0].end
	check(is_equal_approx(first_end,start+9.0),"a reused candidate key does not lengthen an earlier episode")
	_observe_gap(rules,view,start+19.1)
	rules.clock = start + 20.0
	view.observe_bottlenecks()
	rules.clock = start + 22.9
	view.observe_bottlenecks()
	check(not _is_hint(view),"total above twenty seconds still needs three current seconds")
	rules.clock = start + 23.0
	view.observe_bottlenecks()
	check(_is_hint(view),"three nonoverlapping episodes and sufficient current/total wait yield advice")
	check_eq(view._operation_recent.boil.size(),3,"history contains episodes rather than per-frame samples")
	_observe_gap(rules,view,start+23.1)
	rules.clock = start + 84.0
	# Observe while fixed so pruning is tested independently of a new episode.
	check_eq(rules.place_worker(3,"boil"),"","hold recovery past the window")
	view.observe_bottlenecks()
	check(view._operation_recent.is_empty(),"sixty-second window discards old episodes")
	check_eq(rules.place_worker(3,""),"","start a genuinely new wait")
	view.observe_bottlenecks()
	rules.clock = start + 87.0
	view.observe_bottlenecks()
	check(not _is_hint(view),"expired episodes cannot immediately retrigger advice")

func test_two_long_episodes_do_not_meet_repeated_wait_count() -> void:
	var rules := _waiting()
	var view := ShopView.new(rules)
	var start := rules.clock
	view.observe_bottlenecks()
	rules.clock = start + 11.0
	view.observe_bottlenecks()
	_observe_gap(rules,view,start+11.1)
	rules.clock = start + 12.0
	view.observe_bottlenecks()
	rules.clock = start + 23.0
	view.observe_bottlenecks()
	check(not _is_hint(view),"twenty-two cumulative seconds in only two episodes are insufficient")
	check_eq(view._operation_recent.boil.size(),2,"same batch key gets distinct episode records")

func test_overlapping_slot_waits_count_elapsed_time_once() -> void:
	var rules := _waiting()
	var view := ShopView.new(rules)
	var start := rules.clock
	view.observe_bottlenecks()
	var candidate: Dictionary = Hint.candidates(rules.runtime)[0]
	var key := "%s:%d:%s:%d" % [candidate.target,candidate.run,candidate.phase,candidate.stir_index]
	# A synthetic historical observation window isolates the interval-union
	# rule: two simultaneous slots waited ten seconds, not twenty seconds.
	view._operation_wait[key] = start + 27.0
	view._operation_recent[candidate.target] = [
		{"key":"prior-slot-a","start":start,"end":start+10.0},
		{"key":"prior-slot-b","start":start,"end":start+10.0},
		{"key":"prior-episode","start":start+12.0,"end":start+17.0},
		{"key":key,"start":start+27.0,"end":start+27.0}]
	rules.clock = start + 30.0
	view.observe_bottlenecks()
	check(not _is_hint(view),"overlapping slots give eighteen real seconds, not twenty-eight")
	rules.clock = start + 32.0
	view.observe_bottlenecks()
	check(_is_hint(view),"union duration reaches twenty seconds across three separated episodes")
