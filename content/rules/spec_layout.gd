class_name SpecLayout
extends Resource
## 店里的走位数据（规则层寻路和走路时间用）。第 3 个 PR 起改由美术场景的锚点导出，规则层只读这份。

## grid = 按格子寻路（四方向，绕开障碍）；straight = 直线走
@export var nav: String = "straight"
@export var cell: float = 20.0
## 可走区域（格），可以有几块
@export var areas: Array[Rect2i] = []
## 障碍（像素矩形），格子中心落在里面就不能走
@export var obstacles: Array[Rect2] = []
## 和 obstacles 一一对应：这台机器开了这块障碍才在（比如加料台的桌子跟加料台一起摆出来）；空 / 没写 = 一直在
@export var obstacle_stations: Array[String] = []
@export var grid_size: Vector2i = Vector2i.ZERO
## 各处的站位（像素）：机器 id、counter、shelf、rack、home、entrance……
@export var points: Dictionary[String, Vector2] = {}
## 坐班位
@export var posts: Dictionary[String, Vector2] = {}
## 机器 id → 取货 / 放货时走到哪个点（没写就用 points[机器 id]）
@export var aliases: Dictionary[String, String] = {}
## 新员工出现在哪
@export var spawn_point: String = "counter"

## 0保留旧店行为；1启用规则持有的员工/顾客运动。新店必须显式给出权限和顾客端口。
@export var motion_version: int = 0
@export var motion_units: float = 1.0
## 权限名 → Array[Rect2i]；与areas取交集。未登记的权限不能走。
@export var actor_areas: Dictionary = {}
## entrance / exit / pickup / seat:<组>/<序号> / wait:<组>/<序号>。
@export var customer_points: Dictionary[String, Vector2] = {}
@export var customer_queue: Array[Vector2] = []
