extends RefCounted
## Owns order/customer records. Rules retains policy, queries and synchronous events.

var orders: Array = []
var diners: Array = []
var customers: Array = []
var queue: Array = []
var lost := 0
var next_order := 1
var next_customer_id := 1
var order_clock := 0.0
var next_customer := 0.0
var order_ramp: Dictionary = {}

func admit_handoff(dish: String, seat: int, takeaway: bool, weights: Dictionary, ramp_orders: int, takeaway_open: bool) -> Dictionary:
	for key in weights: order_ramp[key] = mini(int(order_ramp.get(key, 0)) + 1, ramp_orders)
	if takeaway_open: order_ramp.takeaway = mini(int(order_ramp.get("takeaway", 0)) + 1, ramp_orders)
	var order := {"id": next_order, "wait": 0.0, "reserved": false, "dish": dish, "takeaway": takeaway, "seat": seat}
	orders.append(order)
	next_order += 1
	return order

func advance_handoff(delta: float) -> void:
	order_clock += delta
	for order in orders: order.wait += delta

func handoff_order(id: int) -> Dictionary:
	for order in orders:
		if order.id == id: return order
	return {}

func set_handoff_reserved(id: int, reserved: bool) -> void:
	for order in orders:
		if order.id == id: order.reserved = reserved

func remove_handoff(id: int) -> void:
	for index in orders.size():
		if orders[index].id == id:
			orders.remove_at(index)
			break

func add_diner(seat: int, dish: String, seconds: float) -> void:
	diners.append({"seat": seat, "dish": dish, "left": seconds})

func advance_diners(delta: float) -> void:
	for index in range(diners.size() - 1, -1, -1):
		diners[index].left -= delta
		if diners[index].left <= 0.000001: diners.remove_at(index)

func overflow_to_takeaway(free_seats: int) -> void:
	for order in orders:
		if order.reserved or order.takeaway or order.seat >= 0: continue
		if free_seats > 0: free_seats -= 1
		else: order.takeaway = true

func admit_single(kind: String, addon: bool, options: Array) -> Dictionary:
	var customer := {"id": next_customer_id, "kind": kind, "addon": addon, "state": "queue", "wait": 0.0, "claimed": false, "paid": 0, "options": options}
	next_customer_id += 1
	customers.append(customer)
	queue.append(customer.id)
	return customer

func reject_single() -> void:
	lost += 1

func single_customer(id: int) -> Dictionary:
	for customer in customers:
		if customer.id == id: return customer
	return {}

func claim_single() -> Dictionary:
	if queue.is_empty(): return {}
	var customer := single_customer(queue[0])
	if customer.claimed: return {}
	customer.claimed = true
	return customer

func advance_single_customer(customer: Dictionary, delta: float, patience: float) -> bool:
	if customer.state == "queue":
		customer.wait += delta
		if patience > 0.0 and customer.wait > patience and not customer.claimed:
			customer.state = "leaving"
			queue.erase(customer.id)
			lost += 1
			return true
	return false

func remove_leaving_single(customer: Dictionary) -> void:
	if customer.state == "leaving": customers.erase(customer)

func dequeue_single(id: int) -> void:
	queue.erase(id)

static func accept_single(customer: Dictionary, paid: int) -> void:
	customer.paid = paid
	customer.state = "paid"

static func leave_single(customer: Dictionary) -> void:
	customer.state = "leaving"
