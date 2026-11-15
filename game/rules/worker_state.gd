extends RefCounted
const Movement := preload("res://game/rules/rule_movement.gd")
## Stateless transitions on a caller-owned worker record. Rules owns decisions,
## navigation, stock, customers and events; routes/steps are explicit owned inputs.

static func create(id: int, kind: String, name: String, stats: Dictionary, position: Vector2) -> Dictionary:
	return {"id": id, "kind": kind, "name": name, "stats": stats.duplicate(),
		"pos": position, "walking": false, "phase": "idle", "task_label": "idle",
		"carry_item": "", "carry_count": 0, "fatigue": 0.0, "completed": 0, "job": {}, "ticket": {},
		"post": "", "path": PackedVector2Array(), "path_index": 0, "action_left": 0.0, "deployed": false, "source": "",
		"target": "", "timer": 0.0, "order": -1, "steps": [], "step": 0, "chore": ""}

static func place(worker: Dictionary, post: String, position: Vector2) -> void:
	worker.erase("motion")
	worker.post = post
	worker.pos = position

static func assign_path(worker: Dictionary, path: PackedVector2Array) -> void:
	Movement.assign(worker,path)

static func begin_walk(worker: Dictionary, path: PackedVector2Array, phase: String) -> void:
	assign_path(worker, path)
	worker.phase = phase
	worker.walking = true

static func advance_walk(worker: Dictionary, distance: float) -> bool:
	return Movement.advance(worker,distance)

static func arrive(worker: Dictionary) -> void:
	worker.walking = false

static func enter_handoff_action(worker: Dictionary, phase: String, seconds: float) -> void:
	worker.walking = false
	worker.phase = phase
	worker.action_left = seconds

static func tick_handoff_action(worker: Dictionary, delta: float) -> bool:
	worker.action_left = maxf(0, worker.action_left - delta)
	return worker.action_left <= 0.000001

static func finish_handoff(worker: Dictionary) -> void:
	worker.completed += 1
	worker.carry_count = 0
	worker.carry_item = ""
	worker.job = {}
	worker.phase = "idle"
	worker.task_label = "idle"
	worker.walking = false

static func cancel_assignment(worker: Dictionary) -> void:
	worker.erase("motion")
	worker.job = {}
	worker.ticket = {}
	worker.carry_count = 0
	worker.carry_item = ""
	worker.phase = "idle"
	worker.task_label = "idle"
	worker.walking = false
	worker.path = PackedVector2Array()
	worker.path_index = 0
	worker.action_left = 0.0

static func begin_single_work(worker: Dictionary, seconds: float) -> void:
	worker.phase = "work"
	worker.timer = seconds
	worker.duration = seconds

static func tick_single_work(worker: Dictionary, delta: float) -> bool:
	worker.timer -= delta
	return worker.timer <= 0.0

static func finish_single_work(worker: Dictionary) -> void:
	worker.phase = "idle"

static func wait_single(worker: Dictionary, label: String) -> void:
	worker.phase = "wait"
	worker.task_label = label

static func standby_single(worker: Dictionary) -> void:
	worker.phase = "walk" if worker.walking else "idle"
	worker.task_label = "待命"

static func claim_single_order(worker: Dictionary, order_id: int, steps: Array) -> void:
	worker.order = order_id
	worker.steps = steps
	worker.step = 0
	worker.walking = false

static func finish_single_order(worker: Dictionary) -> void:
	worker.order = -1
	worker.steps = []
	worker.carry_item = ""
	worker.carry_count = 0
