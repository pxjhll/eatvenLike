class_name RuleNav
extends RefCounted
## 寻路：按 SpecLayout 选格子寻路或直线。路径缓存按起终格。

var layout: SpecLayout
var _grid: RuleGrid
var _paths := {}
var _open_key := ""


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


func path(from: Vector2, to: Vector2) -> PackedVector2Array:
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


static func length(points: PackedVector2Array) -> float:
	var total := 0.0
	for index in range(1, points.size()): total += points[index - 1].distance_to(points[index])
	return total
