class_name SpecPerk
extends Resource
## 永久加成（§3.14，预留）：用奖杯买，每级价格和效果；进加成栈时来源 = permanent。

@export var id: String = ""
@export var display_name: String = ""
@export var trophy_costs: Array[int] = []
@export var effects: Array[SpecEffect] = []
