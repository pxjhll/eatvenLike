class_name StationDef
extends Resource
## 工位定义。行为差异只靠 mode，不按工位 id 写分支。运行时只读。

enum OwnerSystem { PRODUCTION, FRONT_HALL }
## AUTO：机器自动加工；COOP：员工装入 → 机器加工 → 员工取出；
## MANUAL：员工人工完成一份（前厅柜台服务也用它）；
## SUPPLY：原料柜，几个槽各放一种主料，按需轮流出货（布局基线决定⑮）；
## DISPENSER：前厅出品台，像饮水机，不要员工、不囤杯、不限量，柜台服务员过去现打。
enum Mode { AUTO, COOP, MANUAL, SUPPLY, DISPENSER }

@export var id: String = ""
@export var display_name: String = ""
@export var owner: OwnerSystem = OwnerSystem.PRODUCTION
@export var mode: Mode = Mode.AUTO
@export var recipe: RecipeDef
## AUTO / COOP：机器加工一份的秒数；MANUAL：员工做一份的秒数；
## DISPENSER：员工在台前打一杯的秒数（加在柜台服务时间上）
@export var cycle_seconds: float = 0.0
## COOP：装入、取出各一步的人工秒数
@export var manual_seconds: float = 0.0
## 入口缓冲容量，按 item 分别计
@export var input_capacity: Dictionary[String, int] = {}
## 出口缓冲容量（所有 item 合计；SUPPLY 按每个槽分别计）
@export var output_capacity: int = 0
## 所属区域（"kitchen" / "front"），员工效率按它取
@export var zone: String = ""
## 每级速度倍率，下标 0 = Lv1
@export var level_speed: Array[float] = [1.0]
## 下标 i = 从 Lv(i+1) 升到 Lv(i+2) 的价格
@export var upgrade_costs: Array[int] = []
## SUPPLY：每隔多少秒出一份（几个槽轮流）
@export var supply_interval: float = 0.0
## SUPPLY：每个槽放的主料，一个槽一种；每个槽占 1 个全店原料卡位
@export var supply_items: Array[String] = []

## FRONT_HALL：可卖的菜品 id
@export var dishes: Array[String] = []

@export_group("布局（后厨设备）")
## 在设备栏里的买价
@export var price: int = 0
## 占地（格），旋转 0° 时
@export var footprint: Vector2i = Vector2i.ONE
@export var ports: Array[PortDef] = []
## 员工站的那一格（相对设备左上角，可在占地外）；只有要员工的设备用
@export var work_cell: Vector2i = Vector2i.ZERO
## true = 只能贴着可放原料的墙边格摆（原料柜）
@export var wall_only: bool = false


func needs_staff() -> bool:
	return mode == Mode.MANUAL or mode == Mode.COOP


## 这台设备往外送的物品
func output_items() -> Array[String]:
	if mode == Mode.SUPPLY:
		return supply_items
	var out: Array[String] = []
	if recipe != null:
		out.assign(recipe.outputs.keys())
	return out


func accepts(item: String) -> bool:
	return mode != Mode.SUPPLY and recipe != null and recipe.inputs.has(item)


## 接这种物品的入口；没有返回 null
func in_port_for(item: String) -> PortDef:
	if not accepts(item):
		return null
	for port in ports:
		if port.kind == PortDef.Kind.IN and (port.items.is_empty() or item in port.items):
			return port
	return null


func out_port() -> PortDef:
	for port in ports:
		if port.kind == PortDef.Kind.OUT:
			return port
	return null
