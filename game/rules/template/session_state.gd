extends RefCounted
## Public save protocol. Outer commands own identity, purchases, wallet and RNG;
## Runtime alone owns physical inventory, production, service and active actors.
const Runtime := preload("res://game/rules/template/runtime.gd")
const Validator := preload("res://game/rules/shop_state_validator.gd")
const Worker := preload("res://game/rules/worker_state.gd")
const Shape := preload("res://game/rules/template/inventory.gd")
const Contract := preload("res://game/rules/shop_content_contract.gd")
const OUTER := ["gold","revenue","sold","sold_by_dish","stage_index","unlocked","levels","boxes",
	"completed_at","paused","tune","hire_pool","event_ready_at","events_seen","belts","seats",
	"full_seconds","pot_busy","side_idle","_accumulator","_next_staff","_sale_carry","rng","event_rng","mods","log","pending_events"]
const PERSON := ["id","kind","name","stats","post","deployed","source","fatigue"]

static func save(owner: RefCounted) -> Dictionary:
	var legacy: Dictionary = owner._legacy_dict()
	var outer := {}
	for key in OUTER: outer[key] = legacy[key]
	outer.roster = []
	for worker in owner.roster:
		var row := {}
		for key in PERSON: row[key] = worker[key]
		if not worker.deployed: row.standby = {"pos":worker.pos,"completed":worker.completed}
		outer.roster.append(row)
	return owner._plain({"shop":owner.shop.id,"version":2,"template":Contract.describe_template(owner._runtime_template),"outer":outer,"runtime":owner.runtime.snapshot()})

static func restore(owner: RefCounted, data: Dictionary, refresh := false) -> String:
	if not Shape._shape(data,{"shop":"","version":0,"template":{},"outer":{},"runtime":{}}) or data.version!=2 or data.shop!=owner.shop.id: return "invalid public shop state version or identity"
	var template: Resource = owner._runtime_template
	if template==null: return "public state requires an explicit runtime template"
	var identity := Contract.describe_template(template)
	if data.template.get("structure")!=identity.structure: return "public template structure differs"
	if not refresh and data.template!=identity: return "public template numeric revision differs"
	var candidate: RefCounted = owner.get_script().new(owner.shop)
	candidate.runtime = null
	candidate._runtime_template = null
	candidate.event_defs = owner.event_defs.duplicate()
	var defaults: Dictionary = candidate._legacy_dict()
	var flat := defaults.duplicate(true)
	var expected := {}
	for key in OUTER: expected[key] = defaults[key]
	expected.roster = []
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
	if not data.runtime.get("clock") is float or data.runtime.clock<0.0: return "invalid public clock"
	flat.clock = data.runtime.clock
	# Old validator checks purchase metadata; transport clocks belong only to Runtime.
	for id in flat.belts: flat.belt_clock[id] = 0.0
	var error: String = Validator.new().validate(flat,defaults,owner.shop,candidate.chains,candidate.event_defs)
	if not error.is_empty(): return error
	candidate._restore_validated(flat)
	if refresh: candidate._refresh_content_values()
	error = candidate.enable_runtime(template,false)
	if not error.is_empty(): return error
	var recorded: Dictionary = data.runtime.duplicate(true)
	if refresh and data.template!=identity:
		recorded.signature = candidate.runtime._definition.signature
		recorded.runner.machines.definitions = candidate.runtime.runner.machines.snapshot().definitions
		if not recorded.service.arrivals.is_empty():
			recorded.service.arrivals.signature = candidate.runtime.service.arrivals.snapshot().signature
			if not recorded.service.arrivals.started: recorded.service.arrivals.left = candidate.runtime.service.arrivals.snapshot().left
		recorded.service.orders.policy = candidate.runtime.service.orders.snapshot().policy
	error = candidate.runtime.restore(recorded)
	if not error.is_empty(): return error
	candidate.clock = data.runtime.clock
	# Adopt validated outer facts and the same Runtime objects; rebind the one
	# owner before observers are allowed to use the live state again.
	for key in owner.STATE_KEYS: owner.set(key,candidate.get(key))
	owner.workers = candidate.workers
	owner.nav = candidate.nav
	owner.rng = candidate.rng; owner.event_rng = candidate.event_rng; owner.mods = candidate.mods
	owner.pending_events = candidate.pending_events
	owner.events.log = candidate.events.log; owner.events.clock = candidate.clock
	owner.runtime = candidate.runtime
	owner.runtime.runner.owner = owner
	owner.runtime_error = ""
	return ""
