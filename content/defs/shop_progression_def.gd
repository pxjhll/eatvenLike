class_name ShopProgressionDef
extends Resource
## 一家店的阶段列表（菜品解锁表）。运行时只读。

@export var stages: Array[ShopStageDef] = []
## 美术店可买的传送带段（旧版 GameSim 不读）
@export var belts: Array[BeltSlotDef] = []
