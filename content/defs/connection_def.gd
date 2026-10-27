class_name ConnectionDef
extends Resource
## ShopConfig 允许的一条连接（传送带）。to_slot 可以是 "shelf"（备料架）。运行时只读。

@export var id: String = ""
@export var from_slot: String = ""
@export var to_slot: String = ""
@export var length_cells: float = 1.0
@export var initially_connected: bool = true
## 非空：这个机位启用后，这条带不再送货（例如加料机接上后，调奶台不再直送货架）
@export var until_active: String = ""
