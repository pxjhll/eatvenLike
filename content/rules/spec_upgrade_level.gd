class_name SpecUpgradeLevel
extends Resource
## 升级轨的一级：花多少钱从上一级升到这一级，这一级带来的全部效果（可以不止一个，§3.4）。

@export var cost: int = 0
@export var effects: Array[SpecEffect] = []
## 这一级是不是升星（面板显示星星；星级倍率作为普通 price 效果写在 effects 里）
@export var star: bool = false
