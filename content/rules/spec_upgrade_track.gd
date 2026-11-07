class_name SpecUpgradeTrack
extends Resource
## 一条升级轨：机器、原料、口味、传单、座位、前台/后厨员工的升级都用它（§3.4）。
## levels[0] 是从 Lv1 升到 Lv2，长度 = 最高级 - 1。Lv1 的初始值写在 base_effects 里。

@export var id: String = ""
@export var display_name: String = ""
## Lv1 就生效的效果（如煮茶机 Lv1 一锅 2 杯、速度 1.0）
@export var base_effects: Array[SpecEffect] = []
@export var levels: Array[SpecUpgradeLevel] = []
## 机器到几级这条轨才开放（口味槽：加料台升到几级才开）
@export var requires_level: int = 1
## 面板上这条轨的效果说明（“煮茶速度”“售价”“新口味”）
@export var effect_label: String = ""
## 售价预览（界面）：拿哪道菜举例——按顺序取第一道已开的，都没开取第一道；空 = 按菜单顺序取最后一道已开的
@export var preview_dishes: Array[String] = []
## 售价预览里“涨哪些菜”的说法；空 = 列出涨价菜的全名
@export var preview_label: String = ""


func max_level() -> int:
	return levels.size() + 1


func cost(level: int) -> int:
	## 从 level 升到 level + 1 的价格；满级返回 -1
	return levels[level - 1].cost if level >= 1 and level <= levels.size() else -1


## 这条轨到 level 级时某种效果的累计值：从 initial 开始，依次套 Lv1 的 base_effects 和每一级的效果。
## dish 非空时只算作用在这道菜上的 price 效果（effect.dishes 为空就用 default_dishes；都为空 = 全部菜）；
## part 非空时只算乘这一部分价格的效果（空 = 只算乘整道菜的）。
func fold(kind: String, level: int, initial: float, dish := "", default_dishes: Array = [], part := "") -> float:
	var value := initial
	var effects: Array[SpecEffect] = []
	effects.append_array(base_effects)
	for index in mini(level - 1, levels.size()): effects.append_array(levels[index].effects)
	for effect in effects:
		if effect.kind != kind or effect.price_part != part: continue
		if not dish.is_empty():
			var scope: Array = effect.dishes if not effect.dishes.is_empty() else default_dishes
			if not scope.is_empty() and not dish in scope: continue
		match effect.op:
			"set": value = effect.value
			"add": value += effect.value
			_: value *= effect.value
	return value


## 到 level 级为止升了几颗星
func stars(level: int) -> int:
	var count := 0
	for index in mini(level - 1, levels.size()):
		if levels[index].star: count += 1
	return count
