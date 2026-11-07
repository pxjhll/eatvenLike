class_name SpecSeatGroup
extends Resource
## 座位组（§3.2）：dine = 堂食（坐下吃一会儿再走），wait = 等位（收钱后坐着等饼）。

@export var id: String = ""
@export var purpose: String = "dine"
@export var start: int = 0
## 买座位：每次加几个、每次的价格（阶段给座位的店留空）
@export var step: int = 1
@export var costs: Array[int] = []
## 每次加几个，按购买次数排（写了就盖过 step；比如坐垫一组 2/3/4 个）
@export var steps: Array[int] = []
## 默认坐多久（阶段可覆盖）
@export var seconds: float = 0.0
## 坐着等时耐心倍率
@export var patience: float = 1.0
