extends RefCounted
## Public device stages, backed by the same inventory transactions. Automatic
## cooking and employee work have one clock each; views never invent progress.
const Inventory := preload("res://game/rules/template/inventory.gd")
const TERMINAL := ["completed", "cancelled"]
const MANUAL := ["load", "operate", "stir", "unload"]
const PROFILE := {"slots":1, "manual":false, "load_seconds":0.0,
	"unload_seconds":0.0, "stir_points":[], "stir_seconds":0.0}

var _inventory: RefCounted
var _state: Dictionary = {"version":1, "next_run":1, "definitions":{}, "runs":[]}

func _init(inventory: RefCounted) -> void:
	_inventory = inventory

func configure(id: String, input: String, output: String, options: Dictionary = {}) -> String:
	if id.is_empty() or not _inventory.snapshot().places.has(input) or not _inventory.snapshot().places.has(output): return "unknown machine container"
	var profile := PROFILE.duplicate(true)
	for key in options:
		if not profile.has(key): return "unsupported machine capability: " + str(key)
		profile[key] = options[key].duplicate(true) if options[key] is Array else options[key]
	var error := _profile_error(profile)
	if not error.is_empty(): return error
	for key in ["load_seconds", "unload_seconds", "stir_seconds"]: profile[key] = float(profile[key])
	var definition := {"input":input, "output":output, "profile":profile}
	if _state.definitions.has(id): return "" if _state.definitions[id] == definition else "machine already configured"
	_state.definitions[id] = definition
	return ""

func start(machine: String, consumes: Dictionary, produces: Dictionary, seconds: float, owner: int = -1) -> Dictionary:
	if not _state.definitions.has(machine) or not is_finite(seconds) or seconds < 0.0: return {"error":"invalid machine request", "id":-1}
	var definition: Dictionary = _state.definitions[machine]
	var profile: Dictionary = definition.profile
	if seconds == 0.0 and not profile.stir_points.is_empty(): return {"error":"zero-duration process cannot require stirring", "id":-1}
	var occupied := 0
	for run in _state.runs:
		if run.machine == machine and run.phase not in TERMINAL: occupied += 1
	if occupied >= int(profile.slots): return {"error":"machine occupied", "id":-1}
	var task: Dictionary = _inventory.reserve_operation(0, definition.input, consumes, produces, owner, definition.output)
	if not String(task.error).is_empty(): return {"error":task.error, "id":-1}
	var run := _run()
	run.id = _state.next_run
	_state.next_run += 1
	run.machine = machine
	run.claim = task.id
	run.duration = seconds
	run.remaining = seconds
	run.phase = "await_load" if float(profile.load_seconds) > 0.0 else ("await_operate" if profile.manual else "processing")
	_state.runs.append(run)
	return {"error":"", "id":run.id}

func engage(id: int, worker: int, work_rate: float = 1.0) -> String:
	var run := _find(id)
	if run.is_empty() or worker <= 0 or not is_finite(work_rate) or work_rate <= 0.0: return "invalid machine assignment"
	if run.phase in MANUAL: return "" if run.operator == worker else "machine stage already assigned"
	if not String(run.phase).begins_with("await_"): return "machine needs no employee"
	for other in _state.runs:
		if other.operator == worker: return "employee already operating"
	var phase: String = String(run.phase).trim_prefix("await_")
	var profile: Dictionary = _state.definitions[run.machine].profile
	if float(run.stage_total) == 0.0:
		run.stage_total = float(run.duration) if phase == "operate" else float(profile[phase + "_seconds"])
		run.stage_left = run.stage_total
	run.phase = phase
	run.operator = worker
	run.operator_rate = work_rate
	return ""

func advance(dt: float, paused := false) -> String:
	if not is_finite(dt) or dt < 0.0: return "invalid machine time"
	if paused or dt == 0.0: return ""
	for run in _state.runs:
		if run.phase in TERMINAL or String(run.phase).begins_with("await_"): continue
		var profile: Dictionary = _state.definitions[run.machine].profile
		if run.phase in MANUAL:
			run.stage_left = maxf(0.0, float(run.stage_left) - dt * float(run.operator_rate))
			if run.phase == "operate": run.remaining = run.stage_left
			if run.stage_left > 0.000001: continue
			var finished: String = run.phase
			run.operator = -1
			run.stage_left = 0.0
			run.stage_total = 0.0
			match finished:
				"load": run.phase = "await_operate" if profile.manual else "processing"
				"stir":
					run.stir_index += 1
					run.phase = "processing"
				"operate":
					var error := _processed(run, profile)
					if not error.is_empty(): return error
				"unload":
					var error := _complete(run)
					if not error.is_empty(): return error
			continue
		run.remaining = maxf(0.0, float(run.remaining) - dt)
		if run.stir_index < profile.stir_points.size():
			var stop := float(run.duration) * (1.0 - float(profile.stir_points[run.stir_index]))
			if run.remaining <= stop + 0.000001:
				run.remaining = stop
				run.phase = "await_stir"
				continue
		if run.remaining <= 0.000001:
			var error := _processed(run, profile)
			if not error.is_empty(): return error
	return ""

func cancel(id: int) -> String:
	var run := _find(id)
	if run.is_empty(): return "unknown machine operation"
	if run.phase == "cancelled": return ""
	if run.phase == "completed": return "machine operation already committed"
	var error: String = _inventory.cancel(run.claim)
	if not error.is_empty(): return error
	run.phase = "cancelled"
	run.operator = -1
	return ""

func release_employee(id: int, worker: int) -> String:
	var run := _find(id)
	if run.is_empty() or run.operator != worker or run.phase not in MANUAL: return "employee does not own this operation"
	# Reassignment retains completed work, inputs and remaining stage time.
	run.phase = "await_" + String(run.phase)
	run.operator = -1
	return ""

func run(id: int) -> Dictionary:
	return _find(id).duplicate(true)

func status(machine: String) -> Dictionary:
	if not _state.definitions.has(machine): return {}
	var definition: Dictionary = _state.definitions[machine]
	var output: int = _inventory.quantity(definition.output)
	var result := {"working":false, "progress":0.0, "input":_inventory.quantity(definition.input),
		"processing":0, "output":output, "phase":"ready" if output > 0 else "idle", "operator":-1, "need":""}
	for run in _state.runs:
		if run.machine != machine or run.phase in TERMINAL: continue
		result.processing += Inventory._total(_inventory.claim(run.claim).produces)
		if result.phase not in ["idle", "ready"]: continue
		result.phase = run.phase
		result.operator = run.operator
		result.working = run.phase == "processing" or run.phase in MANUAL
		result.need = String(run.phase).trim_prefix("await_") if String(run.phase).begins_with("await_") else ""
		if run.phase in MANUAL:
			result.progress = 1.0 - float(run.stage_left) / maxf(0.000001, float(run.stage_total))
		else: result.progress = 1.0 - float(run.remaining) / maxf(0.000001, float(run.duration))
	return result

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func restore(data: Dictionary) -> String:
	var candidate: RefCounted = get_script().new(_inventory)
	candidate._state = data.duplicate(true)
	var errors: Array = candidate.audit()
	if not errors.is_empty(): return String(errors[0])
	_state = candidate._state
	return ""

func audit() -> Array:
	if not Inventory._shape(_state, {"version":1, "next_run":1, "definitions":{}, "runs":[]}): return ["invalid machine state shape"]
	if _state.version != 1 or _state.next_run < 1: return ["invalid machine state version"]
	var stock: Dictionary = _inventory.snapshot()
	for id in _state.definitions:
		var definition: Variant = _state.definitions[id]
		if not id is String or id.is_empty() or not Inventory._shape(definition, {"input":"", "output":"", "profile":{}}): return ["invalid machine definition"]
		if not stock.places.has(definition.input) or not stock.places.has(definition.output): return ["unknown machine stock container"]
		var error := _profile_error(definition.profile)
		if not error.is_empty(): return [error]
	var ids := {}
	var claims := {}
	var operators := {}
	var occupied := {}
	for run in _state.runs:
		if not Inventory._shape(run, _run()): return ["invalid machine run shape"]
		if run.id < 1 or run.id >= _state.next_run or ids.has(run.id) or claims.has(run.claim) or not _state.definitions.has(run.machine): return ["invalid machine run identity"]
		ids[run.id] = true
		claims[run.claim] = true
		var definition: Dictionary = _state.definitions[run.machine]
		var profile: Dictionary = definition.profile
		var task: Dictionary = _inventory.claim(run.claim)
		if task.is_empty() or task.kind != "operation" or task.worker != 0 or task.from != definition.input or task.to != definition.output: return ["machine claim differs from inventory"]
		if run.phase not in TERMINAL + ["processing", "await_load", "await_operate", "await_stir", "await_unload"] + MANUAL: return ["invalid machine phase"]
		var expected: String = "completed" if run.phase == "completed" else ("cancelled" if run.phase == "cancelled" else "reserved")
		if task.state != expected: return ["machine and inventory commit differ"]
		for key in ["duration", "remaining", "stage_total", "stage_left"]:
			if not is_finite(run[key]) or run[key] < 0.0: return ["invalid machine clock"]
		if run.remaining > run.duration or run.stage_left > run.stage_total or run.stir_index < 0 or run.stir_index > profile.stir_points.size(): return ["machine progress out of range"]
		if run.phase in MANUAL:
			if run.operator < 1 or operators.has(run.operator): return ["machine employee occupancy differs"]
			operators[run.operator] = true
		elif run.operator != -1: return ["unattended phase has employee occupancy"]
		if not is_finite(run.operator_rate) or run.operator_rate <= 0.0: return ["invalid employee work rate"]
		var stage := String(run.phase).trim_prefix("await_")
		if stage == "operate" and not profile.manual: return ["automatic machine cannot request manual processing"]
		if stage in ["load", "unload"] and float(profile[stage + "_seconds"]) <= 0.0: return ["machine requests an undeclared stage"]
		if stage == "stir" and run.stir_index >= profile.stir_points.size(): return ["machine requests an undeclared stir"]
		if run.phase not in TERMINAL: occupied[run.machine] = int(occupied.get(run.machine, 0)) + 1
	for id in occupied:
		if occupied[id] > int(_state.definitions[id].profile.slots): return ["machine slots exceeded"]
	return _inventory.audit()

func _find(id: int) -> Dictionary:
	for run in _state.runs:
		if run.id == id: return run
	return {}

func _processed(run: Dictionary, profile: Dictionary) -> String:
	run.remaining = 0.0
	if float(profile.unload_seconds) > 0.0:
		run.phase = "await_unload"
		return ""
	return _complete(run)

func _complete(run: Dictionary) -> String:
	var error: String = _inventory.complete_operation(run.claim)
	if not error.is_empty(): return error
	run.phase = "completed"
	run.remaining = 0.0
	run.operator = -1
	return ""

static func _run() -> Dictionary:
	return {"id":0, "machine":"", "claim":0, "phase":"", "operator":-1, "operator_rate":1.0,
		"duration":0.0, "remaining":0.0, "stage_total":0.0, "stage_left":0.0, "stir_index":0}

static func _profile_error(profile: Dictionary) -> String:
	if profile.size() != PROFILE.size(): return "invalid machine profile"
	for key in PROFILE:
		if not profile.has(key): return "missing machine capability: " + key
	if not profile.slots is int or profile.slots < 1 or not profile.manual is bool or not profile.stir_points is Array: return "invalid machine capability type"
	for key in ["load_seconds", "unload_seconds", "stir_seconds"]:
		if not (profile[key] is float or profile[key] is int) or not is_finite(float(profile[key])) or profile[key] < 0.0: return "invalid machine stage time"
	var previous := 0.0
	for point in profile.stir_points:
		if not (point is float or point is int) or not is_finite(float(point)) or point <= previous or point >= 1.0: return "invalid stirring points"
		previous = float(point)
	if profile.manual and not profile.stir_points.is_empty(): return "manual processing cannot have automatic stir stops"
	if profile.stir_points.is_empty() and float(profile.stir_seconds) != 0.0: return "unused stirring duration"
	return ""
