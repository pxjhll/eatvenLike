extends RefCounted
## Caller-owned movement records. No business transitions, scene nodes or wall clock.

static func assign(record: Dictionary, route: PackedVector2Array) -> void:
	record.path = route
	record.path_index = 1 if route.size() > 1 else 0

static func advance(record: Dictionary, distance: float) -> bool:
	if not is_finite(distance) or distance < 0.0 or record.path.is_empty(): return false
	while distance > 0 and record.path_index < record.path.size():
		var target: Vector2 = record.path[record.path_index]
		var gap: float = record.pos.distance_to(target)
		if gap <= distance + 0.00001:
			record.pos = target
			distance -= gap
			record.path_index += 1
		else:
			record.pos = record.pos.move_toward(target, distance)
			distance = 0
	if record.path_index < record.path.size(): return false
	record.walking = false
	return true

static func request(record: Dictionary, nav: RuleNav, goal: Vector2, profile: String) -> void:
	record.motion = {"version":1,"goal":goal,"profile":profile,"topology":nav.topology_key()}
	assign(record,nav.path(record.pos,goal,profile))
	record.walking = true

static func tick(record: Dictionary, nav: RuleNav, distance: float) -> bool:
	if not record.has("motion"): return advance(record,distance)
	var motion: Dictionary = record.motion
	if motion.topology != nav.topology_key() or record.path.is_empty():
		assign(record,nav.path(record.pos,motion.goal,motion.profile))
		motion.topology = nav.topology_key()
		record.walking = true
	return advance(record,distance)
