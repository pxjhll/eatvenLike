class_name FrontSpotDef
extends Resource
## 前厅的一个固定位点：开局是价格牌，点一下花金币解锁（布局基线决定⑧）。
## 后厨机器也在固定机位上（SlotDef），按阶段整条线一起解锁。运行时只读。

@export var id: String = ""
@export var station: StationDef
## 显示用的格子坐标，模拟不读
@export var grid_pos: Vector2i = Vector2i.ZERO
## 画面上的像素位置；留 (0, 0) 就按 grid_pos 换算
@export var view_pos: Vector2 = Vector2.ZERO
@export var unlock_cost: int = 0
## 到第几阶段才出现价格牌（0 = 开局就有）
@export var stage: int = 0
## 这个位点能站几名员工（柜台可以站 2 人）；不要员工的位点填 0
@export var posts: int = 1
## 开局就在、不用解锁（首店的柜台）
@export var starts_unlocked: bool = false
