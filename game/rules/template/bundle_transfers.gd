extends RefCounted
## A bundle holds references to ordinary transfer claims, never another stock
## ledger. Offside commits make whole-order reservation/drop/return atomic.

static func reserve(stock: RefCounted, actor: String, entries: Array, capacity: int) -> Dictionary:
	if not stock._actor_valid(actor) or entries.is_empty() or capacity < 1: return stock._failure("invalid bundle carrier or capacity")
	var total := 0
	for entry in entries:
		if not entry is Dictionary: return stock._failure("invalid bundle entry")
		var row: Dictionary = entry.duplicate(true)
		if not row.has("owner"): row.owner = stock.ANY_OWNER
		if not row.has("allocate_owner"): row.allocate_owner = stock.ANY_OWNER
		if not stock._shape(row, {"from":"", "to":"", "item":"", "count":0, "owner":0, "allocate_owner":0}) or row.count < 1: return stock._failure("invalid bundle entry")
		total += int(row.count)
		if total > capacity: return stock._failure("bundle exceeds carrier capacity")
	var candidate: RefCounted = stock.copy_for_reservation()
	var group := {"id":int(candidate._state.next_bundle), "actor":actor, "capacity":capacity, "claims":[]}
	candidate._state.next_bundle += 1
	candidate.append_bundle(group)
	for entry in entries:
		var result: Dictionary = candidate._reserve_actor_transfer(actor, entry.from, entry.to, entry.item,
			entry.count, capacity, entry.get("owner", stock.ANY_OWNER), entry.get("allocate_owner", stock.ANY_OWNER), group.id)
		if not String(result.error).is_empty(): return result
		if result.count != entry.count: return stock._failure("bundle stock or capacity unavailable")
		group.claims.append(int(result.id))
	stock.commit_reservation(candidate)
	for claim in group.claims: stock._record("reserve_transfer",claim)
	return {"error":"", "id":group.id, "count":total}

static func apply(stock: RefCounted, id: int, operation: String, child: int = -1) -> String:
	var group: Dictionary = stock.bundle(id)
	if group.is_empty(): return "unknown bundle"
	if operation == "pickup_part" and child not in group.claims: return "transfer is outside bundle"
	var candidate: RefCounted = stock.copy_for_reservation()
	var claims: Array = [child] if operation == "pickup_part" else group.claims
	var previous := {}
	for claim in claims: previous[claim] = stock.claim(claim).state
	for claim in claims:
		var error := ""
		match operation:
			"pickup", "pickup_part": error = candidate._pickup(claim, true)
			"drop": error = candidate._drop(claim, true)
			"cancel": error = candidate._cancel(claim, true)
		if not error.is_empty(): return error
	stock.commit_reservation(candidate)
	for claim in claims:
		if stock.claim(claim).state!=previous[claim]: stock._record("pickup" if operation=="pickup_part" else operation,claim)
	return ""

static func validate(stock: RefCounted, claims_by_id: Dictionary) -> String:
	var groups := {}
	var children := {}
	for group in stock._state.bundles:
		if not stock._shape(group, {"id":0, "actor":"", "capacity":0, "claims":[]}): return "invalid bundle shape"
		if group.id < 1 or group.id >= stock._state.next_bundle or groups.has(group.id) or not stock._actor_valid(group.actor) or group.capacity < 1 or group.claims.is_empty(): return "invalid bundle identity or carrier"
		groups[group.id] = true
		var total := 0
		var states := {}
		for id in group.claims:
			if not id is int or children.has(id): return "invalid or duplicate bundle child"
			var claim: Dictionary = claims_by_id.get(id, {})
			if claim.is_empty() or claim.kind != "transfer" or claim.group != group.id or claim.actor != group.actor or claim.capacity != group.capacity: return "bundle child differs from parent"
			children[id] = true
			total += int(claim.count)
			states[claim.state] = true
		if total > group.capacity: return "bundle exceeds carrier capacity"
		if states.size() > 1 and (states.has("cancelled") or states.has("dropped")): return "bundle was partially committed"
	for claim in claims_by_id.values():
		if claim.group > 0 and not children.has(claim.id): return "orphan bundle child"
	return ""
