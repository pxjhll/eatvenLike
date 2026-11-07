class_name SpecDispatch
extends Resource
## 员工调度打分表（§3.6）。分数 = 基础分 + 等待加成（有上限）+ 缺口加成 − 路程。

## 各类候选任务的基础分：follow（推进手上的单）/ take（领新单）/ chore（设备杂活）/ stock（备货）
## / deliver（送半成品）/ serve（前厅递餐）/ stir / topping …
@export var base_scores: Dictionary[String, float] = {}
## 等待加成：每秒加多少、上限
@export var wait_bonus_per_second: float = 0.0
@export var wait_bonus_cap: float = 0.0
## 缺口加成：下游缺货时加分（每缺一单 shortage_per，上限 shortage_cap）
@export var shortage_bonus: float = 0.0
@export var shortage_per: float = 0.0
@export var shortage_cap: float = 0.0
## 路程扣分：每像素 / 每秒路程扣多少
@export var travel_penalty: float = 0.0
## 合单：紧挨着的同一种菜一起领，上限 = 员工搬运量（carry）或固定数
@export var merge: String = "carry"
@export var merge_cap: int = 1
## 从工序链上已有的现成物品那一步接着做
@export var resume_from_stock: bool = true
## 在批量锅前等产物时可以接这台锅的杂活
@export var help_while_waiting: bool = true
## 杂活排在领新单之前（煎饼摊）
@export var chores_first: bool = false
## 不在岗的流动员工让出坐班机器那一段（奶茶店：加料段有人坐班时流动员工不碰）
@export var leave_seated_segments: bool = true
## 打分 = (基础分 + 每秒能做几份 × throughput_weight − 路程秒 × travel_penalty) × (1 − 疲劳 × fatigue_weight)
@export var throughput_weight: float = 0.0
@export var fatigue_weight: float = 0.0
## 疲劳：干活每秒涨 fatigue_gain，空闲每秒回 fatigue_recover（0–1）
@export var fatigue_gain: float = 0.0
@export var fatigue_recover: float = 0.0
## 搬一趟（拿 + 放）各要几秒手上功夫（不算走路）
@export var hop_seconds: float = 0.0
## 手上的单这么久推不动就放手（秒）
@export var ticket_give_up: float = 0.0
