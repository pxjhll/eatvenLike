class_name LayoutRules
extends RefCounted
## 摆放合法性用到的格子计算（旋转 0°；旋转在 PXJ-48 再做）。


## 设备本体占的格
static func footprint_cells(def: StationDef, cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in def.footprint.y:
		for x in def.footprint.x:
			out.append(cell + Vector2i(x, y))
	return out


## 本体 + 员工站的那一格（要员工的设备才有）
static func occupied_cells(def: StationDef, cell: Vector2i) -> Array[Vector2i]:
	var out := footprint_cells(def, cell)
	if def.needs_staff():
		out.append(cell + def.work_cell)
	return out


## 这台设备放在 cell 合不合法；others：其余设备 [{"id", "def", "cell"}]（不含它自己）
static func problem(config: ShopConfig, def: StationDef, cell: Vector2i, others: Array) -> String:
	var grid := config.grid
	var taken := {}
	var slots := 0
	for d in others:
		var other := config.device_def(d.def)
		for c in occupied_cells(other, d.cell):
			taken[c] = true
		slots += other.supply_items.size()
	for c in occupied_cells(def, cell):
		if not grid.in_kitchen(c):
			return "超出后厨"
		if taken.has(c):
			return "和别的设备重叠"
		if c == grid.shelf_cell:
			return "挡住了通往货架的位置"
	if def.wall_only:
		for c in footprint_cells(def, cell):
			if not c in grid.supply_wall_cells:
				return "原料柜要贴着墙放"
	if slots + def.supply_items.size() > config.supply_slot_limit:
		return "原料卡位不够"
	return ""
