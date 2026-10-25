class_name GameCatalog
extends Resource

## Fresh profiles choose this stable ID. Legacy saved indices keep their original meaning.
@export var starting_shop_id: String = ""
## 全部店铺（按换店顺序）与员工。运行时只读。

@export var shops: Array[ShopConfig] = []
@export var staff: Array[StaffDef] = []
## 新存档的初始员工名册（staff id）
@export var starting_roster: Array[String] = []

