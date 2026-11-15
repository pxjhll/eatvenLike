extends RefCounted
## Ownership references only. Goods, recipe progress and machine clocks remain
## authoritative in their existing services; this state never duplicates them.
const Inventory := preload("res://game/rules/template/inventory.gd")
var _policy: Dictionary
var _runner_ref: WeakRef
var _state := {"version":1, "scopes":[], "machines":[]}

func _init(policy: Dictionary, runner: RefCounted) -> void:
	_policy = policy
	_runner_ref = weakref(runner)

func record(worker: int) -> Dictionary:
	for row in _state.scopes:
		if row.worker == worker: return row.duplicate(true)
	return {}

func machine_holder(run: int) -> int:
	for row in _state.machines:
		if row.run == run: return int(row.worker)
	return -1

func can_start(worker: Dictionary, scope: String, run: int, devices: RefCounted, active := false) -> String:
	var current := record(worker.id)
	if _policy.affinity == "exclusive":
		if not current.is_empty() and scope != current.scope and not scope.is_empty(): return "employee already follows another order"
		if not current.is_empty() and scope.is_empty() and not _policy.help_while_waiting: return "follower cannot leave for shared work"
		for row in _state.scopes:
			if row.scope == scope and row.worker != worker.id: return "order already has a follower"
	var holder := machine_holder(run)
	if holder > 0 and holder != worker.id: return "machine stages belong to another employee"
	if holder == worker.id: return ""
	for row in _state.machines:
		if row.worker != worker.id or row.run == run: continue
		if not _policy.help_while_waiting: return "employee is holding a machine stage chain"
		if not active and String(devices.run(row.run).get("phase", "")).begins_with("await_"): return "employee must resume held machine"
	return ""

func started(worker: Dictionary, task: Dictionary, profile: String) -> void:
	if _policy.affinity != "none" and not task.scope.is_empty():
		_state.scopes = _state.scopes.filter(func(row: Dictionary) -> bool: return row.worker != worker.id)
		var row := _identity(worker, profile)
		row.scope = String(task.scope)
		_state.scopes.append(row)
	if _policy.hold_machine and task.kind == "operate" and machine_holder(task.run) < 0:
		var row := _identity(worker, profile)
		row.run = int(task.run)
		_state.machines.append(row)

func promote(guest: int, order: int, worker: int) -> void:
	for row in _state.scopes:
		if row.worker == worker and row.scope == "guest:" + str(guest): row.scope = "order:" + str(order)

func release_worker(worker: int) -> void:
	_state.scopes = _state.scopes.filter(func(row: Dictionary) -> bool: return row.worker != worker)
	_state.machines = _state.machines.filter(func(row: Dictionary) -> bool: return row.worker != worker)

func reconcile(open_scopes: Dictionary) -> String:
	var runner: RefCounted = _runner_ref.get_ref()
	var revoked := {}
	for row in _state.scopes + _state.machines:
		var worker: Dictionary = runner.owner.worker_by_id(row.worker)
		if worker.is_empty() or not worker.deployed or worker.post != row.post or runner.access_profile(worker) != row.profile:
			revoked[row.worker] = true
		elif row.has("run"):
			var run: Dictionary = runner.machines.run(row.run)
			if not run.is_empty() and not runner.dispatcher.allowed(worker, {"kind":"operate", "machine":run.machine}): revoked[row.worker] = true
	for worker in revoked:
		var error: String = runner.cancel(worker)
		if not error.is_empty(): return error
		release_worker(worker)
	_state.scopes = _state.scopes.filter(func(row: Dictionary) -> bool: return open_scopes.has(row.scope))
	_state.machines = _state.machines.filter(func(row: Dictionary) -> bool: return runner.machines.run(row.run).get("phase", "") not in ["", "completed", "cancelled"])
	return ""

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func restore(data: Dictionary, facts: Dictionary, devices: RefCounted) -> String:
	if not Inventory._shape(data, {"version":0, "scopes":[], "machines":[]}) or data.version != 1: return "invalid dispatch lease state"
	if _policy.affinity == "none" and not data.scopes.is_empty(): return "disabled follower policy has leases"
	if not _policy.hold_machine and not data.machines.is_empty(): return "disabled machine policy has leases"
	var workers := {}
	var scopes := {}
	var runs := {}
	for row in data.scopes:
		if not Inventory._shape(row, {"worker":0, "post":"", "profile":"", "scope":""}): return "invalid follower lease shape"
		if not facts.open.has(row.scope) or workers.has(row.worker) or (_policy.affinity == "exclusive" and scopes.has(row.scope)): return "invalid or duplicate follower scope"
		var error := _identity_error(row)
		if not error.is_empty(): return error
		workers[row.worker] = true
		scopes[row.scope] = true
	for row in data.machines:
		if not Inventory._shape(row, {"worker":0, "post":"", "profile":"", "run":0}): return "invalid machine lease shape"
		var run: Dictionary = devices.run(row.run)
		if runs.has(row.run) or run.is_empty() or run.phase in ["completed", "cancelled"] or (run.operator > 0 and run.operator != row.worker): return "invalid or duplicate machine lease"
		var error := _identity_error(row)
		if not error.is_empty(): return error
		var runner: RefCounted = _runner_ref.get_ref()
		if not runner.dispatcher.allowed(runner.owner.worker_by_id(row.worker), {"kind":"operate", "machine":run.machine}): return "machine lease violates employee permissions"
		runs[row.run] = true
	_state = data.duplicate(true)
	return ""

func _identity_error(row: Dictionary) -> String:
	var runner: RefCounted = _runner_ref.get_ref()
	var worker: Dictionary = runner.owner.worker_by_id(row.worker)
	if worker.is_empty() or not worker.deployed or row.post != worker.post or row.profile != runner.access_profile(worker): return "dispatch lease employee or post differs"
	return ""

static func _identity(worker: Dictionary, profile: String) -> Dictionary:
	return {"worker":int(worker.id), "post":String(worker.post), "profile":profile}
