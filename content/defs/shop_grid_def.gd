class_name ShopGridDef
extends Resource
## 店铺网格：由店铺场景上的 @tool 脚本在编辑器保存时导出，模拟只读这份 Resource。
## 坐标都是格；后厨格 (x, y) 在 kitchen_rect 里，y 向下（前厅方向）。

## 后厨可摆区（格），首店 6×5（地面格是正方形）
@export var kitchen_rect: Rect2i = Rect2i()
## 前厅区域（格），首店 6×5，和后厨同宽
@export var front_rect: Rect2i = Rect2i()
## 可以放原料柜的墙边格（墙角和靠前厅那面墙不在内）
@export var supply_wall_cells: Array[Vector2i] = []
## 货架的接口：通往货架的传送带最后一格（在后厨里，紧贴传菜窗口）
@export var shelf_cell: Vector2i = Vector2i.ZERO
## 一键部署的幽灵推荐位，按部署顺序：{"station": 设备定义 id, "cell": Vector2i}
@export var recommended: Array[Dictionary] = []


func in_kitchen(cell: Vector2i) -> bool:
	return kitchen_rect.has_point(cell)
