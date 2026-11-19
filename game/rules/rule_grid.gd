class_name RuleGrid
extends RefCounted
## 格子寻路用的网格：几个可走的矩形区域（区域之间的空隙不算地面）+ 被障碍占住的格。正方形地面格。

var areas: Array[Rect2i] = []
var blocked_cells: Array[Vector2i] = []
var _profile_cells: Variant = null
var _profile_edges: Dictionary[Vector3i, bool] = {}
const DIRECTIONS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]


func contains_cell(cell: Vector2i) -> bool:
	for area in areas:
		if area.has_point(cell): return true
	return false


## Profile grids belong to one obstacle topology. Cache directed edges as BFS
## reaches them so creating a grid does not pay for routes nobody will use.
func prepare_profile(size: Vector2i, can_occupy: Callable) -> void:
	_profile_cells = {}
	_profile_edges.clear()
	for y in size.y:
		for x in size.x:
			var cell := Vector2i(x, y)
			if can_occupy.call(cell): _profile_cells[cell] = true


## 四方向广度优先搜索。包含起终点；不可达返回空数组。
func find_path(from_cell: Vector2i, to_cell: Vector2i, can_step: Callable = Callable()) -> Array[Vector2i]:
	var obstacles := {}
	for cell in blocked_cells:
		obstacles[cell] = true
	var has_edge_check := can_step.is_valid()
	var profiled := _profile_cells != null and has_edge_check
	if profiled:
		if not _profile_cells.has(from_cell) or not _profile_cells.has(to_cell): return []
	elif not contains_cell(from_cell) or not contains_cell(to_cell) or obstacles.has(from_cell) or obstacles.has(to_cell):
		return []
	var previous := {}
	previous[from_cell] = from_cell
	var frontier: Array[Vector2i] = [from_cell]
	var head := 0
	while head < frontier.size():
		var current := frontier[head]
		head += 1
		if current == to_cell:
			var path: Array[Vector2i] = [current]
			while current != from_cell:
				current = previous[current]
				path.append(current)
			path.reverse()
			return path
		for direction in DIRECTIONS.size():
			var next: Vector2i = current + DIRECTIONS[direction]
			if previous.has(next): continue
			if profiled:
				if not _profile_cells.has(next): continue
				var edge := Vector3i(current.x, current.y, direction)
				if not _profile_edges.has(edge): _profile_edges[edge] = can_step.call(current, next)
				if not _profile_edges[edge]: continue
			elif not contains_cell(next) or obstacles.has(next):
				continue
			elif has_edge_check and not can_step.call(current, next):
				continue
			previous[next] = current
			frontier.append(next)
	return []


func cell_center(cell: Vector2i, cell_size: float) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size


func world_to_cell(point: Vector2, cell_size: float) -> Vector2i:
	var local := point / cell_size
	return Vector2i(floori(local.x), floori(local.y))
