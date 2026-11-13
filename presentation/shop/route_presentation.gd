extends RefCounted
## Sub-tick presentation only. The authoritative route and arrival remain owned
## by rules; prediction follows waypoints and never runs beyond one fixed tick.
const TICK_SECONDS := 0.1
var _clock := -1.0
var age := 0.0

func advance(clock: float, elapsed: float) -> void:
	if _clock < 0.0 or clock < _clock or clock-_clock > TICK_SECONDS+maxf(elapsed,0.0)+0.00001:
		age = 0.0
	else:
		age = clampf(age+maxf(elapsed,0.0)-(clock-_clock),0.0,TICK_SECONDS)
	_clock = clock

func point(row: Dictionary, speed: float) -> Vector2:
	var result: Vector2 = row.pos
	if not row.get("walking",false): return result
	var path: PackedVector2Array = row.get("path",PackedVector2Array())
	var remaining := age*maxf(speed,0.0)
	for index in range(int(row.get("path_index",0)),path.size()):
		var distance := result.distance_to(path[index])
		if remaining<=distance: return result.move_toward(path[index],remaining)
		remaining -= distance
		result = path[index]
	return result
