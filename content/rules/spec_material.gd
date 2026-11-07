class_name SpecMaterial
extends Resource
## 机器上的一个物料槽：原料箱的一种原料，或加料台的一种料（§3.3）。

@export var id: String = ""
@export var display_name: String = ""
## 原料：出的原料；加料：加完的成品菜
@export var item: String = ""
## 单独解锁这一箱的价格（0 = 随机器一起有）
@export var box_cost: int = 0
## 这一箱跟着哪台机器出现
@export var box_station: String = ""
## 这个槽自己的升级轨（requires_level = 机器几级才开放）
@export var track: SpecUpgradeTrack
