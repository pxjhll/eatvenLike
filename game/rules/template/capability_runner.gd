extends RefCounted
## Executes public inventory/device requests through the shared action and
## movement lifecycle. Recipe/order planning is a separate producer of requests.
const Inventory := preload("res://game/rules/template/inventory.gd")
const Machines := preload("res://game/rules/template/machines.gd")
const Frame := preload("res://game/rules/template/view_frame.gd")
const Actions := preload("res://game/rules/rule_actions.gd")
const Context := preload("res://game/rules/template/action_context.gd")
const MotionValidation := preload("res://game/rules/movement_validator.gd")
const ACTOR_FIELDS := ["id", "pos", "walking", "phase", "task_label", "carry_item", "carry_count",
	"path", "path_index", "action_left", "completed", "target"]
const ACTOR_OPTIONAL := ["duration", "motion", "action"]

var _owner_ref: WeakRef
var _retained_owner: RefCounted
var owner: RefCounted:
	get: return _retained_owner if _retained_owner!=null else _owner_ref.get_ref()
	set(value): _owner_ref = weakref(value)
var inventory := Inventory.new()
var machines: RefCounted
var dispatcher: RefCounted
var ports: Dictionary = {}
var _dynamic_places: Dictionary = {}
var tasks: Dictionary = {}
var _next_task := 1
var last_error := ""
var trace: RefCounted
var _interactions: Array = []

func _init(rules: RefCounted) -> void:
	owner = rules
	_retained_owner = rules
	machines = Machines.new(inventory)

func release_owner() -> void:
	_retained_owner = null

func define_place(id: String, port: Vector2, capacity: int = -1, infinite_items: Array = []) -> String:
	if not port.is_finite(): return "invalid capability port"
	if ports.has(id) and ports[id] != port: return "capability port already configured"
	var error := inventory.configure(id, capacity, infinite_items)
	if error.is_empty(): ports[id] = port
	return error

func define_dynamic_place(id: String, port: Vector2) -> String:
	if ports.has(id) and not _dynamic_places.has(id): return "dynamic container conflicts with template"
	var error := define_place(id, port)
	if error.is_empty(): _dynamic_places[id] = {"port":port, "capacity":-1, "infinite":[]}
	return error

func transfer(worker_id: int, source: String, destination: String, item: String, count: int,
		hop_seconds: float, stock_owner: int = -2, allocate_owner: int = -2, pickup_seconds: float = -1.0) -> String:
	var error := _available_worker(worker_id)
	if not error.is_empty(): return error
	if not ports.has(source) or not ports.has(destination) or not is_finite(hop_seconds) or hop_seconds < 0.0: return "invalid transfer ports or duration"
	if not is_finite(pickup_seconds) or (pickup_seconds < 0.0 and pickup_seconds != -1.0): return "invalid pickup duration"
	var worker: Dictionary = owner.worker_by_id(worker_id)
	if dispatcher != null and not dispatcher.allowed(worker, {"kind":"transfer", "from":source, "to":destination}): return "employee cannot perform this transfer"
	var stock := _reservation_stock()
	var claim: Dictionary = stock.reserve_transfer(worker_id, source, destination, item, count, owner.carry(worker), stock_owner, allocate_owner)
	if not String(claim.error).is_empty(): return claim.error
	var context := _transport_scope(stock, [stock.claim(claim.id)], worker)
	if not String(context.error).is_empty(): return context.error
	if dispatcher != null:
		inventory.commit_reservation(stock)
		inventory._record("reserve_transfer",claim.id)
	var task := _task("transfer", worker)
	task.scope = context.scope
	task.claim = claim.id
	task.from = source
	task.to = destination
	task.seconds = (hop_seconds if pickup_seconds == -1.0 else pickup_seconds) / float(owner.skill(worker))
	task.drop_seconds = hop_seconds / float(owner.skill(worker))
	return _start(worker, task)

func operate(worker_id: int, run_id: int, port: String) -> String:
	var error := _available_worker(worker_id)
	if not error.is_empty(): return error
	var run: Dictionary = machines.run(run_id)
	if not ports.has(port) or run.is_empty() or not String(run.phase).begins_with("await_"): return "invalid machine stage request"
	var required_port: String = machines.stage_port(run_id)
	if port != required_port: return "operation port differs from the declared device port"
	var timing: Dictionary = machines.stage_seconds(run_id,owner.mods,owner.tune)
	if not timing.error.is_empty(): return timing.error
	for task in tasks.values():
		if task.kind == "operate" and task.run == run_id: return "machine stage already assigned"
	var worker: Dictionary = owner.worker_by_id(worker_id)
	if dispatcher != null and not dispatcher.allowed(worker, {"kind":"operate", "machine":run.machine}): return "employee cannot operate this device"
	var context: Dictionary = {"error":"", "scope":""} if dispatcher == null else dispatcher.context_for_claims(inventory, [inventory.claim(run.claim)])
	if not String(context.error).is_empty(): return context.error
	if dispatcher != null:
		error = dispatcher.can_start(worker, context.scope, run.id)
		if not error.is_empty(): return error
	var task := _task("operate", worker)
	task.scope = context.scope
	task.run = run_id
	task.from = port
	task.to = port
	task.stage = String(run.phase).trim_prefix("await_")
	return _start(worker, task)

func transfer_bundle(worker_id: int, entries: Array, hop_seconds: float) -> String:
	var error := _available_worker(worker_id)
	if not error.is_empty(): return error
	if entries.is_empty() or not is_finite(hop_seconds) or hop_seconds < 0.0: return "invalid bundle route or duration"
	var destination := ""
	var stock_entries: Array = []
	var pickup_times: Array = []
	for entry in entries:
		if not entry is Dictionary or not entry.get("from") is String or not entry.get("to") is String: return "invalid bundle route"
		if not ports.has(entry.from) or not ports.has(entry.to): return "invalid bundle ports"
		if not destination.is_empty() and destination != entry.to: return "bundle requires one physical drop port"
		destination = entry.to
		var seconds: Variant = entry.get("pickup_seconds", hop_seconds)
		if not (seconds is int or seconds is float) or not is_finite(float(seconds)) or seconds < 0.0: return "invalid bundle pickup duration"
		var stock_entry: Dictionary = entry.duplicate(true)
		stock_entry.erase("pickup_seconds")
		stock_entries.append(stock_entry)
		pickup_times.append(float(seconds))
	var worker: Dictionary = owner.worker_by_id(worker_id)
	var sources: Array = []
	for entry in entries: sources.append(String(entry.from))
	if dispatcher != null and not dispatcher.allowed(worker, {"kind":"bundle", "froms":sources, "to":destination}): return "employee cannot collect or deliver this bundle"
	var stock := _reservation_stock()
	var result: Dictionary = stock.reserve_bundle("staff:" + str(worker_id), stock_entries, owner.carry(worker))
	if not String(result.error).is_empty(): return result.error
	var claims: Array = []
	for id in stock.bundle(result.id).claims: claims.append(stock.claim(id))
	var context := _transport_scope(stock, claims, worker)
	if not String(context.error).is_empty(): return context.error
	if dispatcher != null:
		inventory.commit_reservation(stock)
		for claim in inventory.bundle(result.id).claims: inventory._record("reserve_transfer",claim)
	var task := _task("bundle", worker)
	task.scope = context.scope
	task.bundle = result.id
	task.from = entries[0].from
	task.to = destination
	task.seconds = hop_seconds / float(owner.skill(worker))
	task.drop_seconds = task.seconds
	for id in inventory.bundle(result.id).claims:
		task.picks.append({"claim":int(id), "from":String(inventory.claim(id).from), "seconds":float(pickup_times[task.picks.size()]) / float(owner.skill(worker))})
	return _start(worker, task)

func interact(worker_id: int, port: String, seconds: float, purpose: String, subject: int) -> String:
	var error := _available_worker(worker_id)
	if not error.is_empty(): return error
	if not ports.has(port) or not is_finite(seconds) or seconds < 0.0 or purpose != "admit" or subject < 1: return "invalid public interaction"
	var worker: Dictionary = owner.worker_by_id(worker_id)
	if dispatcher != null and not dispatcher.allowed(worker, {"kind":"interact", "port":port}): return "employee cannot perform this interaction"
	var context: Dictionary = {"error":"", "scope":""} if dispatcher == null else dispatcher.context_for_guest(subject)
	if dispatcher != null:
		error = dispatcher.can_start(worker, context.scope)
		if not error.is_empty(): return error
	var task := _task("interact", worker)
	task.scope = context.scope
	task.from = port
	task.to = port
	task.seconds = seconds / float(owner.skill(worker))
	task.purpose = purpose
	task.subject = subject
	return _start(worker, task)

func take_interactions() -> Array:
	var result := _interactions
	_interactions = []
	return result.duplicate(true)

func step(dt: float, paused := false) -> String:
	if not is_finite(dt) or dt < 0.0: return "invalid capability time"
	if paused or dt == 0.0: return ""
	if dispatcher != null:
		var lease_error: String = dispatcher.reconcile()
		if not lease_error.is_empty(): return lease_error
	# Revoke leases before advancing any manual clock or committing a pickup.
	for id in tasks.keys():
		var worker: Dictionary = owner.worker_by_id(id)
		if worker.is_empty(): return "assigned employee missing"
		if not worker.deployed or tasks[id].profile != access_profile(worker) or (dispatcher != null and not dispatcher.allowed_task(worker, tasks[id], machines)):
			var revoked := cancel(id)
			if not revoked.is_empty(): return revoked
	var error: String = machines.advance(dt)
	if not error.is_empty(): return error
	last_error = ""
	for id in tasks.keys():
		var worker: Dictionary = owner.worker_by_id(id)
		if worker.is_empty(): return "assigned employee missing"
		if not worker.deployed:
			cancel(id)
			continue
		Actions.tick(worker, dt, Context.new(self))
		if not last_error.is_empty(): return last_error
	return dispatcher.reconcile() if dispatcher != null else ""

func cancel(worker_id: int) -> String:
	if not tasks.has(worker_id):
		if dispatcher != null: dispatcher.release_worker(worker_id)
		return ""
	var worker: Dictionary = owner.worker_by_id(worker_id)
	if worker.is_empty(): return "assigned employee missing"
	last_error = ""
	if not Actions.cancel(worker, Context.new(self)): _cancel_effect(worker)
	return last_error

func idle(worker_id: int) -> bool:
	return not tasks.has(worker_id)

func frame(displays: Array = []) -> Dictionary:
	var out: Dictionary = Frame.build(inventory, machines, displays)
	out.workers = owner.workers.duplicate(true)
	for worker in out.workers:
		worker.walking = worker.walking and not worker.path.is_empty()
	return out

func snapshot() -> Dictionary:
	var actors: Array = []
	for worker in owner.workers:
		var actor := {}
		for key in ACTOR_FIELDS + ACTOR_OPTIONAL:
			if worker.has(key): actor[key] = worker[key]
		actors.append(actor)
	return {"version":1, "next_task":_next_task, "ports":ports.duplicate(true),
		"inventory":inventory.snapshot(), "machines":machines.snapshot(),
		"tasks":tasks.values().duplicate(true), "actors":actors.duplicate(true), "interactions":_interactions.duplicate(true)}

func validate_snapshot(data: Dictionary, dynamic: Variant = null, limits: Dictionary = {}) -> String:
	return String(prepare_restore(data, dynamic, limits).error)

func restore(data: Dictionary, dynamic: Variant = null, limits: Dictionary = {}) -> String:
	var candidate := prepare_restore(data, dynamic, limits)
	if not String(candidate.error).is_empty(): return candidate.error
	adopt_restore(data, candidate)
	return ""

func adopt_restore(data: Dictionary, candidate: Dictionary) -> void:
	# Validation is complete before replacing any actor or service.
	inventory = candidate.inventory
	inventory.trace = trace
	machines = candidate.machines
	tasks = candidate.tasks
	ports = data.ports.duplicate(true)
	_dynamic_places = candidate.dynamic
	_next_task = data.next_task
	_interactions = data.interactions.duplicate(true)
	for actor in data.actors:
		var worker: Dictionary = owner.worker_by_id(actor.id)
		for key in ACTOR_OPTIONAL: worker.erase(key)
		for key in actor: worker[key] = actor[key].duplicate(true) if actor[key] is Dictionary or actor[key] is Array else actor[key]
	last_error = ""

func prepare_restore(data: Dictionary, dynamic: Variant = null, limits: Dictionary = {}) -> Dictionary:
	if not Inventory._shape(data, {"version":0, "next_task":0, "ports":{}, "inventory":{}, "machines":{}, "tasks":[], "actors":[], "interactions":[]}): return {"error":"invalid capability state shape"}
	var additions: Dictionary = _dynamic_places if dynamic == null else dynamic
	var expected_ports := ports.duplicate(true)
	var expected_places: Dictionary = inventory.snapshot().places
	for id in _dynamic_places:
		expected_ports.erase(id)
		expected_places.erase(id)
	for id in additions:
		var place: Variant = additions[id]
		if not id is String or not Inventory._shape(place, {"port":Vector2.ZERO, "capacity":0, "infinite":[]}) or expected_ports.has(id) or not place.port.is_finite() or place.capacity != -1 or not place.infinite.is_empty(): return {"error":"invalid dynamic container declaration"}
		expected_ports[id] = place.port
		expected_places[id] = {"capacity":place.capacity, "infinite":place.infinite}
	for id in limits.get("capacity",{}):
		var value: Variant = limits.capacity[id]
		if not expected_places.has(id) or additions.has(id) or Inventory.is_hand_place(id) or not value is int or value < 0: return {"error":"invalid numeric container override"}
		expected_places[id].capacity = value
	if data.version != 1 or data.next_task < 1 or data.ports != expected_ports: return {"error":"capability version or ports differ"}
	var stock := Inventory.new()
	var error := stock.restore(data.inventory)
	if not error.is_empty(): return {"error":error}
	for place in data.inventory.places:
		if Inventory.is_hand_place(place): continue
		if not expected_places.has(place) or data.inventory.places[place] != expected_places[place]: return {"error":"inventory definition differs from template"}
	for place in expected_places:
		if Inventory.is_hand_place(place): continue
		if not data.inventory.places.has(place): return {"error":"missing template container"}
	var devices := Machines.new(stock)
	error = devices.restore(data.machines)
	if not error.is_empty(): return {"error":error}
	var expected_machines: Dictionary = machines.snapshot().definitions
	for id in limits.get("slots",{}):
		var value: Variant = limits.slots[id]
		if not expected_machines.has(id) or not value is int or value < 1: return {"error":"invalid numeric machine override"}
		expected_machines[id].profile.slots = value
	if data.machines.definitions != expected_machines: return {"error":"machine definitions differ from template"}
	var actors := {}
	var deployed := {}
	for worker in owner.workers: deployed[int(worker.id)] = true
	for actor in data.actors:
		error = MotionValidation._shape(actor, {"id":0, "pos":Vector2.ZERO, "walking":false, "phase":"", "task_label":"", "carry_item":"", "carry_count":0,
			"path":PackedVector2Array(), "path_index":0, "action_left":0.0, "completed":0, "target":""})
		if not error.is_empty(): return {"error":error}
		for key in actor:
			if key not in ACTOR_FIELDS + ACTOR_OPTIONAL: return {"error":"unsupported actor state"}
		if not deployed.has(actor.id) or actors.has(actor.id) or not actor.pos.is_finite() or actor.carry_count < 0 or actor.completed < 0 or not is_finite(float(actor.action_left)) or actor.action_left < 0.0: return {"error":"invalid actor identity or values"}
		if actor.path_index < 0 or actor.path_index > actor.path.size(): return {"error":"invalid actor path cursor"}
		for point in actor.path:
			if not point.is_finite(): return {"error":"invalid actor route"}
		if actor.has("duration") and (not (actor.duration is float or actor.duration is int) or not is_finite(float(actor.duration)) or actor.duration < 0.0): return {"error":"invalid actor duration"}
		if actor.has("motion"):
			if not actor.motion is Dictionary: return {"error":"invalid actor motion"}
			error = MotionValidation._record(actor, owner.nav)
			if not error.is_empty(): return {"error":error}
		var held: Dictionary = Frame.build(stock, devices).held.get(actor.id, {"count":0, "items":[]})
		if actor.carry_count != held.count or actor.carry_item != ("" if held.items.is_empty() else String(held.items[0].item)): return {"error":"actor hand differs from inventory"}
		actors[actor.id] = actor
	if actors.size() != deployed.size(): return {"error":"deployed actor set differs"}
	var restored_tasks := {}
	var task_ids := {}
	var transfer_claims := {}
	var machine_runs := {}
	for task in data.tasks:
		if not Inventory._shape(task, {"id":0, "worker":0, "kind":"", "claim":0, "run":0,
			"from":"", "to":"", "seconds":0.0, "drop_seconds":0.0, "stage":"", "profile":"", "bundle":0, "picks":[], "purpose":"", "subject":0, "scope":""}): return {"error":"invalid capability task shape"}
		if task.id < 1 or task.id >= data.next_task or task_ids.has(task.id) or restored_tasks.has(task.worker) or not actors.has(task.worker) or task.kind not in ["transfer", "operate", "bundle", "interact"] or not expected_ports.has(task.from) or not expected_ports.has(task.to): return {"error":"invalid capability task identity or port"}
		if task.kind == "interact":
			if task.purpose != "admit" or task.subject < 1 or task.from != task.to or task.claim != -1 or task.run != -1 or not task.stage.is_empty(): return {"error":"invalid interaction request"}
		elif not task.purpose.is_empty() or task.subject != -1: return {"error":"unrelated interaction fields"}
		if task.kind != "bundle" and (task.bundle != -1 or not task.picks.is_empty()): return {"error":"unrelated bundle fields"}
		if task.kind == "bundle":
			var group: Dictionary = stock.bundle(task.bundle)
			if group.is_empty() or group.actor != "staff:" + str(task.worker) or group.claims.size() != task.picks.size() or task.claim != -1 or task.run != -1 or not task.stage.is_empty(): return {"error":"bundle differs from assigned actor"}
			for index in task.picks.size():
				var pick: Variant = task.picks[index]
				if not Inventory._shape(pick, {"claim":0, "from":"", "seconds":0.0}) or pick.claim != group.claims[index] or not expected_ports.has(pick.from) or not is_finite(pick.seconds) or pick.seconds < 0.0: return {"error":"invalid bundle collection stop"}
				var child: Dictionary = stock.claim(pick.claim)
				if child.from != pick.from or child.to != task.to or (index == 0 and task.from != pick.from): return {"error":"bundle collection ports differ"}
		if not is_finite(task.seconds) or not is_finite(task.drop_seconds) or task.seconds < 0.0 or task.drop_seconds < 0.0 or not owner.shop.layout.actor_areas.has(task.profile): return {"error":"invalid task timing or access profile"}
		if task.profile != _task(task.kind, owner.worker_by_id(task.worker)).profile: return {"error":"employee access profile differs from assigned role"}
		var actor: Dictionary = actors[task.worker]
		if not actor.get("action") is Dictionary: return {"error":"task has no actor program"}
		error = Actions.validate(actor.action)
		if not error.is_empty(): return {"error":error}
		if actor.action.status not in Actions.ACTIVE or actor.action.steps != Context.plan(task) or actor.action.lease != Context._binding(task): return {"error":"program differs from capability request"}
		var action: Dictionary = actor.action.steps[actor.action.index]
		if task.kind == "transfer":
			var claim: Dictionary = stock.claim(task.claim)
			var expected: String = "reserved" if int(actor.action.index) < 2 else "held"
			if claim.is_empty() or claim.kind != "transfer" or claim.group != -1 or claim.worker != task.worker or claim.state != expected or claim.from != task.from or claim.to != task.to or transfer_claims.has(task.claim): return {"error":"transfer program differs from stock claim"}
			transfer_claims[task.claim] = true
		elif task.kind == "bundle":
			for index in task.picks.size():
				var child: Dictionary = stock.claim(task.picks[index].claim)
				var expected := "held" if actor.action.index > index * 2 + 1 else "reserved"
				if child.state != expected or transfer_claims.has(child.id): return {"error":"bundle progress differs from actor cursor"}
				transfer_claims[child.id] = true
		elif task.kind == "operate":
			var run: Dictionary = devices.run(task.run)
			if run.is_empty() or machine_runs.has(task.run) or task.stage not in Machines.MANUAL: return {"error":"invalid machine task"}
			var expected_port: String = devices.stage_port(task.run)
			if task.from != expected_port or task.to != expected_port: return {"error":"machine program has an unrelated port"}
			if int(actor.action.index) == 0 or not actor.action.started:
				if run.phase != "await_" + task.stage or run.operator != -1: return {"error":"machine stage differs from walking employee"}
			elif run.phase != task.stage or run.operator != task.worker: return {"error":"machine stage differs from operating employee"}
			machine_runs[task.run] = task.worker
		if actor.action.started:
			if action.kind in ["move", "transport"]:
				if not actor.walking or actor.phase != "walk" or not actor.has("motion") or actor.motion.goal != expected_ports[action.target] or actor.motion.profile != task.profile: return {"error":"actor movement differs from action request"}
			else:
				var phase: String = "work" if action.kind == "operate" else ("pickup" if action.kind == "pickup" else "dropoff")
				if actor.walking or actor.phase != phase or not Vector2(actor.pos).is_equal_approx(expected_ports[action.target]): return {"error":"actor operation is not at its port"}
		if dispatcher != null and not dispatcher.allowed_task(owner.worker_by_id(task.worker), task, devices, false): return {"error":"restored task is not authorized for employee role or post"}
		restored_tasks[task.worker] = task.duplicate(true)
		task_ids[task.id] = true
	for actor in actors.values():
		if not restored_tasks.has(actor.id) and (actor.has("action") or actor.walking or actor.carry_count > 0 or actor.phase != "idle"): return {"error":"actor activity has no capability request"}
	for claim in data.inventory.claims:
		if claim.worker > 0 and claim.state in Inventory.ACTIVE and not transfer_claims.has(claim.id): return {"error":"orphan employee stock claim"}
	for run in data.machines.runs:
		if run.operator > 0 and machine_runs.get(run.id, -1) != run.operator: return {"error":"orphan machine employee"}
	for event in data.interactions:
		if not Inventory._shape(event, {"id":0, "worker":0, "purpose":"", "subject":0, "result":""}): return {"error":"invalid interaction result shape"}
		if event.id < 1 or event.id >= data.next_task or task_ids.has(event.id) or not actors.has(event.worker) or event.purpose != "admit" or event.subject < 1 or event.result not in ["completed", "cancelled"]: return {"error":"invalid or duplicate interaction result"}
		task_ids[event.id] = true
	return {"error":"", "inventory":stock, "machines":devices, "tasks":restored_tasks, "dynamic":additions.duplicate(true)}

func _available_worker(id: int) -> String:
	var worker: Dictionary = owner.worker_by_id(id)
	if worker.is_empty() or not worker.deployed: return "employee unavailable"
	if tasks.has(id) or worker.has("action") or worker.phase != "idle" or worker.carry_count != 0: return "employee already assigned"
	return ""

func _task(kind: String, worker: Dictionary) -> Dictionary:
	var profile := access_profile(worker)
	return {"id":0, "worker":int(worker.id), "kind":kind, "claim":-1, "run":-1,
		"from":"", "to":"", "seconds":0.0, "drop_seconds":0.0, "stage":"", "profile":profile, "bundle":-1, "picks":[], "purpose":"", "subject":-1, "scope":""}

func access_profile(worker: Dictionary) -> String:
	var side: String = owner.side_of(worker)
	return side if not side.is_empty() and owner.shop.layout.actor_areas.has(side) else "staff"

func _start(worker: Dictionary, task: Dictionary) -> String:
	task.id = _next_task
	_next_task += 1
	tasks[worker.id] = task
	var error := Actions.start(worker, Context.plan(task), Context.new(self))
	if not error.is_empty():
		_cancel_effect(worker)
		return error
	if dispatcher != null: dispatcher.started(worker, task)
	return ""

func _reservation_stock() -> RefCounted:
	if dispatcher == null: return inventory
	return inventory.copy_for_reservation()

func _transport_scope(stock: RefCounted, claims: Array, worker: Dictionary) -> Dictionary:
	if dispatcher == null: return {"error":"", "scope":""}
	var context: Dictionary = dispatcher.context_for_claims(stock, claims)
	if String(context.error).is_empty(): context.error = dispatcher.can_start(worker, context.scope)
	return context

func _sync_hand(worker: Dictionary) -> void:
	worker.carry_item = ""
	worker.carry_count = 0
	for lot in inventory.active_snapshot().lots:
		if lot.place != "hand:" + str(worker.id): continue
		if worker.carry_item.is_empty(): worker.carry_item = String(lot.item)
		worker.carry_count += int(lot.count)

func _finish(worker: Dictionary) -> void:
	_interaction_result(tasks[worker.id], "completed")
	tasks.erase(worker.id)
	_clear_actor(worker)
	_sync_hand(worker)
	worker.completed += 1

func _cancel_effect(worker: Dictionary) -> void:
	var task: Dictionary = tasks.get(worker.id, {})
	if task.is_empty(): return
	if task.kind == "transfer": last_error = inventory.cancel(task.claim)
	elif task.kind == "bundle": last_error = inventory.cancel_bundle(task.bundle)
	elif task.kind == "operate":
		var run: Dictionary = machines.run(task.run)
		if run.get("operator", -1) == int(worker.id): last_error = machines.release_employee(task.run, worker.id)
	if not last_error.is_empty(): return
	if dispatcher != null: dispatcher.release_worker(worker.id)
	_interaction_result(task, "cancelled")
	tasks.erase(worker.id)
	_clear_actor(worker)
	_sync_hand(worker)

func _interaction_result(task: Dictionary, result: String) -> void:
	if task.kind != "interact": return
	_interactions.append({"id":int(task.id), "worker":int(task.worker), "purpose":String(task.purpose), "subject":int(task.subject), "result":result})

static func _clear_actor(worker: Dictionary) -> void:
	worker.erase("action")
	worker.erase("motion")
	worker.path = PackedVector2Array()
	worker.path_index = 0
	worker.walking = false
	worker.phase = "idle"
	worker.task_label = "idle"
	worker.action_left = 0.0
