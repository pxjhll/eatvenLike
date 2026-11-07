class_name SpecStockRule
extends Resource
## 备货规则（§3.6）：目标 = max(base, 正在等这样东西的单数 × per_waiting)，不超过 cap；低于 low 就开工。

@export var item: String = ""
@export var base: int = 0
@export var per_waiting: int = 0
@export var cap: int = 0
@export var low: int = 0
## 开张时已有几份
@export var start: int = 0
