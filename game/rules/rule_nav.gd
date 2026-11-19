class_name RuleNav
extends RefCounted
## 寻路：按 SpecLayout 选格子寻路或直线。路径缓存按起终格。

var layout: SpecLayout
var _grid: RuleGrid
var _paths := {}
var _open_key := ""
const FOOT_RADIUS := 12.0
var _active: Array[Rect2] = []
var _grown_obstacles: Array[Rect2] = []
var _obstacles_by_cell := {}
var _profile_grids := {}
var _profile_permissions := {}


func _init(layout_: SpecLayout) -> void:
	layout = layout_
	if layout.nav != "grid": return
	_grid = RuleGrid.new()
	_grid.areas.assign(layout.areas)
	set_open({})


## 哪些机器开着（跟机器一起出现的障碍才挡路）。开着的机器变了就重算格子、清路线缓存。
func set_open(unlocked: Dictionary) -> void:
	if _grid == null: return
	var active: Array[Rect2] = []
	var key := ""
	for index in layout.obstacles.size():
		var station: String = layout.obstacle_stations[index] if index < layout.obstacle_stations.size() else ""
		if station.is_empty() or unlocked.get(station, false):
			active.append(layout.obstacles[index])
			key += "%d," % index
	if key == _open_key and active == _active: return
	_open_key = key
	_paths.clear()
	_profile_grids.clear()
	_active = active
	if layout.motion_version == 1: _index_obstacles()
	var blocked := {}
	for box in active:
		var low := Vector2i((box.position / layout.cell).floor()).max(Vector2i.ZERO)
		var high := Vector2i((box.end / layout.cell).floor()).min(layout.grid_size - Vector2i.ONE)
		for y in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1):
				var cell := Vector2i(x, y)
				if box.has_point(_grid.cell_center(cell, layout.cell)): blocked[cell] = true
	_grid.blocked_cells.clear()
	_grid.blocked_cells.assign(blocked.keys())


func _index_obstacles() -> void:
	_grown_obstacles.clear()
	_obstacles_by_cell.clear()
	var radius := FOOT_RADIUS * layout.motion_units
	for box in _active:
		var grown := box.grow(radius)
		_grown_obstacles.append(grown)
		var low := Vector2i((grown.position / layout.cell).floor()).max(Vector2i.ZERO)
		var high := Vector2i((grown.end / layout.cell).floor()).min(layout.grid_size - Vector2i.ONE)
		for y in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1):
				var cell := Vector2i(x, y)
				if not _obstacles_by_cell.has(cell): _obstacles_by_cell[cell] = []
				_obstacles_by_cell[cell].append(grown)


func point(name: String) -> Vector2:
	var key: String = layout.aliases.get(name, name)
	return layout.points.get(key, Vector2.ZERO)


func post(name: String) -> Vector2:
	return layout.posts.get(name, point(name))


func has_post(name: String) -> bool:
	return layout.posts.has(name)


## 能不能站人：格子寻路的店要在可走区域里、不在障碍上，并且走得到 to；直线走的店哪里都行。
func walkable(point: Vector2, to: Vector2) -> bool:
	if not is_finite(point.x) or not is_finite(point.y): return false
	if _grid == null: return true
	var c := _grid.world_to_cell(point, layout.cell)
	if not _grid.contains_cell(c) or c in _grid.blocked_cells: return false
	return not path(point, to).is_empty()


func path(from: Vector2, to: Vector2, profile := "staff") -> PackedVector2Array:
	if layout.motion_version == 1: return _profile_path(from,to,profile)
	if _grid == null: return PackedVector2Array([from, to])
	var start := _grid.world_to_cell(from, layout.cell)
	var finish := _grid.world_to_cell(to, layout.cell)
	var key := "%s>%s" % [start, finish]
	if not _paths.has(key):
		var points := PackedVector2Array()
		for c in _grid.find_path(start, finish):
			points.append(_grid.cell_center(c, layout.cell))
		_paths[key] = points
	var route: PackedVector2Array = _paths[key].duplicate()
	if not route.is_empty():
		route[0] = from
		route[route.size() - 1] = to
	return route


func topology_key() -> String:
	return _open_key


func _allowed(cell: Vector2i, profile: String) -> bool:
	if _profile_permissions.has(profile): return _profile_permissions[profile].has(cell)
	if cell.x < 0 or cell.y < 0 or cell.x >= layout.grid_size.x or cell.y >= layout.grid_size.y: return false
	if not _grid.contains_cell(cell): return false
	for area: Rect2i in layout.actor_areas.get(profile,[]):
		if area.has_point(cell): return true
	return false


func _index_permissions(profile: String) -> void:
	var allowed := {}
	var bounds := Rect2i(Vector2i.ZERO, layout.grid_size)
	for area in layout.areas:
		for access: Rect2i in layout.actor_areas.get(profile, []):
			var shared := area.intersection(access).intersection(bounds)
			for y in range(shared.position.y, shared.end.y):
				for x in range(shared.position.x, shared.end.x):
					allowed[Vector2i(x, y)] = true
	_profile_permissions[profile] = allowed


func can_stand(at: Vector2, profile := "staff") -> bool:
	if not at.is_finite(): return false
	if layout.motion_version != 1: return walkable(at,at)
	if _grid == null or not layout.actor_areas.has(profile): return false
	var radius := FOOT_RADIUS * layout.motion_units
	if radius <= 0.0 or not is_finite(radius): return false
	var low := Vector2i(floori((at.x-radius)/layout.cell),floori((at.y-radius)/layout.cell))
	var high := Vector2i(ceili((at.x+radius)/layout.cell)-1,ceili((at.y+radius)/layout.cell)-1)
	if low.x < 0 or low.y < 0 or high.x >= layout.grid_size.x or high.y >= layout.grid_size.y: return false
	for y in range(low.y,high.y+1):
		for x in range(low.x,high.x+1):
			if not _allowed(Vector2i(x,y),profile): return false
	for grown: Rect2 in _obstacles_by_cell.get(Vector2i(at / layout.cell), []):
		if at.x >= grown.position.x and at.x <= grown.end.x and at.y >= grown.position.y and at.y <= grown.end.y: return false
	return true


## Save migration can land an actor inside a moved footprint.
func nearest_reachable(at: Vector2, goal: Vector2, profile: String) -> Vector2:
	if can_stand(at,profile) and not path(at,goal,profile).is_empty(): return at
	# Include the authored destination, which may fit between grid centers.
	var candidates: Array = [{"point":goal,"distance":goal.distance_squared_to(at)}]
	for y in layout.grid_size.y:
		for x in layout.grid_size.x:
			var point := (Vector2(x,y)+Vector2.ONE*0.5)*layout.cell
			candidates.append({"point":point,"distance":point.distance_squared_to(at)})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		if a.distance!=b.distance: return a.distance<b.distance
		if a.point.y!=b.point.y: return a.point.y<b.point.y
		return a.point.x<b.point.x)
	for row: Dictionary in candidates:
		if can_stand(row.point,profile) and not path(row.point,goal,profile).is_empty(): return row.point
	return Vector2.INF


## Slab intersection includes touching: routes conservatively keep the entire footprint clear.
func _crosses_rect(from: Vector2, to: Vector2, box: Rect2) -> bool:
	var enter := 0.0
	var leave := 1.0
	for axis in 2:
		var step := to[axis]-from[axis]
		if absf(step) < 0.000001:
			if from[axis] < box.position[axis] or from[axis] > box.end[axis]: return false
		else:
			var a := (box.position[axis]-from[axis])/step
			var b := (box.end[axis]-from[axis])/step
			enter = maxf(enter,minf(a,b))
			leave = minf(leave,maxf(a,b))
			if enter > leave: return false
	return true


func segment_clear(from: Vector2, to: Vector2, profile := "staff") -> bool:
	if not can_stand(from,profile) or not can_stand(to,profile): return false
	return _segment_body_clear(from,to,profile)


func _segment_body_clear(from: Vector2, to: Vector2, profile: String) -> bool:
	var radius := FOOT_RADIUS * layout.motion_units
	if _hits_obstacle(from, to): return false
	var low := Vector2i((from.min(to)-Vector2.ONE*radius)/layout.cell)
	var high := Vector2i((from.max(to)+Vector2.ONE*radius)/layout.cell)
	for y in range(maxi(0,low.y),mini(layout.grid_size.y-1,high.y)+1):
		for x in range(maxi(0,low.x),mini(layout.grid_size.x-1,high.x)+1):
			if not _allowed(Vector2i(x,y),profile) and _crosses_rect(from,to,Rect2(Vector2(x,y)*layout.cell,Vector2.ONE*layout.cell).grow(radius)):
				return false
	return true


func _hits_obstacle(from: Vector2, to: Vector2) -> bool:
	var low := Vector2i(from.min(to) / layout.cell)
	var high := Vector2i(from.max(to) / layout.cell)
	var span := high - low + Vector2i.ONE
	if span.x * span.y >= _grown_obstacles.size():
		for box in _grown_obstacles:
			if _crosses_rect(from, to, box): return true
		return false
	for y in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			for box: Rect2 in _obstacles_by_cell.get(Vector2i(x, y), []):
				if _crosses_rect(from, to, box): return true
	return false


func _cell_step_clear(from: Vector2, to: Vector2, profile: String) -> bool:
	# At adjacent cell centers, the checked endpoint footprints already cover
	# the cells swept on this axis. The inclusive upper edge can touch one
	# additional cell when the footprint lands exactly on a grid boundary.
	var upper := (from.max(to) + Vector2.ONE * FOOT_RADIUS * layout.motion_units) / layout.cell
	if is_equal_approx(upper.x, roundf(upper.x)) or is_equal_approx(upper.y, roundf(upper.y)):
		return _segment_body_clear(from, to, profile)
	return not _hits_obstacle(from, to)


func _profile_path(from: Vector2, to: Vector2, profile: String) -> PackedVector2Array:
	if not can_stand(from,profile) or not can_stand(to,profile): return PackedVector2Array()
	if _segment_body_clear(from,to,profile): return PackedVector2Array([from,to])
	if not _profile_grids.has(profile):
		if not _profile_permissions.has(profile): _index_permissions(profile)
		var grid := RuleGrid.new()
		var can_occupy := func(cell: Vector2i) -> bool: return can_stand(grid.cell_center(cell, layout.cell), profile)
		grid.prepare_profile(layout.grid_size, can_occupy)
		_profile_grids[profile] = grid
	var grid: RuleGrid = _profile_grids[profile]
	var start := grid.world_to_cell(from,layout.cell)
	var finish := grid.world_to_cell(to,layout.cell)
	var key := "%s:%s>%s" % [profile,start,finish]
	if not _paths.has(key):
		var middle := PackedVector2Array()
		# The profile grid already checked the footprint at each cell center.
		var can_step := func(a: Vector2i, b: Vector2i) -> bool: return _cell_step_clear(grid.cell_center(a, layout.cell), grid.cell_center(b, layout.cell), profile)
		for cell in grid.find_path(start,finish,can_step): middle.append(grid.cell_center(cell,layout.cell))
		_paths[key] = middle
	var middle: PackedVector2Array = _paths[key]
	if middle.is_empty(): return PackedVector2Array()
	# Only the links to the exact endpoints are new to the cached route.
	if from != middle[0] and not _segment_body_clear(from, middle[0], profile): return PackedVector2Array()
	if middle[-1] != to and not _segment_body_clear(middle[-1], to, profile): return PackedVector2Array()
	var route := PackedVector2Array([from])
	for point in middle:
		if point != route[-1]: route.append(point)
	if route[-1] != to: route.append(to)
	if route.size() == 1: route.append(to)
	return route


static func length(points: PackedVector2Array) -> float:
	var total := 0.0
	for index in range(1, points.size()): total += points[index - 1].distance_to(points[index])
	return total
