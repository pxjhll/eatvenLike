extends RefCounted
## Public save protocol. Outer commands own identity, purchases, wallet and RNG;
## Runtime alone owns physical inventory, production, service and active actors.
const Runtime := preload("res://game/rules/template/runtime.gd")
const Validator := preload("res://game/rules/shop_state_validator.gd")
const Worker := preload("res://game/rules/worker_state.gd")
const Shape := preload("res://game/rules/template/inventory.gd")
const Contract := preload("res://game/rules/shop_content_contract.gd")
const Runner := preload("res://game/rules/template/capability_runner.gd")
const Compiler := preload("res://game/rules/template/compiler.gd")
const TemplateProjection := preload("res://game/rules/template/content_projection.gd")
const OUTER := ["gold","revenue","sold","sold_by_dish","stage_index","unlocked","levels","boxes",
	"completed_at","paused","tune","hire_pool","event_ready_at","events_seen","belts","seats",
	"full_seconds","pot_busy","side_idle","_accumulator","_next_staff","_sale_carry","rng","event_rng","mods","log","pending_events"]
const PERSON := ["id","kind","name","stats","post","deployed","source","fatigue"]

## Reuse only the authored template and its resolved ports. The restore still
## rebuilds and validates current gameplay against the resulting definition.
static func prepare_save(template: SpecShopTemplate, layout: SpecLayout, previous: Dictionary) -> Dictionary:
	var ports := Compiler.ports_from_layout(layout)
	var inputs: Array = [ports]
	for field in TemplateProjection.FIELDS: inputs.append(template.get(field))
	# Binary values retain exact types and ordering, unlike JSON or Dictionary equality.
	var source := var_to_bytes(inputs)
	if not previous.is_empty() and source == previous.source: return previous
	return {"source":source, "identity":Contract.describe_template(template), "compiled":Compiler.compile(template, ports)}

static func save(owner: RefCounted, compact_history := false, identity: Dictionary = {}) -> Dictionary:
	var outer := {}
	for key in OUTER:
		match key:
			"rng": outer[key] = [owner.rng.seed, owner.rng.state]
			"event_rng": outer[key] = [owner.event_rng.seed, owner.event_rng.state]
			"mods": outer[key] = owner.mods.entries
			"log": outer[key] = owner.events.log
			"pending_events": outer[key] = owner.pending_events.map(func(event: SpecEvent) -> String: return event.id)
			_: outer[key] = owner.get(key)
	outer.fortunes = owner.lucky.snapshot()
	outer.roster = []
	for worker in owner.roster:
		var row := {}
		for key in PERSON: row[key] = worker[key]
		if not worker.deployed: row.standby = {"pos":worker.pos,"completed":worker.completed}
		outer.roster.append(row)
	if identity.is_empty(): identity = Contract.describe_template(owner._runtime_template)
	return owner._plain({"shop":owner.shop.id,"version":2,"template":identity,"outer":outer,"runtime":owner.runtime.snapshot(compact_history)})

static func restore(owner: RefCounted, data: Dictionary, refresh := false, prepared: Dictionary = {}) -> String:
	if not Shape._shape(data,{"shop":"","version":0,"template":{},"outer":{},"runtime":{}}) or data.version!=2 or data.shop!=owner.shop.id: return "invalid public shop state version or identity"
	var template: Resource = owner._runtime_template
	if template==null: return "public state requires an explicit runtime template"
	var identity: Dictionary = prepared.identity if not prepared.is_empty() else Contract.describe_template(template)
	var refresh_layout := false
	var refresh_staff_tasks := false
	if data.template.get("structure")!=identity.structure:
		var previous: Dictionary = owner.shop.previous_progression
		if not refresh or identity.structure!=previous.get("current_structure"):
			return "public template structure differs"
		var source: Dictionary = previous if data.template.get("structure")==previous.get("template_structure") else previous.get("other_templates",{}).get(data.template.get("structure"),{})
		if source.is_empty(): return "public template structure differs"
		var converted := adopt_progression(owner.shop,data.outer,source)
		if converted.is_empty(): return "previous purchase stage is invalid"
		data = data.duplicate()
		data.outer = converted
		refresh_layout = previous.get("refresh_layout",false) == true
		refresh_staff_tasks = previous.get("refresh_staff_tasks",false) == true
	if not refresh and data.template!=identity: return "public template numeric revision differs"
	var script: Script = owner.get_script()
	# The candidate gets its runtime after the saved purchase state is restored.
	var candidate: RefCounted = script.new(owner.shop,-1,false) if script == load("res://game/rules/shop_rules.gd") else script.new(owner.shop)
	candidate.runtime = null
	candidate._runtime_template = null
	candidate.event_defs = owner.event_defs.duplicate()
	var defaults: Dictionary = candidate._legacy_dict()
	var flat := defaults.duplicate(true)
	var expected := {}
	for key in OUTER: expected[key] = defaults[key]
	expected.roster = []
	if data.outer.has("fortunes"): expected.fortunes = {}
	if not Shape._shape(data.outer,expected): return "invalid outer state shape"
	for key in OUTER: flat[key] = data.outer[key]
	flat.roster = []; flat.workers = []
	for row in data.outer.roster:
		var pattern := {"id":0,"kind":"","name":"","stats":{},"post":"","deployed":false,"source":"","fatigue":0.0}
		if row is Dictionary and not row.get("deployed",true): pattern.standby = {"pos":Vector2.ZERO,"completed":0}
		if not Shape._shape(row,pattern): return "invalid outer employee metadata"
		var worker := Worker.create(row.id,row.kind,row.name,row.stats,candidate.nav.point(owner.shop.layout.spawn_point))
		for key in PERSON: worker[key] = row[key]
		if row.deployed: flat.workers.append(row.id)
		else:
			if not Shape._shape(row.standby,{"pos":Vector2.ZERO,"completed":0}) or not row.standby.pos.is_finite() or row.standby.completed<0: return "invalid standby employee"
			worker.pos = row.standby.pos; worker.completed = row.standby.completed
		flat.roster.append(worker)
	# Runner actors already own active iteration order. Recall/redeploy can
	# differ from roster order; preserve it without storing a second list.
	var runner_data: Variant = data.runtime.get("runner")
	if not runner_data is Dictionary: return "invalid active employee runtime"
	var actors: Variant = runner_data.get("actors")
	if not actors is Array: return "invalid active employee order"
	var deployed: Array = flat.workers.duplicate()
	flat.workers = []
	for actor in actors:
		if not actor is Dictionary or not actor.get("id") is int or actor.id not in deployed or actor.id in flat.workers: return "invalid active employee order"
		flat.workers.append(int(actor.id))
	if flat.workers.size()!=deployed.size(): return "active employees differ from roster"
	if not data.runtime.get("clock") is float or data.runtime.clock<0.0: return "invalid public clock"
	flat.clock = data.runtime.clock
	# Old validator checks purchase metadata; transport clocks belong only to Runtime.
	for id in flat.belts: flat.belt_clock[id] = 0.0
	var error: String = Validator.new().validate(flat,defaults,owner.shop,candidate.chains,candidate.event_defs)
	if not error.is_empty(): return error
	candidate._restore_validated(flat)
	if data.outer.has("fortunes") and not candidate.lucky.restore(data.outer.fortunes): return "invalid fortune box"
	candidate.lucky.sync(flat.clock, flat.sold)
	if refresh: candidate._refresh_content_values()
	error = candidate.enable_runtime(template, false, prepared.get("compiled", {}))
	if not error.is_empty(): return error
	var recorded: Dictionary = data.runtime.duplicate(true)
	if refresh and data.template!=identity:
		recorded.signature = candidate.runtime._definition.signature
		recorded.runner.machines.definitions = candidate.runtime.runner.machines.snapshot().definitions
		if not recorded.service.arrivals.is_empty():
			recorded.service.arrivals.signature = candidate.runtime.service.arrivals.snapshot().signature
			if not recorded.service.arrivals.started: recorded.service.arrivals.left = candidate.runtime.service.arrivals.snapshot().left
		recorded.service.orders.policy = candidate.runtime.service.orders.snapshot().policy
		if candidate.runtime.service._policy.has("previous_pickup") and not recorded.service.has("pickup_before"):
			recorded.service.pickup_before = recorded.service.orders.next_order
	var refresh_retained_inputs: bool = refresh and data.template!=identity and candidate.runtime.uses_retained_inputs
	if refresh_staff_tasks or refresh_retained_inputs:
		error = _adopt_staff_tasks(candidate.runtime,recorded,refresh_staff_tasks)
		if not error.is_empty(): return error
	error = candidate.runtime.restore(recorded,refresh and data.template!=identity,refresh_layout)
	if not error.is_empty(): return error
	candidate.clock = data.runtime.clock
	if refresh:
		candidate._restore_material_grants()
		# Earlier shops allowed a paid kitchen hire before any kitchen work existed.
		if candidate._front_expanded() and candidate.kitchen_slots() == 0:
			for worker in candidate.workers.duplicate():
				if worker.post == candidate.counter_id: continue
				if not candidate.place_worker(worker.id, candidate.counter_id).is_empty():
					candidate.recall_worker(worker.id)
	# Adopt validated outer facts and the same Runtime objects; rebind the one
	# owner before observers are allowed to use the live state again.
	for key in owner.STATE_KEYS: owner.set(key,candidate.get(key))
	owner.workers = candidate.workers
	owner.nav = candidate.nav
	owner.rng = candidate.rng; owner.event_rng = candidate.event_rng; owner.mods = candidate.mods
	owner.pending_events = candidate.pending_events
	owner.events.log = candidate.events.log; owner.events.clock = candidate.clock
	owner._sales.lucky = candidate.lucky
	owner.runtime = candidate.runtime
	owner.runtime.runner.owner = owner
	owner.runtime_error = ""
	return ""

## Release obsolete work through the inventory ledger before validating the
## saved session against the new permissions and automatic admission policy.
static func _adopt_staff_tasks(runtime: RefCounted, recorded: Dictionary, refresh_permissions: bool) -> String:
	var data: Dictionary = recorded.runner
	var stock := Shape.new()
	var error := stock.restore(data.inventory)
	if not error.is_empty(): return error
	var admissions := {}
	var released := {}
	var kept := []
	var automatic: bool = refresh_permissions and runtime.service!=null and runtime.service._policy.admission=="automatic"
	var recipe_by_owner := {}
	if runtime.uses_retained_inputs:
		if not recorded.get("units") is Array: return "invalid production unit shape"
		for unit in recorded.units:
			if unit is Dictionary and unit.get("id") is int and unit.get("recipe") is String:
				recipe_by_owner[unit.id] = runtime._definition.recipes.get(unit.recipe,{})
	for task in data.tasks:
		var worker: Dictionary = runtime.runner.owner.worker_by_id(task.worker)
		if worker.is_empty(): return "obsolete task references an unknown employee"
		if automatic and task.kind=="interact":
			admissions[task.subject] = task.worker
		elif task.kind in ["transfer","bundle"] and (
				_replaced_by_retained_input(runtime,stock,task,recipe_by_owner) or
				(refresh_permissions and not runtime.runner.dispatcher.allowed_task(worker,task,runtime.runner.machines,false))):
			error = stock.cancel_bundle(task.bundle) if task.kind=="bundle" else stock.cancel(task.claim)
			if not error.is_empty(): return error
		else:
			kept.append(task)
			continue
		released[task.worker] = true
	if automatic:
		for event in data.interactions:
			admissions[event.subject] = event.worker
			released[event.worker] = true
		data.interactions.clear()
	if not admissions.is_empty():
		for guest in recorded.service.orders.guests:
			if not admissions.has(guest.id): continue
			if guest.state!="queue" or guest.claimed!=admissions[guest.id]: return "obsolete admission differs from the queued customer"
			guest.claimed = -1
			admissions.erase(guest.id)
	if not admissions.is_empty(): return "obsolete admission references an unknown customer"
	for actor in data.actors:
		if not released.has(actor.id) or kept.any(func(task: Dictionary) -> bool: return task.worker==actor.id): continue
		Runner._clear_actor(actor)
		actor.carry_item = ""
		actor.carry_count = 0
	data.tasks = kept
	data.inventory = stock.snapshot()
	recorded.dispatch.scopes = recorded.dispatch.scopes.filter(func(lease: Dictionary) -> bool: return not released.has(lease.worker))
	return ""


static func _replaced_by_retained_input(runtime: RefCounted, stock: RefCounted, task: Dictionary, recipes: Dictionary) -> bool:
	if recipes.is_empty(): return false
	var claims: Array = stock.bundle(task.bundle).get("claims",[]) if task.kind=="bundle" else [task.claim]
	for id in claims:
		var claim: Dictionary = stock.claim(id)
		var recipe: Dictionary = recipes.get(claim.get("allocate_owner"),{})
		if not recipe.has("machine_reservation"): continue
		var reservation: Dictionary = recipe.machine_reservation
		if claim.item not in recipe.nodes[reservation.last].get("retained_inputs",[]): continue
		var machine: Dictionary = runtime._definition.machines[reservation.machine]
		if claim.from==machine.output and claim.to==machine.input: return true
	return false


## Stage-only migration keeps production, order receipts and actor references intact.
static func adopt_progression(shop: SpecShop, saved: Dictionary, source: Dictionary = {}) -> Dictionary:
	var migration := shop.previous_progression if source.is_empty() else source
	var indices: Variant = migration.get("stage_indices")
	var previous_open: Variant = migration.get("opening_station")
	var stage: Variant = saved.get("stage_index")
	var unlocked: Variant = saved.get("unlocked")
	if not indices is PackedInt32Array or not previous_open is String or not stage is int or not unlocked is Dictionary: return {}
	if stage<0 or stage>=indices.size() or indices[stage]<0 or indices[stage]>=shop.stages.size(): return {}
	var was_open: Variant = unlocked.get(previous_open)
	if not was_open is bool or (not was_open and stage!=0): return {}
	var result := saved.duplicate()
	result.unlocked = unlocked.duplicate()
	for station in shop.stations:
		if station.starts_unlocked: result.unlocked[station.id] = true
	result.unlocked[shop.goals.opening_station] = was_open
	result.stage_index = indices[stage] if was_open else 0
	if was_open and shop.previous_progression.get("grant_stage_stations",false)==true:
		for index in result.stage_index+1:
			for id in shop.stages[index].stations:
				result.unlocked[id] = true
				for station in shop.stations:
					if station.companion_of==id: result.unlocked[station.id] = true
	if not was_open and result.get("gold") is float:
		result.gold = maxf(result.gold,float(shop.start_gold))
	if result.get("levels") is Dictionary and result.get("gold") is float:
		result.levels = result.levels.duplicate()
		for id in shop.previous_progression.get("retired_upgrade_costs",{}):
			var costs: PackedInt32Array = shop.previous_progression.retired_upgrade_costs[id]
			var level: Variant = result.levels.get(id,1)
			if not level is int or level<1 or level>costs.size()+1: return {}
			for index in level-1: result.gold += costs[index]
			result.levels.erase(id)
	return result
