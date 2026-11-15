extends "res://tests/test_case.gd"
const Runtime := preload("res://game/rules/template/runtime.gd")
const Fixture := preload("res://tests/fixtures/template_service.gd")
const Orders := preload("res://game/rules/template/orders.gd")
const Legacy := preload("res://tests/fixtures/legacy_shops/reference_rules.gd")

class MeasuredInventory extends "res://game/rules/template/inventory.gd":
	var history_reads := 0
	func snapshot() -> Dictionary:
		history_reads += 1
		return super.snapshot()

class MeasuredMachines extends "res://game/rules/template/machines.gd":
	var run_reads := 0
	var history_reads := 0
	func run(id: int) -> Dictionary:
		run_reads += 1
		return super.run(id)
	func snapshot() -> Dictionary:
		history_reads += 1
		return super.snapshot()

class MeasuredOrders extends "res://game/rules/template/orders.gd":
	var history_reads := 0
	func snapshot() -> Dictionary:
		history_reads += 1
		return super.snapshot()

func test_idle_ticks_and_display_reads_do_not_copy_or_recheck_completed_history() -> void:
	var runtime := Fixture.runtime()
	var unit: int = runtime.request_production("drink").id
	for tick in 1000:
		check_eq(runtime.step(0.1),"","finish a real production unit")
		if runtime.ready(unit): break
	check(runtime.ready(unit),"a completed machine proof exists")
	var saved: Dictionary = runtime.snapshot()
	var owner: ShopRules = runtime.runner.owner
	owner.runtime = runtime
	runtime.runner.release_owner()
	var stock := MeasuredInventory.new()
	check_eq(stock.restore(saved.runner.inventory),"","restore the real ledger into a measured implementation")
	var machines := MeasuredMachines.new(stock)
	check_eq(machines.restore(saved.runner.machines),"","retain the actual completed device records")
	var orders := MeasuredOrders.new(runtime.service._policy.orders)
	check_eq(orders.restore(saved.service.orders,stock),"","retain actual order facts")
	runtime.runner.inventory = stock
	runtime.runner.machines = machines
	runtime.service.orders = orders
	stock.history_reads = 0
	runtime._reconcile()
	check_eq(machines.run_reads,0,"completed production nodes are not polled every tick")
	check_eq(runtime.step(0.1),"","idle progression still runs normally")
	var frame: Dictionary = runtime.frame([],true)
	check_eq(frame.stock.a_out.count,1,"active display still exposes the real finished item")
	var view := ShopView.new(owner)
	view.render_snapshot()
	view.guide_snapshot()
	owner.arrivals()
	owner.seated_orders()
	check_eq(stock.history_reads,0,"normal progression and display do not copy the entire inventory history")
	check_eq(machines.history_reads,0,"display does not copy terminal machine runs")
	check_eq(orders.history_reads,0,"normal service does not copy departed-order history")
	check_eq(load("res://game/rules/template/source_demand.gd").build(runtime._definition,runtime._units,stock,machines),{},"completed process-output recipes have no shared-source demand")
	check_eq(stock.history_reads,0,"process-output demand does not materialize unrelated historical transfers")
	var after: Dictionary = runtime.snapshot()
	check_eq(after.runner.inventory,saved.runner.inventory,"optimization preserves every stock proof for saving")
	check_eq(after.runner.machines,saved.runner.machines,"optimization preserves every device proof for restoring")
	check_eq(runtime.restore(after),"","optimized state still passes the complete save validator")

func test_delivery_sale_reports_the_committed_receipt_for_both_payment_policies() -> void:
	for payment in ["on_take","on_deliver"]:
		var owner := Fixture.owner()
		var template := Fixture.definition("counter")
		template.service.orders.pay_at = payment
		var runtime := Runtime.new(owner,template)
		var receipts := []
		var listener := func(data: Dictionary) -> void: receipts.append(data)
		owner.events.on("sale",listener)
		check_eq(runtime.arrive(Fixture.request()).error,"","two-item order arrives")
		for tick in 1600:
			check_eq(runtime.step(0.1),"","actual production and delivery")
			if not receipts.is_empty(): break
		owner.events.off("sale",listener)
		check_eq(receipts.size(),1,"one completed-order notification")
		if receipts.is_empty(): continue
		check_eq(receipts[0].income,40,"sale contains the actual 12 + 28 receipt")
		check_eq(owner.revenue,40.0,"notification agrees with wallet")
		check_eq(runtime.restore(runtime.snapshot()),"","notified order remains resumable")

func test_accepted_guests_keep_waiting_without_becoming_abandonment_candidates() -> void:
	var orders := Orders.new({"patience":5.0})
	var request := [{"dish":"meal","recipe":"meal","item":"meal","qty":1}]
	var accepted: int = orders.arrive(request,3).id
	var queued: int = orders.arrive(request,3).id
	check_eq(orders.advance(2.0),"","queue wait accumulates before acceptance")
	check_eq(orders.admit(accepted,{"meal":12.0}).error,"","accept one guest")
	check_eq(orders.advance(40.0),"","accepted guest still waits for food")
	check_eq(orders.guest(accepted).wait,42.0,"time before and after acceptance contributes to mood")
	check_eq(orders.guest(accepted).state,"waiting","accepted guest cannot abandon a committed order")
	check_eq(orders.guest(queued).state,"leaving","unclaimed queue guest still abandons")
	check_eq(orders.snapshot().lost,1,"accepted guest is never counted as lost")
	var stopped: Dictionary = orders.snapshot()
	orders.advance(10.0,true)
	check_eq(orders.snapshot(),stopped,"paused time changes neither waiting nor departures")

func test_numeric_refresh_adopts_smaller_ramp_and_flyer_limits_without_losing_pending_work() -> void:
	var shop: SpecShop = load("res://content/shops/tea/shop.tres").copy_for_editing()
	var owner := ShopRules.new(shop,42)
	owner.gold = 1000000.0
	for stage in shop.stages.size(): check_eq(owner.unlock(shop.sold_at(stage)),"","open formal menu")
	owner.run(2.0)
	check_eq(owner.send_flyers(),"","commit a spread wave")
	var saved := owner.to_dict()
	check_eq(saved.runtime.service.ramp.counts.lemonade,3,"authentic old exposure is above the new cap")
	check_eq(saved.runtime.service.flyers.wave_left,30.0,"old wave was committed")
	var changed: SpecShop = shop.copy_for_editing()
	changed.runtime_template = shop.runtime_template.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	changed.runtime_template.service.selection.ramp.orders = 0
	changed.runtime_template.service.flyers.seconds = 1.0
	var target := ShopRules.new(changed,42)
	var error := target.load_dict(saved,true)
	check_eq(error,"","valid numeric update must not block an existing shop")
	if not error.is_empty(): return
	var migrated := target.to_dict()
	check_eq(migrated.runtime.service.ramp.counts.lemonade,0,"exposure is capped to the new neutral ramp")
	check_eq(migrated.runtime.service.flyers.wave_left,1.0,"remaining spread window respects the new duration")
	check_eq(migrated.runtime.service.flyers.pending,saved.runtime.service.flyers.pending,"every pending flyer customer is retained")
	check_eq(migrated.runtime.service.flyers.cooldown,saved.runtime.service.flyers.cooldown,"already committed cooldown is retained")
	check_eq(target.rng.state,saved.outer.rng[1],"migration never redraws arrivals")
	check_eq(target.load_dict(migrated),"","migrated state can reopen with strict current validation")
	for bad_count in [-1,1.5,999999]:
		var invalid := saved.duplicate(true)
		invalid.runtime.service.ramp.counts.lemonade = bad_count
		check(not target.load_dict(invalid,true).is_empty(),"numeric refresh still rejects impossible old exposure")
		check_eq(target.to_dict(),migrated,"invalid numeric adoption is atomic")

func test_legacy_pancake_keeps_the_accepted_quote_after_post_acceptance_upgrades() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/runtime_legacy/pancake.json"))
	var saved: Dictionary = bytes_to_var(Marshalls.base64_to_raw(fixture.states["599"]))
	var previous := Legacy.new(load("res://tests/fixtures/legacy_shops/current/pancake/shop.tres"),42)
	check_eq(previous.load_dict(saved),"","authentic accepted legacy order")
	check_eq(previous.customer(6).paid,32,"the already accepted order locked 32 coins")
	previous.gold = 1000000.0
	for key in ["soy_milk","rear_equipment","fryer","topping"]:
		check_eq(previous.upgrade(key),"","legal upgrade after the order was accepted")
	check_eq(previous.order_price_single(previous.customer(6)),33,"new orders now have a different price")
	var owner := ShopRules.new(load("res://content/shops/pancake/shop.tres"),42)
	check_eq(owner.load_dict(previous.to_dict(),true),"","migrate without restarting the old order")
	var revenue := owner.revenue
	for tick in 2000:
		owner.step(0.1)
		if owner.runtime.service.orders.order(6).paid: break
	check_eq(owner.runtime.service.orders.order(6).income,32,"delivery uses the original accepted quote")
	check_eq(owner.revenue-revenue,32.0,"migration neither invents nor drops settlement money")
	check_eq(owner.load_dict(owner.to_dict()),"","locked line prices survive a strict round trip")
