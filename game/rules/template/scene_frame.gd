extends RefCounted
## One detached presentation protocol over the public runtime. Wallet,
## purchases and employee stats retain their outer command-owned source.
const Numbers := preload("res://game/rules/rule_numbers.gd")
const TemplatePresentation := preload("res://game/rules/template/presentation.gd")

static func build(runtime: RefCounted, displays: Array = [], presentation: Dictionary = {}) -> Dictionary:
	var frame: Dictionary = runtime.frame(displays,true)
	var owner: RefCounted = runtime.runner.owner
	frame.presentation_version = 1
	for key in ["gold","revenue","sold","paused","stage_index","completed_at","seats","belts"]:
		var value: Variant = owner.get(key)
		frame[key] = value.duplicate(true) if value is Dictionary or value is Array else value
	frame.stage_queue_capacity = runtime.service.queue_capacity() if runtime.service!=null else 0
	frame.movement = {"customers":{}}
	var counter_pose := _counter_pose(runtime)
	for worker in frame.workers:
		for legacy in ["steps","step","job","timer"]: worker.erase(legacy)
		worker.presentation_version = 1
		var held: Dictionary = frame.held.get(worker.id,{"count":0,"items":[]})
		worker.held_items = held.items.duplicate(true)
		worker.carry_count = int(held.count)
		worker.carry_item = "" if held.items.is_empty() else String(held.items[0].item)
		worker.speed = owner.walk_speed(worker)/owner.shop.layout.motion_units
		var task: Dictionary = runtime.runner.tasks.get(worker.id,{})
		var action_status: String = worker.get("action", {}).get("status", "")
		worker.display_task = task.get("kind","idle")
		worker.work_station = ""
		worker.display_working = worker.phase in ["work","pickup","dropoff"] and action_status != "blocked"
		worker.display_progress = _progress(runtime,worker,task)
		if not worker.walking:
			var standing_by: bool = (task.is_empty() and worker.phase == "idle") or (task.get("kind") == "interact" and action_status == "blocked")
			if not counter_pose.is_empty() and standing_by and Vector2(worker.pos).is_equal_approx(counter_pose.position):
				worker.facing = counter_pose.direction
			if worker.phase == "dropoff" and worker.display_working and task.get("kind") == "bundle" and String(task.to).begins_with("guest:"):
				var guest_id := int(String(task.to).trim_prefix("guest:"))
				for customer in frame.customers:
					if customer.id != guest_id: continue
					var toward_customer: Vector2 = customer.pos - worker.pos
					if not toward_customer.is_zero_approx(): worker.facing = _direction(toward_customer)
					break
		if task.get("kind")=="operate": worker.work_station = runtime.runner.machines.run(task.run).machine
		elif worker.display_working and worker.has("action"):
			var target: String = worker.action.steps[worker.action.index].target
			for id in runtime._definition.machines:
				var machine: Dictionary = runtime._definition.machines[id]
				if target in [machine.input,machine.output,machine.get("work_port","")]: worker.work_station = id; break
	if runtime.service==null:
		TemplatePresentation.project(frame,presentation)
		return frame
	var guests := {}
	for guest in frame.guests: guests[guest.id] = guest
	var routes := {}
	for route in frame.get("dining",{}).get("routes",[]): routes[route.guest] = route.takeaway
	var waiting := {}
	for lease in frame.get("waiting",{}).get("leases",[]): waiting[lease.guest] = lease.port
	for actor in frame.customers:
		var guest: Dictionary = guests[actor.id]
		var row: Dictionary = actor.duplicate(true)
		row.presentation_version = 1
		row.state = guest.state
		row.wait = float(guest.wait)
		row.dish = "" if guest.request.is_empty() else String(guest.request[0].dish)
		if runtime.service.uses_mixed_line():
			row.compact_order = String(row.target).begins_with("queue:") or String(row.target).begins_with("pickup:")
		row.seat_key = String(guest.seat) if not String(guest.seat).is_empty() else String(waiting.get(guest.id,""))
		row.seat = -1 if row.seat_key.is_empty() else int(String(row.seat_key).get_slice("/",1))
		row.seated = not row.seat_key.is_empty() and runtime.service.customers.ready(guest.id,row.seat_key)
		row.exiting = guest.state=="leaving"
		row.takeaway = bool(routes.get(guest.id,false))
		row.mood = owner.order_mood({"wait":guest.wait,"seat":row.seat})
		var patience: float = runtime._definition.service.orders.patience
		row.patience = maxf(0.0,1.0-float(guest.wait)/patience) if patience>0.0 and guest.state=="queue" else -1.0
		var held: Dictionary = frame.held.get("customer:"+str(guest.id),{"count":0,"items":[]})
		row.held_items = held.items.duplicate(true)
		row.carry_count = int(held.count)
		row.carry_item = "" if held.items.is_empty() else String(held.items[0].item)
		frame.movement.customers["guest:"+str(guest.id)] = row
	TemplatePresentation.project(frame,presentation)
	return frame

static func _counter_pose(runtime: RefCounted) -> Dictionary:
	if runtime.service == null: return {}
	var policy: Dictionary = runtime._definition.service
	var port: String = policy.get("staff_handoff", {}).get("counter_port", policy.handoff_port)
	if port.is_empty(): return {}
	var staff_position: Vector2 = runtime.runner.ports[port]
	var pickup_ports: Array = policy.get("pickup_queue", {}).get("ports", ["pickup"])
	var pickup: Dictionary = runtime.service.customers._target(pickup_ports[0])
	if not pickup.error.is_empty(): return {}
	var toward_customer: Vector2 = pickup.point - staff_position
	if toward_customer.is_zero_approx(): return {}
	return {"position": staff_position, "direction": _direction(toward_customer)}

static func _direction(vector: Vector2) -> int:
	return posmod(roundi(atan2(vector.x, vector.y) / (PI / 4.0)), 8)

static func seats_used(runtime: RefCounted, group: Resource) -> int:
	if runtime.service==null or group==null: return 0
	if group.purpose=="wait":
		if runtime.service.waiting==null: return 0
		return runtime.service.waiting.snapshot().leases.size()
	var used := {}
	for guest in runtime.service.orders.active_snapshot().guests:
		if not guest.seat.is_empty() and guest.state not in ["leaving","gone"]: used[guest.seat] = true
	return used.size()

static func activity(runtime: RefCounted, frame: Dictionary = {}) -> Dictionary:
	if frame.is_empty(): frame = build(runtime)
	var owner: RefCounted = runtime.runner.owner
	var idle := 0
	for worker in frame.workers:
		if runtime.runner.idle(worker.id): idle += 1
	var angry := 0
	for row in frame.movement.customers.values():
		if row.mood>=2 and row.state in ["queue","waiting"]: angry += 1
	var working := {}
	for machine in frame.machines: working[machine] = frame.machines[machine].working
	var interval := 0.0
	if runtime.service!=null and runtime.service.arrivals!=null:
		var policy: Dictionary = runtime._definition.service
		var base: float = policy.selection.stages[owner.stage_index].interval if policy.has("selection") else policy.arrivals.interval
		interval = Numbers.flow_interval(base,runtime.service.flow_multiplier(),owner.tune)
	return {"clock":frame.clock,"stage_index":frame.stage_index,"gold":frame.gold,"revenue":frame.revenue,"sold":frame.sold,
		"lost":frame.get("lost",0),"queue":frame.get("queue",[]).size(),"queue_capacity":frame.stage_queue_capacity,"angry_count":angry,
		"staff_count":frame.workers.size(),"idle_count":idle,"machine_working":working,
		"seat_count":owner.seat_count(),"seats_used":seats_used(runtime,owner.buy_group()),"customer_interval":interval}

static func _progress(runtime: RefCounted, worker: Dictionary, task: Dictionary) -> float:
	if task.is_empty() or not worker.get("display_working",false): return -1.0
	if task.kind=="operate":
		var run: Dictionary = runtime.runner.machines.run(task.run)
		return clampf(1.0-float(run.stage_left)/float(run.stage_total),0.0,1.0) if run.stage_total>0.0 else -1.0
	var total: float = task.drop_seconds if worker.phase=="dropoff" else task.seconds
	if task.kind=="bundle" and worker.phase=="pickup" and worker.has("action"):
		var step: Dictionary = worker.action.steps[worker.action.index]
		for pick in task.picks:
			if pick.claim==step.data.get("claim",-1): total = float(pick.seconds); break
	return clampf(1.0-float(worker.action_left)/total,0.0,1.0) if total>float(runtime._definition.hop_seconds)+0.000001 else -1.0
