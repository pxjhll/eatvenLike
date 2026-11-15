extends RefCounted
## Transitional old-record conversion only. Shared motion consumes the resulting
## neutral intents; the template runtime never imports this compatibility file.
const Ports := preload("res://game/rules/customer_ports.gd")
const Movement := preload("res://game/rules/rule_movement.gd")

static func _rows(rules: ShopRules) -> Dictionary:
	if rules.movement.is_empty(): rules.movement = {"version":1,"customers":{}}
	return rules.movement.customers

static func port(rules: ShopRules, name: String) -> Vector2:
	return Ports.port(rules,name)

static func queue_point(rules: ShopRules, slot: int) -> Vector2:
	return Ports.queue_point(rules,slot)

static func seat_target(rules: ShopRules, seat: int, purpose := "dine") -> String:
	return Ports.seat_target(rules,seat,purpose)

static func records(rules: ShopRules, migrate := false) -> Array:
	var out: Array = []
	match rules.shop.fulfillment.handoff:
		"serve": _serve(rules,out,migrate)
		"single": _single(rules,out,migrate)
		_: _handoff(rules,out,migrate)
	return out

static func _append(rules: ShopRules, out: Array, key: String, id: int, target: String, goal: Vector2, data: Dictionary, seated: bool, migrate: bool) -> void:
	var row := {"key":key,"id":id,"target":target,"goal":goal,"data":data,"seated":seated}
	if migrate:
		var start := port(rules,"entrance")
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
		row.start = start
	out.append(row)

static func _serve(rules: ShopRules, out: Array, migrate: bool) -> void:
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
		_append(rules,out,key,int(guest.id),target,goal,data,guest.state in ["seated","eating"],migrate)

static func _single(rules: ShopRules, out: Array, migrate: bool) -> void:
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
		_append(rules,out,"customer:%d"%id,id,target,goal,data,seat>=0 and target.begins_with("wait:"),migrate)

static func _handoff(rules: ShopRules, out: Array, migrate: bool) -> void:
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
		_append(rules,out,"order:%d"%int(order.id),int(order.id),target,goal,data,int(order.seat)>=0 and not order.reserved,migrate)
	for diner: Dictionary in rules.diners:
		var key := "diner:%d"%int(diner.seat)
		var target := seat_target(rules,int(diner.seat))
		var data := diner.duplicate()
		data.state = "diner"
		var rows := _rows(rules)
		_append(rules,out,key,int(rows.get(key,{}).get("id",int(diner.seat)+1)),target,port(rules,target),data,true,migrate)
