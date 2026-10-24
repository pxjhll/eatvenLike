class_name SlotDef
extends Resource
## 店铺里的一个固定机位。运行时只读。

@export var id: String = ""
@export var station: StationDef
## 开店时是否为未解锁（灰色虚影 + 价格牌），只能由 UnlockStation 激活
@export var initially_locked: bool = false
## 非空表示这是某个固定机位的并联槽，只能由 ActivateParallel 启用
@export var parallel_of: String = ""
@export var grid_pos: Vector2i = Vector2i.ZERO
