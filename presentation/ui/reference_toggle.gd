extends Control
## Decorative native switch; its parent Button owns input and real glass state.
const ReferenceTheme := preload("res://presentation/ui/reference_theme.gd")
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	(get_parent() as BaseButton).toggled.connect(func(_value:bool) -> void: queue_redraw())
func _draw() -> void:
	var active:bool = (get_parent() as BaseButton).button_pressed
	draw_style_box(ReferenceTheme.style("gold" if active else "track",size.y/2),Rect2(Vector2.ZERO,size))
	var r:float = size.y/2-3
	var center := Vector2(size.x-r-3 if active else r+3,size.y/2-1)
	draw_circle(center,r,Color("fff7e4"))
	draw_arc(center,r,0,TAU,40,Color("ac7948"),1.5,true)
