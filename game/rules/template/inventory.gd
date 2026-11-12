extends RefCounted
## One authoritative lot/claim ledger. Locations and ownership are data; there
## are no shop modes or per-mode inventory backends. All reads are detached.
const ANY_OWNER := -2
const SHARED := -1
const ACTIVE := ["reserved", "held"]
const Bundles := preload("res://game/rules/template/bundle_transfers.gd")

var _state: Dictionary = {"version":1, "next_lot":1, "next_claim":1, "next_bundle":1,
	"places":{}, "lots":[], "claims":[], "bundles":[], "created":{}, "consumed":{}}

func configure(place: String, capacity: int = -1, infinite_items: Array = []) -> String:
	if place.is_empty() or capacity < -1: return "invalid container"
	if is_hand_place(place) and (not _actor_valid(_hand_actor(place)) or _hand_place(_hand_actor(place)) != place or capacity != -1 or not infinite_items.is_empty()): return "invalid managed hand container"
	var seen := {}
	for item in infinite_items:
		if not item is String or item.is_empty() or seen.has(item): return "invalid source items"
		seen[item] = true
	var definition := {"capacity":capacity, "infinite":infinite_items.duplicate()}
	if _state.places.has(place):
		return "" if _state.places[place] == definition else "container already configured"
	_state.places[place] = definition
	return ""

func seed(place: String, item: String, count: int, owner: int = SHARED) -> Dictionary:
	if is_hand_place(place): return _failure("hand stock requires a pickup claim")
	if not _state.places.has(place) or item.is_empty() or count <= 0 or owner < SHARED: return _failure("invalid stock")
	if item in _state.places[place].infinite: return _failure("cannot seed an infinite item")
	if _free(place) < count: return _failure("container full")
	var lot := _insert(place, item, count, owner)
	_add(_state.created, item, count)
	return {"error":"", "lot":lot.id}

func quantity(place: String, item: String = "", owner: int = ANY_OWNER, available_only := false) -> int:
	var count := 0
	for lot in _state.lots:
		if lot.place != place or (not item.is_empty() and lot.item != item) or (owner != ANY_OWNER and lot.owner != owner): continue
		count += int(lot.count) - (_reserved_lot(int(lot.id)) if available_only else 0)
	return count

func remaining_capacity(place: String) -> int:
	return _free(place) if _state.places.has(place) else 0

func incoming(place: String, item: String, owner: int = ANY_OWNER) -> int:
	var count := 0
	for task in _state.claims:
		if task.kind != "transfer" or task.state not in ACTIVE or task.to != place or task.item != item: continue
		var assigned: int = task.allocate_owner if task.allocate_owner != ANY_OWNER else task.owner
		if owner == ANY_OWNER or assigned == owner or (assigned == ANY_OWNER and task.minted and owner == SHARED):
			count += int(task.count)
		elif assigned == ANY_OWNER and not task.minted:
			var parts: Array = task.parts if task.state == "reserved" else task.held
			for part in parts:
				var original_owner: int = _find(_state.lots, part.lot).owner if task.state == "reserved" else part.owner
				if original_owner == owner: count += int(part.count)
	return count

func reserve_transfer(worker: int, source: String, destination: String, item: String,
		requested: int, capacity: int, owner: int = ANY_OWNER, allocate_owner: int = ANY_OWNER) -> Dictionary:
	if worker <= 0: return _failure("invalid worker")
	return reserve_actor_transfer("staff:" + str(worker), source, destination, item, requested, capacity, owner, allocate_owner)

func reserve_actor_transfer(actor: String, source: String, destination: String, item: String,
		requested: int, capacity: int, owner: int = ANY_OWNER, allocate_owner: int = ANY_OWNER) -> Dictionary:
	return _reserve_actor_transfer(actor, source, destination, item, requested, capacity, owner, allocate_owner)

func reserve_bundle(actor: String, entries: Array, capacity: int) -> Dictionary:
	return Bundles.reserve(self, actor, entries, capacity)

func bundle(id: int) -> Dictionary:
	return _find(_state.bundles, id).duplicate(true)

func pickup_bundle_part(id: int, child: int) -> String:
	return Bundles.apply(self, id, "pickup_part", child)

func pickup_bundle(id: int) -> String:
	return Bundles.apply(self, id, "pickup")

func drop_bundle(id: int) -> String:
	return Bundles.apply(self, id, "drop")

func cancel_bundle(id: int) -> String:
	return Bundles.apply(self, id, "cancel")

func _reserve_actor_transfer(actor: String, source: String, destination: String, item: String,
		requested: int, capacity: int, owner: int, allocate_owner: int, group: int = -1) -> Dictionary:
	if not _actor_valid(actor) or requested <= 0 or capacity <= 0 or owner < ANY_OWNER or allocate_owner < ANY_OWNER or item.is_empty(): return _failure("invalid transfer")
	if not _state.places.has(source) or not _state.places.has(destination) or source == destination: return _failure("invalid transfer containers")
	if is_hand_place(source) or is_hand_place(destination): return _failure("hand containers are managed by pickup and drop")
	if item in _state.places[destination].infinite: return _failure("integrated supply cannot receive finite stock")
	for active in _state.claims:
		if active.actor == actor and active.state in ACTIVE and (group < 1 or active.group != group): return _failure("carrier already assigned")
	var minted: bool = item in _state.places[source].infinite
	var amount := mini(requested, mini(capacity, _free(destination)))
	if not minted: amount = mini(amount, quantity(source, item, owner, true))
	if amount <= 0: return _failure("stock or capacity unavailable")
	var parts: Array = [] if minted else _parts(source, {item:amount}, owner)
	var task := _task("transfer", _staff_id(actor), source, destination, owner)
	task.actor = actor
	task.group = group
	task.item = item
	task.count = amount
	task.capacity = capacity
	task.allocate_owner = allocate_owner
	task.minted = minted
	task.parts = parts
	task.space = amount
	configure(_hand_place(actor))
	return _store(task)

func pickup(id: int) -> String:
	return _pickup(id, false)

func _pickup(id: int, grouped: bool) -> String:
	var task := _find(_state.claims, id)
	if task.is_empty() or task.kind != "transfer": return "unknown transfer"
	if task.group > 0 and not grouped: return "bundle child requires bundle lifecycle"
	if task.state in ["held", "dropped"]: return ""
	if task.state != "reserved": return "transfer not reserved"
	var hand := _hand_place(task.actor)
	if task.minted:
		var owner: int = task.allocate_owner if task.allocate_owner != ANY_OWNER else (task.owner if task.owner != ANY_OWNER else SHARED)
		var lot := _insert(hand, task.item, task.count, owner)
		task.held.append({"lot":lot.id, "count":task.count, "owner":owner})
		_add(_state.created, task.item, task.count)
	else:
		for part in task.parts:
			var original := _find(_state.lots, part.lot)
			if original.is_empty() or original.count < part.count: return "reserved stock unavailable"
		# All checks precede the first mutation.
		for part in task.parts:
			var original := _find(_state.lots, part.lot)
			var owner: int = original.owner
			_remove(original, part.count)
			var lot := _insert(hand, task.item, part.count, task.allocate_owner if task.allocate_owner != ANY_OWNER else owner)
			task.held.append({"lot":lot.id, "count":part.count, "owner":owner})
	task.state = "held"
	return ""

func drop(id: int) -> String:
	return _drop(id, false)

func _drop(id: int, grouped: bool) -> String:
	var task := _find(_state.claims, id)
	if task.is_empty() or task.kind != "transfer": return "unknown transfer"
	if task.group > 0 and not grouped: return "bundle child requires bundle lifecycle"
	if task.state == "dropped": return ""
	if task.state != "held" or not _held_valid(task): return "carried stock unavailable"
	for held in task.held: _find(_state.lots, held.lot).place = task.to
	task.state = "dropped"
	return ""

func reserve_operation(worker: int, place: String, consumes: Dictionary, produces: Dictionary,
		owner: int = SHARED, output_place: String = "") -> Dictionary:
	var destination := place if output_place.is_empty() else output_place
	if is_hand_place(place) or is_hand_place(destination): return _failure("operation requires a declared stock container")
	if worker < 0 or owner < SHARED or not _counts_valid(consumes) or not _counts_valid(produces) or (consumes.is_empty() and produces.is_empty()): return _failure("invalid operation")
	if not _state.places.has(place) or not _state.places.has(destination): return _failure("unknown operation container")
	if worker > 0 and _busy(worker): return _failure("worker already assigned")
	var finite := _finite_inputs(place, consumes)
	for item in finite:
		if quantity(place, item, owner, true) < int(finite[item]): return _failure("recipe input unavailable")
	for item in produces:
		if item in _state.places[destination].infinite: return _failure("integrated supply cannot hold finite output")
	var space := maxi(0, _total(produces) - (_total(finite) if place == destination else 0))
	if _free(destination) < space: return _failure("recipe output capacity unavailable")
	var task := _task("operation", worker, place, destination, owner)
	task.parts = _parts(place, finite, owner)
	task.consumes = consumes.duplicate(true)
	task.produces = produces.duplicate(true)
	task.count = _total(produces)
	task.space = space
	return _store(task)

func complete_operation(id: int) -> String:
	var task := _find(_state.claims, id)
	if task.is_empty() or task.kind != "operation": return "unknown operation"
	if task.state == "completed": return ""
	if task.state != "reserved": return "operation not reserved"
	for part in task.parts:
		var lot := _find(_state.lots, part.lot)
		if lot.is_empty() or lot.count < part.count: return "recipe input unavailable"
	for part in task.parts:
		var lot := _find(_state.lots, part.lot)
		_add(_state.consumed, lot.item, part.count)
		_remove(lot, part.count)
	for item in task.consumes:
		if item not in _state.places[task.from].infinite: continue
		# An installed source supplies an input at use, without a loose lot or
		# a fictional employee pickup. Both sides of conservation commit once.
		_add(_state.created, item, task.consumes[item])
		_add(_state.consumed, item, task.consumes[item])
	for item in task.produces:
		_insert(task.to, item, task.produces[item], task.owner)
		_add(_state.created, item, task.produces[item])
	task.state = "completed"
	return ""

func cancel(id: int) -> String:
	return _cancel(id, false)

func _cancel(id: int, grouped: bool) -> String:
	var task := _find(_state.claims, id)
	if task.is_empty(): return "unknown claim"
	if task.group > 0 and not grouped: return "bundle child requires bundle lifecycle"
	if task.state == "cancelled": return ""
	if task.state not in ACTIVE: return "claim already committed"
	if task.state == "held":
		if not _held_valid(task): return "carried stock unavailable"
		for held in task.held:
			var lot := _find(_state.lots, held.lot)
			if task.minted:
				_add(_state.consumed, lot.item, lot.count)
				_state.lots.erase(lot)
			else:
				lot.place = task.from
				lot.owner = held.owner
	task.state = "cancelled"
	return ""

func claim(id: int) -> Dictionary:
	return _find(_state.claims, id).duplicate(true)

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func restore(data: Dictionary) -> String:
	var candidate: RefCounted = get_script().new()
	candidate._state = data.duplicate(true)
	var errors: Array = candidate.audit()
	if not errors.is_empty(): return String(errors[0])
	_state = candidate._state
	return ""

func audit() -> Array:
	var errors: Array = []
	if not _shape(_state, {"version":1, "next_lot":1, "next_claim":1, "next_bundle":1, "places":{}, "lots":[], "claims":[], "bundles":[], "created":{}, "consumed":{}}): return ["invalid inventory shape"]
	if _state.version != 1 or _state.next_lot < 1 or _state.next_claim < 1 or _state.next_bundle < 1: return ["invalid inventory version or sequence"]
	if not _counts_valid(_state.created) or not _counts_valid(_state.consumed): return ["invalid inventory accounting"]
	for place in _state.places:
		var definition: Variant = _state.places[place]
		if not place is String or place.is_empty() or not _shape(definition, {"capacity":0, "infinite":[]}): return ["invalid container definition"]
		if definition.capacity < -1: return ["invalid container capacity"]
		if is_hand_place(place) and (not _actor_valid(_hand_actor(place)) or _hand_place(_hand_actor(place)) != place or definition.capacity != -1 or not definition.infinite.is_empty()): return ["invalid hand definition"]
		var items := {}
		for item in definition.infinite:
			if not item is String or item.is_empty() or items.has(item): return ["invalid source item"]
			items[item] = true
	var lot_ids := {}
	var totals := {}
	for lot in _state.lots:
		if not _shape(lot, {"id":0, "place":"", "item":"", "count":0, "owner":0}): return ["invalid lot shape"]
		if lot.id < 1 or lot.id >= _state.next_lot or lot_ids.has(lot.id) or lot.count <= 0 or lot.owner < SHARED or lot.item.is_empty() or not _state.places.has(lot.place): return ["invalid lot identity, amount or owner"]
		if lot.item in _state.places[lot.place].infinite: return ["infinite supply has a finite lot"]
		lot_ids[lot.id] = lot
		_add(totals, lot.item, lot.count)
	var claim_ids := {}
	var actors := {}
	var held_ids := {}
	for task in _state.claims:
		if not _shape(task, _task("", 0, "", "", 0)): return ["invalid claim shape"]
		if task.id < 1 or task.id >= _state.next_claim or claim_ids.has(task.id): return ["invalid claim identity"]
		claim_ids[task.id] = true
		if task.kind not in ["transfer", "operation"] or task.state not in ACTIVE + ["dropped", "completed", "cancelled"]: return ["invalid claim kind or state"]
		if task.group != -1 and (task.group < 1 or task.kind != "transfer"): return ["invalid claim group"]
		if not _state.places.has(task.from) or not _state.places.has(task.to) or task.owner < ANY_OWNER or task.allocate_owner < ANY_OWNER or task.worker < 0 or task.count < 0 or task.space < 0: return ["invalid claim values"]
		if task.kind == "transfer":
			if not _actor_valid(task.actor) or task.worker != _staff_id(task.actor) or is_hand_place(task.from) or is_hand_place(task.to) or task.from == task.to or task.count <= 0 or task.count > task.capacity or task.space != task.count or task.item.is_empty() or not task.consumes.is_empty() or not task.produces.is_empty() or task.state == "completed": return ["invalid transfer claim"]
			if task.minted != (task.item in _state.places[task.from].infinite): return ["invalid source claim"]
		else:
			if task.actor != ("staff:" + str(task.worker) if task.worker > 0 else "") or is_hand_place(task.from) or is_hand_place(task.to): return ["invalid operation actor or container"]
			if task.owner < SHARED or task.minted or not _counts_valid(task.consumes) or not _counts_valid(task.produces) or (task.consumes.is_empty() and task.produces.is_empty()) or task.state in ["held", "dropped"]: return ["invalid operation claim"]
			if task.count != _total(task.produces) or task.space != maxi(0, task.count - (_total(_finite_inputs(task.from, task.consumes)) if task.from == task.to else 0)): return ["invalid operation capacity claim"]
			for item in task.produces:
				if item in _state.places[task.to].infinite: return ["recipe produces into integrated supply"]
		var part_total := 0
		var recipe_counts := {}
		var parts_seen := {}
		for part in task.parts:
			if not _shape(part, {"lot":0, "count":0}) or part.lot < 1 or part.count <= 0 or parts_seen.has(part.lot): return ["invalid reserved part"]
			parts_seen[part.lot] = true
			part_total += int(part.count)
			if task.state != "reserved": continue
			var lot: Dictionary = lot_ids.get(part.lot, {})
			if lot.is_empty() or lot.place != task.from or (task.owner != ANY_OWNER and lot.owner != task.owner): return ["reserved lot location or owner differs"]
			if task.kind == "transfer" and lot.item != task.item: return ["reserved item differs"]
			_add(recipe_counts, lot.item, part.count)
		if task.kind == "transfer" and part_total != (0 if task.minted else int(task.count)): return ["transfer reservation amount differs"]
		if task.kind == "operation" and task.state == "reserved" and recipe_counts != _finite_inputs(task.from, task.consumes): return ["recipe reservation differs"]
		if task.state in ACTIVE and not task.actor.is_empty():
			if actors.has(task.actor) and (task.group < 1 or actors[task.actor] != task.group): return ["carrier has multiple assignments"]
			actors[task.actor] = task.group
		var held_total := 0
		for held in task.held:
			if not _shape(held, {"lot":0, "count":0, "owner":0}) or held.lot < 1 or held.count <= 0 or held.owner < SHARED: return ["invalid held part"]
			if not task.minted and task.owner != ANY_OWNER and held.owner != task.owner: return ["carried return ownership differs from source claim"]
			held_total += int(held.count)
			if task.state == "held":
				if held_ids.has(held.lot): return ["carried lot claimed twice"]
				held_ids[held.lot] = true
		if task.state == "held" and (held_total != task.count or not _held_valid(task)): return ["carried goods differ from claim"]
		if task.state == "reserved" and not task.held.is_empty(): return ["unpicked claim has held goods"]
	var group_error := Bundles.validate(self)
	if not group_error.is_empty(): return [group_error]
	for lot in _state.lots:
		if _reserved_lot(lot.id) > lot.count: errors.append("stock over-reserved")
		if is_hand_place(lot.place) and not held_ids.has(lot.id): errors.append("orphan carried lot")
	for place in _state.places:
		if _free(place) < 0: errors.append("container capacity exceeded")
	var all_items := totals.duplicate()
	for item in _state.created: all_items[item] = true
	for item in _state.consumed: all_items[item] = true
	for item in all_items:
		if int(totals.get(item, 0)) != int(_state.created.get(item, 0)) - int(_state.consumed.get(item, 0)): errors.append("inventory conservation differs: " + item)
	return errors

func _task(kind: String, worker: int, source: String, destination: String, owner: int) -> Dictionary:
	return {"id":0, "kind":kind, "worker":worker, "actor":"staff:" + str(worker) if worker > 0 else "", "from":source, "to":destination,
		"item":"", "count":0, "capacity":0, "owner":owner, "allocate_owner":ANY_OWNER,
		"state":"reserved", "parts":[], "held":[], "consumes":{}, "produces":{}, "space":0, "minted":false, "group":-1}

func _store(task: Dictionary) -> Dictionary:
	task.id = _state.next_claim
	_state.next_claim += 1
	_state.claims.append(task)
	return {"error":"", "id":task.id, "count":task.count}

func _insert(place: String, item: String, count: int, owner: int) -> Dictionary:
	var lot := {"id":_state.next_lot, "place":place, "item":item, "count":count, "owner":owner}
	_state.next_lot += 1
	_state.lots.append(lot)
	return lot

func _remove(lot: Dictionary, count: int) -> void:
	lot.count -= count
	if lot.count == 0: _state.lots.erase(lot)

func _parts(place: String, needs: Dictionary, owner: int) -> Array:
	var parts: Array = []
	for item in needs:
		var remaining: int = needs[item]
		for lot in _state.lots:
			if remaining == 0: break
			if lot.place != place or lot.item != item or (owner != ANY_OWNER and lot.owner != owner): continue
			var count := mini(remaining, int(lot.count) - _reserved_lot(lot.id))
			if count <= 0: continue
			parts.append({"lot":lot.id, "count":count})
			remaining -= count
	return parts

func _reserved_lot(id: int) -> int:
	var reserved := 0
	for task in _state.claims:
		if task.state not in ACTIVE: continue
		var parts: Array = task.parts if task.state == "reserved" else task.held
		for part in parts:
			if part.lot == id: reserved += int(part.count)
	return reserved

func _free(place: String) -> int:
	var capacity: int = _state.places[place].capacity
	if capacity < 0: return 2147483647
	var used := quantity(place)
	for task in _state.claims:
		if task.state not in ACTIVE: continue
		if task.to == place: used += int(task.space)
		if task.state == "held" and task.from == place and not task.minted: used += int(task.count)
	return capacity - used

func _busy(worker: int) -> bool:
	return _busy_actor("staff:" + str(worker))

func _busy_actor(actor: String) -> bool:
	for task in _state.claims:
		if task.actor == actor and task.state in ACTIVE: return true
	return false

func _finite_inputs(place: String, consumes: Dictionary) -> Dictionary:
	var result := consumes.duplicate()
	for item in _state.places[place].infinite: result.erase(item)
	return result

func _held_valid(task: Dictionary) -> bool:
	for held in task.held:
		var lot := _find(_state.lots, held.lot)
		if lot.is_empty() or lot.place != _hand_place(task.actor) or lot.item != task.item or lot.count != held.count: return false
		var owner: int = task.allocate_owner if task.allocate_owner != ANY_OWNER else held.owner
		if lot.owner != owner: return false
	return true

static func _failure(error: String) -> Dictionary:
	return {"error":error, "id":-1, "count":0}

static func _find(rows: Array, id: int) -> Dictionary:
	for row in rows:
		if row.id == id: return row
	return {}

static func _add(values: Dictionary, item: String, count: int) -> void:
	values[item] = int(values.get(item, 0)) + count

static func _total(values: Dictionary) -> int:
	var count := 0
	for value in values.values(): count += int(value)
	return count

static func _counts_valid(values: Dictionary) -> bool:
	for item in values:
		if not item is String or item.is_empty() or not values[item] is int or values[item] <= 0: return false
	return true

static func _shape(value: Variant, example: Dictionary) -> bool:
	if not value is Dictionary or value.size() != example.size(): return false
	for key in example:
		if not value.has(key) or typeof(value[key]) != typeof(example[key]): return false
	return true

static func is_hand_place(place: String) -> bool:
	return place.begins_with("hand:") or place.begins_with("hand@")

static func _hand_actor(place: String) -> String:
	return "staff:" + place.trim_prefix("hand:") if place.begins_with("hand:") else place.trim_prefix("hand@")

static func _hand_place(actor: String) -> String:
	return "hand:" + actor.trim_prefix("staff:") if actor.begins_with("staff:") else "hand@" + actor

static func _actor_valid(actor: String) -> bool:
	var parts := actor.split(":")
	return parts.size() == 2 and parts[0] in ["staff", "customer"] and parts[1].is_valid_int() and int(parts[1]) > 0 and str(int(parts[1])) == parts[1]

static func _staff_id(actor: String) -> int:
	return int(actor.trim_prefix("staff:")) if actor.begins_with("staff:") else 0
