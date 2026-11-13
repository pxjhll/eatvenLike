extends RefCounted
## One customer movement source for all service policies. Business code issues
## named targets; this component owns positions and real arrival facts only.
const Movement := preload("res://game/rules/rule_movement.gd")
const Validation := preload("res://game/rules/movement_validator.gd")
const Inventory := preload("res://game/rules/template/inventory.gd")
const Presentation := preload("res://content/characters/actor_presentation.tres")

var last_error := ""
var _nav: RuleNav
var _records: Array = []
var _extra_ports: Dictionary = {}

func _init(nav: RuleNav, extra_ports: Dictionary = {}) -> void:
	_nav = nav
	if nav == null or nav.layout == null or nav.layout.motion_version != 1 or not nav.layout.actor_areas.has("customer"):
		last_error = "customer motion requires a declared access profile"
		return
	for key in extra_ports:
		if not key is String or not key.begins_with("waiting_line:") or nav.layout.customer_points.has(key) or not extra_ports[key] is Vector2 or not extra_ports[key].is_finite(): last_error = "invalid additional customer port"; return
	_extra_ports = extra_ports.duplicate()

func spawn(id: int) -> String:
	if not last_error.is_empty(): return last_error
	if id < 1: return "invalid customer identity"
	if not _find(id).is_empty(): return ""
	var entrance := _target("entrance")
	if not String(entrance.error).is_empty(): return entrance.error
	var row := _row()
	row.id = id
	row.pos = entrance.point
	_records.append(row)
	return ""

func request(id: int, target: String) -> String:
	var row := _find(id)
	if row.is_empty(): return "unknown customer"
	var resolved := _target(target)
	if not String(resolved.error).is_empty(): return resolved.error
	if row.target == target and row.has("motion") and row.motion.goal == resolved.point: return ""
	row.target = target
	Movement.request(row, _nav, resolved.point, "customer")
	return ""

func advance(dt: float, paused := false) -> String:
	if not last_error.is_empty(): return last_error
	if not is_finite(dt) or dt < 0.0: return "invalid customer motion time"
	if paused or dt == 0.0: return ""
	for row in _records:
		if not row.has("motion"): continue
		if row.walking or row.motion.topology != _nav.topology_key():
			Movement.tick(row, _nav, float(Presentation.customer_speed) * _nav.layout.motion_units * dt)
	return ""

func ready(id: int, target: String = "") -> bool:
	var row := _find(id)
	if row.is_empty() or not row.has("motion") or (not target.is_empty() and row.target != target): return false
	return not row.walking and not row.path.is_empty() and row.path_index == row.path.size() and Vector2(row.pos).is_equal_approx(row.motion.goal)

func remove(id: int) -> String:
	var row := _find(id)
	if row.is_empty(): return ""
	if not ready(id, "exit"): return "customer has not reached the exit"
	_records.erase(row)
	return ""

func record(id: int) -> Dictionary:
	return _find(id).duplicate(true)

func snapshot() -> Dictionary:
	return {"version":1, "customers":_records.duplicate(true)}

func restore(data: Dictionary) -> String:
	if not last_error.is_empty(): return last_error
	if not Inventory._shape(data, {"version":0, "customers":[]}) or data.version != 1: return "invalid customer motion state"
	var ids := {}
	for row in data.customers:
		var error := Validation._shape(row, _row())
		if not error.is_empty(): return error
		for key in row:
			if key not in _row() and key != "motion": return "unsupported customer motion field"
		if row.id < 1 or ids.has(row.id) or not row.pos.is_finite() or row.path_index < 0 or row.path_index > row.path.size(): return "invalid customer motion identity or cursor"
		ids[row.id] = true
		for point in row.path:
			if not point.is_finite(): return "invalid customer route"
		if row.target.is_empty():
			var entrance := _target("entrance")
			if not String(entrance.error).is_empty(): return entrance.error
			if row.has("motion") or row.walking or not row.path.is_empty() or row.path_index != 0 or row.pos != entrance.point: return "unrequested customer moved from entrance"
			continue
		var target := _target(row.target)
		if not String(target.error).is_empty(): return target.error
		if not row.get("motion") is Dictionary or row.motion.get("profile", "") != "customer" or row.motion.get("goal") != target.point: return "customer motion differs from declared target or access profile"
		error = Validation._record(row, _nav)
		if not error.is_empty(): return error
	_records = data.customers.duplicate(true)
	return ""

func _find(id: int) -> Dictionary:
	for row in _records:
		if row.id == id: return row
	return {}

func _target(key: String) -> Dictionary:
	if _nav == null or _nav.layout == null: return {"error":"missing customer geometry"}
	var point: Variant
	if _extra_ports.has(key): point = _extra_ports[key]
	elif key.begins_with("queue:"):
		var suffix := key.trim_prefix("queue:")
		if not suffix.is_valid_int() or str(int(suffix)) != suffix: return {"error":"invalid customer queue port"}
		var index := int(suffix)
		if index < 0 or index >= _nav.layout.customer_queue.size(): return {"error":"missing customer queue port"}
		point = _nav.layout.customer_queue[index]
	else:
		if not _nav.layout.customer_points.has(key): return {"error":"missing customer port: " + key}
		point = _nav.layout.customer_points[key]
	if not point is Vector2 or not point.is_finite(): return {"error":"invalid customer port"}
	return {"error":"", "point":point}

static func _row() -> Dictionary:
	return {"id":0, "pos":Vector2.ZERO, "path":PackedVector2Array(), "path_index":0, "walking":false, "target":""}
