class_name ShopGridDef
extends Resource
## 店铺网格：由店铺场景上的 @tool 脚本在编辑器保存时导出，模拟只读这份 Resource。
## 阶段 1 只用到尺寸和区域；推荐位、可放原料箱的墙格在布局模式（PXJ-47）才用上。

## 后厨可摆区（格），首店 6×5（地面格是正方形）
@export var kitchen_rect: Rect2i = Rect2i()
## 前厅区域（格），首店 6×5，和后厨同宽
@export var front_rect: Rect2i = Rect2i()
## 可以放原料箱的墙边格（墙角和靠前厅那面墙不在内）
@export var supply_wall_cells: Array[Vector2i] = []
## 一键部署的幽灵推荐位，按部署顺序：{"station": 设备定义 id, "cell": Vector2i, "rotation": int}
@export var recommended: Array[Dictionary] = []

## 固定障碍（墙、隔断等）；家具占地由调用者单独传入。未标定布局时保持为空。
@export var blocked_cells: Array[Vector2i] = []


## 逻辑单位始终是格；两个区域之间的空隙不视为地面。
func contains_cell(cell: Vector2i) -> bool:
	return kitchen_rect.has_point(cell) or front_rect.has_point(cell)


## 按顺时针 90 度旋转局部坐标，旋转后的占地左上角仍为原点。
## 坐标允许在占地外，因此操作点、输入口、输出口可使用同一变换。
func rotate_offset(offset: Vector2i, footprint: Vector2i, quarter_turns := 0) -> Vector2i:
	match posmod(quarter_turns, 4):
		1:
			return Vector2i(footprint.y - 1 - offset.y, offset.x)
		2:
			return Vector2i(footprint.x - 1 - offset.x, footprint.y - 1 - offset.y)
		3:
			return Vector2i(offset.y, footprint.x - 1 - offset.x)
	return offset


func footprint_cells(origin: Vector2i, footprint: Vector2i, quarter_turns := 0) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if footprint.x <= 0 or footprint.y <= 0:
		return cells
	for y in footprint.y:
		for x in footprint.x:
			cells.append(origin + rotate_offset(Vector2i(x, y), footprint, quarter_turns))
	return cells


## 只读验证。移动物体时，occupied 应排除该物体自己的旧占地。
## 可达性另用 find_path 检查；此函数不会修改布局或替玩家提交摆放。
func placement_error(origin: Vector2i, footprint: Vector2i, quarter_turns := 0, occupied: Array[Vector2i] = []) -> String:
	var cells := footprint_cells(origin, footprint, quarter_turns)
	if cells.is_empty():
		return "invalid_footprint"
	for cell in cells:
		if not contains_cell(cell):
			return "out_of_bounds"
		if cell in blocked_cells:
			return "blocked"
		if cell in occupied:
			return "occupied"
	return ""


## 小店使用四方向广度优先搜索。包含起终点；不可达返回空数组。
## occupied 为家具的不可行走占地，不应包含整张图片的外接矩形。
## 员工的动态避让、任务认领不属于此处的静态寻路。
func find_path(from_cell: Vector2i, to_cell: Vector2i, occupied: Array[Vector2i] = []) -> Array[Vector2i]:
	var obstacles := {}
	for cell in blocked_cells:
		obstacles[cell] = true
	for cell in occupied:
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


## 路径长度（格）/ 移速（格/秒）。不可达或无有效移速时为 INF，不能派工。
func travel_seconds(from_cell: Vector2i, to_cell: Vector2i, speed_cells_per_second: float, occupied: Array[Vector2i] = []) -> float:
	if speed_cells_per_second <= 0.0:
		return INF
	var path := find_path(from_cell, to_cell, occupied)
	return INF if path.is_empty() else float(path.size() - 1) / speed_cells_per_second


## 显示换算，正方形地面格。不使用 PNG 宽高；256 像素/格属于美术导出规格。
func cell_center(cell: Vector2i, display_cell_size: float, origin := Vector2.ZERO) -> Vector2:
	assert(display_cell_size > 0.0, "display cell size must be positive")
	return origin + (Vector2(cell) + Vector2(0.5, 0.5)) * display_cell_size


func world_to_cell(point: Vector2, display_cell_size: float, origin := Vector2.ZERO) -> Vector2i:
	assert(display_cell_size > 0.0, "display cell size must be positive")
	var local := (point - origin) / display_cell_size
	return Vector2i(floori(local.x), floori(local.y))
