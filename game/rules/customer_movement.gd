extends RefCounted
## Authoritative customer locations for the shared movement protocol. Business
## modes own orders/stock/timers; this module owns only goals, routes and poses.
const Movement := preload("res://game/rules/rule_movement.gd")
const Presentation := preload("res://content/characters/actor_presentation.tres")

static func _rows(rules: ShopRules) -> Dictionary:
	if rules.movement.is_empty(): rules.movement = {"version":1,"customers":{}}
	return rules.movement.customers

static func port(rules: ShopRules, name: String) -> Vector2:
	return rules.shop.layout.customer_points.get(name,Vector2.ZERO)

static func queue_point(rules: ShopRules, slot: int) -> Vector2:
	var points := rules.shop.layout.customer_queue
	if points.is_empty(): return Vector2.ZERO
	if slot < points.size(): return points[slot]
	var step := points[-1]-points[-2] if points.size()>1 else Vector2(0,40)*rules.shop.layout.motion_units
	return points[-1]+step*float(slot-points.size()+1)

static func seat_target(rules: ShopRules, seat: int, purpose := "dine") -> String:
	for group in rules.shop.seat_groups:
		if group.purpose == purpose: return ("wait:" if purpose=="wait" else "seat:")+"%s/%d"%[group.id,seat]
	return ""

static func _request(rules: ShopRules, active: Dictionary, key: String, id: int, target: String, goal: Vector2, data: Dictionary, seated := false, migrate := false) -> void:
	var rows := _rows(rules)
	active[key] = true
	if not rows.has(key):
		var start := port(rules,"entrance")
		if migrate:
			if data.state in ["seated","eating","diner","await"]: start = goal
			elif data.state in ["to_seat","to_pickup"]:
				start = queue_point(rules,0)
				if data.state=="to_seat" and rules.shop.fulfillment.dine_rule=="self_pickup": start = port(rules,"pickup")
				var route := rules.nav.path(start,goal,"customer")
				var total := float(data.get("walk_total",0.0))
				var fraction := clampf(1.0-float(data.get("walk_left",0.0))/total,0.0,1.0) if total>0 else 0.0
				var temporary := {"pos":start,"path":route,"path_index":1 if route.size()>1 else 0,"walking":true}
				Movement.advance(temporary,RuleNav.length(route)*fraction)
				start = temporary.pos
		rows[key] = {"id":id,"pos":start,"path":PackedVector2Array(),"path_index":0,"walking":true,
			"target":"","state":"","seat":-1,"seated":false,"exiting":false,"dish":"","wait":0.0,"takeaway":false,"carry_item":""}
	var row: Dictionary = rows[key]
	row.state = String(data.state)
	row.seat = int(data.get("seat",-1))
	row.dish = String(data.get("dish",data.get("kind","")))
	row.wait = float(data.get("wait",0.0))
	row.takeaway = bool(data.get("takeaway",false))
	row.carry_item = String(data.get("carry_item",""))
	row.exiting = false
	if row.target != target or not row.has("motion") or row.motion.goal != goal:
		row.target = target
		Movement.request(row,rules.nav,goal,"customer")
	row.seated = seated and ready(rules,key)

static func sync(rules: ShopRules, migrate := false) -> void:
	if not rules.movement_enabled(): return
	var active := {}
	match rules.shop.fulfillment.handoff:
		"serve": _serve(rules,active,migrate)
		"single": _single(rules,active,migrate)
		_: _handoff(rules,active,migrate)
	var rows := _rows(rules)
	for key in rows.keys():
		if active.has(key): continue
		var row: Dictionary = rows[key]
		if not row.exiting:
			row.exiting = true
			row.seated = false
			row.state = "leaving"
			row.target = "exit"
			Movement.request(row,rules.nav,port(rules,"exit"),"customer")

static func tick(rules: ShopRules, dt: float) -> void:
	var rows := _rows(rules)
	for key in rows.keys():
		var row: Dictionary = rows[key]
		if row.walking or row.motion.topology != rules.nav.topology_key():
			Movement.tick(row,rules.nav,Presentation.customer_speed*rules.shop.layout.motion_units*dt)
		if row.exiting and ready(rules,key): rows.erase(key)

static func ready(rules: ShopRules, key: String) -> bool:
	if not rules.movement_enabled(): return true
	var row: Dictionary = rules.movement.get("customers",{}).get(key,{})
	return not row.is_empty() and not row.walking and not row.path.is_empty() and row.path_index>=row.path.size() and row.pos.is_equal_approx(row.motion.goal) and rules.nav.can_stand(row.pos,"customer")

static func _serve(rules: ShopRules, active: Dictionary, migrate: bool) -> void:
	var line := 0
	var waiting := 0
	for guest: Dictionary in rules.serve.guests:
		var data := guest.duplicate()
		var key := "guest:%d"%int(guest.id)
		var target: String
		var goal: Vector2
		if guest.state=="queue":
			target = "queue:%d"%line
			goal = queue_point(rules,line)
			line += 1
		elif guest.state in ["to_pickup","await"]:
			target = "pickup:%d"%waiting
			goal = rules.shop.layout.customer_points.get(target,port(rules,"pickup")+Vector2((waiting%4-1.5)*48,int(waiting/4)*40)*rules.shop.layout.motion_units)
			waiting += 1
		else:
			target = seat_target(rules,int(guest.seat))
			goal = port(rules,target)
		var order := {}
		for record: Dictionary in rules.serve.orders:
			if record.id==guest.order: order = record; break
		if not order.is_empty() and not order.lines.is_empty():
			data.dish = order.lines[0].dish
			if guest.state=="to_seat" and rules.shop.fulfillment.dine_rule=="self_pickup": data.carry_item = data.dish
		_request(rules,active,key,int(guest.id),target,goal,data,guest.state in ["seated","eating"],migrate)

static func _single(rules: ShopRules, active: Dictionary, migrate: bool) -> void:
	var rows := _rows(rules)
	var cap := rules.wait_seats()
	var assigned := {}
	for customer: Dictionary in rules.customers:
		var key := "customer:%d"%int(customer.id)
		var seat := int(rows.get(key,{}).get("seat",-1))
		if customer.state in ["queue","paid"] and seat>=0 and seat<cap: assigned[customer.id] = seat
	var in_line := 0
	# Paid customers and queue overflow keep a stable waiting seat.
	var list: Array = rules.customers.filter(func(c: Dictionary) -> bool: return c.state=="paid")
	for id in rules.queue:
		var customer := rules.customer(int(id))
		if not customer.is_empty(): list.append(customer)
	var queue_index := 0
	for customer: Dictionary in list:
		var id := int(customer.id)
		var queued: bool = customer.state=="queue"
		var use_seat: bool = not queued or assigned.has(id) or queue_index>=rules.current_stage().queue_capacity
		if use_seat and not assigned.has(id):
			for seat in cap:
				if not assigned.values().has(seat): assigned[id] = seat; break
		var seat := int(assigned.get(id,-1))
		var target := "queue:%d"%in_line
		var goal := queue_point(rules,in_line)
		if seat>=0:
			target = seat_target(rules,seat,"wait")
			goal = port(rules,target)
		else: in_line += 1
		if queued: queue_index += 1
		for worker: Dictionary in rules.workers:
			if worker.order==id and not worker.steps.is_empty() and worker.step<worker.steps.size():
				var action: String = worker.steps[worker.step].action
				if action=="hand":
					target = "pickup"
					goal = port(rules,"pickup")
				elif action=="take" and rules.shop.dispatch.action_version==1:
					target = "queue:0"
					goal = queue_point(rules,0)
		var data := customer.duplicate()
		data.seat = seat
		_request(rules,active,"customer:%d"%id,id,target,goal,data,seat>=0 and target.begins_with("wait:"),migrate)

static func _handoff(rules: ShopRules, active: Dictionary, migrate: bool) -> void:
	var line := 0
	for order: Dictionary in rules.orders:
		var target := seat_target(rules,int(order.seat)) if int(order.seat)>=0 else "queue:%d"%line
		var goal := port(rules,target) if int(order.seat)>=0 else queue_point(rules,line)
		if int(order.seat)<0: line += 1
		if order.reserved:
			target = "pickup"
			goal = port(rules,target)
		var data := order.duplicate()
		data.state = "order"
		_request(rules,active,"order:%d"%int(order.id),int(order.id),target,goal,data,int(order.seat)>=0 and not order.reserved,migrate)
	for diner: Dictionary in rules.diners:
		var key := "diner:%d"%int(diner.seat)
		var target := seat_target(rules,int(diner.seat))
		var data := diner.duplicate()
		data.state = "diner"
		var rows := _rows(rules)
		_request(rules,active,key,int(rows.get(key,{}).get("id",int(diner.seat)+1)),target,port(rules,target),data,true,migrate)

static func handoff_sale(rules: ShopRules, order_id: int, seat: int) -> void:
	var rows := _rows(rules)
	var key := "order:%d"%order_id
	if seat>=0 and rows.has(key):
		rows["diner:%d"%seat] = rows[key]
		rows.erase(key)
	sync(rules)

static func single_sale(rules: ShopRules, id: int, dish: String) -> void:
	var row: Dictionary = _rows(rules).get("customer:%d"%id,{})
	if not row.is_empty(): row.carry_item = dish
	sync(rules)
