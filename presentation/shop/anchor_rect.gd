@tool
class_name AnchorRect
extends Node2D
## 场景锚点里的一块矩形（规格 §6.1）：点按区域、虚线框、坐班区、障碍……位置 = 左上角，size = 大小。
## 只在编辑器里画出来，游戏里看不见。

@export var size := Vector2(64, 64):
	set(value):
		size = value
		queue_redraw()


func rect() -> Rect2:
	return Rect2(position, size)


func _draw() -> void:
	if not Engine.is_editor_hint(): return
	draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.6, 0.1, 0.18))
	draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.5, 0.0, 0.9), false, 2.0)
