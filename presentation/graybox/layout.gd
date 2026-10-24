extends RefCounted
## Display coordinates only. The simulation's grid and belt lengths are unchanged.

## Machines share the character scale so a worker reads as tall as the station they operate.
const MACHINE_SCALE := 0.6
const RACK_SCALE := 0.75
const MACHINE_EDGE := 40.0
const CHAR_SCALE := 0.62
const KITCHEN := Rect2(40, 118, 640, 662)
const FRONT := Rect2(40, 810, 640, 380)
const SHELF := Vector2(560, 736)
const WINDOW := Vector2(560, 812)
const COUNTER := Vector2(372, 980)
const COUNTER_WIDTH := 520.0
const STAFF_LINE := 948.0
const CUSTOMER_LINE := 1102.0
const KITCHEN_HOME := Vector2(250, 690)
const ENTRANCE := Vector2(30, 1170)


static func positions(config: ShopConfig) -> Dictionary:
	var result := {"shelf": SHELF}
	for slot in config.slots:
		if slot.station.owner == StationDef.OwnerSystem.FRONT_HALL:
			result[slot.id] = COUNTER
		else:
			result[slot.id] = Vector2(120 + slot.grid_pos.x * 115, 320 + slot.grid_pos.y * 220)
	return result


## Where a worker stands to operate a station: just in front of it, clear of the belts.
static func work_spot(station: Vector2) -> Vector2:
	return station + Vector2(0, 40)


## Behind the counter, one spot per customer place so servers never stack.
static func serve_spot(place: int) -> Vector2:
	return Vector2(customer_spot(place).x, STAFF_LINE)


static func front_idle_spot(index: int) -> Vector2:
	return Vector2(250 + index * 88, STAFF_LINE)


static func customer_spot(place: int) -> Vector2:
	return Vector2(160 + place * 84, CUSTOMER_LINE)


static func route(connection: ConnectionDef, points: Dictionary) -> PackedVector2Array:
	# Belts stop at machine edges: items vanish into a machine instead of sliding underneath it.
	var a: Vector2 = points.get(connection.from_slot, Vector2(120, 330)) + Vector2(MACHINE_EDGE, -24)
	var b: Vector2 = points.get(connection.to_slot, SHELF) + Vector2(-MACHINE_EDGE, -24)
	if connection.to_slot == "shelf":
		# Each producer gets its own lane down the right wall, so items never pass behind a machine.
		var top := a.y < 420
		var lane := 668.0 if top else 638.0
		var drop := SHELF.y - (52.0 if top else 66.0)
		return PackedVector2Array([a, Vector2(lane, a.y), Vector2(lane, drop), Vector2(SHELF.x + 50, drop)])
	if absf(a.y - b.y) > 1.0:
		var turn := (a.x + b.x) / 2.0
		return PackedVector2Array([a, Vector2(turn, a.y), Vector2(turn, b.y), b])
	return PackedVector2Array([a, b])


static func along(points: PackedVector2Array, fraction: float) -> Vector2:
	var length := 0.0
	for i in points.size() - 1:
		length += points[i].distance_to(points[i + 1])
	var left := clampf(fraction, 0.0, 1.0) * length
	for i in points.size() - 1:
		var segment := points[i].distance_to(points[i + 1])
		if left <= segment:
			return points[i].lerp(points[i + 1], left / maxf(segment, 0.001))
		left -= segment
	return points[-1]


static func distance_to_route(points: PackedVector2Array, at: Vector2) -> float:
	var best := INF
	for i in points.size() - 1:
		var closest := Geometry2D.get_closest_point_to_segment(at, points[i], points[i + 1])
		best = minf(best, closest.distance_to(at))
	return best
