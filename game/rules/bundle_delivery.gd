extends RefCounted
const Customers := preload("res://game/rules/customer_movement.gd")
## A business lease over existing goods. No inventory copy and no visual state.

static func enabled(shop: SpecShop) -> bool:
	return shop.fulfillment.flow_version==1 and shop.fulfillment.delivery_batch=="order"

static func source_port(shop: SpecShop, dish: String) -> String:
	if shop.fulfillment.flow_version==1 and shop.fulfillment.delivery_points.has(dish): return shop.fulfillment.delivery_points[dish]
	for station in shop.stations:
		if station.block=="pickup": return station.id
	return ""

static func candidates(rules: ShopRules, worker: Dictionary, flow: Script) -> Array:
	var out: Array = []
	for order: Dictionary in rules.serve.orders:
		if order.paid: continue
		var busy := false
		for job: Dictionary in rules.serve.jobs.values():
			if job.kind=="bundle" and job.order==order.id: busy = true
			elif job.kind=="serve":
				var unit: Dictionary = flow.unit(rules,int(job.unit))
				if unit.get("order",-1)==order.id: busy = true
		if busy: continue
		var entries: Array = []
		var complete := true
		var remaining := 0
		for line: Dictionary in order.lines: remaining += int(line.qty)-int(line.delivered)
		for unit: Dictionary in rules.serve.units:
			if unit.order!=order.id: continue
			var dish := rules.shop.dish(String(unit.dish))
			var port: String = flow.pickup_for(rules.shop,dish.id)
			var found := {}
			var delivered := false
			for good: Dictionary in rules.serve.goods:
				if good.owner!=unit.id or good.item!=dish.item: continue
				if good.at=="seat:"+str(order.seat): delivered = true; break
				if good.at==port and int(good.res)==-1 and rules.station_unlocked(port): found = good; break
			if delivered: continue
			if found.is_empty(): complete = false; break
			entries.append({"id":int(found.id),"from":port})
		if not complete or entries.is_empty() or entries.size()!=remaining or rules.carry(worker)<entries.size(): continue
		var good: Dictionary = flow._good(rules,int(entries[0].id))
		var job: Dictionary = flow._job("bundle",-1,-1,String(good.item),int(good.id),entries[0].from,"seat:"+str(order.seat),int(order.guest))
		job.order = int(order.id)
		job.goods = entries
		job.capacity = rules.carry(worker)
		job.bundle_version = 1
		out.append(flow._scored(rules,worker,job,"serve",float(flow.guest(rules,int(order.guest)).wait),"送餐"))
	return out

static func binding(worker: Dictionary, job: Dictionary) -> Dictionary:
	return {"scope":"bundle","owner":int(worker.id),"order":int(job.order),"goods":job.goods.duplicate(true),"capacity":int(job.capacity),"version":1}

static func check_goods(rules: ShopRules, worker: Dictionary, job: Dictionary, flow: Script, reserved: bool) -> String:
	var order: Dictionary = flow.order(rules,int(job.order))
	if order.is_empty() or order.paid: return "order unavailable"
	if job.goods.is_empty() or int(job.capacity)<job.goods.size(): return "invalid bundle capacity"
	if not reserved and rules.carry(worker)<job.goods.size(): return "capacity unavailable"
	var ids := {}
	for entry: Dictionary in job.goods:
		if ids.has(entry.id): return "duplicate bundle good"
		ids[entry.id] = true
		var good: Dictionary = flow._good(rules,int(entry.id))
		if good.is_empty(): return "good unavailable"
		var unit: Dictionary = flow.unit(rules,int(good.owner))
		if unit.get("order",-1)!=job.order or rules.shop.dish(String(unit.dish)).item!=good.item: return "wrong order good"
		if entry.from!=flow.pickup_for(rules.shop,String(unit.dish)): return "wrong collection port"
		if reserved:
			if int(good.res)!=int(worker.id) or good.at not in [entry.from,"hand:"+str(worker.id)]: return "lease unavailable"
		elif int(good.res)!=-1 or good.at!=entry.from: return "good already claimed"
	return ""

static func reserve(rules: ShopRules, worker: Dictionary, job: Dictionary, flow: Script) -> Dictionary:
	var error := check_goods(rules,worker,job,flow,false)
	if not error.is_empty(): return {"error":error,"lease":{}}
	# No mutation until every member and capacity check succeeds.
	for entry: Dictionary in job.goods: flow._good(rules,int(entry.id)).res = int(worker.id)
	return {"error":"","lease":binding(worker,job)}

static func complete(rules: ShopRules, worker: Dictionary, job: Dictionary, flow: Script) -> void:
	if not is_same(flow.job_of(rules,worker),job) or not check_goods(rules,worker,job,flow,true).is_empty(): return
	var customer: Dictionary = flow.guest(rules,int(job.guest))
	if customer.get("state","")!="seated" or not Customers.ready(rules,"guest:%d"%int(job.guest)): return
	if worker.walking or worker.carry_count!=job.goods.size() or not Vector2(worker.pos).is_equal_approx(flow._point(rules,job.to)): return
	for entry: Dictionary in job.goods:
		if flow._good(rules,int(entry.id)).at!="hand:"+str(worker.id): return
	var units: Array[int] = []
	for entry: Dictionary in job.goods:
		var good: Dictionary = flow._good(rules,int(entry.id))
		good.at = job.to
		good.res = -1
		units.append(int(good.owner))
	worker.carry_item = ""
	worker.carry_count = 0
	flow._end(rules,worker)
	var done: Array = []
	for id in units: done.append(flow._commit_delivery(rules,id))
	var guest: Dictionary = flow.guest(rules,int(job.guest))
	var started: bool = flow._start_eating(rules,guest)
	# Entire order, lease, physical items and eating state commit before events.
	for event: Dictionary in done: flow._announce_delivery(rules,event)
	if started: rules.events.emit("eat_start",{"guest":guest.id,"seat":guest.seat})

static func cancel(rules: ShopRules, worker: Dictionary, job: Dictionary, flow: Script) -> void:
	if not is_same(flow.job_of(rules,worker),job): return
	for entry: Dictionary in job.goods:
		var good: Dictionary = flow._good(rules,int(entry.id))
		if good.is_empty() or int(good.res)!=int(worker.id): continue
		if good.at=="hand:"+str(worker.id): good.at = entry.from
		good.res = -1
	rules.serve.jobs.erase(str(worker.id))
	worker.erase("action")
	worker.erase("motion")
	worker.carry_item = ""
	worker.carry_count = 0
	worker.walking = false
	worker.phase = "idle"
	worker.task_label = "idle"
	worker.action_left = 0.0
