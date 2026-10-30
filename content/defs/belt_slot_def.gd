class_name BeltSlotDef
extends Resource
## 美术店的一段可买传送带：装在两台机器之间，装上后这段不用员工搬，自动运货。运行时只读。

@export var id: String = ""
@export var display_name: String = ""
## 起点 / 终点：supply、boil、mix、topping、seal、shelf
@export var from: String = ""
@export var to: String = ""
@export var cost: int = 0
## 店铺进行到第几阶段（含）才能装：1 红茶线、2 调奶台、3 加料机
@export var stage: int = 1
## 每隔多少秒往带上放 1 杯（份），每份在带上走多少秒
@export var interval: float = 1.5
@export var seconds: float = 3.0
## 画面上的折线（像素坐标），货物沿它移动
@export var view_points: PackedVector2Array = PackedVector2Array()
