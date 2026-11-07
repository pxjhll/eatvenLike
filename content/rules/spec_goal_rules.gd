class_name SpecGoalRules
extends Resource
## 当前目标与完店（§3.9）。

## 目标顺序：open（开张）→ box（待买原料箱）→ stage（下一阶段）→ tasks
@export var order: Array[String] = ["open", "box", "stage", "tasks"]
## 文案模板，{cost} {name} {current} {target} 由规则层填
@export var texts: Dictionary[String, String] = {}
## 开张那台机器
@export var opening_station: String = ""
## 完店：all_stages + all_tasks；all_flavors = 口味全开
@export var complete_when: Array[String] = ["all_stages", "all_tasks"]
## 结店评分：完店分钟数门槛（3 星、2 星），流失率超过多少扣一星
@export var rating_minutes: Array[float] = []
@export var rating_lost_share: float = 0.0
