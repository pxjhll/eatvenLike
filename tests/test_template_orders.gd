extends "res://tests/test_case.gd"
const Inventory := preload("res://game/rules/template/inventory.gd")
const Sales := preload("res://game/rules/rule_sales.gd")
const PATH := "res://game/rules/template/orders.gd"

func _orders(policy: Dictionary = {}) -> RefCounted:
	check(ResourceLoader.exists(PATH), "customer orders and settlement need a common capability")
	return load(PATH).new(policy) if ResourceLoader.exists(PATH) else null

func _economy() -> RefCounted:
	var sales := Sales.new()
	sales.sold_by_dish = {"meal":0,"soup":0}
	return sales

func _request() -> Array:
	return [{"dish":"meal","recipe":"meal","item":"meal","qty":1}, {"dish":"soup","recipe":"soup","item":"soup","qty":1}]

func _inventory(guest: int) -> RefCounted:
	var stock := Inventory.new()
	stock.configure("pass", 8)
	stock.configure("guest:"+str(guest), 8)
	stock.seed("pass", "meal", 1, 11)
	stock.seed("pass", "soup", 1, 12)
	return stock

func _deliver(stock: RefCounted, guest: int, item: String, unit: int) -> int:
	var claim: Dictionary = stock.reserve_transfer(1, "pass", "guest:"+str(guest), item, 1, 2, unit)
	stock.pickup(claim.id)
	stock.drop(claim.id)
	return claim.id

func test_admission_keeps_queue_until_declared_release_and_binds_recipe_units() -> void:
	var orders := _orders()
	if orders == null: return
	var guest: Dictionary = orders.arrive(_request(), 3)
	check_eq(guest.error, "", "customer admitted to queue")
	check_eq(orders.queue(), [guest.id], "one queued customer")
	check_eq(orders.claim_admission(guest.id, 1), "", "employee can reserve order taking")
	check(not orders.claim_admission(guest.id, 2).is_empty(), "same customer cannot be taken twice")
	var accepted: Dictionary = orders.admit(guest.id, {"meal":10.5,"soup":2.0}, 1)
	check_eq(accepted.error, "", "order created once")
	check_eq(orders.queue(), [guest.id], "default blueprint releases queue on delivery")
	var order: Dictionary = orders.order(accepted.id)
	check_eq(order.lines.size(), 2, "main and addon are ordinary order lines")
	check_eq(orders.bind_unit(order.id, order.lines[0].id, 11), "", "main recipe unit")
	check_eq(orders.bind_unit(order.id, order.lines[1].id, 12), "", "addon recipe unit")
	check(not orders.bind_unit(order.id, order.lines[1].id, 11).is_empty(), "one production unit cannot belong to two lines")

func test_partial_delivery_never_settles_and_the_last_physical_delivery_settles_once() -> void:
	var orders := _orders()
	if orders == null: return
	var guest: Dictionary = orders.arrive(_request(), 3)
	var accepted: Dictionary = orders.admit(guest.id, {"meal":10.5,"soup":2.0})
	var order: Dictionary = orders.order(accepted.id)
	orders.bind_unit(order.id, order.lines[0].id, 11)
	orders.bind_unit(order.id, order.lines[1].id, 12)
	var stock := _inventory(guest.id)
	var economy := _economy()
	var meal := _deliver(stock, guest.id, "meal", 11)
	check_eq(orders.record_delivery(order.id, order.lines[0].id, meal, stock, economy), "", "record committed main delivery")
	check(not orders.settle(order.id, economy).error.is_empty(), "cannot pay an incomplete order")
	check_eq(economy.gold, 0.0, "no early money")
	check_eq(economy.sold, 1, "item count follows real delivery")
	var soup := _deliver(stock, guest.id, "soup", 12)
	check_eq(orders.record_delivery(order.id, order.lines[1].id, soup, stock, economy), "", "record committed addon delivery")
	check_eq(orders.settle(order.id, economy).income, 12, "fractional dish prices settle through the shared cash ledger")
	check_eq(economy.gold, 12.0, "one order credit")
	check_eq(economy.sold, 2, "two actual items sold")
	check_eq(orders.record_delivery(order.id, order.lines[1].id, soup, stock, economy), "", "replayed delivery is harmless")
	orders.settle(order.id, economy)
	check_eq(economy.gold, 12.0, "replayed settlement cannot duplicate income")
	check_eq(economy.sold, 2, "replayed handoff cannot duplicate item counters")
	check_eq(orders.queue(), [], "delivery releases queue through the common policy")

func test_receipt_and_delivery_policies_are_data_and_do_not_need_another_order_engine() -> void:
	var orders := _orders({"pay_at":"on_take","queue_release":"after_take","rounding":"order_round"})
	if orders == null: return
	var guest: Dictionary = orders.arrive([_request()[0]], 2)
	var accepted: Dictionary = orders.admit(guest.id, {"meal":10.6})
	var economy := _economy()
	check_eq(orders.queue(), [], "configured acceptance releases queue")
	check_eq(orders.settle(accepted.id, economy).income, 11, "same shared settlement supports the configured rounding policy")
	check_eq(economy.sold, 0, "prepayment is separate from delivered items")
	orders.settle(accepted.id, economy)
	check_eq(economy.gold, 11.0, "prepayment cannot repeat")

func test_uncommitted_stock_or_wrong_owner_cannot_be_used_as_delivery_proof() -> void:
	var orders := _orders()
	if orders == null: return
	var guest: Dictionary = orders.arrive([_request()[0]], 2)
	var accepted: Dictionary = orders.admit(guest.id, {"meal":10.0})
	var line: Dictionary = orders.order(accepted.id).lines[0]
	orders.bind_unit(accepted.id, line.id, 11)
	var stock := _inventory(guest.id)
	var economy := _economy()
	var claim: Dictionary = stock.reserve_transfer(1, "pass", "guest:"+str(guest.id), "meal", 1, 2, 11)
	check(not orders.record_delivery(accepted.id, line.id, claim.id, stock, economy).is_empty(), "reservation is not a delivery")
	stock.pickup(claim.id)
	check(not orders.record_delivery(accepted.id, line.id, claim.id, stock, economy).is_empty(), "carried goods are not yet delivered")
	check_eq(economy.sold, 0, "uncommitted goods do not change sales")
	stock.cancel(claim.id)
	var soup := _deliver(stock, guest.id, "soup", 12)
	check(not orders.record_delivery(accepted.id, line.id, soup, stock, economy).is_empty(), "another unit or item cannot satisfy this line")

func test_unclaimed_customer_timeout_and_cancelled_admission_use_one_queue_state() -> void:
	var orders := _orders({"patience":2.0})
	if orders == null: return
	var first: Dictionary = orders.arrive([_request()[0]], 2)
	var second: Dictionary = orders.arrive([_request()[0]], 2)
	check(not orders.arrive([_request()[0]], 2).error.is_empty(), "full queue rejects admission")
	orders.claim_admission(first.id, 1)
	orders.advance(3.0)
	check_eq(orders.queue(), [first.id], "claimed customer retained while unclaimed customer leaves")
	check_eq(orders.guest(second.id).state, "leaving", "timeout produces a shared departure state")
	orders.cancel_admission(first.id, 1)
	orders.advance(0.1)
	check_eq(orders.queue(), [], "released timed-out customer can leave normally")

func test_order_restore_keeps_delivery_idempotence_and_rejects_forged_line_progress() -> void:
	var orders := _orders()
	if orders == null: return
	var guest: Dictionary = orders.arrive([_request()[0]], 2)
	var accepted: Dictionary = orders.admit(guest.id, {"meal":10.5})
	var line: Dictionary = orders.order(accepted.id).lines[0]
	orders.bind_unit(accepted.id, line.id, 11)
	var stock := _inventory(guest.id)
	var economy := _economy()
	var claim := _deliver(stock, guest.id, "meal", 11)
	orders.record_delivery(accepted.id, line.id, claim, stock, economy)
	orders.settle(accepted.id, economy)
	var saved: Dictionary = orders.snapshot()
	var reopened := _orders()
	check_eq(reopened.restore(saved, stock), "", "restore facts against authoritative delivery claims")
	reopened.record_delivery(accepted.id, line.id, claim, stock, economy)
	reopened.settle(accepted.id, economy)
	check_eq(economy.gold, 10.0, "restored order cannot credit the receipt twice")
	check_eq(economy.sold, 1, "restored delivery cannot increment sold twice")
	var broken: Dictionary = saved.duplicate(true)
	broken.orders[0].lines[0].delivered = 2
	check(not reopened.restore(broken, stock).is_empty(), "line progress cannot exceed committed proof")
	check_eq(reopened.snapshot(), saved, "bad restored order cannot partially replace live state")
	broken = saved.duplicate(true)
	broken.orders[0].lines[0].dish = "soup"
	check(not reopened.restore(broken, stock).is_empty(), "delivery cannot be relabeled as a dish different from the customer's request")
	check_eq(reopened.snapshot(), saved, "bad item identity cannot replace live state")

func test_restored_queue_membership_must_follow_the_shared_release_policy() -> void:
	var orders := _orders({"queue_release":"after_take"})
	if orders == null: return
	var guest: Dictionary = orders.arrive([_request()[0]], 2)
	orders.admit(guest.id, {"meal":10.0})
	var stock := _inventory(guest.id)
	var saved: Dictionary = orders.snapshot()
	var broken: Dictionary = saved.duplicate(true)
	broken.guests[0].queued = true
	check(not orders.restore(broken, stock).is_empty(), "accepted customer cannot rejoin the queue contrary to the template policy")
	check_eq(orders.snapshot(), saved, "queue policy validation is atomic")
