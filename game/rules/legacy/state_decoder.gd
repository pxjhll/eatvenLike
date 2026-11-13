extends RefCounted
## Read-only historical protocol decoder. It never advances a legacy business
## clock or restores an executable mode context; adoption builds public tasks.
const Validator := preload("res://game/rules/shop_state_validator.gd")
const Adoption := preload("res://game/rules/movement_adoption.gd")
const Movement := preload("res://game/rules/customer_movement.gd")
const Intents := preload("res://game/rules/legacy/customer_intents.gd")

static func restore(owner: RefCounted, recorded: Dictionary, refresh: bool) -> String:
	var candidate: RefCounted = owner.get_script().new(owner.shop)
	candidate.event_defs = owner.event_defs.duplicate()
	var data := recorded.duplicate(true)
	if not data.has("serve"): data.serve = {"guests":[],"orders":[],"units":[],"goods":[],"jobs":{},"next_id":1,"served":0,"orders_done":0,"items_sold":0}
	var rebuild: bool = candidate.movement_enabled() and not data.has("movement")
	if rebuild: data.movement = {"version":1,"customers":{}}
	if refresh:
		for id in candidate.stations:
			var row: Variant = data.get("stations",{}).get(id)
			if not row is Dictionary: continue
			for field in ["input","output","reserved_out"]:
				if not row.get(field) is Dictionary: continue
				for item in candidate.stations[id][field]:
					if not row[field].has(item): row[field][item] = candidate.stations[id][field][item]
	var error: String = Validator.new().validate(data,candidate._legacy_dict(),owner.shop,candidate.chains,candidate.event_defs)
	if not error.is_empty(): return error
	candidate._restore_validated(data)
	if candidate.movement_enabled(): candidate.movement = data.movement.duplicate(true)
	if rebuild:
		error = Adoption.workers(candidate)
		if not error.is_empty(): return error
		error = Movement.sync_records(candidate,Intents.records(candidate,true))
		if not error.is_empty(): return error
	if refresh: candidate._refresh_content_values()
	for key in owner.STATE_KEYS: owner.set(key,candidate.get(key))
	owner.workers = candidate.workers; owner.movement = candidate.movement
	owner.nav = candidate.nav; owner.rng = candidate.rng; owner.event_rng = candidate.event_rng; owner.mods = candidate.mods
	owner.pending_events = candidate.pending_events
	owner.events.log = candidate.events.log; owner.events.clock = candidate.clock
	return ""
