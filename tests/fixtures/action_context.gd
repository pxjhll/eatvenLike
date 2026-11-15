extends RefCounted
## A small real inventory/workbench, not a callback mock. Owns its stock and lease.
const Movement := preload("res://game/rules/rule_movement.gd")
var stock := 1
var output := 0
var processed := 0
var available := true
var locks := {}
var committed: Array = []
var on_commit: Callable
var nav: RuleNav

func _init() -> void:
	var layout := SpecLayout.new()
	layout.motion_version = 1
	layout.nav = "grid"
	layout.cell = 20.0
	layout.grid_size = Vector2i(12,8)
	layout.areas = [Rect2i(0,0,12,8)]
	layout.actor_areas = {"staff":[Rect2i(0,0,12,8)]}
	nav = RuleNav.new(layout)

func reserve(worker: Dictionary, _steps: Array) -> Dictionary:
	if not locks.is_empty(): return {"error":"workbench occupied","lease":{}}
	locks[str(worker.id)] = true
	return {"error":"","lease":{"scope":"fixture","owner":int(worker.id)}}

func ready(worker: Dictionary, step: Dictionary) -> String:
	if not available: return "not available"
	if step.kind=="pickup" and stock<1: return "no stock"
	if step.kind in ["transport","drop"] and worker.carry_count<1: return "empty hands"
	return ""

func enter(worker: Dictionary, step: Dictionary) -> void:
	worker.task_label = step.label
	if step.kind in ["move","transport"]:
		Movement.request(worker,nav,Vector2(150,50) if step.target=="to" else Vector2(50,50),"staff")
		worker.phase = "walk"
	else:
		worker.phase = "work"
		worker.walking = false
		worker.action_left = step.seconds

func advance(worker: Dictionary, step: Dictionary, dt: float) -> bool:
	if step.kind in ["move","transport"]: return Movement.tick(worker,nav,40.0*dt)
	worker.action_left = maxf(0.0,worker.action_left-dt)
	return worker.action_left<=0.000001

func commit(worker: Dictionary, step: Dictionary) -> void:
	match step.kind:
		"pickup":
			stock -= 1
			worker.carry_item = "raw"
			worker.carry_count = 1
		"operate":
			processed += 1
			if worker.carry_count>0: worker.carry_item = "cooked"
		"drop":
			output += worker.carry_count
			worker.carry_count = 0
			worker.carry_item = ""
	committed.append(step.kind)
	if worker.action.status=="completed": locks.erase(str(worker.id))
	if on_commit.is_valid(): on_commit.call(worker,step)

func cancel(worker: Dictionary, lease: Dictionary) -> void:
	stock += int(worker.carry_count)
	worker.carry_count = 0
	worker.carry_item = ""
	worker.walking = false
	worker.phase = "idle"
	worker.erase("motion")
	locks.erase(str(lease.owner))

func snapshot() -> Dictionary:
	return {"stock":stock,"output":output,"processed":processed,"available":available,"locks":locks.duplicate(true),"committed":committed.duplicate()}

func restore(data: Dictionary) -> void:
	for key in data: set(key,data[key].duplicate(true) if data[key] is Dictionary or data[key] is Array else data[key])
