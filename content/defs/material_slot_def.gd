class_name MaterialSlotDef
extends Resource
## 机器上的一个物料槽：原料柜里的一种原料，或加料机上的一种配料。点开机器能单独升级（首店流程稿 5）。
## 运行时只读。

@export var id: String = ""
@export var display_name: String = ""
## 原料柜：这个槽出的原料；加料机：加完这种料出来的成品
@export var item_id: String = ""
## 机器升到几级这个槽才开放（1 = 机器一解锁就有）
@export var unlock_level: int = 1
## 原料柜：这一格（原料箱）要单独花钱解锁，0 = 不用解锁
@export var box_cost: int = 0
## 原料箱跟着哪台机器出现（这台机器解锁后才能买箱）
@export var box_machine: String = ""
## 下标 i = 从 Lv(i+1) 升到 Lv(i+2) 的价格
@export var upgrade_costs: Array[int] = []
## 美术店加价升级（同 StationDef.art_*，每级售价 ×(1 + art_price_step)）：art_costs 非空时用这一套、不再影响速度
@export var art_costs: Array[int] = []
@export var art_price_step: float = 0.0
@export var art_price_dishes: Array[String] = []
## 每级倍率，下标 0 = Lv1。原料柜 = 这种原料的出货速度；加料机 = 这个口味的售价
@export var level_bonus: Array[float] = [1.0]


func max_level() -> int:
	return mini(level_bonus.size(), upgrade_costs.size() + 1)


func bonus(level: int) -> float:
	return level_bonus[level - 1] if level >= 1 and level <= level_bonus.size() else 1.0
