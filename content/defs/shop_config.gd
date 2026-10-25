class_name ShopConfig
extends Resource
## 一家店的全部配置。调参时复制一份，在 GameSim 上切换。运行时只读。

@export var id: String = ""
@export var display_name: String = ""
@export var items: Array[ItemDef] = []
@export var dishes: Array[DishDef] = []
@export var slots: Array[SlotDef] = []
@export var connections: Array[ConnectionDef] = []
## 传送带速度（格/秒）
@export var belt_speed: float = 0.0
## 工作区 id，第一个是默认工作区
@export var zones: Array[String] = []
## "a>b" -> 秒，反方向没写时按同一个值
@export var walk_seconds: Dictionary[String, float] = {}
@export var starting_gold: int = 0
## staff_id -> 开店时所在工作区
@export var staff_start_zones: Dictionary[String, String] = {}
## 备料架每种 item 的容量
@export var shelf_capacity: int = 0
## 前厅最多排几位顾客，满了新顾客直接走
@export var queue_capacity: int = 0
## 顾客等多少秒没人接待就走
@export var customer_patience: float = 0.0
## 来客间隔的随机浮动比例（0.25 = ±25%）
@export var arrival_jitter: float = 0.0
@export var progression: ShopProgressionDef
@export var random_seed: int = 0
## Derived access gate. Zero preserves existing shops; never store a second kitchen-open flag.
@export var kitchen_unlock_stage: int = 0
@export var kitchen_zone: String = "kitchen"

