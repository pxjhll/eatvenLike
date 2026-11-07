class_name RuleGrid
extends RefCounted
## 格子寻路用的网格：几个可走的矩形区域（区域之间的空隙不算地面）+ 被障碍占住的格。正方形地面格。

var areas: Array[Rect2i] = []
var blocked_cells: Array[Vector2i] = []


func contains_cell(cell: Vector2i) -> bool:
	for area in areas:
		if area.has_point(cell): return true
	return false


## 四方向广度优先搜索。包含起终点；不可达返回空数组。
func find_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var obstacles := {}
	for cell in blocked_cells:
		obstacles[cell] = true
	if not contains_cell(from_cell) or not contains_cell(to_cell) or obstacles.has(from_cell) or obstacles.has(to_cell):
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
		for direction in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var next: Vector2i = current + direction
			if contains_cell(next) and not obstacles.has(next) and not previous.has(next):
				previous[next] = current
				frontier.append(next)
	return []


func cell_center(cell: Vector2i, cell_size: float) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size


func world_to_cell(point: Vector2, cell_size: float) -> Vector2i:
	var local := point / cell_size
	return Vector2i(floori(local.x), floori(local.y))
