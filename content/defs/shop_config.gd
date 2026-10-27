class_name ShopConfig
extends Resource
## 一家店的全部配置。调参时复制一份，在 GameSim 上切换。运行时只读。

@export var id: String = ""
@export var display_name: String = ""
@export var items: Array[ItemDef] = []
@export var dishes: Array[DishDef] = []
## 后厨设备（设备栏里能买的），哪个阶段开放见 ShopStageDef.kitchen_devices
@export var kitchen_devices: Array[StationDef] = []
## 全店原料卡位：所有原料柜的槽数合计不能超过它
@export var supply_slot_limit: int = 0
## 前厅固定位点（点一下解锁）
@export var front_spots: Array[FrontSpotDef] = []
## 第 N 名员工的招人价（下标 0 = 第 1 名）；超出长度按最后一个
@export var hire_costs: Array[int] = []
## 招人时按顺序取用的员工模板；用完后重复最后一个
@export var hire_defs: Array[StaffDef] = []
## true = 空店开局，店里一个人都没有，全靠局内招人（跨店名册不带人进来）
@export var hires_own_staff: bool = false
## 店铺网格，由店铺场景导出
@export var grid: ShopGridDef
## 传送带速度（格/秒）
@export var belt_speed: float = 0.0
@export var starting_gold: int = 0
## 备料架每种 item 的容量
@export var shelf_capacity: int = 0
## 前厅最多排几位顾客，满了新顾客直接走
@export var queue_capacity: int = 0
## 顾客等多少秒没人接待就走
@export var customer_patience: float = 0.0
## 来客间隔的随机浮动比例（0.25 = ±25%）
@export var arrival_jitter: float = 0.0
@export var progression: ShopProgressionDef
@export var random_seed: int = 0


func device_def(def_id: String) -> StationDef:
	for d in kitchen_devices:
		if d.id == def_id:
			return d
	return null


func dish_for_item(item_id: String) -> DishDef:
	for d in dishes:
		if d.item_id == item_id:
			return d
	return null
