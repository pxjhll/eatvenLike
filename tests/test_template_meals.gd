extends "res://tests/test_case.gd"
const Orders := preload("res://game/rules/template/orders.gd")
const Inventory := preload("res://game/rules/template/inventory.gd")
const Sales := preload("res://game/rules/rule_sales.gd")

func _served() -> Dictionary:
	var orders := Orders.new()
	check(orders.has_method("begin_meal"), "eating and departure must extend common customer order facts")
	if not orders.has_method("begin_meal"): return {}
	var stock := Inventory.new()
	stock.configure("pass", 4)
	stock.configure("guest:1", 4)
	var sales := Sales.new()
	sales.sold_by_dish = {"meal":0, "soup":0}
	var guest: Dictionary = orders.arrive([
		{"dish":"meal", "recipe":"meal", "item":"meal", "qty":1},
		{"dish":"soup", "recipe":"soup", "item":"soup", "qty":1}], 2)
	var accepted: Dictionary = orders.admit(guest.id, {"meal":10.0, "soup":2.0})
	var order: Dictionary = orders.order(accepted.id)
	var entries: Array = []
	for index in order.lines.size():
		var line: Dictionary = order.lines[index]
		orders.bind_unit(order.id, line.id, 11 + index)
		stock.seed("pass", line.item, 1, 11 + index)
		entries.append({"from":"pass", "to":"guest:1", "item":line.item, "count":1, "owner":11 + index})
	var bundle: Dictionary = stock.reserve_bundle("staff:1", entries, 2)
	stock.pickup_bundle(bundle.id)
	stock.drop_bundle(bundle.id)
	for index in order.lines.size():
		orders.record_delivery(order.id, order.lines[index].id, stock.bundle(bundle.id).claims[index], stock, sales)
	return {"orders":orders, "stock":stock, "sales":sales, "guest":guest.id, "order":order.id}

func test_meal_starts_only_after_receipt_and_advances_with_pause_then_consumes_each_owned_item_once() -> void:
	var f := _served()
	if f.is_empty(): return
	check(not f.orders.begin_meal(f.guest, 2.0, f.stock).is_empty(), "unpaid guests cannot begin meal")
	f.orders.settle(f.order, f.sales)
	check_eq(f.orders.begin_meal(f.guest, 2.0, f.stock), "", "paid whole order begins meal")
	var before: Dictionary = f.orders.snapshot()
	f.orders.advance_meals(100.0, f.stock, true)
	check_eq(f.orders.snapshot(), before, "pause does not consume time or goods")
	f.orders.advance_meals(1.0, f.stock)
	check_eq(f.stock.quantity("guest:1"), 2, "food remains during eating")
	f.orders.advance_meals(1.0, f.stock)
	check_eq(f.orders.guest(f.guest).state, "leaving", "eating completion requests departure")
	check_eq(f.stock.quantity("guest:1"), 0, "all owned food consumed through public recipe operations")
	f.orders.advance_meals(5.0, f.stock)
	check_eq(f.stock.audit(), [], "meal completion is conservative and idempotent")
	check_eq(f.sales.gold, 12.0, "meal does not settle twice")
	check_eq(f.sales.sold, 2, "meal does not recount deliveries")

func test_saved_meal_resumes_its_remaining_time_and_rejects_forged_consumption_proof() -> void:
	var f := _served()
	if f.is_empty(): return
	f.orders.settle(f.order, f.sales)
	f.orders.begin_meal(f.guest, 2.0, f.stock)
	f.orders.advance_meals(0.5, f.stock)
	var reopened := Orders.new()
	check_eq(reopened.restore(f.orders.snapshot(), f.stock), "", "restore active meal")
	reopened.advance_meals(1.4, f.stock)
	check_eq(reopened.guest(f.guest).state, "eating", "remaining time preserved")
	reopened.advance_meals(0.1, f.stock)
	check_eq(reopened.guest(f.guest).state, "leaving", "resume commits consumption once")
	check_eq(reopened.restore(reopened.snapshot(), f.stock), "", "validate committed consumption")
	var before: Dictionary = reopened.snapshot()
	var broken: Dictionary = before.duplicate(true)
	broken.guests[0].consumption[0] = broken.guests[0].consumption[1]
	check(not reopened.restore(broken, f.stock).is_empty(), "meal consumption proofs cannot be reused")
	check_eq(reopened.snapshot(), before, "failed restore preserves customer facts")

func test_missing_delivered_food_blocks_meal_without_fabricating_or_destroying_other_items() -> void:
	var f := _served()
	if f.is_empty(): return
	f.orders.settle(f.order, f.sales)
	var moved: Dictionary = f.stock.reserve_transfer(2, "guest:1", "pass", "soup", 1, 2, 12)
	f.stock.pickup(moved.id)
	var before: Dictionary = f.stock.snapshot()
	check(not f.orders.begin_meal(f.guest, 2.0, f.stock).is_empty(), "delivery proof alone is not currently available food")
	check_eq(f.stock.snapshot(), before, "failed meal is atomic")
	check_eq(f.orders.guest(f.guest).state, "served", "guest waits for actual goods")
