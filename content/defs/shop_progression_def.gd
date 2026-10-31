class_name ShopProgressionDef
extends Resource
## 一家店的阶段列表（菜品解锁表）。运行时只读。

@export var stages: Array[ShopStageDef] = []
## 美术店可买的传送带段（旧版 GameSim 不读）
@export var belts: Array[BeltSlotDef] = []
## 美术店：堂食座位。开局几张、最多几张，第 n 张加座的价格，每位客人坐多久
@export var seat_start: int = 3
@export var seat_costs: Array[int] = []
@export var seat_seconds: float = 40.0
## 美术店：封口机封一杯外带要几秒（一次一杯）
@export var seal_seconds: float = 14.0
