extends "res://tests/test_case.gd"
const Fixture := preload("res://tests/fixtures/template_service.gd")
const Inventory := preload("res://game/rules/template/inventory.gd")
const Trace := preload("res://game/rules/template/trace.gd")

func test_failed_and_idempotent_bundle_actions_do_not_trace_uncommitted_work() -> void:
	var stock := Inventory.new()
	stock.trace = Trace.new()
	for place in ["main","side","guest:1"]: stock.configure(place,4)
	stock.seed("main","meal",1,11); stock.seed("side","soup",1,12)
	stock.trace.take()
	var entries := [{"from":"main","to":"guest:1","item":"meal","count":1,"owner":11},
		{"from":"side","to":"guest:1","item":"missing","count":1,"owner":12}]
	check(not stock.reserve_bundle("staff:1",entries,2).error.is_empty(),"second child reservation fails")
	check_eq(stock.trace.take().events,[],"offside successful first child is not a real reservation")
	entries[1].item = "soup"
	var result: Dictionary = stock.reserve_bundle("staff:1",entries,2)
	check_eq(stock.trace.take().events.size(),2,"only committed reservations traced")
	var group: Dictionary = stock.bundle(result.id)
	stock.pickup_bundle_part(group.id,group.claims[0])
	check_eq(stock.trace.take().events.size(),1,"one actual child pickup")
	stock.pickup_bundle_part(group.id,group.claims[0])
	check_eq(stock.trace.take().events,[],"duplicate pickup adds no operation")
	check(not stock.drop_bundle(group.id).is_empty(),"incomplete bundle cannot drop")
	check_eq(stock.trace.take().events,[],"failed commit has no trace")
	stock.cancel_bundle(group.id)
	check_eq(stock.trace.take().events.size(),2,"both real cancellations traced")
	stock.cancel_bundle(group.id)
	check_eq(stock.trace.take().events,[],"compensation traced once")
	check_eq(stock.audit(),[],"actual ledger remains consistent")

func test_trace_overflow_is_explicit_and_draining_resets_the_bound() -> void:
	var trace := Trace.new()
	for i in Trace.LIMIT+1: trace.record("diagnostic",{"index":i})
	var batch := trace.take()
	check_eq(batch.events.size(),Trace.LIMIT,"bounded collector")
	check(batch.overflow,"lost evidence cannot silently pass as a complete trace")
	check_eq(trace.take(),{"events":[],"overflow":false},"drain resets overflow")

func test_live_restore_keeps_enabled_tracing_on_the_actual_inventory() -> void:
	var runtime: RefCounted = Fixture.runtime("counter")
	runtime.set_tracing(true)
	check_eq(runtime.restore(runtime.snapshot()),"","live restore")
	check(is_same(runtime.runner.inventory.trace,runtime.runner.trace),"restored inventory uses the same enabled collector")

func test_real_public_operations_produce_opt_in_trace_with_physical_action_proofs() -> void:
	var runtime: RefCounted = Fixture.runtime("counter")
	check(runtime.has_method("set_tracing"),"runtime exposes optional common-operation tracing")
	if not runtime.has_method("set_tracing"): return
	runtime.call("set_tracing",true)
	check_eq(runtime.arrive(Fixture.request()).error,"","real order")
	var events := []
	for tick in 1200:
		check_eq(runtime.step(0.1),"","actual shared execution")
		var trace: Dictionary = runtime.call("take_trace")
		check(not trace.overflow,"trace is complete")
		events.append_array(trace.events)
		if runtime.runner.owner.sold==2: break
	for operation in ["runtime.step","inventory.reserve_transfer","inventory.pickup","inventory.drop","inventory.reserve_operation","inventory.complete_operation","action.pickup","action.drop","action.operate"]:
		check(events.any(func(row: Dictionary) -> bool: return row.operation==operation),"actual call traced: "+operation)
	for event in events:
		if event.operation not in ["action.pickup","action.drop","action.operate"]: continue
		check(event.facts.pos.is_equal_approx(event.facts.port),"physical action actually committed at its declared port")
		check(event.facts.worker>0 and not event.facts.target.is_empty(),"proof identifies actual employee and port")
	check_eq(runtime.runner.inventory.audit(),[],"trace does not replace authoritative stock")

func test_tracing_does_not_change_business_or_survive_save_restore() -> void:
	var observed: RefCounted = Fixture.runtime("self_pickup")
	var control: RefCounted = Fixture.runtime("self_pickup")
	if not observed.has_method("set_tracing"): check(false,"trace API required"); return
	observed.call("set_tracing",true)
	for runtime in [observed,control]: runtime.arrive(Fixture.request())
	for tick in 500:
		observed.step(0.1); control.step(0.1)
	check_eq(observed.snapshot(),control.snapshot(),"observability cannot alter inventory, clocks, actions, customers or RNG")
	check_eq(observed.runner.owner.gold,control.runner.owner.gold,"same real settlement")
	var restored: RefCounted = Fixture.runtime("self_pickup")
	check_eq(restored.restore(observed.snapshot()),"","ordinary runtime restore")
	check_eq(restored.call("take_trace"),{"events":[],"overflow":false},"diagnostics are not persistent business state")
	observed.call("set_tracing",false)
	observed.step(0.1)
	check_eq(observed.call("take_trace"),{"events":[],"overflow":false},"disabled trace retains no old events")
