class_name ShopStageDef
extends Resource
## 单店节奏页解锁表的一行。运行时只读。

@export var dish_id: String = ""
## 累计营业额达到多少才能解锁本阶段（第 1 阶段为 0）
@export var revenue_threshold: int = 0
## 本阶段需要解锁的机位 id
@export var unlock_slots: Array[String] = []
## 大于 0：unlock_slots 整条线一次点解锁（UnlockLine），机器和传送带一起出现，不能单台买
@export var line_cost: int = 0
## 整条线的名字，显示在价格牌和解锁按钮上（如「奶茶生产线」）；空 = 用菜名
@export var line_name: String = ""
## 美术店：到本阶段时店内最多同时派出几位员工（旧版 GameSim 不读）
@export var staff_slots: int = 3
## 本阶段的平均来客间隔（秒）
@export var customer_interval: float = 0.0
## 本阶段起的点单权重：dish_id -> 权重
@export var order_weights: Dictionary[String, float] = {}
## 美术店：本阶段排队上限（排满后新客人不进店）
@export var queue_capacity: int = 6
## 美术店：本阶段想外带的顾客比例（需已解锁封口机）
@export var takeaway_share: float = 0.0
## 美术店：未解锁时面板上的一句说明（空 = 用菜名）
@export var unlock_note: String = ""
@export var tasks: Array[TaskDef] = []
