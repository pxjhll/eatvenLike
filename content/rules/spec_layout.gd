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
@export var grid_size: Vector2i = Vector2i.ZERO
## 各处的站位（像素）：机器 id、counter、shelf、rack、home、entrance……
@export var points: Dictionary[String, Vector2] = {}
## 坐班位
@export var posts: Dictionary[String, Vector2] = {}
## 机器 id → 取货 / 放货时走到哪个点（没写就用 points[机器 id]）
@export var aliases: Dictionary[String, String] = {}
## 新员工出现在哪
@export var spawn_point: String = "counter"
