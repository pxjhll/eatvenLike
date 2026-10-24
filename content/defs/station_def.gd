class_name StationDef
extends Resource
## 工位定义。行为差异只靠 mode，不按工位 id 写分支。运行时只读。

enum OwnerSystem { PRODUCTION, FRONT_HALL }
## AUTO：机器自动加工；COOP：员工装入 → 机器加工 → 员工取出；
## MANUAL：员工人工完成一份（前厅服务也用它）；SUPPLY：外购箱按间隔到货。
enum Mode { AUTO, COOP, MANUAL, SUPPLY }

@export var id: String = ""
@export var display_name: String = ""
@export var owner: OwnerSystem = OwnerSystem.PRODUCTION
@export var mode: Mode = Mode.AUTO
@export var recipe: RecipeDef
## AUTO / COOP：机器加工一份的秒数；MANUAL：员工做一份的秒数
@export var cycle_seconds: float = 0.0
## COOP：装入、取出各一步的人工秒数
@export var manual_seconds: float = 0.0
## 入口缓冲容量，按 item 分别计
@export var input_capacity: Dictionary[String, int] = {}
## 出口缓冲容量（所有 item 合计）
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
