extends RefCounted
## Authoritative customer locations for the shared movement protocol. Business
## modes own orders/stock/timers; this module owns only goals, routes and poses.
const Ports := preload("res://game/rules/customer_ports.gd")
const LegacyIntents := preload("res://game/rules/legacy/customer_intents.gd")
const Movement := preload("res://game/rules/rule_movement.gd")
const Presentation := preload("res://content/characters/actor_presentation.tres")

static func _rows(rules: ShopRules) -> Dictionary:
	if rules.movement.is_empty(): rules.movement = {"version":1,"customers":{}}
	return rules.movement.customers

static func port(rules: ShopRules, name: String) -> Vector2:
	return Ports.port(rules,name)

static func queue_point(rules: ShopRules, slot: int) -> Vector2:
	return Ports.queue_point(rules,slot)

static func seat_target(rules: ShopRules, seat: int, purpose := "dine") -> String:
	return Ports.seat_target(rules,seat,purpose)

static func _request(rules: ShopRules, active: Dictionary, key: String, id: int, target: String, goal: Vector2, data: Dictionary, seated := false, initial: Variant = null) -> void:
	var rows := _rows(rules)
	active[key] = true
	if not rows.has(key):
		var start: Vector2 = port(rules,"entrance") if initial==null else initial
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
	var error := sync_records(rules,LegacyIntents.records(rules,migrate))
	if not error.is_empty(): push_error(error)

static func sync_records(rules: ShopRules, intents: Array) -> String:
	if not rules.movement_enabled(): return ""
	var active := {}
	for intent in intents:
		if not intent is Dictionary or not intent.get("key") is String or intent.key.is_empty() or active.has(intent.key) or not intent.get("id") is int or intent.id<1 or not intent.get("target") is String or intent.target.is_empty() or not intent.get("goal") is Vector2 or not intent.goal.is_finite() or not intent.get("data") is Dictionary or not intent.data.get("state") is String or not intent.get("seated") is bool: return "invalid customer motion intent"
		if intent.has("start") and (not intent.start is Vector2 or not intent.start.is_finite()): return "invalid migrated customer origin"
		active[intent.key] = true
	active.clear()
	for intent in intents:
		_request(rules,active,intent.key,intent.id,intent.target,intent.goal,intent.data,intent.seated,intent.get("start"))
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

	return ""

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
