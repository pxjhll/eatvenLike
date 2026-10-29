class_name StationDef
extends Resource
## 工位定义。行为差异只靠 mode，不按工位 id 写分支。运行时只读。

enum OwnerSystem { PRODUCTION, FRONT_HALL }
## AUTO：机器自动加工；COOP：员工装入 → 机器加工 → 员工取出；
## MANUAL：员工人工完成一份（前厅柜台服务也用它）；SUPPLY：外购箱按间隔到货；
## DISPENSER：前厅出品台，像饮水机，不要员工、不囤杯、不限量，柜台服务员过去现打。
## TOPPING：加料机，自动；每杯在已开放的配料槽之间轮流加料，某口味货架格满了（含在途）就跳过。
enum Mode { AUTO, COOP, MANUAL, SUPPLY, DISPENSER, TOPPING }

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
## 出口缓冲容量（所有 item 合计；带物料槽的原料柜按每种原料分别计）
@export var output_capacity: int = 0
## 所属工作区
@export var zone: String = ""
## 每级速度倍率，下标 0 = Lv1
@export var level_speed: Array[float] = [1.0]
## 下标 i = 从 Lv(i+1) 升到 Lv(i+2) 的价格
@export var upgrade_costs: Array[int] = []
@export var parallel_cost: int = 0
@export var unlock_cost: int = 0
## SUPPLY：每隔多少秒到一批
@export var supply_interval: float = 0.0
## SUPPLY：每批到几份配方输出
@export var supply_batch: int = 1
## FRONT_HALL：可卖的菜品 id
@export var dishes: Array[String] = []
## 物料槽：SUPPLY = 原料柜的各原料（每种单独计时、单独出货）；TOPPING = 加料机的各配料
@export var materials: Array[MaterialSlotDef] = []
## 美术店升级（旧版 GameSim 不读这几项）。art_costs 非空时美术店改用这一套：
## 下标 i = 从 Lv(i+1) 升到 Lv(i+2) 的价格
@export var art_costs: Array[int] = []
## 加价：每升 1 级，art_price_dishes 里的饮品每杯 +底价 × art_price_step（多台机器相加，不连乘）
@export var art_price_step: float = 0.0
@export var art_price_dishes: Array[String] = []
## 提速：机器做一批的秒数（Lv1），和每级速度倍率（下标 0 = Lv1，长度 = art_costs + 1）
@export var art_seconds: float = 0.0
@export var art_speeds: Array[float] = []
## TOPPING：每个口味在货架上最多几杯（含传送带上和机器里的）
@export var flavor_cap: int = 0


func material(material_id: String) -> MaterialSlotDef:
	for m in materials:
		if m.id == material_id:
			return m
	return null
