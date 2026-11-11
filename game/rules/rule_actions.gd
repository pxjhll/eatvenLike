extends RefCounted
## A data-only FIFO lifecycle, not a recipe/branching interpreter. The context
## supplies capabilities and one authoritative ledger; this module owns cursors.
const KINDS := ["move","pickup","operate","transport","drop","wait"]
const ACTIVE := ["ready","running","blocked"]

static func start(worker: Dictionary, steps: Array, context: RefCounted) -> String:
	if worker.get("action",{}).get("status","") in ACTIVE: return "worker already has an active action"
	var program := {"version":1,"steps":steps.duplicate(true),"index":0,"status":"ready","reason":"","started":false,"lease":{}}
	var error := validate(program)
	if not error.is_empty(): return error
	var reservation: Dictionary = context.reserve(worker,program.steps)
	if not String(reservation.get("error","invalid reservation")).is_empty(): return str(reservation.get("error","invalid reservation"))
	program.lease = reservation.lease.duplicate(true)
	worker.action = program
	_enter(worker,program,context)
	return ""

static func _enter(worker: Dictionary, program: Dictionary, context: RefCounted) -> bool:
	var step: Dictionary = program.steps[program.index]
	var reason: String = context.ready(worker,step)
	if not reason.is_empty():
		program.status = "blocked"
		program.reason = reason
		return false
	program.status = "running"
	program.reason = ""
	program.started = true
	context.enter(worker,step)
	return true

static func tick(worker: Dictionary, dt: float, context: RefCounted) -> bool:
	if not is_finite(dt) or dt<=0.0: return false
	var program: Dictionary = worker.get("action",{})
	if program.is_empty() or program.get("status","") not in ACTIVE: return false
	if not program.started:
		_enter(worker,program,context)
		return false
	var step: Dictionary = program.steps[program.index]
	var reason: String = context.ready(worker,step)
	if not reason.is_empty():
		program.status = "blocked"
		program.reason = reason
		return false
	program.status = "running"
	program.reason = ""
	if not context.advance(worker,step,dt): return false
	program.index += 1
	program.started = false
	var completed: bool = program.index==program.steps.size()
	program.status = "completed" if completed else "ready"
	# Commit the cursor before synchronous business events can save/reassign.
	context.commit(worker,step)
	if not is_same(worker.get("action",{}),program): return completed
	if not completed: _enter(worker,program,context)
	return completed

static func cancel(worker: Dictionary, context: RefCounted) -> bool:
	var program: Dictionary = worker.get("action",{})
	if program.is_empty() or program.get("status","") not in ACTIVE: return false
	program.status = "cancelled"
	worker.erase("action")
	context.cancel(worker,program.lease)
	return true

static func validate(program: Variant) -> String:
	if not program is Dictionary: return "action must be a dictionary"
	var shape := {"version":0,"steps":[],"index":0,"status":"","reason":"","started":false,"lease":{}}
	for key in shape:
		if not program.has(key) or typeof(program[key])!=typeof(shape[key]): return "action."+key+" has invalid type"
	if program.version!=1: return "action.version unsupported"
	if program.steps.is_empty(): return "action needs at least one step"
	if program.status not in ACTIVE+["completed","cancelled"]: return "action.status invalid"
	if program.index<0 or program.index>program.steps.size(): return "action.index out of range"
	if program.status in ACTIVE and program.index>=program.steps.size(): return "active action cursor is past the plan"
	if program.status=="completed" and (program.index!=program.steps.size() or program.started): return "completed action cursor invalid"
	if program.status=="running" and not program.started: return "running action has not started"
	if program.status=="ready" and program.started: return "ready action already started"
	if program.status=="blocked" and program.reason.is_empty(): return "blocked action needs a reason"
	for step in program.steps:
		if not step is Dictionary: return "action step must be a dictionary"
		for key in ["kind","target","label"]:
			if not step.get(key) is String: return "action step."+key+" must be a string"
		if step.kind not in KINDS: return "action step.kind unsupported"
		if not (step.get("seconds") is int or step.get("seconds") is float) or not is_finite(float(step.seconds)) or step.seconds<0: return "action step.seconds invalid"
		if not step.get("data") is Dictionary: return "action step.data must be a dictionary"
	return "" if _plain(program) else "action contains non-data or non-finite values"

static func _plain(value: Variant, depth := 0) -> bool:
	if depth>32: return false
	if value is Dictionary:
		for key in value:
			if not key is String and not key is StringName: return false
			if not _plain(value[key],depth+1): return false
		return true
	if value is Array:
		for item in value:
			if not _plain(item,depth+1): return false
		return true
	if value is float: return is_finite(value)
	if value is Vector2: return value.is_finite()
	return typeof(value) in [TYPE_NIL,TYPE_BOOL,TYPE_INT,TYPE_STRING,TYPE_STRING_NAME]
