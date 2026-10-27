class_name PortDef
extends Resource
## 设备占地边上的一个接口（旋转 0° 时）。传送带接在接口外侧那一格。运行时只读。

enum Kind { IN, OUT }
enum Facing { RIGHT, DOWN, LEFT, UP }

@export var kind: Kind = Kind.IN
## 占地内的格（相对设备左上角）
@export var cell: Vector2i = Vector2i.ZERO
## 接口朝哪边；传送带在这一边外侧的那一格
@export var side: Facing = Facing.RIGHT
## IN：接受哪些物品，空 = 配方的全部输入
@export var items: Array[String] = []


## 接口外侧那一格（相对设备左上角）
func outside() -> Vector2i:
	return cell + direction(side)


static func direction(s: Facing) -> Vector2i:
	match s:
		Facing.RIGHT:
			return Vector2i.RIGHT
		Facing.DOWN:
			return Vector2i.DOWN
		Facing.LEFT:
			return Vector2i.LEFT
	return Vector2i.UP
