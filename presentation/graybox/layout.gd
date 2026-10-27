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
const ENTRANCE := Vector2(30, 1170)
## 后厨地面格（正方形）的边长和左上角
const CELL := 106.0
const GRID_ORIGIN := Vector2(42, 186)


static func positions(config: ShopConfig) -> Dictionary:
	var result := {"shelf": shelf_point(config)}
	# 前厅一格的显示宽度：前厅多少列就把 600 像素分成几份
	var columns := config.grid.front_rect.size.x if config.grid != null and config.grid.front_rect.size.x > 0 else 8
	var cell := 600.0 / columns
	for spot in config.front_spots:
		# 柜台横贯前厅，其余位点按格子排在前厅上半部分
		if spot.station.mode == StationDef.Mode.MANUAL:
			result[spot.id] = COUNTER
		else:
			result[spot.id] = Vector2(60 + (spot.grid_pos.x + 0.5) * cell, 840 + spot.grid_pos.y * 60)
	return result


## Where a worker stands to operate a station: just in front of it, clear of the belts.
static func work_spot(station: Vector2) -> Vector2:
	return station + Vector2(0, 40)


## Behind the counter, one spot per customer place so servers never stack.
static func serve_spot(place: int) -> Vector2:
	return Vector2(customer_spot(place).x, STAFF_LINE)


## 站在前厅位点上的员工：柜台按人数排开，其余位点站在台前
static func post_spot(station: Vector2, index: int) -> Vector2:
	if station == COUNTER:
		return Vector2(station.x - 90 + index * 120, STAFF_LINE)
	return work_spot(station)


static func front_idle_spot(index: int) -> Vector2:
	return Vector2(250 + index * 88, STAFF_LINE)


static func customer_spot(place: int) -> Vector2:
	return Vector2(160 + place * 84, CUSTOMER_LINE)


## 后厨格 cell 的屏幕矩形（size 格）
static func cell_rect(cell: Vector2i, size := Vector2i.ONE) -> Rect2:
	return Rect2(GRID_ORIGIN + Vector2(cell) * CELL, Vector2(size) * CELL)


static func cell_center(cell: Vector2i) -> Vector2:
	return GRID_ORIGIN + (Vector2(cell) + Vector2(0.5, 0.5)) * CELL


## 屏幕点落在哪一格（可能在后厨外）
static func cell_at(point: Vector2) -> Vector2i:
	var at := (point - GRID_ORIGIN) / CELL
	return Vector2i(floori(at.x), floori(at.y))


## 设备本体的屏幕矩形
static func device_rect(def: StationDef, cell: Vector2i) -> Rect2:
	return cell_rect(cell, def.footprint)


## 员工站的位置：工位格中间
static func device_post(def: StationDef, cell: Vector2i) -> Vector2:
	return cell_center(cell + def.work_cell) + Vector2(0, 30)


## 货架画在通往它的那一格正下方，紧贴传菜窗口
static func shelf_point(config: ShopConfig) -> Vector2:
	if config.grid == null:
		return SHELF
	return Vector2(cell_center(config.grid.shelf_cell).x, SHELF.y)


## 传送带的折线：从上游接口的边，经过每一格中心，到下游接口的边（到货架就一直往下进窗口）。
## 长度正好等于格数，物料的 pos 按格算就能直接用。
static func belt_points(config: ShopConfig, devices: Dictionary, belt: Dictionary) -> PackedVector2Array:
	var path: Array = belt.path
	var points := PackedVector2Array()
	var first := Vector2i(path[0][0], path[0][1])
	var from: Dictionary = devices.get(belt.from, {})
	var out_dir := Vector2.ZERO
	if not from.is_empty():
		var port := config.device_def(from.def).out_port()
		out_dir = Vector2(PortDef.direction(port.side))
	points.append(cell_center(first) - out_dir * CELL / 2.0)
	for c in path:
		points.append(cell_center(Vector2i(c[0], c[1])))
	var last := Vector2i(path[-1][0], path[-1][1])
	if belt.to == "shelf":
		points.append(cell_center(last) + Vector2(0, CELL / 2.0))
	else:
		var to: Dictionary = devices.get(belt.to, {})
		if not to.is_empty():
			var port := config.device_def(to.def).in_port_for(belt.item)
			points.append(cell_center(last) - Vector2(PortDef.direction(port.side)) * CELL / 2.0)
	return points


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
