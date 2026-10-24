extends RefCounted
## Display coordinates only. The simulation's grid and belt lengths are unchanged.

const SHELF := Vector2(486, 738)


static func positions(config: ShopConfig) -> Dictionary:
	var result := {"shelf": SHELF}
	for slot in config.slots:
		if slot.station.owner == StationDef.OwnerSystem.FRONT_HALL:
			result[slot.id] = Vector2(486, 940)
		else:
			result[slot.id] = Vector2(126 + slot.grid_pos.x * 90, 370 + slot.grid_pos.y * 165)
	return result


static func route(connection: ConnectionDef, points: Dictionary) -> PackedVector2Array:
	var a: Vector2 = points.get(connection.from_slot, Vector2(120, 350)) + Vector2(0, -20)
	var b: Vector2 = points.get(connection.to_slot, SHELF) + Vector2(0, -20)
	if connection.to_slot == "shelf":
		var lane := 570.0 if a.y > 400 else 636.0
		return PackedVector2Array([a, Vector2(lane, a.y), Vector2(lane, b.y), b])
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
