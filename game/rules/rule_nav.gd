class_name RuleNav
extends RefCounted
## 寻路：按 SpecLayout 选格子寻路或直线。路径缓存按起终格。

var layout: SpecLayout
var _grid: RuleGrid
var _paths := {}
var _open_key := ""
const FOOT_RADIUS := 12.0
var _active: Array[Rect2] = []
var _profile_grids := {}


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
	if key == _open_key and not _grid.blocked_cells.is_empty(): return
	_open_key = key
	_paths.clear()
	_profile_grids.clear()
	_active = active
	_grid.blocked_cells.clear()
	for y in layout.grid_size.y:
		for x in layout.grid_size.x:
			var c := Vector2i(x, y)
			var center := _grid.cell_center(c, layout.cell)
			for box in active:
				if box.has_point(center):
					_grid.blocked_cells.append(c)
					break


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
	if cell.x < 0 or cell.y < 0 or cell.x >= layout.grid_size.x or cell.y >= layout.grid_size.y: return false
	if not _grid.contains_cell(cell): return false
	for area: Rect2i in layout.actor_areas.get(profile,[]):
		if area.has_point(cell): return true
	return false


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
	for box in _active:
		var grown := box.grow(radius)
		if at.x >= grown.position.x and at.x <= grown.end.x and at.y >= grown.position.y and at.y <= grown.end.y: return false
	return true


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
	var radius := FOOT_RADIUS * layout.motion_units
	for box in _active:
		if _crosses_rect(from,to,box.grow(radius)): return false
	var low := Vector2i((from.min(to)-Vector2.ONE*radius)/layout.cell)
	var high := Vector2i((from.max(to)+Vector2.ONE*radius)/layout.cell)
	for y in range(maxi(0,low.y),mini(layout.grid_size.y-1,high.y)+1):
		for x in range(maxi(0,low.x),mini(layout.grid_size.x-1,high.x)+1):
			if not _allowed(Vector2i(x,y),profile) and _crosses_rect(from,to,Rect2(Vector2(x,y)*layout.cell,Vector2.ONE*layout.cell).grow(radius)):
				return false
	return true


func _profile_path(from: Vector2, to: Vector2, profile: String) -> PackedVector2Array:
	if not can_stand(from,profile) or not can_stand(to,profile): return PackedVector2Array()
	if segment_clear(from,to,profile): return PackedVector2Array([from,to])
	if not _profile_grids.has(profile):
		var grid := RuleGrid.new()
		grid.areas.assign(layout.areas)
		for y in layout.grid_size.y:
			for x in layout.grid_size.x:
				var cell := Vector2i(x,y)
				if not can_stand(grid.cell_center(cell,layout.cell),profile): grid.blocked_cells.append(cell)
		_profile_grids[profile] = grid
	var grid: RuleGrid = _profile_grids[profile]
	var start := grid.world_to_cell(from,layout.cell)
	var finish := grid.world_to_cell(to,layout.cell)
	var key := "%s:%s>%s" % [profile,start,finish]
	if not _paths.has(key):
		var middle := PackedVector2Array()
		var can_step := func(a: Vector2i,b: Vector2i) -> bool: return segment_clear(grid.cell_center(a,layout.cell),grid.cell_center(b,layout.cell),profile)
		for cell in grid.find_path(start,finish,can_step): middle.append(grid.cell_center(cell,layout.cell))
		_paths[key] = middle
	var middle: PackedVector2Array = _paths[key]
	if middle.is_empty(): return PackedVector2Array()
	var route := PackedVector2Array([from])
	for point in middle:
		if point != route[-1]: route.append(point)
	if route[-1] != to: route.append(to)
	if route.size() == 1: route.append(to)
	for i in range(1,route.size()):
		if not segment_clear(route[i-1],route[i],profile): return PackedVector2Array()
	return route


static func length(points: PackedVector2Array) -> float:
	var total := 0.0
	for index in range(1, points.size()): total += points[index - 1].distance_to(points[index])
	return total
