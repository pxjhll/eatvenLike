extends "res://tests/test_case.gd"
const Runtime := preload("res://game/rules/template/runtime.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")
const Production := preload("res://tests/fixtures/template_shop.gd")
const Actors := preload("res://tests/fixtures/template_service.gd")
const Validator := preload("res://game/rules/shop_spec_validator.gd")

func _definition() -> Resource:
	var template := Production.linear()
	template.places.a_in.capacity = 2
	template.places.a_in.capacity_binding = {"target":"hopper","max":4}
	template.places.a_out.capacity = 1
	template.places.a_out.capacity_binding = {"target":"shelf","max":4}
	template.places["sink"] = {"port":Vector2(500,100),"capacity":8}
	template.machines.a.profile.manual = false
	template.machines.a.slots_binding = {"target":"a","max":3}
	return template

func _runtime(template: Resource) -> RefCounted:
	var runtime := Runtime.new(Actors.owner(),template)
	check_eq(runtime.last_error,"","explicit container and machine numeric bindings compile")
	return runtime if runtime.last_error.is_empty() else null

func _effect(runtime: RefCounted, kind: String, target: String, value: float) -> void:
	runtime.runner.owner.mods.remove("event",kind+target)
	runtime.runner.owner.apply_effect("event",kind+target,SpecEffect.make(kind,"set",value,target))

func _advance(runtime: RefCounted, ticks := 300) -> void:
	for tick in ticks: check_eq(runtime.step(0.1),"","shared limits runtime step")

func _active(runtime: RefCounted) -> int:
	var count := 0
	for run in runtime.runner.machines.snapshot().runs:
		if run.machine == "a" and run.phase not in ["completed","cancelled"]: count += 1
	return count

func _two_active(runtime: RefCounted) -> void:
	_effect(runtime,"capacity","shelf",4.0)
	_effect(runtime,"process_slots","a",2.0)
	for index in 2: runtime.request_production("drink")
	for tick in 300:
		check_eq(runtime.step(0.1),"","physically supply parallel machine slots")
		if _active(runtime) == 2: return
	check(false,"two actual operations ran concurrently")

func test_capacity_is_a_public_effect_but_legacy_shop_definitions_cannot_silently_ignore_it() -> void:
	check("capacity" in SpecEffect.KINDS,"capacity is registered in the shared effect vocabulary")
	var shop: SpecShop = preload("res://content/shops/tea/shop.tres").copy_for_editing()
	shop.station("boil").tracks[0].base_effects.append(SpecEffect.make("capacity","set",8.0,"boil"))
	check(not Validator.validate(shop).is_empty(),"legacy shop entry must reject a template-only capacity effect until adopted")

func test_capacity_upgrade_changes_real_storage_and_unblocks_waiting_production() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	for index in 3: runtime.request_production("drink")
	_advance(runtime)
	check_eq(runtime.runner.inventory.quantity("a_out","drink"),1,"base output capacity blocks additional physical production")
	_effect(runtime,"capacity","shelf",3.0)
	_advance(runtime)
	check_eq(runtime.runner.inventory.quantity("a_out","drink"),3,"upgraded capacity admits the two waiting owned outputs")
	check_eq(runtime.frame().limits.capacity.a_out.target,3,"view exposes actual requested capacity")
	check_eq(runtime.runner.inventory.audit(),[],"capacity upgrade never creates stock directly")

func test_shrinking_storage_retains_held_return_space_and_blocks_new_stock_until_drained() -> void:
	var template := _definition()
	template.places["store"] = {"port":Vector2(100,100),"capacity":4,"initial":{"raw_a":3},"capacity_binding":{"target":"store","max":4}}
	var runtime := _runtime(template)
	if runtime == null: return
	_effect(runtime,"capacity","store",1.0)
	check_eq(runtime.step(0.1),"","shrink without deleting existing stock")
	check_eq(runtime.runner.inventory.quantity("store","raw_a"),3,"all existing goods retained")
	check_eq(runtime.frame().limits.capacity.store.applied,3,"applied capacity retains actual occupancy")
	check(not runtime.runner.inventory.seed("store","raw_a",1).error.is_empty(),"retained headroom cannot accept new stock")
	var worker: Dictionary = runtime.runner.owner.workers[0]
	check_eq(runtime.runner.transfer(worker.id,"store","sink","raw_a",2,0.2),"","real outflow may drain old stock")
	for tick in 300:
		check_eq(runtime.step(0.1),"","pickup before shrinking source capacity")
		if worker.carry_count == 2: break
	check_eq(worker.carry_count,2,"real goods held during shrink")
	check_eq(runtime.frame().limits.capacity.store.used,3,"held goods keep their source return reservation")
	check(not runtime.runner.inventory.seed("store","raw_a",1).error.is_empty(),"pickup cannot expose reserved return space")
	for tick in 300:
		check_eq(runtime.step(0.1),"","drop frees source return space")
		if runtime.runner.idle(worker.id): break
	check_eq(runtime.frame().limits.capacity.store.applied,1,"drop converges immediately to the new limit")
	check_eq(runtime.runner.inventory.quantity("sink","raw_a"),2,"both goods really arrived")
	check_eq(runtime.runner.inventory.audit(),[],"shrink preserves stock and reservations")

func test_slots_upgrade_controls_actual_concurrent_runs_and_shrink_preserves_in_flight_work() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	_two_active(runtime)
	check_eq(_active(runtime),2,"two slots execute concurrently")
	_effect(runtime,"process_slots","a",1.0)
	check_eq(runtime.step(0.1),"","shrink while both operations are running")
	check_eq(_active(runtime),2,"no in-flight operation is cancelled")
	check_eq(runtime.frame().limits.slots.a.target,1,"requested slot count has shrunk")
	check_eq(runtime.frame().limits.slots.a.applied,2,"occupied old slots are retained")
	check(not runtime.runner.machines.start("a",{}, {"extra":1},1.0).error.is_empty(),"direct operation cannot claim a third retained slot")
	_advance(runtime)
	check_eq(runtime.runner.inventory.quantity("a_out","drink"),2,"both original committed products finish")
	check_eq(runtime.runner.machines.snapshot().definitions.a.profile.slots,1,"slots converge after old work completes")
	check_eq(runtime.runner.machines.audit(),[],"machine definitions and occupancy remain valid")

func test_shrunk_capacity_and_slots_restore_with_old_inventory_and_operations_intact() -> void:
	var template := _definition()
	var runtime := _runtime(template)
	if runtime == null: return
	_two_active(runtime)
	_effect(runtime,"capacity","hopper",0.0)
	_effect(runtime,"capacity","shelf",0.0)
	_effect(runtime,"process_slots","a",1.0)
	check_eq(runtime.step(0.1),"","capture occupied shrunk limits")
	var reopened := _runtime(template)
	if reopened == null: return
	_effect(reopened,"capacity","hopper",0.0)
	_effect(reopened,"capacity","shelf",0.0)
	_effect(reopened,"process_slots","a",1.0)
	check_eq(reopened.restore(runtime.snapshot()),"","only declared numeric definitions may differ from baseline")
	for tick in 150:
		check_eq(runtime.step(0.1),"","continue original draining limits")
		check_eq(reopened.step(0.1),"","continue restored draining limits")
	check_eq(reopened.snapshot(),runtime.snapshot(),"limits, claims, remaining work and actors replay identically")
	check_eq(reopened.runner.inventory.quantity("a_out","drink"),2,"shrink-to-zero retains finished products")
	check_eq(reopened.frame().limits.capacity.a_out.target,0,"zero target does not discard old output")
	check_eq(reopened.runner.inventory.audit(),[],"restored over-target stock remains conserved")

func test_restore_rejects_out_of_range_and_unbound_definition_changes_before_actor_adoption() -> void:
	var template := _definition()
	var runtime := _runtime(template)
	if runtime == null: return
	for patch in ["capacity","slots","infinite","unbound","profile"]:
		var saved: Dictionary = runtime.snapshot()
		match patch:
			"capacity": saved.runner.inventory.places.a_out.capacity = 5
			"slots": saved.runner.machines.definitions.a.profile.slots = 4
			"infinite": saved.runner.inventory.places.a_in.infinite = ["milk"]
			"unbound": saved.runner.inventory.places.pantry.capacity = 3
			"profile": saved.runner.machines.definitions.a.profile.manual = true
		var reopened := _runtime(template)
		if reopened == null: return
		var before: Dictionary = reopened.snapshot()
		check(not reopened.restore(saved).is_empty(),"cannot use numeric binding to forge " + patch)
		check_eq(reopened.snapshot(),before,"rejected limit state preserves all live state")

func test_pause_and_invalid_numeric_targets_do_not_partially_apply_limits() -> void:
	var runtime := _runtime(_definition())
	if runtime == null: return
	_effect(runtime,"capacity","shelf",3.0)
	var before: Dictionary = runtime.snapshot()
	check_eq(runtime.step(100.0,true),"","paused resize")
	check_eq(runtime.snapshot(),before,"pause changes no applied capacities or physics")
	_effect(runtime,"process_slots","a",1.5)
	check(not runtime.step(0.1).is_empty(),"fractional slot limit is an explicit error")
	check_eq(runtime.snapshot(),before,"invalid second binding cannot apply the first binding or advance time")

func test_binding_shape_and_unbounded_or_impossible_ranges_are_authoring_errors() -> void:
	for patch in ["unlimited","small_max","fraction","callback","target"]:
		var template := _definition()
		match patch:
			"unlimited": template.places.a_in.capacity = -1
			"small_max": template.places.a_in.capacity_binding.max = 1
			"fraction": template.machines.a.slots_binding.max = 2.5
			"callback": template.places.a_in.capacity_binding.callback = "private"
			"target": template.machines.a.slots_binding.target = null
		check(not Compiler.compile(template).errors.is_empty(),"invalid limit metadata cannot be coerced or ignored")

func test_same_container_capacity_is_shared_by_inputs_outputs_and_parallel_work() -> void:
	var template := _definition()
	template.machines.a.output = "a_in"
	var runtime := _runtime(template)
	if runtime == null: return
	_effect(runtime,"capacity","hopper",3.0)
	_effect(runtime,"process_slots","a",2.0)
	for index in 3: runtime.request_production("drink")
	_advance(runtime)
	check_eq(runtime.runner.inventory.quantity("a_in","drink"),3,"space-neutral transformations finish in the real shared container")
	check_eq(runtime.runner.inventory.quantity("a_in","raw_a"),0,"all finite inputs were transformed")
	check_eq(runtime.frame().limits.capacity.a_in.used,3,"one quota accounts for inputs, output and reservations")
	check_eq(runtime.runner.inventory.audit(),[],"shared-container upgrades conserve space and goods")

func test_bundle_drop_converges_shrunk_source_before_another_direct_reservation() -> void:
	var stock := preload("res://game/rules/template/inventory.gd").new()
	stock.configure("store",2)
	stock.configure("guest",2)
	stock.seed("store","meal",2)
	check_eq(stock.set_capacity_limit("store",0),"","shrink a filled source")
	var bundle: Dictionary = stock.reserve_bundle("customer:1",[{"from":"store","to":"guest","item":"meal","count":2}],2)
	check_eq(bundle.error,"","ordinary bundle can drain the source")
	check_eq(stock.pickup_bundle(bundle.id),"","real bundle pickup")
	check_eq(stock.drop_bundle(bundle.id),"","real whole-order drop")
	check_eq(stock.snapshot().places.store.capacity,0,"bundle commit releases retained capacity immediately")
	check(not stock.seed("store","meal",1).error.is_empty(),"offside bundle adoption cannot reopen admission before the next runtime tick")
	check_eq(stock.audit(),[],"bundle shrink keeps the existing transaction contract")
