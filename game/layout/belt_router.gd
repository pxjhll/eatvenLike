class_name BeltRouter
extends RefCounted
## 自动传送带：按物品推出上下游，在隐藏网格上寻路（布局基线 §12、决定⑮）。
## 同一布局总铺出同样的带子（不变量 14）：设备按列表顺序处理，邻格按固定顺序展开。
##
## 规则：带子不穿设备、不占人工设备的工位格、不出后厨；不同设备出来的带子不能重叠或交叉；
## 同一台设备出来的几条带子可以共用一段（原料柜的主带到分叉处再分开）；
## 货架口那一格只留给通往货架的带子。

## 通往货架的连接终点 id
const SHELF := "shelf"
const NEIGHBORS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]


## devices：[{"id", "def", "cell"}]。
## 返回 {"belts": [{"id", "from", "to", "item", "path"}], "failed": [{"from", "to", "item"}]}
static func route(config: ShopConfig, devices: Array) -> Dictionary:
	var blocked := {}
	for d in devices:
		for c in LayoutRules.occupied_cells(config.device_def(d.def), d.cell):
			blocked[c] = true
	blocked[config.grid.shelf_cell] = true
	var used := {}  # cell -> 哪台设备的带子
	var belts := []
	var failed := []
	for d in devices:
		var def := config.device_def(d.def)
		var port := def.out_port()
		if port == null:
			continue
		var start: Vector2i = d.cell + port.outside()
		for item in def.output_items():
			for target in _consumers(config, devices, item, d.id):
				var path := _bfs(config.grid, start, target.goal, blocked, used, d.id)
				if path.is_empty():
					failed.append({"from": d.id, "to": target.to, "item": item})
					continue
				for c in path:
					used[c] = d.id
				belts.append({"id": "%s>%s:%s" % [d.id, target.to, item], "from": d.id, "to": target.to, "item": item, "path": path})
	return {"belts": belts, "failed": failed}


## 收这种物品的下游：接受它的设备；没有设备要、它又是菜品成品，就送去货架
static func _consumers(config: ShopConfig, devices: Array, item: String, from_id: String) -> Array:
	var out := []
	for d in devices:
		if d.id == from_id:
			continue
		var port := config.device_def(d.def).in_port_for(item)
		if port != null:
			out.append({"to": d.id, "goal": d.cell + port.outside()})
	if out.is_empty() and config.dish_for_item(item) != null:
		out.append({"to": SHELF, "goal": config.grid.shelf_cell})
	return out


static func _bfs(grid: ShopGridDef, start: Vector2i, goal: Vector2i, blocked: Dictionary, used: Dictionary, source: String) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	# 货架口平时算堵住的，只有终点就是它的那条带子能进去
	if goal == grid.shelf_cell:
		blocked = blocked.duplicate()
		blocked.erase(goal)
	if not _free(grid, start, blocked, used, source) or not _free(grid, goal, blocked, used, source):
		return path
	var parent := {start: start}
	var queue: Array[Vector2i] = [start]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		if c == goal:
			break
		for n in NEIGHBORS:
			var next := c + n
			if not parent.has(next) and _free(grid, next, blocked, used, source):
				parent[next] = c
				queue.append(next)
	if not parent.has(goal):
		return path
	var c := goal
	while c != start:
		path.push_front(c)
		c = parent[c]
	path.push_front(start)
	return path


static func _free(grid: ShopGridDef, cell: Vector2i, blocked: Dictionary, used: Dictionary, source: String) -> bool:
	return grid.in_kitchen(cell) and not blocked.has(cell) and String(used.get(cell, source)) == source
