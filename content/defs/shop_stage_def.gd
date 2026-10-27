class_name ShopStageDef
extends Resource
## 单店节奏页解锁表的一行。运行时只读。

@export var dish_id: String = ""
## 累计营业额达到多少本阶段自动开放（第 1 阶段为 0）
@export var revenue_threshold: int = 0
## 本阶段开放的后厨设备（StationDef id），开放后能在设备栏里买
@export var kitchen_devices: Array[String] = []
## 本阶段的平均来客间隔（秒）
@export var customer_interval: float = 0.0
## 本阶段起的点单权重：dish_id -> 权重
@export var order_weights: Dictionary[String, float] = {}
@export var tasks: Array[TaskDef] = []
