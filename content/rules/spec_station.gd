class_name SpecStation
extends Resource
## 一台机器（§3.3）：工序积木类型 + 这个类型的参数 + 通用参数。规则层只按 block 和 params 干活。

## 七类工序积木 + 柜台（每店固定部件）
const BLOCKS := ["supply", "batch_pot", "hand", "combine", "topping", "dispenser", "pickup", "counter"]

@export var id: String = ""
@export var display_name: String = ""
@export var block: String = ""
## 类型参数，键见规格 §3.3：
## supply     fetch_seconds
## batch_pot  cook_seconds, load_seconds, unload_seconds, batch, capacity, manual_load, manual_unload, stir_points, stir_seconds,
##            load_label, unload_label（员工头顶的字）
## hand       seconds, users
## combine    seconds, manual
## topping    seconds, users, flavor_cap
## dispenser  seconds
## pickup     zones {区: 容量}, process_seconds, process_slots, process_into
## counter    take_seconds, hand_seconds, posts
## 通用（界面用）：unit（一份叫什么：杯 / 份）、slot_label（加工位叫什么：封口位）
@export var params: Dictionary = {}
## front / kitchen / 空（不分区）
@export var zone: String = ""
## 能否坐班，坐班时走速 / 手速倍率
@export var seatable: bool = false
@export var seated_bonus: float = 1.0
## 解锁：价格；随哪台机器一起开（companion_of）；开局就在
@export var unlock_cost: int = 0
@export var starts_unlocked: bool = false
@export var companion_of: String = ""
@export var materials: Array[SpecMaterial] = []
@export var tracks: Array[SpecUpgradeTrack] = []
@export var stock: Array[SpecStockRule] = []
## 默认涨价范围（price 效果 dishes 为空时用）
@export var price_dishes: Array[String] = []
## 升级是否算进“机器等级加客流”
@export var counts_for_flow: bool = false
@export_multiline var description: String = ""
## 图标键（art/ui/icons/<icon>.svg）；空 = 用 id
@export var icon: String = ""


func track(track_id: String) -> SpecUpgradeTrack:
	for t in tracks:
		if t.id == track_id: return t
	return null


func material(material_id: String) -> SpecMaterial:
	for m in materials:
		if m.id == material_id: return m
	return null
