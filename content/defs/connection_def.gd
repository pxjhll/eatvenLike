class_name ConnectionDef
extends Resource
## ShopConfig 允许的一条连接（传送带）。to_slot 可以是 "shelf"（备料架）。运行时只读。

@export var id: String = ""
@export var from_slot: String = ""
@export var to_slot: String = ""
@export var length_cells: float = 1.0
@export var initially_connected: bool = true
