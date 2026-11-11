extends RefCounted
## Validation for the opt-in, data-only movement protocol. No mutation or migration.

static func validate(data: Dictionary, shop: SpecShop) -> String:
	if not data.has("movement"): return ""
	if shop.layout.motion_version!=1: return "movement requires an enabled layout protocol"
	var state: Variant = data.movement
	if not state is Dictionary or not state.get("version") is int or state.version!=1: return "movement.version unsupported"
	if not state.get("customers") is Dictionary: return "movement.customers must be a dictionary"
	var nav := RuleNav.new(shop.layout)
	nav.set_open(data.unlocked)
	for key in state.customers:
		if not key is String: return "movement customer key must be a string"
		var row: Variant = state.customers[key]
		var error := _shape(row,{"id":0,"pos":Vector2.ZERO,"path":PackedVector2Array(),"path_index":0,"walking":false,
			"target":"","state":"","seat":0,"seated":false,"exiting":false,"dish":"","wait":0.0,"takeaway":false,"carry_item":"","motion":{}})
		if not error.is_empty(): return "movement.customers."+key+"."+error
		if row.id<1 or row.wait<0 or row.seat< -1: return "movement customer values invalid"
		if row.seated and row.walking: return "movement seated customer cannot be walking"
		if not row.exiting and not _has_source(key,row,data): return "movement customer has no active business record"
		error = _record(row,nav)
		if not error.is_empty(): return "movement.customers."+key+"."+error
	for worker: Dictionary in data.roster:
		if worker.has("motion"):
			var error := _record(worker,nav)
			if not error.is_empty(): return "roster[%d].motion.%s"%[worker.id,error]
	return ""

static func _has_source(key: String, row: Dictionary, data: Dictionary) -> bool:
	if key=="diner:%d"%int(row.seat):
		return data.diners.any(func(d: Dictionary) -> bool: return d.seat==row.seat)
	for pair in [["guest",data.serve.guests],["customer",data.customers],["order",data.orders]]:
		if key=="%s:%d"%[pair[0],int(row.id)]: return pair[1].any(func(record: Dictionary) -> bool: return record.id==row.id)
	return false

static func _shape(value: Variant, shape: Dictionary) -> String:
	if not value is Dictionary: return "must be a dictionary"
	for key in shape:
		if not value.has(key): return "missing "+key
		if typeof(value[key])!=typeof(shape[key]) and not (shape[key] is float and value[key] is int): return key+" has invalid type"
	return ""

static func _record(row: Dictionary, nav: RuleNav) -> String:
	var error := _shape(row.motion,{"version":0,"goal":Vector2.ZERO,"profile":"","topology":""})
	if not error.is_empty(): return error
	if row.motion.version!=1: return "unsupported version"
	if not nav.layout.actor_areas.has(row.motion.profile): return "unknown access profile"
	if not row.motion.goal.is_finite() or not row.pos.is_finite(): return "non-finite position"
	if row.path_index<0 or row.path_index>row.path.size(): return "path_index out of range"
	if row.path.is_empty(): return "" if row.walking else "empty path cannot mean arrived"
	if row.path[-1]!=row.motion.goal: return "route destination differs from request"
	if row.path_index==row.path.size() and not row.pos.is_equal_approx(row.motion.goal): return "consumed route differs from real position"
	if row.walking and row.path_index==0: return "route has no consumed starting point"
	if not row.walking:
		if row.path_index!=row.path.size() or not row.pos.is_equal_approx(row.motion.goal): return "arrival differs from real position"
	# A topology change is allowed between a command and the next tick; tick must
	# replan from the recorded position before consuming any distance.
	if row.motion.topology==nav.topology_key():
		var previous: Vector2 = row.pos
		for i in range(row.path_index,row.path.size()):
			if not nav.segment_clear(previous,row.path[i],row.motion.profile): return "route crosses forbidden space"
			previous = row.path[i]
	return ""
