extends RefCounted
## Compose already authorized logistics into one ordinary bundle. Each entry
## retains its owner, allocation and pickup clock; only the walk/drop is shared.

static func compose(runtime: RefCounted, worker: Dictionary, ranked: Array) -> Array:
	if not runtime._definition.dispatch.get("batch_transfers",false): return ranked
	var result: Array = []
	var used := {}
	var capacity: int = runtime.runner.owner.carry(worker)
	for index in ranked.size():
		if used.has(index): continue
		var first: Dictionary = ranked[index]
		if not _logistics(first): result.append(first); continue
		var members: Array = []
		var entries: Array = []
		for next in range(index,ranked.size()):
			if used.has(next): continue
			var candidate: Dictionary = ranked[next]
			if not _logistics(candidate) or candidate.category!=first.category or candidate.to!=first.to or candidate.has("node")!=first.has("node") or _drop(runtime,candidate)!=_drop(runtime,first): continue
			var extra := _entry(runtime,candidate,entries,capacity)
			if extra.is_empty(): continue
			var combined: Array = entries + [extra]
			var context: Dictionary = runtime.runner.dispatcher.context_for_candidate({"kind":"bundle","entries":combined})
			if not String(context.error).is_empty() or not runtime.runner.dispatcher.can_start(worker,context.scope).is_empty(): continue
			var stock: RefCounted = runtime.runner.inventory.copy_for_probe()
			var raw: Array = combined.duplicate(true)
			for entry in raw: entry.erase("pickup_seconds")
			if not String(stock.reserve_bundle("staff:"+str(worker.id),raw,capacity).error).is_empty(): continue
			entries = combined
			members.append(next)
		if members.size()<2: result.append(first); continue
		if runtime._definition.dispatch.get("collect_at_drop_last",false):
			entries = _collect_at_drop_last(entries,runtime.runner.ports,first.to)
		var batch := {"kind":"bundle","category":first.category,"from":entries[0].from,"to":first.to,"unit":first.unit,
			"entries":entries,"seconds":_drop(runtime,first),"nodes":[]}
		for member in members:
			used[member] = true
			if ranked[member].has("node"): batch.nodes.append({"unit":ranked[member].unit,"node":ranked[member].node})
		result.append(batch)
	return result

static func _collect_at_drop_last(entries: Array, ports: Dictionary, target: String) -> Array:
	# Keep the ranked order inside each group. Pick up any ingredient at the
	# destination after the employee has finished visiting other stations.
	var remote: Array = []
	var local: Array = []
	var drop: Vector2 = ports[target]
	for entry in entries:
		var source: Vector2 = ports[entry.from]
		(local if source.is_equal_approx(drop) else remote).append(entry)
	return remote + local

static func _logistics(candidate: Dictionary) -> bool:
	return candidate.category in ["transfer","restock_transfer","stage"] and (candidate.kind=="transfer" or (candidate.kind=="bundle" and candidate.has("node") and candidate.entries.size()==1))

static func _drop(runtime: RefCounted, candidate: Dictionary) -> float:
	return float(candidate.seconds) if candidate.has("node") else float(runtime._definition.hop_seconds)

static func _entry(runtime: RefCounted, candidate: Dictionary, existing: Array, capacity: int) -> Dictionary:
	var entry: Dictionary = candidate.entries[0].duplicate(true) if candidate.has("node") else {
		"from":candidate.from,"to":candidate.to,"item":candidate.item,"count":candidate.count,
		"owner":candidate.owner,"allocate_owner":candidate.unit,"pickup_seconds":candidate.seconds}
	var total := 0
	var selected := 0
	for other in existing:
		total += int(other.count)
		if other.from==entry.from and other.item==entry.item and other.owner==entry.owner: selected += int(other.count)
	var room := mini(capacity,runtime.runner.inventory.remaining_capacity(entry.to))-total
	if entry.item not in runtime._definition.places[entry.from].infinite:
		room = mini(room,int(runtime.runner.inventory.quantity(entry.from,entry.item,entry.owner,true))-selected)
	if candidate.has("node") and room<int(entry.count): return {}
	entry.count = mini(int(entry.count),room)
	return entry if entry.count>0 else {}
