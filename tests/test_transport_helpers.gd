extends "res://tests/test_case.gd"
const LegacyRules := preload("res://tests/fixtures/legacy_shops/reference_rules.gd")
const Fixture := preload("res://tests/fixtures/movement_shop.gd")
const Flow := preload("res://game/rules/serve_flow.gd")
const Schema := preload("res://game/rules/shop_spec_validator.gd")
const Content := preload("res://game/rules/shop_content_contract.gd")

func _definition() -> SpecShop:
	var shop := Fixture.definition()
	shop.fulfillment.flow_version = 1
	shop.dispatch.action_version = 1
	check(shop.dispatch.get("transport_helpers")!=null,"transport assistance is an explicit opt-in dispatch capability")
	if shop.dispatch.get("transport_helpers")==null: return null
	shop.dispatch.transport_helpers.assign(["front"])
	shop.fulfillment.addon_chance = 0.0
	for stage in shop.stages: stage.order_weights = {"tomato_rice":1.0}
	return shop

func _opened(shop: SpecShop) -> ShopRules:
	var rules := LegacyRules.new(shop,42)
	rules.unlock("wok_a")
	return rules

func test_transport_assistance_is_explicit_and_rejects_unsupported_protocols_and_roles() -> void:
	var shop := _definition()
	if shop==null: return
	check_eq(Schema.validate(shop),[],"front assistance is supported by shared serve actions")
	for invalid in ["flow","actions","zones","duplicate","role","single"]:
		var bad := shop.copy_for_editing()
		match invalid:
			"flow": bad.fulfillment.flow_version = 0
			"actions": bad.dispatch.action_version = 0
			"zones": bad.staff.zones.clear()
			"duplicate": bad.dispatch.transport_helpers.assign(["front","front"])
			"role": bad.dispatch.transport_helpers.assign(["seated"])
			"single": bad.fulfillment.handoff = "single"
		check(not Schema.validate(bad).is_empty(),"unsupported assistance is rejected: "+invalid)
	for invalid in ["flow","actions"]:
		var bad := shop.copy_for_editing()
		bad.dispatch.transport_helpers.clear()
		bad.dispatch.set("preposition_work",true)
		if invalid=="flow": bad.fulfillment.flow_version = 0
		else: bad.dispatch.action_version = 0
		check(not Schema.validate(bad).is_empty(),"prepositioning alone also requires the supported protocol: "+invalid)

func test_idle_front_assists_real_kitchen_transport_without_cooking_or_stealing_native_work() -> void:
	var shop := _definition()
	if shop==null: return
	var rules := _opened(shop)
	var helped := false
	var violations := {}
	var native_priority := false
	for tick in 2400:
		rules.step(0.1)
		for worker: Dictionary in rules.workers:
			if Flow.role(rules,worker)!="front": continue
			var job := Flow.job_of(rules,worker)
			if job.get("kind","")=="take" and not native_priority:
				# Allocation claims immediately each tick; release one real take
				# to inspect the same ready queue before it is claimed again.
				Flow.cancel(rules,worker)
				var ready := Flow.candidates(rules,worker)
				check(not ready.is_empty() and ready.all(func(row: Dictionary) -> bool: return row.kind=="take"),"ready counter work takes priority over assistance")
				native_priority = true
			if not job.is_empty() and int(job.unit)>=0:
				helped = true
				if job.kind not in ["carry","pass"]: violations[job.kind] = true
			var choices := Flow.candidates(rules,worker)
			if choices.any(func(row: Dictionary) -> bool: return row.kind=="take"):
				native_priority = true
				check(choices.all(func(row: Dictionary) -> bool: return row.kind=="take"),"ready counter work takes priority over assistance")
		if helped and native_priority and rules.sold>=3: break
	check(helped,"front employee actually transports a kitchen order")
	check_eq(violations,{},"helping never gives the front employee kitchen cooking work")
	check(native_priority,"real queued guests exercise native priority")
	check(rules.sold>=3,"cooperative production completes repeated real sales")
	check_eq(LegacyRules.new(shop).load_dict(rules.to_dict()),"","shared reservations remain valid")

func test_helping_carry_restores_exactly_and_recall_returns_the_reserved_object() -> void:
	var shop := _definition()
	if shop==null: return
	var rules := _opened(shop)
	for tick in 2400:
		rules.step(0.1)
		for worker: Dictionary in rules.workers:
			var job := Flow.job_of(rules,worker)
			if Flow.role(rules,worker)!="front" or job.get("kind","") not in ["carry","pass"] or worker.carry_count!=1: continue
			var snapshot := rules.to_dict()
			var clone := LegacyRules.new(shop)
			check_eq(clone.load_dict(snapshot),"","partially carried helper object restores")
			for step in 40:
				rules.step(0.1)
				clone.step(0.1)
			check_eq(clone.to_dict(),rules.to_dict(),"helper has exact independent continuation")
			# Restore the captured partial carry before exercising compensation.
			var recalled := LegacyRules.new(shop)
			check_eq(recalled.load_dict(snapshot),"","partial carry can be recalled independently")
			var id := int(job.good)
			var from := String(job.from)
			var revenue := recalled.revenue
			check_eq(recalled.recall_worker(worker.id),"","helper recall succeeds")
			var good := Flow._good(recalled,id)
			check_eq(good.at,from,"same object returns to its actual source")
			check_eq(good.res,-1,"helper reservation is released")
			check_eq(recalled.revenue,revenue,"recall cannot produce extra income")
			check_eq(LegacyRules.new(shop).load_dict(recalled.to_dict()),"","recalled state remains valid")
			return
	check(false,"captured a real helper carrying a kitchen product")

func test_disabled_helpers_keep_legacy_content_fingerprints_and_front_roles() -> void:
	var shop := _definition()
	if shop==null: return
	shop.dispatch.transport_helpers.clear()
	var rules := _opened(shop)
	for tick in 1000:
		rules.step(0.1)
		for worker: Dictionary in rules.workers:
			if Flow.role(rules,worker)=="front":
				var job := Flow.job_of(rules,worker)
				check(job.get("kind","") in ["","take","home"],"disabled front retains original counter duties")
	var old: SpecShop = load("res://tests/fixtures/stirfry_modularity/legacy_shop.tres")
	var state: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/stirfry_modularity/legacy_states.json"))
	check_eq(JSON.parse_string(JSON.stringify(Content.describe(old))),state.states.active.content,"empty capability preserves the frozen pre-feature fingerprint")

func test_continuation_priority_finishes_cooked_food_before_starting_another_batch() -> void:
	var shop := _definition()
	if shop==null: return
	shop.dispatch.base_scores["continuation"] = 40.0
	check_eq(Schema.validate(shop),[],"finishing partially made recipes is an explicit scoring policy")
	var rules := _opened(shop)
	var cooked: Array[int] = []
	var record := func(event: Dictionary) -> void:
		if event.station=="wok_a": cooked.append(int(event.unit))
	rules.events.on("made",record)
	var found := false
	for tick in 2000:
		rules.step(0.1)
		if cooked.is_empty(): continue
		var id := cooked[0]
		for worker: Dictionary in rules.workers:
			if Flow.role(rules,worker)!="kitchen": continue
			var job := Flow.job_of(rules,worker)
			if job.is_empty(): continue
			check_eq(job.unit,id,"chef continues the first cooked order instead of cooking later orders")
			found = true
		break
	rules.events.off("made",record)
	check(found,"real cooked dish produced a continuation decision")

func test_prepositioned_work_waits_for_real_inputs_and_recovers_after_helper_recall() -> void:
	var shop := _definition()
	if shop==null: return
	check(shop.dispatch.get("preposition_work")!=null,"prepositioning is an explicit opt-in capability")
	if shop.dispatch.get("preposition_work")==null: return
	shop.dispatch.set("preposition_work",true)
	shop.dispatch.base_scores.continuation = 40.0
	var rules := _opened(shop)
	var found := false
	for tick in 3000:
		rules.step(0.1)
		for worker: Dictionary in rules.workers:
			var job := Flow.job_of(rules,worker)
			if job.get("kind","")!="work" or not worker.has("action") or worker.action.get("reason","")!="inputs unavailable": continue
			var inbound: Dictionary = {}
			for other: Dictionary in rules.workers:
				var carry := Flow.job_of(rules,other)
				if carry.get("kind","")=="carry" and carry.unit==job.unit and carry.to==job.from:
					inbound = other
			if inbound.is_empty(): continue
			var unit := Flow.unit(rules,int(job.unit))
			var step := int(job.step)
			check(step not in unit.done,"missing physical inputs cannot finish the recipe")
			var saved := rules.to_dict()
			var clone := LegacyRules.new(shop)
			check_eq(clone.load_dict(saved),"","prepositioned work independently restores")
			for sample in 30:
				rules.step(0.1)
				clone.step(0.1)
			check_eq(clone.to_dict(),rules.to_dict(),"waiting and arrival resume identically")
			var cancelled := LegacyRules.new(shop)
			check_eq(cancelled.load_dict(saved),"","recall starts from the same waiting state")
			check_eq(cancelled.recall_worker(inbound.id),"","inbound helper can be recalled")
			cancelled.run(0.3)
			check_eq(LegacyRules.new(shop).load_dict(cancelled.to_dict()),"","vanished incoming reservation leaves a valid state")
			cancelled.run(150.0)
			check(cancelled.sold>0,"remaining employee can recover without a permanent workbench deadlock")
			found = true
			break
		if found: break
	check(found,"real shared transport produced a brief wait at the workbench")

func test_independent_rice_input_can_arrive_before_cooking_but_cannot_start_plating() -> void:
	var shop := _definition()
	if shop==null: return
	check(shop.dispatch.get("prefetch_inputs")!=null,"parallel input preparation is explicit")
	if shop.dispatch.get("prefetch_inputs")==null: return
	shop.dispatch.set("prefetch_inputs",true)
	shop.dispatch.set("preposition_work",true)
	shop.dispatch.base_scores.continuation = 40.0
	var rules := _opened(shop)
	var found := false
	for tick in 2400:
		rules.step(0.1)
		for good: Dictionary in rules.serve.goods:
			if good.item!="rice" or good.at!="plating" or good.owner<0: continue
			var unit := Flow.unit(rules,int(good.owner))
			if 2 in unit.done: continue
			check(3 not in unit.done,"parallel rice preparation cannot skip cooking dependencies")
			check_eq(LegacyRules.new(shop).load_dict(rules.to_dict()),"","early reserved ingredients preserve a valid ledger")
			found = true
			break
		if found: break
	check(found,"actual rice reached the combine station before the cooked branch completed")

func test_formal_opening_has_bounded_waits_and_legal_movement_across_three_seeds() -> void:
	var shop: SpecShop = load("res://tests/fixtures/legacy_shops/current/stirfry/shop.tres")
	for seed_ in [11,42,84]:
		var rules := LegacyRules.new(shop,seed_)
		rules.unlock("wok_a")
		var sales: Array[float] = []
		var record := func(_sale: Dictionary) -> void: sales.append(rules.clock)
		rules.events.on("sale",record)
		var illegal := 0
		var overspeed := 0
		for tick in 1800:
			var before := {}
			for worker: Dictionary in rules.workers: before[worker.id] = worker.pos
			rules.step(0.1)
			for worker: Dictionary in rules.workers:
				if not rules.nav.can_stand(worker.pos,"staff"): illegal += 1
				if Vector2(before[worker.id]).distance_to(worker.pos)>rules.walk_speed(worker)*0.1+0.01: overspeed += 1
		rules.events.off("sale",record)
		check(sales.size()>=6,"opening maintains repeated real sales: seed "+str(seed_))
		if not sales.is_empty(): check(sales[0]<=35.0,"first sale arrives without a long empty opening: seed "+str(seed_))
		var gaps: Array[float] = []
		for index in range(1,sales.size()): gaps.append(sales[index]-sales[index-1])
		gaps.sort()
		if not gaps.is_empty(): check(gaps[(gaps.size()-1)/2]<=25.0,"opening sale cadence stays within its target: seed "+str(seed_))
		check_eq(rules.lost,0,"opening demand fits the initial crew: seed "+str(seed_))
		check_eq([illegal,overspeed],[0,0],"rhythm never uses clipping or faster movement: seed "+str(seed_))
		check_eq(LegacyRules.new(shop).load_dict(rules.to_dict()),"","opening trace remains independently resumable: seed "+str(seed_))
