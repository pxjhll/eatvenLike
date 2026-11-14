extends "res://game/rules/action_context.gd"
## One existing recipe step (or pot chore) per program. No recipe interpreter.
const Worker := preload("res://game/rules/worker_state.gd")
const Customers := preload("res://game/rules/customer_movement.gd")
const Step := preload("res://game/rules/serve_action_context.gd")
var rules: ShopRules

func _init(owner: ShopRules) -> void:
	rules = owner

static func target(worker: Dictionary, shop: SpecShop) -> String:
	if not worker.chore.is_empty(): return worker.chore.get_slice(":",1)
	if worker.order>=0: return worker.steps[worker.step].point
	return shop.staff.home_anchor

static func plan(worker: Dictionary, shop: SpecShop) -> Array:
	var point := target(worker,shop)
	var out := [Step.step("move",point)]
	if worker.chore.is_empty() and worker.order<0: return out
	var kind := "operate"
	if worker.chore.is_empty():
		var recipe: Dictionary = worker.steps[worker.step]
		if recipe.action=="hand": kind = "drop"
		elif shop.station(recipe.station).block=="batch_pot": kind = "pickup"
	out.append(Step.step(kind,point))
	return out

static func binding(worker: Dictionary, shop: SpecShop, stock_taken := false) -> Dictionary:
	return {"scope":"single","owner":int(worker.id),"order":int(worker.order),"step":int(worker.step),"chore":String(worker.chore),"target":target(worker,shop),"stock_taken":stock_taken}

func reserve(worker: Dictionary, _steps: Array) -> Dictionary:
	return {"error":"","lease":binding(worker,rules.shop)}

func ready(worker: Dictionary, action: Dictionary) -> String:
	if worker.action.lease!=binding(worker,rules.shop,bool(worker.action.lease.get("stock_taken",false))): return "assignment changed"
	if action.kind=="move": return ""
	if worker.walking or not Vector2(worker.pos).is_equal_approx(rules.nav.point(action.target)): return "not at action port"
	if worker.action.started: return ""
	if not worker.chore.is_empty():
		return "" if int(rules.stations[action.target].user)==int(worker.id) else "chore station unavailable"
	var recipe: Dictionary = worker.steps[worker.step]
	if recipe.action in ["take","hand"] and not Customers.ready(rules,"customer:%d"%int(worker.order)): return "customer not at counter"
	var station := rules.shop.station(recipe.station)
	if station.block=="batch_pot" and int(rules.stations[station.id].stock)<1: return "material unavailable"
	if station.block=="hand" and int(station.params.get("users",0))>0 and int(rules.stations[station.id].user) not in [-1,int(worker.id)]: return "workstation unavailable"
	return ""

func enter(worker: Dictionary, action: Dictionary) -> void:
	if action.kind=="move":
		rules.begin_move(worker,rules.nav.point(action.target),"walk")
	else:
		rules._arrived_single(worker)
		if action.kind=="pickup": worker.action.lease.stock_taken = true

func advance(worker: Dictionary, action: Dictionary, dt: float) -> bool:
	if action.kind=="move":
		var arrived := rules.advance_move(worker,dt)
		if not arrived and worker.path.is_empty():
			worker.action.status = "blocked"
			worker.action.reason = "route unavailable"
		return arrived
	return Worker.tick_single_work(worker,dt)

func commit(worker: Dictionary, action: Dictionary) -> void:
	if action.kind=="move":
		if worker.action.steps.size()==1:
			worker.erase("action")
			Worker.standby_single(worker)
		return
	worker.erase("action")
	rules._finish_work_single(worker)

func cancel(worker: Dictionary, lease: Dictionary) -> void:
	if lease.get("stock_taken",false):
		var recipe: Dictionary = worker.steps[worker.step]
		rules.stations[recipe.station].stock += 1
	for station: Dictionary in rules.stations.values():
		if int(station.user)==int(worker.id): station.user = -1
	worker.chore = ""
	worker.erase("motion")
	worker.walking = false
	worker.phase = "idle"
	worker.task_label = "待命"
	worker.target = ""
	worker.path = PackedVector2Array()
	worker.path_index = 0
	worker.timer = 0.0

func restore(worker: Dictionary) -> void:
	var steps := plan(worker,rules.shop)
	var index := 0 if worker.walking else 1
	if index>=steps.size(): return
	var started: bool = worker.walking or worker.phase=="work"
	var taken: bool = index==1 and started and steps[1].kind=="pickup"
	worker.action = {"version":1,"steps":steps,"index":index,"status":"running" if started else "blocked","reason":"" if started else "waiting for capability","started":started,"lease":binding(worker,rules.shop,taken)}

static func validate(worker: Dictionary, shop: SpecShop, stations: Dictionary) -> String:
	var program: Dictionary = worker.action
	var lease: Dictionary = program.lease
	if not lease.get("stock_taken") is bool or lease!=binding(worker,shop,bool(lease.get("stock_taken",false))): return "single action lease differs from assignment"
	if program.steps!=plan(worker,shop): return "single action effects differ from recipe step"
	var action: Dictionary = program.steps[program.index]
	var taken: bool = action.kind=="pickup" and program.started
	if taken!=lease.stock_taken: return "single material lease differs from cursor"
	if program.started:
		if action.kind=="move":
			if not worker.walking or worker.phase!="walk": return "single move differs from real phase"
		else:
			if worker.walking or worker.phase!="work": return "single work differs from real phase"
			if not worker.chore.is_empty() and int(stations[action.target].user)!=int(worker.id): return "single chore ownership differs"
			if worker.chore.is_empty():
				var station := shop.station(worker.steps[worker.step].station)
				if station.block=="hand" and int(station.params.get("users",0))>0 and int(stations[station.id].user)!=int(worker.id): return "single workstation ownership differs"
	return ""
