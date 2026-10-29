class_name GameCatalog
extends Resource
## 全部店铺（按换店顺序）与员工。运行时只读。

@export var shops: Array[ShopConfig] = []
@export var staff: Array[StaffDef] = []
## 新存档的初始员工名册（staff id）
@export var starting_roster: Array[String] = []
## 新存档从哪家店开局（店铺 id）；旧存档里的店铺下标含义不变
@export var starting_shop_id: String = ""
