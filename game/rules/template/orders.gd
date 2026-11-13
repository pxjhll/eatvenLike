extends RefCounted
## Shared order facts and settlement. Physical stock stays in Inventory;
## recipe execution and customer motion consume these records by stable IDs.
const Inventory := preload("res://game/rules/template/inventory.gd")
const Contract := preload("res://game/rules/shop_content_contract.gd")
const POLICY := {"pay_at":"on_deliver", "queue_release":"after_delivery", "rounding":"dish_tenth_carry", "patience":0.0}

var last_error := ""
var _policy: Dictionary
var _state: Dictionary = {"version":1, "policy":"", "next_guest":1, "next_order":1, "next_line":1, "lost":0, "guests":[], "orders":[]}

func _init(options: Dictionary = {}) -> void:
	_policy = POLICY.duplicate()
	for key in options:
		if key=="request_at":
			if options[key]!="admission": last_error = "invalid deferred request policy"; return
			_policy[key] = options[key]
			continue
		if not _policy.has(key): last_error = "unsupported order policy"; return
		_policy[key] = options[key]
	if _policy.pay_at not in ["on_take", "on_deliver"] or _policy.queue_release not in ["after_take", "after_delivery"] or _policy.rounding not in ["dish_tenth_carry", "order_round"]: last_error = "unsupported order policy"; return
	if not (_policy.patience is float or _policy.patience is int) or not is_finite(float(_policy.patience)) or _policy.patience < 0.0: last_error = "invalid customer patience"; return
	_policy.patience = float(_policy.patience)
	_state.policy = Contract._canonical(_policy).sha256_text()

func arrive(request: Array, capacity: int) -> Dictionary:
	if not last_error.is_empty(): return {"error":last_error, "id":-1}
	if (not _request_valid(request) and not (request.is_empty() and _policy.get("request_at")=="admission")) or capacity < 1: return {"error":"invalid customer request or queue capacity", "id":-1}
	if _policy.get("request_at")=="admission" and not request.is_empty(): return {"error":"admission menu cannot be selected at arrival","id":-1}
	if queue().size() >= capacity:
		return reject_arrival()
	var guest := _guest()
	guest.id = _state.next_guest
	_state.next_guest += 1
	guest.request = request.duplicate(true)
	_state.guests.append(guest)
	return {"error":"", "id":guest.id}

func reject_arrival() -> Dictionary:
	_state.lost += 1
	return {"error":"queue full", "id":-1}

func queue() -> Array:
	var out: Array = []
	for guest in _state.guests:
		if guest.queued: out.append(guest.id)
	return out

func claim_admission(guest_id: int, worker: int) -> String:
	var guest := _find(_state.guests, guest_id)
	if guest.is_empty() or guest.state != "queue" or worker < 1: return "customer unavailable"
	if guest.claimed not in [-1, worker]: return "customer already claimed"
	guest.claimed = worker
	return ""

func cancel_admission(guest_id: int, worker: int) -> String:
	var guest := _find(_state.guests, guest_id)
	if guest.is_empty(): return "unknown customer"
	if guest.claimed == -1: return ""
	if guest.claimed != worker or guest.order >= 0: return "admission claim differs"
	guest.claimed = -1
	return ""

func admit(guest_id: int, quotes: Dictionary, worker: int = -1) -> Dictionary:
	var guest := _find(_state.guests, guest_id)
	if guest.is_empty(): return {"error":"unknown customer", "id":-1}
	if guest.order >= 0: return {"error":"", "id":guest.order}
	if guest.request.is_empty(): return {"error":"admission requires a selected request","id":-1}
	if guest.state != "queue" or (guest.claimed != -1 and guest.claimed != worker): return {"error":"customer admission unavailable", "id":-1}
	var total := 0.0
	for index in guest.request.size():
		var row: Dictionary = guest.request[index]
		var quote: Variant = quotes.get(index,quotes.get(row.dish))
		if not (quote is float or quote is int) or not is_finite(float(quote)) or quote < 0.0: return {"error":"missing or invalid dish quote", "id":-1}
		total += float(quote) * int(row.qty)
	if not is_finite(total): return {"error":"invalid order quote", "id":-1}
	var order := _order()
	order.id = _state.next_order
	_state.next_order += 1
	order.guest = guest_id
	order.quote = total
	for index in guest.request.size():
		var row: Dictionary = guest.request[index]
		var line := _line()
		line.id = _state.next_line
		_state.next_line += 1
		for key in ["dish", "recipe", "item", "qty"]: line[key] = row[key]
		if row.has("options"): line.options = row.options.duplicate()
		line.price = float(quotes.get(index,quotes.get(row.dish)))
		order.lines.append(line)
	_state.orders.append(order)
	guest.order = order.id
	guest.state = "waiting"
	guest.claimed = -1
	if _policy.queue_release == "after_take": guest.queued = false
	return {"error":"", "id":order.id}

func admit_selected(guest_id: int, request: Array, quotes: Dictionary, worker: int = -1) -> Dictionary:
	var guest := _find(_state.guests,guest_id)
	if _policy.get("request_at")!="admission" or guest.is_empty() or guest.order!=-1 or guest.state!="queue" or not guest.request.is_empty() or not _request_valid(request): return {"error":"customer cannot commit selected admission","id":-1}
	guest.request = request.duplicate(true)
	var result := admit(guest_id,quotes,worker)
	if not String(result.error).is_empty(): guest.request = []
	return result

func bind_unit(order_id: int, line_id: int, unit: int, quantity: int = 1) -> String:
	var line := _order_line(order_id, line_id)
	if line.is_empty() or unit < 1 or quantity < 1: return "invalid production binding"
	for order in _state.orders:
		for row in order.lines:
			for binding in row.units:
				if binding.unit == unit: return "" if row.id == line_id and binding.qty == quantity else "production unit already bound"
	var bound := 0
	for binding in line.units: bound += int(binding.qty)
	if bound + quantity > int(line.qty): return "production quantity exceeds order line"
	line.units.append({"unit":unit, "qty":quantity, "delivered":0})
	return ""

func record_delivery(order_id: int, line_id: int, proof: int, inventory: RefCounted, economy: RefCounted) -> String:
	var order := _find(_state.orders, order_id)
	var line := _order_line(order_id, line_id)
	if order.is_empty() or line.is_empty(): return "unknown order line"
	if proof in line.claims: return ""
	for other in _state.orders:
		for row in other.lines:
			if proof in row.claims: return "delivery already belongs to another line"
	var claim: Dictionary = inventory.claim(proof)
	var error := _proof_error(order, line, claim)
	if not error.is_empty(): return error
	var binding := _binding(line, _claim_owner(claim))
	if int(binding.delivered) + int(claim.count) > int(binding.qty) or int(line.delivered) + int(claim.count) > int(line.qty): return "delivery exceeds requested quantity"
	binding.delivered += int(claim.count)
	line.delivered += int(claim.count)
	line.claims.append(proof)
	economy.count_handoff(line.dish, claim.count)
	var complete := true
	for row in order.lines:
		if row.delivered != row.qty: complete = false; break
	if complete:
		order.state = "delivered"
		var guest := _find(_state.guests, order.guest)
		guest.state = "served"
		guest.queued = false
	return ""

func settle(order_id: int, economy: RefCounted) -> Dictionary:
	var order := _find(_state.orders, order_id)
	if order.is_empty(): return {"error":"unknown order", "income":0}
	if order.paid: return {"error":"", "income":order.income, "duplicate":true}
	if _policy.pay_at == "on_deliver" and order.state != "delivered": return {"error":"order not delivered", "income":0}
	var amount: float = roundf(order.quote) if _policy.rounding == "order_round" else float(order.quote)
	var receipt: Dictionary = economy.credit_order(amount)
	order.income = int(receipt.income)
	order.paid = true
	return {"error":"", "income":order.income, "duplicate":false}

func advance(dt: float, paused := false) -> String:
	if not is_finite(dt) or dt < 0.0: return "invalid customer time"
	if paused or dt == 0.0: return ""
	for guest in _state.guests:
		if guest.state not in ["queue","waiting"]: continue
		guest.wait += dt
		if guest.state == "queue" and float(_policy.patience) > 0.0 and guest.wait >= float(_policy.patience) and guest.claimed == -1:
			guest.state = "leaving"
			guest.queued = false
			_state.lost += 1
	return ""

func assign_seat(id: int, seat: String) -> String:
	var row := _find(_state.guests, id)
	if row.is_empty() or row.state != "waiting" or not row.seat.is_empty() or seat.is_empty(): return "customer cannot acquire seat"
	for other in _state.guests:
		if other.id != id and other.seat == seat and other.state not in ["leaving","gone"]: return "seat already occupied"
	row.seat = seat
	return ""

func resolve_request(id: int, request: Array) -> String:
	var row := _find(_state.guests,id)
	if row.is_empty() or row.state!="queue" or row.order!=-1 or row.claimed!=-1 or not _request_valid(request) or request.size()!=row.request.size(): return "customer request is already committed or invalid"
	for index in request.size():
		for key in ["dish","qty","options"]:
			if row.request[index].get(key)!=request[index].get(key): return "route resolution cannot replace selected food or quantities"
	row.request = request.duplicate(true)
	return ""

func prepare_meal(id: int, seconds: float) -> String:
	var row := _find(_state.guests,id)
	if row.is_empty() or row.state!="served" or not is_finite(seconds) or seconds<0.0: return "meal duration requires actual delivery"
	row.meal_left = seconds
	return ""

func begin_meal(id: int, seconds: float, inventory: RefCounted) -> String:
	var row := _find(_state.guests, id)
	if row.is_empty() or not is_finite(seconds) or seconds < 0.0: return "invalid meal request"
	if row.state == "eating": return ""
	var order := _find(_state.orders, row.order)
	if row.state != "served" or order.is_empty() or not order.paid: return "meal requires a paid and delivered order"
	var error := _meal_stock(order, inventory)
	if not error.is_empty(): return error
	row.state = "eating"
	row.meal_left = seconds
	return ""

func advance_meals(dt: float, inventory: RefCounted, paused := false) -> String:
	if not is_finite(dt) or dt < 0.0: return "invalid meal time"
	if paused or dt == 0.0: return ""
	for row in _state.guests:
		if row.state != "eating": continue
		var remaining := maxf(0.0, float(row.meal_left) - dt)
		if remaining > 0.000001:
			row.meal_left = remaining
			continue
		var order := _find(_state.orders, row.order)
		var error := _meal_stock(order, inventory)
		if not error.is_empty(): return error
		var candidate := Inventory.new()
		error = candidate.restore(inventory.snapshot())
		if not error.is_empty(): return error
		var proofs: Array = []
		for entry in _meal_entries(order):
			var result := candidate.reserve_operation(0, "guest:" + str(row.id), {entry.item:entry.count}, {}, entry.owner)
			if not String(result.error).is_empty(): return result.error
			error = candidate.complete_operation(result.id)
			if not error.is_empty(): return error
			proofs.append(int(result.id))
		error = inventory.restore(candidate.snapshot())
		if not error.is_empty(): return error
		row.consumption = proofs
		row.meal_left = 0.0
		row.state = "leaving"
	return ""

func finish_departure(id: int) -> String:
	var row := _find(_state.guests, id)
	if row.is_empty(): return "unknown customer"
	if row.state == "gone": return ""
	if row.state != "leaving": return "customer is not leaving"
	row.state = "gone"
	return ""

func guest(id: int) -> Dictionary:
	return _find(_state.guests, id).duplicate(true)

func order(id: int) -> Dictionary:
	return _find(_state.orders, id).duplicate(true)

func snapshot() -> Dictionary:
	return _state.duplicate(true)

## Current service reads do not need departed customers and their receipts.
## Full history remains available through snapshot() for saves and validation.
func active_snapshot() -> Dictionary:
	var result := _state.duplicate()
	var active := {}
	result.guests = []
	for guest in _state.guests:
		if guest.state == "gone": continue
		active[guest.id] = true
		result.guests.append(guest.duplicate(true))
	result.orders = []
	for order in _state.orders:
		if active.has(order.guest): result.orders.append(order.duplicate(true))
	return result

func restore(data: Dictionary, inventory: RefCounted) -> String:
	var error := _validate(data, inventory)
	if not error.is_empty(): return error
	_state = data.duplicate(true)
	return ""

func _validate(data: Dictionary, inventory: RefCounted) -> String:
	if not Inventory._shape(data, {"version":0, "policy":"", "next_guest":0, "next_order":0, "next_line":0, "lost":0, "guests":[], "orders":[]}): return "invalid order state shape"
	if data.version != 1 or data.policy != _state.policy or data.next_guest < 1 or data.next_order < 1 or data.next_line < 1 or data.lost < 0: return "order policy or sequence differs"
	var guests := {}
	for guest in data.guests:
		if not Inventory._shape(guest, _guest()): return "invalid guest state"
		var unresolved: bool = _policy.get("request_at")=="admission" and guest.order==-1
		if unresolved:
			if not guest.request.is_empty(): return "unaccepted admission menu was selected early"
		elif not _request_valid(guest.request): return "invalid guest request"
		if guest.id < 1 or guest.id >= data.next_guest or guests.has(guest.id) or guest.order < -1 or guest.claimed < -1 or guest.claimed == 0 or not is_finite(guest.wait) or guest.wait < 0.0: return "invalid guest identity or values"
		if guest.state not in ["queue", "waiting", "served", "eating", "leaving", "gone"]: return "invalid customer state"
		if not is_finite(guest.meal_left) or guest.meal_left < 0.0 or (guest.state not in ["served","eating"] and guest.meal_left != 0.0): return "invalid meal clock"
		if guest.state not in ["leaving", "gone"] and not guest.consumption.is_empty(): return "customer has premature consumption"
		if guest.state == "queue" and (guest.order != -1 or not guest.queued): return "queue customer has an accepted order"
		if guest.state in ["waiting", "served", "eating"] and guest.order < 1: return "accepted customer has no order"
		if guest.state == "waiting" and guest.queued != (_policy.queue_release == "after_delivery"): return "customer queue membership differs from release policy"
		if guest.state != "queue" and guest.claimed != -1: return "accepted customer retains an admission claim"
		if guest.state in ["served", "eating", "leaving", "gone"] and guest.queued: return "departing customer remains queued"
		guests[guest.id] = guest
	var orders := {}
	var lines := {}
	var units := {}
	var proofs := {}
	for order in data.orders:
		if not Inventory._shape(order, _order()): return "invalid order record"
		if order.id < 1 or order.id >= data.next_order or orders.has(order.id) or not guests.has(order.guest) or guests[order.guest].order != order.id or order.lines.is_empty(): return "invalid order identity"
		if not is_finite(order.quote) or order.quote < 0.0 or order.income < 0 or order.state not in ["accepted", "delivered"]: return "invalid receipt values"
		if not order.paid and order.income != 0: return "unpaid order has income"
		if order.paid and _policy.pay_at == "on_deliver" and order.state != "delivered": return "incomplete order has a delivery receipt"
		var quote := 0.0
		var complete := true
		var request: Array = guests[order.guest].request
		if request.size() != order.lines.size(): return "order lines differ from customer request"
		var request_index := 0
		for line in order.lines:
			if not _with_options_shape(line, _line()): return "invalid order line shape"
			if line.get("options") != request[request_index].get("options"): return "order line options differ from customer request"
			for key in ["dish", "recipe", "item", "qty"]:
				if line[key] != request[request_index][key]: return "order line identity differs from customer request"
			request_index += 1
			if line.id < 1 or line.id >= data.next_line or lines.has(line.id) or line.qty < 1 or line.delivered < 0 or line.delivered > line.qty or not is_finite(line.price) or line.price < 0.0: return "invalid order line quantities"
			for key in ["dish", "recipe", "item"]:
				if String(line[key]).is_empty(): return "missing order line identity"
			lines[line.id] = true
			quote += float(line.price) * int(line.qty)
			if line.delivered != line.qty: complete = false
			var bound := 0
			var delivered := 0
			var by_unit := {}
			for binding in line.units:
				if not Inventory._shape(binding, {"unit":0, "qty":0, "delivered":0}) or binding.unit < 1 or binding.qty < 1 or binding.delivered < 0 or binding.delivered > binding.qty or units.has(binding.unit): return "invalid or duplicated recipe unit"
				units[binding.unit] = true
				bound += int(binding.qty)
				by_unit[binding.unit] = 0
			if bound > line.qty: return "recipe units exceed line quantity"
			for proof in line.claims:
				if not proof is int or proof < 1 or proofs.has(proof): return "invalid or reused delivery proof"
				var claim: Dictionary = inventory.claim(proof)
				var error := _proof_error(order, line, claim)
				if not error.is_empty(): return error
				proofs[proof] = true
				delivered += int(claim.count)
				by_unit[_claim_owner(claim)] += int(claim.count)
			if delivered != line.delivered: return "line progress differs from physical delivery proofs"
			for binding in line.units:
				if binding.delivered != by_unit[binding.unit]: return "unit progress differs from delivery proofs"
		if not is_finite(quote) or quote != order.quote or (order.state == "delivered") != complete: return "order total or completion differs from lines"
		if order.paid:
			var expected := roundi(order.quote) if _policy.rounding == "order_round" else floori(order.quote)
			if order.income < expected or order.income > expected + (0 if _policy.rounding == "order_round" else 1): return "receipt differs from configured rounding"
		var guest: Dictionary = guests[order.guest]
		if (complete and guest.state not in ["served", "eating", "leaving", "gone"]) or (not complete and guest.state != "waiting"): return "customer state differs from order completion"
		if guest.state in ["eating", "leaving", "gone"] and not order.paid: return "meal has no receipt"
		if guest.state in ["served", "eating"]:
			var error := _meal_stock(order, inventory)
			if not error.is_empty(): return error
		if guest.state in ["leaving", "gone"]:
			var entries := _meal_entries(order)
			if guest.consumption.size() != entries.size(): return "meal consumption differs from delivered food"
			for index in entries.size():
				var proof: Variant = guest.consumption[index]
				if not proof is int or proofs.has(proof): return "invalid or reused meal consumption proof"
				var claim: Dictionary = inventory.claim(proof)
				var entry: Dictionary = entries[index]
				if claim.is_empty() or claim.kind != "operation" or claim.state != "completed" or claim.worker != 0 or claim.from != "guest:" + str(order.guest) or claim.to != claim.from or claim.owner != entry.owner or claim.consumes != {entry.item:entry.count} or not claim.produces.is_empty(): return "meal consumption has no matching stock operation"
				proofs[proof] = true
		orders[order.id] = order
	for guest in data.guests:
		if guest.order >= 0 and not orders.has(guest.order): return "customer order missing"
	return ""

static func _meal_entries(order: Dictionary) -> Array:
	var entries: Array = []
	for line in order.lines:
		for binding in line.units: entries.append({"item":String(line.item), "count":int(binding.qty), "owner":int(binding.unit)})
	return entries

static func _meal_stock(order: Dictionary, inventory: RefCounted) -> String:
	for entry in _meal_entries(order):
		if inventory.quantity("guest:" + str(order.guest), entry.item, entry.owner, true) < entry.count: return "meal food unavailable"
	return ""

func _order_line(order_id: int, line_id: int) -> Dictionary:
	var order := _find(_state.orders, order_id)
	return {} if order.is_empty() else _find(order.lines, line_id)

static func _proof_error(order: Dictionary, line: Dictionary, claim: Dictionary) -> String:
	if claim.is_empty() or claim.kind != "transfer" or claim.state != "dropped" or claim.to != "guest:" + str(order.guest) or claim.item != line.item: return "no committed matching delivery"
	if _binding(line, _claim_owner(claim)).is_empty(): return "delivery belongs to another production unit"
	return ""

static func _claim_owner(claim: Dictionary) -> int:
	return int(claim.allocate_owner) if claim.allocate_owner != -2 else int(claim.owner)

static func _binding(line: Dictionary, unit: int) -> Dictionary:
	for binding in line.units:
		if binding.unit == unit: return binding
	return {}

static func _request_valid(request: Array) -> bool:
	if request.is_empty(): return false
	for row in request:
		if not _with_options_shape(row, {"dish":"", "recipe":"", "item":"", "qty":0}) or row.qty < 1: return false
		for key in ["dish", "recipe", "item"]:
			if String(row[key]).is_empty(): return false
	return true

static func _with_options_shape(value: Variant, example: Dictionary) -> bool:
	if not value is Dictionary: return false
	if not value.has("options"): return Inventory._shape(value,example)
	if not value.options is Array: return false
	var seen := {}
	for id in value.options:
		if not id is String or id.is_empty() or seen.has(id): return false
		seen[id] = true
	var plain: Dictionary = value.duplicate()
	plain.erase("options")
	return Inventory._shape(plain,example)

static func _find(rows: Array, id: int) -> Dictionary:
	for row in rows:
		if row.id == id: return row
	return {}

static func _guest() -> Dictionary:
	return {"id":0, "request":[], "order":-1, "state":"queue", "queued":true, "claimed":-1, "wait":0.0,
		"seat":"", "meal_left":0.0, "consumption":[]}

static func _order() -> Dictionary:
	return {"id":0, "guest":0, "quote":0.0, "income":0, "paid":false, "state":"accepted", "lines":[]}

static func _line() -> Dictionary:
	return {"id":0, "dish":"", "recipe":"", "item":"", "qty":0, "price":0.0, "delivered":0, "units":[], "claims":[]}
