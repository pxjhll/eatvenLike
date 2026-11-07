class_name RuleNav
extends RefCounted
## 寻路：按 SpecLayout 选格子寻路或直线。路径缓存按起终格。

var layout: SpecLayout
var _grid: ShopGridDef
var _paths := {}


func _init(layout_: SpecLayout) -> void:
	layout = layout_
	if layout.nav != "grid": return
	_grid = ShopGridDef.new()
	if layout.areas.size() > 0: _grid.kitchen_rect = layout.areas[0]
	if layout.areas.size() > 1: _grid.front_rect = layout.areas[1]
	for y in layout.grid_size.y:
		for x in layout.grid_size.x:
			var c := Vector2i(x, y)
			var center := _grid.cell_center(c, layout.cell)
			for box in layout.obstacles:
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
