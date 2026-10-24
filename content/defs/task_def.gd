class_name TaskDef
extends Resource
## 换店任务。只靠条件枚举 + 参数，不按具体任务写代码。运行时只读。

enum Condition { SELL_COUNT, NO_STOCKOUT_SECONDS, STATION_LEVEL }

@export var id: String = ""
@export var display_name: String = ""
@export var condition: Condition = Condition.SELL_COUNT
## SELL_COUNT / NO_STOCKOUT_SECONDS：菜品 id；STATION_LEVEL：工位定义 id
@export var target_id: String = ""
## 份数 / 秒数 / 等级
@export var amount: float = 0.0
