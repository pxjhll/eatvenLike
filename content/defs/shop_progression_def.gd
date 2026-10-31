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
## 美术店：封口机 Lv1 封一杯外带要几秒
@export var seal_seconds: float = 14.0
## 封口机升级（产能类）：下标 i = Lv(i+1)→Lv(i+2) 的价格；每级速度倍率和封口位（下标 0 = Lv1，长度 = 价格数 + 1）
## 封口位 n = 同时封 n 杯，每杯用时 = seal_seconds / 速度 / n 的产能
@export var seal_costs: Array[int] = []
@export var seal_speeds: Array[float] = [1.0]
@export var seal_slots: Array[int] = [1]
## 客流（产能类）：每开一种口味客人来得快 flavor_flow；发传单每级再快 flyer_flow；flyer_costs 下标 i = Lv(i+1)→Lv(i+2)
@export var flavor_flow: float = 0.05
@export var flyer_flow: float = 0.10
@export var flyer_costs: Array[int] = []
## 员工培养（产能类）：每级走路、干活 ×(1 + train_step)，到 train_star_levels 时一次多搬 1 杯
@export var train_costs: Array[int] = []
@export var train_step: float = 0.05
@export var train_star_levels: Array[int] = [5, 10]
## 员工升级清单（原版式）：前台、后厨各一串一次性升级，按顺序买，每条效果不同。
## 种类：walk = 走路快 walk_step；work = 干活快 work_step；carry = 一次多搬 1 杯；slot = 多一个前台位。
@export var front_upgrade_kinds: Array[String] = []
@export var front_upgrade_costs: Array[int] = []
@export var kitchen_upgrade_kinds: Array[String] = []
@export var kitchen_upgrade_costs: Array[int] = []
@export var walk_step: float = 0.2
@export var work_step: float = 0.25
