class_name SpecStage
extends Resource
## 阶段（§3.9）：解锁一组机器开启下一阶段，带自己的客流、菜单、人数和任务。

@export var id: String = ""
@export var display_name: String = ""
## 这一阶段新开的机器（一起解锁）
@export var stations: Array[String] = []
## 配方阶段：不开新机器，在这台（已开的）机器面板的配方栏里买，买了 dish 才上菜单。和 stations 二选一。
@export var recipe_at: String = ""
@export var cost: int = 0
## 新上菜单的主打菜（解锁卡上显示）
@export var dish: String = ""
@export var unlock_note: String = ""
@export var customer_interval: float = 0.0
@export var order_weights: Dictionary[String, float] = {}
## 权重里的“一组口味”键：weights[group] 平分给已开放的口味，没口味时给 fallback（煎饼摊 meat → guozi）
@export var flavor_group: String = ""
@export var flavor_fallback: String = ""
@export var takeaway_share: float = 0.0
## 各区域员工上限：{"kitchen": 2}；不分区的店用 {"": n}
@export var staff_slots: Dictionary[String, int] = {}
## 站位上限（不含座位）
@export var queue_capacity: int = 0
## 等位座位数（煎饼摊坐垫随阶段给）
@export var wait_seats: int = 0
## 堂食坐多久
@export var seat_seconds: float = 0.0
@export var tasks: Array[SpecTask] = []
