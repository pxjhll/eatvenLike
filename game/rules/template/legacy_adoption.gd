extends RefCounted
## One-way loading boundary. Historical formats are converted to public facts,
## transactions and programs, then validated by the ordinary Runtime restore.
const Orders := preload("res://game/rules/template/orders.gd")
const Machines := preload("res://game/rules/template/machines.gd")
const Context := preload("res://game/rules/template/action_context.gd")
const Motion := preload("res://game/rules/rule_movement.gd")
const Actions := preload("res://game/rules/rule_actions.gd")
const Clock := preload("res://game/rules/template/production_clock.gd")
const State := preload("res://game/rules/template/session_state.gd")
const Options := preload("res://game/rules/template/customization.gd")
var source: RefCounted
var target: RefCounted
var runtime: RefCounted
var stock: RefCounted
var error := ""

func adopt(owner: RefCounted, data: Dictionary, refresh: bool) -> String:
	var legacy_shop: Resource = owner.shop.copy_for_editing()
	legacy_shop.runtime_template = null
	source = owner.get_script().new(legacy_shop)
	source.event_defs = owner.event_defs.duplicate()
	error = source._load_legacy_dict(data,refresh)
	if not error.is_empty(): return "legacy validation: "+error
	target = owner.get_script().new(owner.shop)
	target.runtime = null
	target.event_defs = owner.event_defs.duplicate()
	target._restore_validated(source.to_dict())
	for worker in target.roster:
		ContextRunnerClear(worker)
	error = target.enable_runtime(owner._runtime_template,false)
	if not error.is_empty(): return error
	runtime = target.runtime; stock = runtime.runner.inventory
	# Initial template balances must be replaced by the actual saved balances.
	stock._state.lots = []; stock._state.created = {}; stock._state.consumed = {}
	runtime._clock = source.clock
	match source.shop.fulfillment.handoff:
		"serve": _serve()
		"handoff": _handoff()
		"single": _single()
		_: error = "legacy format conversion is not implemented"
	if not error.is_empty(): return error
	_clocks()
	if not error.is_empty(): return error
	stock._state.created = stock._state.consumed.duplicate()
	for lot in stock._state.lots: stock._add(stock._state.created,lot.item,int(lot.count))
	# Remove all old running ledgers before serializing the new ownership split.
	target.orders = []; target.customers = []; target.queue = []; target.diners = []
	target.movement = {}; target.serve = source.serve.duplicate(true)
	target.serve.clear()
	target._build_stations()
	target.rng.state = source.rng.state; target.event_rng.state = source.event_rng.state
	target.gold = source.gold; target.revenue = source.revenue
	target.sold = source.sold; target.sold_by_dish = source.sold_by_dish.duplicate()
	target.events.log = source.events.log.duplicate(true)
	return State.restore(owner,State.save(target))

static func ContextRunnerClear(worker: Dictionary) -> void:
	for key in ["action","motion","duration"]: worker.erase(key)
	worker.path = PackedVector2Array(); worker.path_index = 0
	worker.walking = false; worker.phase = "idle"; worker.task_label = "idle"
	worker.carry_count = 0; worker.carry_item = ""; worker.action_left = 0.0
	worker.job = {}; worker.ticket = {}; worker.steps = []; worker.step = 0; worker.order = -1; worker.chore = ""

func _clocks() -> void:
	var service: RefCounted = runtime.service
	var arrivals: Dictionary = service.arrivals._state
	arrivals.open = source.is_open(); arrivals.started = source.is_open()
	arrivals.attempts = maxi(int(service.arrivals._definition.opening),source._next_order-1)
	arrivals.left = source._next_customer if source._queued_arrivals() else maxf(0.0,source._order_interval()-source._order_clock)
	if not arrivals.started:
		arrivals.left = service.arrivals._definition.first_delay; arrivals.attempts = 0
	service.orders._state.lost = source.lost
	if service.ramp!=null:
		for dish in service.ramp._counts: service.ramp._counts[dish] = mini(int(source.order_ramp.get(dish,0)),int(service.ramp._definition.orders))
	if service.flyers!=null:
		var flyers: Dictionary = service.flyers._state
		flyers.pending = source.flyer_left if source._queued_arrivals() else source.flyer_pending
		flyers.cooldown = maxf(0.0,source.flyer_ready_at-source.clock) if source._queued_arrivals() else source.flyer_wait
		if service.flyers._definition.pattern=="spread":
			flyers.wave_left = source.flyer_wave
			flyers.elapsed = source.flyer_clock if flyers.pending>0 else 0.0
		else:
			flyers.first = flyers.pending>0 and source.flyer_timer<=0.0
			flyers.elapsed = 0.0 if flyers.pending==0 else maxf(0.0,float(service.flyers._definition.gap)-source.flyer_timer)

func _handoff() -> void:
	var service: RefCounted = runtime.service
	for before in source.orders:
		var seat: String = "seat:"+source.dine_group().id+"/"+str(before.seat) if int(before.seat)>=0 else ""
		_create_order(int(before.id),String(before.dish),seat,bool(before.takeaway),float(before.wait))
	for before in source.diners:
		var previous: Dictionary = source.movement.get("customers",{}).get("diner:"+str(before.seat),{})
		var id: int = int(previous.id) if not previous.is_empty() else int(source._next_order)+int(before.seat)
		var guest := _create_order(id,String(before.dish),"seat:"+source.dine_group().id+"/"+str(before.seat),false,0.0)
		guest.state = "eating"; guest.queued = false; guest.meal_left = float(before.left)
		var order: Dictionary = service.orders._find(service.orders._state.orders,int(guest.order))
		order.state = "delivered"; order.paid = true; order.income = floori(order.quote)
		var line: Dictionary = order.lines[0]
		line.delivered = 1
		var unit: Dictionary = runtime._find_unit(line.units[0].unit)
		_history_node(unit,runtime._definition.recipes[unit.recipe].output.node)
		_insert("guest:"+str(id),line.item,1,int(unit.id))
	for id in source.stations:
		var before: Dictionary = source.stations[id]
		for direction in ["input","output"]:
			for original in before[direction]:
				var count: int = int(before[direction][original])
				if count<1: continue
				var item := _tea_item(String(original))
				if id==source.RACK:
					for unused in count: _prepared(String(original),"rack",item)
				elif id==source.pickup_id and direction=="output":
					for unused in count: _prepared(String(original),"shelf:"+String(original),item)
				elif runtime.runner.ports.has(id): _insert(id,item,count)
				else: _fail("unmapped legacy machine stock: "+id); return
	for dish in source.shelf_stock:
		for unused in int(source.shelf_stock[dish]): _prepared(String(dish),"shelf:"+String(dish),String(dish))
	for id in source.stations:
		var before: Dictionary = source.stations[id]
		if int(before.processing)<1: continue
		if runtime._definition.restocks.has(id):
			var rule: Dictionary = runtime._definition.restocks[id]
			var amount: int = int(before.processing)
			var consumes := {}; var produces := {}
			for item in rule.consumes:
				consumes[item] = int(rule.consumes[item])*amount
				_insert(runtime._definition.machines[id].input,item,int(consumes[item]))
			for item in rule.produces: produces[item] = int(rule.produces[item])*amount
			var started: Dictionary = runtime.runner.machines.start(id,consumes,produces,float(before.duration))
			if not started.error.is_empty(): _fail(started.error); return
			var run: Dictionary = runtime.runner.machines._find(started.id)
			runtime._restocks._runs[id] = int(run.id)
			_restore_machine_clock(run,before)
		else:
			var item := _tea_item(String(before.processing_item))
			var unit := _unstarted_unit(item,true)
			var recipe: Dictionary = runtime._definition.recipes[unit.recipe]
			for node in recipe.nodes.values():
				if node.capability!="process" or node.machine!=id: continue
				for dependency in node.dependencies: _history_node(unit,dependency)
				for ingredient in node.consumes: _insert(runtime._definition.machines[id].input,ingredient,int(node.consumes[ingredient]),int(unit.id))
				var started: Dictionary = runtime.runner.machines.start(id,node.consumes,node.produces,float(before.duration),unit.id)
				if not started.error.is_empty(): _fail(started.error); return
				unit.running[node.id] = int(started.id)
				_restore_machine_clock(runtime.runner.machines._find(started.id),before)
				break
	for before in source.workers:
		var job: Dictionary = before.job
		if job.is_empty(): continue
		var worker: Dictionary = target.worker_by_id(before.id)
		if job.kind=="serve":
			var order: Dictionary = service.orders._find(service.orders._state.orders,int(job.order_id))
			var unit: Dictionary = runtime._find_unit(order.lines[0].units[0].unit)
			var recipe: Dictionary = runtime._definition.recipes[unit.recipe]
			_history_node(unit,recipe.output.node)
			var output: Dictionary = runtime.production_output(unit.id)
			var existing: int = stock.quantity(output.place,order.lines[0].item,int(output.owner),true)
			if existing<1: _insert(output.place,order.lines[0].item,1,int(output.owner))
			error = _import_bundle(worker,[{"from":String(output.place),"to":"guest:"+str(order.guest),"item":String(order.lines[0].item),"count":1,"owner":int(output.owner),"allocate_owner":int(unit.id)}],float(source.shop.dispatch.hop_seconds))
			if not error.is_empty(): return
			var bundle: int = runtime.runner.tasks[worker.id].bundle
			service._deliveries.append({"order":int(order.id),"bundle":bundle,"phase":"staff","left":0.0})
			var index: int = {"walk_pickup":0,"pickup":1,"walk_dropoff":2,"dropoff":3}.get(String(before.phase),0)
			if index>=2:
				error = stock.pickup_bundle(bundle)
				if not error.is_empty(): return
				runtime.runner._sync_hand(worker)
			_program(worker,index,float(before.action_left))
		elif job.kind=="load":
			error = _import_bundle(worker,[{"from":String(job.src),"to":String(job.dst),"item":_tea_item(job.item),"count":int(job.count),"owner":-1,"allocate_owner":-1}],float(source.shop.dispatch.hop_seconds))
			if not error.is_empty(): return
			var index: int = {"walk_pickup":0,"pickup":1,"walk_dropoff":2,"dropoff":3}.get(String(before.phase),0)
			if index>=2:
				error = stock.pickup_bundle(runtime.runner.tasks[worker.id].bundle)
				if not error.is_empty(): return
				runtime.runner._sync_hand(worker)
			_program(worker,index,float(before.action_left))
		elif job.kind in ["transfer","carry_to_process","carry_to_shelf","carry_to_rack"]:
			var dish: String = before.ticket.get("dish",job.item)
			var unit := _unstarted_unit(dish,job.dst==source.pickup_id)
			var recipe: Dictionary = runtime._definition.recipes[unit.recipe]
			var destination: String = String(job.dst)
			if job.dst==source.SHELF: destination = "shelf:"+dish
			var from: String = String(job.src)
			var item := _tea_item(job.item)
			var origin := -1
			var transfer_node := ""
			for node in recipe.nodes.values():
				if node.produces.has(item) and node.place==from:
					_history_node(unit,node.id)
					origin = -1 if node.capability=="source" else int(unit.id)
					break
			for node in recipe.nodes.values():
				if node.capability=="process" and node.machine==destination and node.inputs.has(item):
					var producer: Dictionary = recipe.nodes[node.inputs[item]]
					if producer.place!=from: _history_node(unit,producer.id)
				elif node.capability=="transfer" and node.place==destination and node.inputs.has(item):
					var producer: Dictionary = recipe.nodes[node.inputs[item]]
					if producer.place==from: transfer_node = node.id
			var found := false
			for lot in stock._state.lots:
				if lot.place==from and lot.item==item and lot.owner==-1 and lot.count>=int(job.count): lot.owner = origin; found = true; break
			if not found: _insert(from,item,int(job.count),origin)
			error = _import_bundle(worker,[{"from":from,"to":destination,"item":item,"count":int(job.count),"owner":origin,"allocate_owner":int(unit.id)}],float(source.shop.dispatch.hop_seconds))
			if not error.is_empty(): return
			if not transfer_node.is_empty(): unit.running[transfer_node] = int(runtime.runner.tasks[worker.id].bundle)
			var index: int = {"walk_pickup":0,"pickup":1,"walk_dropoff":2,"dropoff":3}.get(String(before.phase),0)
			if index>=2:
				error = stock.pickup_bundle(runtime.runner.tasks[worker.id].bundle)
				if not error.is_empty(): return
				runtime.runner._sync_hand(worker)
			_program(worker,index,float(before.action_left))
		elif job.kind in ["stir","pot_take","work"]:
			var run := {}
			for candidate in runtime.runner.machines._state.runs:
				if candidate.machine==job.src and candidate.phase not in Machines.TERMINAL: run = candidate; break
			if run.is_empty() and job.kind=="work":
				var unit := _unstarted_unit(before.ticket.get("dish",job.item))
				var recipe: Dictionary = runtime._definition.recipes[unit.recipe]
				for node in recipe.nodes.values():
					if node.capability!="process" or node.machine!=job.src: continue
					for dependency in node.dependencies: _history_node(unit,dependency)
					for item in node.consumes:
						var missing: int = int(node.consumes[item])-stock.quantity(runtime._definition.machines[job.src].input,item,int(unit.id),true)
						if missing>0: _insert(runtime._definition.machines[job.src].input,item,missing,int(unit.id))
					var timing := Clock.evaluate(node,target)
					var started: Dictionary = runtime.runner.machines.start(job.src,node.consumes,node.produces,timing.seconds,int(unit.id))
					if not started.error.is_empty(): _fail(started.error); return
					unit.running[node.id] = int(started.id); run = runtime.runner.machines._find(started.id)
					break
			if run.is_empty(): _fail("old machine task has no matching run"); return
			error = runtime.runner.operate(worker.id,run.id,runtime.runner.machines.stage_port(run.id))
			if not error.is_empty(): return
			_program(worker,1 if before.phase=="work" else 0,float(before.action_left))
			if before.phase=="work":
				run.stage_left = maxf(0.0,float(before.action_left))*target.skill(worker)
				run.stage_total = maxf(run.stage_left,float(run.stage_total))
		elif job.kind=="pot_start":
			var rule: Dictionary = runtime._definition.restocks[job.src]
			var needs := {rule.consumes.keys()[0]:int(job.count)}
			var output := {rule.produces.keys()[0]:int(job.count)}
			var started: Dictionary = runtime.runner.machines.start(job.src,needs,output,source.pot_seconds(job.src))
			if not started.error.is_empty(): _fail(started.error); return
			runtime._restocks._runs[job.src] = int(started.id)
			error = runtime.runner.operate(worker.id,started.id,runtime.runner.machines.stage_port(started.id))
			if not error.is_empty(): return
			_program(worker,1 if before.phase=="work" else 0,float(before.action_left))
			if before.phase=="work":
				var run: Dictionary = runtime.runner.machines._find(started.id)
				run.stage_left = maxf(0.0,float(before.action_left))*target.skill(worker)
				run.stage_total = maxf(run.stage_left,float(run.stage_total))
		else: _fail("unconverted legacy preparation: "+String(job.kind)); return
	_import_belts()
	if not error.is_empty(): return
	_reconcile_receipts()
	if not error.is_empty(): return
	_sync_customers()

func _restore_machine_clock(run: Dictionary, before: Dictionary) -> void:
	run.phase = {"stir":"await_stir","awaiting_take":"await_unload"}.get(String(before.phase),"processing")
	run.duration = float(before.duration); run.remaining = maxf(0.0,float(before.remaining))
	var profile: Dictionary = runtime.runner.machines._state.definitions[run.machine].profile
	for point in profile.stir_points:
		if float(point)<float(before.progress) or (float(point)==float(before.progress) and before.phase!="stir"): run.stir_index += 1

func _tea_item(item: String) -> String:
	return source._cup(item)

func _insert(place: String, item: String, count: int, owner: int = -1) -> void:
	if count<=0: return
	if not stock._state.places.has(place): _fail("unknown migrated container: "+place); return
	if item in stock._state.places[place].infinite: return
	stock._insert(place,item,count,owner)
	stock._add(stock._state.created,item,count)

func _create_order(id: int, dish: String, seat: String, takeaway: bool, wait: float, selected: Array = []) -> Dictionary:
	var service: RefCounted = runtime.service
	var guest := Orders._guest()
	guest.id = id; guest.order = id; guest.wait = wait; guest.seat = seat
	guest.state = "waiting"; guest.queued = service._policy.orders.queue_release=="after_delivery"
	var recipe: String = service._policy.menu[dish]
	if service.dining!=null:
		recipe = service.dining.recipe(dish,recipe,takeaway)
		service.dining.record(id,takeaway)
	if service._policy.has("customization"): recipe = Options.resolve(service._policy.customization,dish,recipe,selected).recipe
	var line := Orders._line()
	line.id = int(service.orders._state.next_line); service.orders._state.next_line += 1
	line.dish = dish; line.recipe = recipe; line.item = runtime._definition.recipes[recipe].output.item
	line.qty = 1; line.price = float(source.dish_price(dish)); line.units = [{"unit":id,"qty":1,"delivered":0}]
	if service._policy.has("customization"):
		line.options = selected.duplicate()
		line.price = Options.quote(service._policy.customization,source,dish,selected)
	var order := Orders._order()
	order.id = id; order.guest = id; order.quote = line.price; order.lines = [line]
	guest.request = [{"dish":dish,"recipe":recipe,"item":line.item,"qty":1}]
	if service._policy.has("customization"): guest.request[0].options = selected.duplicate()
	service.orders._state.guests.append(guest); service.orders._state.orders.append(order)
	service.orders._state.next_guest = maxi(int(service.orders._state.next_guest),id+1)
	service.orders._state.next_order = maxi(int(service.orders._state.next_order),id+1)
	runtime._units.append({"id":id,"recipe":recipe,"done":[],"running":{}})
	runtime._next_unit = maxi(runtime._next_unit,id+1)
	service.customers.spawn(id)
	var place: String = service._guest_place(guest)
	error = runtime.runner.define_dynamic_place("guest:"+str(id),runtime.runner.ports[place])
	return guest

func _unstarted_unit(dish: String, sealed := false) -> Dictionary:
	var recipe: String = runtime.service._policy.menu[dish]
	if sealed and runtime.service.dining!=null: recipe = runtime.service.dining.recipe(dish,recipe,true)
	for unit in runtime._units:
		if unit.recipe==recipe and unit.done.is_empty() and unit.running.is_empty(): return unit
	var id: int = runtime.request_production(recipe).id
	return runtime._find_unit(id)

func _prepared(dish: String, place: String, item: String) -> void:
	var unit := _unstarted_unit(dish,place=="rack")
	var recipe: Dictionary = runtime._definition.recipes[unit.recipe]
	for node in recipe.nodes.values():
		if node.place==place and node.produces.has(item): _history_node(unit,node.id)
	_insert(place,item,1,int(unit.id))

func _single() -> void:
	var service: RefCounted = runtime.service
	var orders: Dictionary = service.orders._state
	orders.next_guest = source._next_customer_id; orders.next_order = source._next_customer_id
	runtime._next_unit = int(source._next_customer_id)
	for before in source.customers:
		if before.state=="paid":
			var guest := _create_order(int(before.id),String(before.kind),"",false,float(before.wait),before.get("options",[]))
			var order: Dictionary = service.orders._find(orders.orders,int(guest.order))
			order.paid = source.shop.fulfillment.pay_at=="on_take"
			order.income = int(before.paid) if order.paid else 0
			if before.addon and before.kind!=source.shop.fulfillment.addon_dish:
				var dish: String = source.shop.fulfillment.addon_dish
				var recipe: String = service._policy.menu[dish]
				var line := Orders._line()
				line.id = int(orders.next_line); orders.next_line += 1
				line.dish = dish; line.recipe = recipe; line.item = runtime._definition.recipes[recipe].output.item
				line.qty = 1; line.price = float(source.dish_price(dish))
				var unit_id: int = runtime.request_production(recipe).id
				line.units = [{"unit":unit_id,"qty":1,"delivered":0}]
				order.lines.append(line); order.quote += line.price
				guest.request.append({"dish":dish,"recipe":recipe,"item":line.item,"qty":1})
		else:
			var guest := Orders._guest()
			guest.id = int(before.id); guest.wait = float(before.wait)
			guest.state = "leaving" if before.state=="leaving" else "queue"
			guest.queued = guest.state=="queue"
			var recipe: String = service._policy.menu[before.kind]
			recipe = Options.resolve(service._policy.customization,String(before.kind),recipe,before.get("options",[])).recipe
			guest.request = [{"dish":String(before.kind),"recipe":recipe,"item":runtime._definition.recipes[recipe].output.item,"qty":1,"options":before.get("options",[]).duplicate()}]
			if before.addon and before.kind!=source.shop.fulfillment.addon_dish:
				var dish: String = source.shop.fulfillment.addon_dish
				var extra: String = service._policy.menu[dish]
				guest.request.append({"dish":dish,"recipe":extra,"item":runtime._definition.recipes[extra].output.item,"qty":1})
			orders.guests.append(guest); service.customers.spawn(guest.id)
	for id in runtime._definition.restocks:
		var rule: Dictionary = runtime._definition.restocks[id]
		var before: Dictionary = source.stations[id]
		for item in rule.produces: _insert(runtime._definition.machines[id].output,item,int(before.stock))
		if before.phase in ["cook","done"]:
			var started: Dictionary = runtime.runner.machines.start(id,rule.consumes,rule.produces,maxf(0.0,float(before.duration)))
			if not started.error.is_empty(): _fail(started.error); return
			var run: Dictionary = runtime.runner.machines._find(started.id)
			run.phase = "processing" if before.phase=="cook" else "await_unload"
			run.remaining = maxf(0.0,float(before.remaining)); runtime._restocks._runs[id] = int(run.id)
	for before in source.workers:
		_single_job(before)
		if not error.is_empty(): return
	_sync_customers()

func _single_job(before: Dictionary) -> void:
	var worker: Dictionary = target.worker_by_id(before.id)
	if not before.chore.is_empty():
		var id: String = before.chore.get_slice(":",1)
		var rule: Dictionary = runtime._definition.restocks[id]
		var run_id: int = runtime._restocks._runs[id]
		if run_id<0:
			var started: Dictionary = runtime.runner.machines.start(id,rule.consumes,rule.produces,float(rule.seconds))
			if not started.error.is_empty(): _fail(started.error); return
			run_id = int(started.id); runtime._restocks._runs[id] = run_id
		error = runtime.runner.operate(worker.id,run_id,runtime.runner.machines.stage_port(run_id))
		if not error.is_empty(): return
		_program(worker,1 if before.phase=="work" else 0,float(before.timer))
		if before.phase=="work":
			var run: Dictionary = runtime.runner.machines._find(run_id)
			run.stage_left = maxf(0.0,float(before.timer))*target.skill(worker)
			run.stage_total = maxf(run.stage_left,float(before.get("duration",0.0))*target.skill(worker))
		return
	if int(before.order)<1 or before.steps.is_empty(): return
	var guest: Dictionary = runtime.service.orders._find(runtime.service.orders._state.guests,int(before.order))
	if guest.order<0:
		guest.claimed = int(worker.id)
		error = runtime.runner.interact(worker.id,runtime.service._policy.admission_port,runtime.service._policy.admission_seconds,"admit",guest.id)
		if error.is_empty(): _program(worker,1 if before.phase=="work" else 0,maxf(0.0,float(before.timer)))
		return
	var order: Dictionary = runtime.service.orders._find(runtime.service.orders._state.orders,int(guest.order))
	var current: Dictionary = before.steps[int(before.step)]
	if current.action=="hand":
		var entries: Array = []
		for line in order.lines:
			var unit: Dictionary = runtime._find_unit(line.units[0].unit)
			_history_node(unit,runtime._definition.recipes[unit.recipe].output.node)
			var output: Dictionary = runtime.production_output(unit.id)
			_insert(output.place,line.item,1,int(output.owner))
			entries.append({"from":String(output.place),"to":"guest:"+str(guest.id),"item":String(line.item),"count":1,"owner":int(output.owner),"allocate_owner":int(unit.id)})
		error = _import_bundle(worker,entries,float(current.seconds))
		if not error.is_empty(): return
		var task: Dictionary = runtime.runner.tasks[worker.id]
		error = stock.pickup_bundle(task.bundle)
		if not error.is_empty(): return
		runtime.runner._sync_hand(worker)
		runtime.service._deliveries.append({"order":int(order.id),"bundle":int(task.bundle),"phase":"staff","left":0.0})
		_program(worker,task.picks.size()*2+1 if before.phase=="work" else task.picks.size()*2,maxf(0.0,float(before.timer)))
		return
	var active := _single_node(order,current)
	if active.is_empty(): _fail("unmapped single work stage: "+String(current.action)); return
	var unit: Dictionary = active.unit
	var node: Dictionary = active.node
	# Completed side dishes remain real ready stock; their old holds field was
	# a display label, never an independent inventory or settlement source.
	for line in order.lines:
		if line.units[0].unit==unit.id: continue
		var other: Dictionary = runtime._find_unit(line.units[0].unit)
		var completed := false
		for index in int(before.step):
			var step: Dictionary = before.steps[index]
			if String(step.get("holds",""))==line.dish: completed = true
		if completed:
			_history_node(other,runtime._definition.recipes[other.recipe].output.node)
			var output: Dictionary = runtime.production_output(other.id)
			_insert(output.place,line.item,1,int(output.owner))
	if node.capability=="source":
		for dependency in node.dependencies:
			_history_node(unit,dependency)
			var previous: Dictionary = runtime._definition.recipes[unit.recipe].nodes[dependency]
			for item in previous.produces:
				if stock.quantity(previous.place,item,int(unit.id),true)<1: _insert(previous.place,item,int(previous.produces[item]),int(unit.id))
		var recipe: Dictionary = runtime._definition.recipes[unit.recipe]
		var destination := ""
		for next in recipe.nodes.values():
			if next.capability=="process" and node.id in next.inputs.values(): destination = runtime._definition.machines[next.machine].input; break
		if destination.is_empty(): _fail("single pickup has no next process"); return
		var item: String = node.produces.keys()[0]
		if stock.quantity(node.place,item,-1,true)<1 and item not in stock._state.places[node.place].infinite:
			return # Await the existing restock; no old finite stock was acquired yet.
		error = _import_bundle(worker,[{"from":String(node.place),"to":destination,"item":String(node.produces.keys()[0]),"count":1,"owner":-1,"allocate_owner":int(unit.id)}],float(current.seconds))
		if error.is_empty(): _program(worker,1 if before.phase=="work" else 0,maxf(0.0,float(before.timer)))
		return
	for dependency in node.dependencies: _history_node(unit,dependency)
	var definition: Dictionary = runtime._definition.machines[node.machine]
	var loading: bool = not node.produces.has(String(current.get("holds",""))) and float(definition.profile.load_seconds)>0.0
	for item in node.consumes: _insert(definition.input,item,int(node.consumes[item]),int(unit.id))
	var timing: Dictionary = Clock.evaluate(node,target)
	var started: Dictionary = runtime.runner.machines.start(node.machine,node.consumes,node.produces,float(timing.seconds),int(unit.id))
	if not started.error.is_empty(): _fail(started.error); return
	unit.running[node.id] = int(started.id)
	var run: Dictionary = runtime.runner.machines._find(started.id)
	if not loading: run.phase = "await_operate"
	error = runtime.runner.operate(worker.id,run.id,runtime.runner.machines.stage_port(run.id))
	if not error.is_empty(): return
	_program(worker,1 if before.phase=="work" else 0,maxf(0.0,float(before.timer)))
	if before.phase=="work":
		run.stage_left = maxf(0.0,float(before.timer))*target.skill(worker)
		run.stage_total = maxf(run.stage_left,float(before.get("duration",0.0))*target.skill(worker))
		if not loading: run.remaining = run.stage_left; run.duration = maxf(run.duration,run.stage_total)

func _single_node(order: Dictionary, step: Dictionary) -> Dictionary:
	for line in order.lines:
		var unit: Dictionary = runtime._find_unit(line.units[0].unit)
		var recipe: Dictionary = runtime._definition.recipes[unit.recipe]
		for node in recipe.nodes.values():
			if node.produces.has(step.get("holds","")) or (node.capability=="process" and node.machine==step.station and float(runtime._definition.machines[node.machine].profile.load_seconds)>0.0):
				if node.capability=="process" and not runtime._definition.machines[node.machine].profile.get("manual",false):
					for input in node.inputs.values():
						if not input is String: continue
						var parent: Dictionary = recipe.nodes[input]
						if parent.capability=="source" and parent.get("timing_target")==step.station: return {"unit":unit,"node":parent}
				if node.capability!="transfer": return {"unit":unit,"node":node}
	return {}

func _serve() -> void:
	var service: RefCounted = runtime.service
	var orders: Dictionary = service.orders._state
	orders.next_guest = source.serve.next_id; orders.next_order = source.serve.next_id
	for old in source.serve.guests:
		var guest := Orders._guest()
		guest.id = int(old.id); guest.order = int(old.order); guest.wait = float(old.wait)
		guest.state = "queue" if old.order<0 else ("eating" if old.state=="eating" else "waiting")
		guest.queued = guest.state=="queue"
		if int(old.seat)>=0 and old.order>=0: guest.seat = service._policy.seating.order[int(old.seat)]
		guest.meal_left = float(old.eat_left) if guest.state=="eating" else 0.0
		orders.guests.append(guest)
	for old in source.serve.orders:
		var guest: Dictionary = service.orders._find(orders.guests,int(old.guest))
		var order := Orders._order()
		order.id = int(old.id); order.guest = int(old.guest); order.paid = bool(old.paid)
		order.state = "delivered" if old.paid else "accepted"
		if old.paid and guest.state!="eating": guest.state = "served"; guest.meal_left = source.seat_seconds()
		for index in old.lines.size():
			var before: Dictionary = old.lines[index]
			var line := Orders._line()
			line.id = int(orders.next_line); orders.next_line += 1
			line.dish = String(before.dish); line.recipe = service._policy.menu[line.dish]
			line.item = runtime._definition.recipes[line.recipe].output.item
			line.qty = int(before.qty); line.price = float(source.dish_price(line.dish))
			line.delivered = int(before.delivered)
			order.quote += line.price*line.qty
			for unit in source.serve.units:
				if int(unit.order)!=old.id or int(unit.line)!=index: continue
				line.units.append({"unit":int(unit.id),"qty":1,"delivered":0})
				var current := {"id":int(unit.id),"recipe":line.recipe,"done":[],"running":{}}
				runtime._units.append(current); runtime._next_unit = maxi(runtime._next_unit,int(unit.id)+1)
				for step in unit.done: _history_node(current,"step:"+str(step))
			guest.request.append({"dish":line.dish,"recipe":line.recipe,"item":line.item,"qty":line.qty})
			order.lines.append(line)
		if order.paid: order.income = floori(order.quote)
		orders.orders.append(order)
	for guest in orders.guests:
		service.customers.spawn(guest.id)
		if guest.order>0:
			var place: String = service._guest_place(guest)
			error = runtime.runner.define_dynamic_place("guest:"+str(guest.id),runtime.runner.ports[place])
			if not error.is_empty(): return
	# Physical goods are imported once, retaining their original IDs and owners.
	for good in source.serve.goods:
		var place := _serve_place(good)
		if place.is_empty(): return
		if place.begins_with("hand:"): stock.configure(place)
		var created: Dictionary = stock._insert(place,String(good.item),1,int(good.owner))
		created.id = int(good.id)
		stock._state.next_lot = maxi(stock._state.next_lot,int(good.id)+1)
		stock._add(stock._state.created,String(good.item),1)
	for worker in source.workers:
		var job: Dictionary = source.serve.jobs.get(str(worker.id),{})
		if not job.is_empty(): _serve_job(worker,job)
		if not error.is_empty(): return
	for id in runtime._definition.restocks:
		var before: Dictionary = source.stations.get(id,{})
		if before.get("phase")=="cook":
			var rule: Dictionary = runtime._definition.restocks[id]
			var started: Dictionary = runtime.runner.machines.start(id,rule.consumes,rule.produces,float(before.duration))
			if not started.error.is_empty(): _fail(started.error); return
			var run: Dictionary = runtime.runner.machines._find(started.id)
			run.phase = "processing"; run.remaining = maxf(0.0,float(before.remaining))
			runtime._restocks._runs[id] = int(run.id)
	_reconcile_receipts()
	if not error.is_empty(): return
	_sync_customers()

func _serve_place(good: Dictionary) -> String:
	var at: String = good.at
	if at.begins_with("hand:"): return at
	if at.begins_with("seat:"):
		for guest in runtime.service.orders._state.guests:
			if guest.seat=="seat:"+source.dine_group().id+"/"+at.trim_prefix("seat:"): return "guest:"+str(guest.id)
		return _fail("old table goods have no customer")
	if runtime.runner.ports.has(at): return at
	if not runtime._definition.machines.has(at): return _fail("unmapped legacy goods place: "+at)
	var device: Dictionary = runtime._definition.machines[at]
	if good.owner<0: return device.output
	var unit: Dictionary = runtime._find_unit(int(good.owner))
	var recipe: Dictionary = runtime._definition.recipes[unit.recipe]
	for node in recipe.nodes.values():
		if node.capability=="process" and node.machine==at and node.produces.has(good.item) and node.id in unit.done: return device.output
	return device.input

func _history_node(unit: Dictionary, id: String) -> void:
	if id in unit.done: return
	var recipe: Dictionary = runtime._definition.recipes[unit.recipe]
	if not recipe.nodes.has(id): _fail("legacy recipe step has no public node: "+id); return
	var node: Dictionary = recipe.nodes[id]
	if node.capability=="source": return
	for before in node.dependencies: _history_node(unit,before)
	if node.capability=="transfer":
		var item: String = node.consumes.keys()[0]
		var parent: Dictionary = recipe.nodes[node.inputs[item]]
		var group := _historical_transfer(parent.place,node.place,item,int(node.consumes[item]),-1 if parent.capability=="source" else int(unit.id),int(unit.id),"staff:1")
		unit.running[id] = group.id
	else:
		var definition: Dictionary = runtime._definition.machines[node.machine]
		var claim: Dictionary = stock._task("operation",0,definition.input,definition.output,int(unit.id))
		claim.consumes = node.consumes.duplicate(); claim.produces = node.produces.duplicate()
		claim.count = stock._total(claim.produces)
		claim.space = maxi(0,claim.count-(stock._total(stock._finite_inputs(claim.from,claim.consumes)) if claim.from==claim.to else 0))
		claim.state = "completed"
		stock._store(claim)
		var run := Machines._run()
		run.id = int(runtime.runner.machines._state.next_run); runtime.runner.machines._state.next_run += 1
		run.machine = node.machine; run.claim = int(claim.id); run.phase = "completed"
		if runtime.runner.machines._state.definitions[node.machine].has("slot_ceiling"): run.slot = 0
		runtime.runner.machines._state.runs.append(run)
		unit.running[id] = run.id
	unit.done.append(id)

func _historical_transfer(from: String, to: String, item: String, count: int, owner: int, allocate: int, actor: String) -> Dictionary:
	var claim: Dictionary = stock._task("transfer",stock._staff_id(actor),from,to,owner)
	claim.actor = actor; claim.allocate_owner = allocate; claim.item = item; claim.count = count
	claim.capacity = count; claim.space = count; claim.state = "dropped"
	claim.minted = item in stock._state.places[from].infinite
	if not claim.minted: claim.parts = [{"lot":1,"count":count}]
	var group := {"id":int(stock._state.next_bundle),"actor":actor,"capacity":count,"claims":[]}
	stock._state.next_bundle += 1; claim.group = group.id
	stock._store(claim); group.claims.append(int(claim.id)); stock._state.bundles.append(group)
	return group

func _serve_job(worker: Dictionary, job: Dictionary) -> void:
	var current: Dictionary = target.worker_by_id(worker.id)
	if job.kind=="home": return # Idle positioning has no business claim to replay.
	if job.kind=="take":
		var guest: Dictionary = runtime.service.orders._find(runtime.service.orders._state.guests,int(job.guest))
		guest.claimed = int(worker.id)
		error = runtime.runner.interact(worker.id,runtime.service._policy.admission_port,runtime.service._policy.admission_seconds,"admit",guest.id)
		if error.is_empty(): _program(current,1 if job.stage=="work" else 0,float(worker.action_left))
		return
	if job.kind=="work":
		var unit: Dictionary = runtime._find_unit(int(job.unit))
		var node: Dictionary = runtime._definition.recipes[unit.recipe].nodes["step:"+str(job.step)]
		for dependency in node.dependencies: _history_node(unit,dependency)
		var timing: Dictionary = Clock.evaluate(node,target)
		var started: Dictionary = runtime.runner.machines.start(node.machine,node.consumes,node.produces,float(timing.seconds),unit.id)
		if not started.error.is_empty(): _fail(started.error); return
		unit.running[node.id] = int(started.id)
		var run: Dictionary = runtime.runner.machines._find(started.id)
		error = runtime.runner.operate(worker.id,run.id,runtime.runner.machines.stage_port(run.id))
		if not error.is_empty(): return
		_program(current,1 if job.stage=="work" else 0,float(worker.action_left))
		if job.stage=="work":
			run.stage_left = float(worker.action_left)*target.skill(current)
			run.stage_total = maxf(run.stage_left,float(worker.get("duration",run.duration))*target.skill(current))
			run.duration = maxf(run.duration,run.stage_total); run.remaining = run.stage_left
		return
	if job.kind not in ["carry","pass"]: _fail("unconverted legacy employee program: "+String(job.kind)); return
	var unit: Dictionary = runtime._find_unit(int(job.unit))
	var recipe: Dictionary = runtime._definition.recipes[unit.recipe]
	var from := ""
	var destination := ""
	var origin := -1
	var graph_node := ""
	if job.kind=="carry":
		destination = runtime._definition.machines[job.to].input
		for node in recipe.nodes.values():
			if node.capability!="process" or node.machine!=job.to or not node.consumes.has(job.item): continue
			var parent: Dictionary = recipe.nodes[node.inputs[job.item]]
			_history_node(unit,parent.id)
			from = parent.place; origin = -1 if parent.capability=="source" else int(unit.id)
			break
	else:
		_history_node(unit,recipe.output.node)
		var output: Dictionary = runtime.production_output(unit.id)
		from = output.place; origin = int(output.owner)
		destination = runtime.service._policy.pickup
	if from.is_empty(): _fail("old transfer has no public graph edge"); return
	var good := {}
	for row in stock._state.lots:
		if int(row.id)==int(job.good): good = row; break
	if not good.is_empty():
		good.place = from; good.owner = origin
		if job.item in stock._state.places[from].infinite: stock._state.lots.erase(good)
	error = _import_bundle(current,[{"from":from,"to":destination,"item":String(job.item),"count":1,"owner":origin,"allocate_owner":int(unit.id)}],float(source.shop.dispatch.hop_seconds))
	if not error.is_empty(): error += " from="+from+" to="+destination; return
	var task: Dictionary = runtime.runner.tasks[worker.id]
	if not graph_node.is_empty(): unit.running[graph_node] = int(task.bundle)
	var index: int = {"go_from":0,"pick":1,"go_to":2,"drop":3}.get(String(job.stage),-1)
	if index<0: _fail("unsupported old transfer phase: "+String(job.stage)); return
	if index>=2:
		error = stock.pickup_bundle(task.bundle)
		if not error.is_empty(): return
		if int(job.good)>0:
			var claim: Dictionary = stock._find(stock._state.claims,stock.bundle(task.bundle).claims[0])
			var held: Dictionary = stock._find(stock._state.lots,int(claim.held[0].lot))
			held.id = int(job.good); claim.held[0].lot = int(job.good)
			stock._state.next_lot = maxi(stock._state.next_lot,int(job.good)+1)
		runtime.runner._sync_hand(current)
	_program(current,int(index),float(worker.action_left))

func _import_bundle(worker: Dictionary, entries: Array, seconds: float) -> String:
	var result: Dictionary = stock.reserve_bundle("staff:"+str(worker.id),entries,target.carry(worker))
	if not result.error.is_empty(): return result.error
	var task: Dictionary = runtime.runner._task("bundle",worker)
	task.bundle = int(result.id); task.from = entries[0].from; task.to = entries[0].to
	task.seconds = seconds/target.skill(worker); task.drop_seconds = task.seconds
	var claims: Array = []
	for id in stock.bundle(result.id).claims:
		var claim: Dictionary = stock.claim(id)
		claims.append(claim)
		task.picks.append({"claim":int(id),"from":String(claim.from),"seconds":task.seconds})
	var context: Dictionary = runtime.runner.dispatcher.context_for_claims(stock,claims)
	if not context.error.is_empty(): return context.error
	task.scope = context.scope
	return runtime.runner._start(worker,task)

func _program(worker: Dictionary, index: int, left: float) -> void:
	var program: Dictionary = worker.action
	var step: Dictionary = program.steps[index]
	if step.kind not in ["move","transport"]:
		if Vector2(worker.pos).is_equal_approx(runtime.runner.ports[step.target]):
			Motion.request(worker,target.nav,runtime.runner.ports[step.target],runtime.runner.tasks[worker.id].profile)
			worker.walking = false
			worker.path = PackedVector2Array([worker.pos]); worker.path_index = 1
		else:
			# The old port may differ from the public port. Walk there normally;
			# machine clocks retain their saved work instead of teleporting staff.
			index -= 1
	program.index = index; program.started = false; program.status = "ready"; program.reason = ""
	Actions._enter(worker,program,Context.new(runtime.runner))
	if not worker.walking: worker.action_left = maxf(0.0,left)

func _reconcile_receipts() -> void:
	for order in runtime.service.orders._state.orders:
		for line in order.lines:
			for binding in line.units:
				if line.claims.size()>=int(line.delivered): break
				var unit: Dictionary = runtime._find_unit(binding.unit)
				var recipe: Dictionary = runtime._definition.recipes[unit.recipe]
				_history_node(unit,recipe.output.node)
				var output: Dictionary = runtime.production_output(unit.id)
				var pickup: bool = runtime.service._policy.delivery=="self_pickup"
				var actor := "customer:"+str(order.guest) if pickup else "staff:1"
				var place: String = runtime.service._policy.pickup if pickup else output.place
				var group := _historical_transfer(place,"guest:"+str(order.guest),line.item,1,int(unit.id) if pickup else int(output.owner),int(unit.id),actor)
				line.claims.append(int(group.claims[0])); binding.delivered = 1

func _sync_customers() -> void:
	var service: RefCounted = runtime.service
	error = service._sync_queue()
	if not error.is_empty(): return
	for guest in service.orders._state.guests:
		var destination: String = "queue:"+str(service.orders.queue().find(guest.id)) if guest.state=="queue" else (service._pickup_target(guest) if guest.state=="waiting" and service._policy.delivery=="self_pickup" else service._destination(guest))
		var old: Dictionary = source.movement.get("customers",{}).get("guest:"+str(guest.id),{})
		var actor: Dictionary = service.customers._find(guest.id)
		if service.waiting!=null:
			if guest.state in ["waiting","queue"]: destination = actor.target
			if old.is_empty(): old = source.movement.get("customers",{}).get("customer:"+str(guest.id),{})
		if service.dining!=null:
			if guest.state in ["waiting","queue"]: destination = actor.target
			if old.is_empty() and not guest.seat.is_empty(): old = source.movement.get("customers",{}).get("diner:"+guest.seat.get_slice("/",1),{})
		if not old.is_empty(): actor.pos = old.pos
		if guest.state=="leaving": destination = "exit"
		if guest.state=="eating" and not actor.pos.is_equal_approx(service.customers._target(service._destination(guest)).point): guest.state = "served"
		actor.target = ""
		error = service.customers.request(guest.id,destination)
		if not error.is_empty(): return
		if actor.pos.is_equal_approx(actor.motion.goal):
			actor.path = PackedVector2Array([actor.pos]); actor.path_index = 1; actor.walking = false

func _fail(message: String) -> String:
	error = message
	return ""

func _import_belts() -> void:
	for shipment in source.belt_items:
		var dish: String = shipment.item
		var unit := _unstarted_unit(dish,shipment.dst==source.RACK)
		var recipe: Dictionary = runtime._definition.recipes[unit.recipe]
		var matched := false
		for node in recipe.nodes.values():
			if node.capability!="transfer" or not node.has("transport"): continue
			var route: Dictionary = runtime._definition.transports[node.transport]
			if route.connection!=shipment.route: continue
			for dependency in node.dependencies: _history_node(unit,dependency)
			for item in node.consumes:
				var producer: Dictionary = recipe.nodes[node.inputs[item]]
				var owner := -1 if producer.capability=="source" else int(unit.id)
				_insert(producer.place,item,int(shipment.count),owner)
				var group: Dictionary = runtime._transports.start(node.transport,stock,{"from":String(producer.place),"to":String(node.place),"item":String(item),"count":int(shipment.count),"owner":owner,"allocate_owner":int(unit.id)})
				if not group.error.is_empty(): _fail(group.error); return
				unit.running[node.id] = int(group.id)
				var flight: Dictionary = runtime._transports._state.flights.back()
				flight.left = float(shipment.duration)*(1.0-float(shipment.progress))
			matched = true; break
		if not matched: _fail("old shipment has no declared public route"); return
	for id in runtime._definition.transports:
		var route: Dictionary = runtime._definition.transports[id]
		if source.belt_clock.has(route.connection): runtime._transports._state.cooldowns[id] = float(source.belt_clock[route.connection])
