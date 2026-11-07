class_name SpecTask
extends Resource
## 任务（§3.9）：条件枚举 + 对象 + 数量。

## sell_count（卖出 N 份某菜）/ track_level（某升级轨到 N 级）/ flavor_open（开出某口味）/ revenue（营业额到 N）
@export var condition: String = "sell_count"
@export var id: String = ""
@export var display_name: String = ""
@export var target: String = ""
@export var amount: float = 0.0
