class_name ShopGridDef
extends Resource
## 店铺网格：由店铺场景上的 @tool 脚本在编辑器保存时导出，模拟只读这份 Resource。
## 阶段 1 只用到尺寸和区域；推荐位、可放原料箱的墙格在布局模式（PXJ-47）才用上。

## 后厨可摆区（格），首店 8×6
@export var kitchen_rect: Rect2i = Rect2i()
## 前厅区域（格），首店 8×5
@export var front_rect: Rect2i = Rect2i()
## 可以放原料箱的墙边格（墙角和靠前厅那面墙不在内）
@export var supply_wall_cells: Array[Vector2i] = []
## 一键部署的幽灵推荐位，按部署顺序：{"station": 设备定义 id, "cell": Vector2i, "rotation": int}
@export var recommended: Array[Dictionary] = []
