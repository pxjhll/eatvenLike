extends "res://tests/test_case.gd"
const Fixture := preload("res://tests/fixtures/template_service.gd")
const Runtime := preload("res://game/rules/template/runtime.gd")
func test_service_events_observe_complete_orders_for_both_payment_policies() -> void:
	for payment in ["on_take","on_deliver"]:
		var owner := Fixture.owner()
		var template := Fixture.definition("counter")
		template.service.orders.pay_at = payment
		var runtime := Runtime.new(owner,template)
		var seen := []; var snapshots := []
		var observer := func(event: Dictionary) -> void:
			if event.name not in ["arrived","order_taken","sale","lost"]: return
			seen.append(event)
			snapshots.append(runtime.snapshot())
		owner.events.on("*",observer)
		check_eq(runtime.arrive(Fixture.request()).error,"","enqueue")
		for tick in 1600:
			check_eq(runtime.step(0.1),"","shared service runs")
			if owner.sold==2: break
		check_eq(seen.filter(func(e: Dictionary) -> bool: return e.name=="arrived").size(),1,"one arrival event")
		check_eq(seen.filter(func(e: Dictionary) -> bool: return e.name=="order_taken").size(),1,"one accepted order event")
		var sales := seen.filter(func(e: Dictionary) -> bool: return e.name=="sale")
		check_eq(sales.size(),1,"one complete order sale regardless of payment timing")
		if not sales.is_empty():
			check_eq(sales[0].data.get("count"),2,"sale includes fulfilled quantity")
			check_eq(sales[0].data.get("order"),1,"stable order identity")
			check_eq(sales[0].data.get("guest"),1,"stable guest identity")
			check(sales[0].data.get("items") is Array,"sale carries item metadata")
			var sale_index: int = seen.find(sales[0])
			check_eq(snapshots[sale_index].service.orders.orders[0].state,"delivered","sale fires after actual delivery")
		owner.events.off("*",observer)
		for saved in snapshots:
			var restored := Runtime.new(Fixture.owner(),template)
			check_eq(restored.restore(saved),"","every event snapshot is transaction complete")

func test_formal_loss_queries_and_reentrant_unlock_share_the_public_state() -> void:
	var owner := ShopRules.new(load("res://content/shops/tea/shop.tres"),42)
	owner.gold = 1000000.0
	var saves := []
	var on_unlock := func(_data: Dictionary) -> void:
		var saved := owner.to_dict()
		saves.append(saved)
		check_eq(owner.load_dict(saved),"","unlock observer can restore")
	owner.events.on("unlocked",on_unlock)
	check_eq(owner.unlock(owner.shop.sold_at(0)),"","open through normal command")
	owner.events.off("unlocked",on_unlock)
	check(not saves.is_empty(),"unlock observer ran")
	check_eq(owner.load_dict(owner.to_dict()),"","no mutation of replaced runtime after callback")
	var lost := []
	var on_lost := func(data: Dictionary) -> void: lost.append(data)
	owner.events.on("lost",on_lost)
	for unused in 30: owner.runtime.arrive([{"dish":"lemonade","qty":1}])
	check(owner.runtime.service.orders.snapshot().lost>0,"real full queue")
	check_eq(owner.lost,owner.runtime.service.orders.snapshot().lost,"guides and summary see public losses")
	owner.events.off("lost",on_lost)
	check_eq(lost.size(),owner.lost,"one event for each rejected customer")
func test_public_guide_uses_actual_waiting_customers_and_declared_production() -> void:
	var owner := ShopRules.new(load("res://content/shops/tea/shop.tres"),42)
	owner.gold = 1000000.0
	owner.unlock(owner.shop.sold_at(0))
	for guest in owner.runtime.service.orders._state.guests: guest.wait = 200.0
	var view := ShopView.new(owner)
	check(view.guide_snapshot().any_angry,"actual public waiting customer is angry")
	check(not view.guide_snapshot().angry_cause.is_empty(),"guide reads no empty legacy order array")
	check_eq(view.guide_snapshot().slow_machine,"lemonade","guide identifies the actual public recipe device")
func test_bonus_wave_limits_and_event_effect_callbacks_use_committed_public_state() -> void:
	for id in ["tea","pancake"]:
		var owner := ShopRules.new(load("res://content/shops/"+id+"/shop.tres"),42)
		check(owner.runtime.has_method("enqueue_wave"),"bonus waves enter the public scheduler")
		if not owner.runtime.has_method("enqueue_wave"): continue
		check_eq(owner.runtime.call("enqueue_wave",3),"","public bonus arrivals")
		var saved := owner.to_dict()
		check_eq(saved.runtime.service.flyers.pending,3,"one authoritative wave queue")
		check(not String(owner.runtime.call("enqueue_wave",9007199254740991)).is_empty(),"wave addition cannot overflow")
		check_eq(owner.to_dict(),saved,"invalid wave changes no clock, RNG or inventory")
		check_eq(owner.load_dict(saved),"","bonus wave is immediately resumable")
	var owner := ShopRules.new(load("res://content/shops/tea/shop.tres"),42)
	var event := SpecEvent.new(); event.id = "u06_bonus"
	var first := SpecEffect.new(); first.kind = "grant_gold"; first.value = 10.0
	var second := SpecEffect.new(); second.kind = "grant_gold"; second.value = 20.0
	event.effects.assign([first,second]); owner.add_event(event)
	var initial := owner.gold; var observations := []
	var observer := func(_data: Dictionary) -> void:
		observations.append(owner.gold)
		check_eq(owner.gold,initial+30.0,"effect callbacks see the complete event")
		check_eq(owner.load_dict(owner.to_dict()),"","event callback state strictly resumes")
	owner.events.on("gold_granted",observer)
	owner.trigger_event(event)
	owner.events.off("gold_granted",observer)
	check_eq(observations.size(),2,"both committed effects emit once")
