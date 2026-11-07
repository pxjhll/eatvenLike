extends Control
## The red ↑ shown wherever the coins on hand can buy something right now: a locked spot,
## a machine upgrade, a seat, a hire. It needs no tutorial; it hides again when coins run short.

const COLOR := Color("e5483b")
const RADIUS := 17.0


static func draw_badge(canvas: CanvasItem, center: Vector2, radius := RADIUS) -> void:
	var k := radius / RADIUS
	canvas.draw_circle(center + Vector2(0, 1.1) * k, radius + 1.4, Color("63321d"), true, -1.0, true)
	canvas.draw_circle(center, radius, COLOR, true, -1.0, true)
	canvas.draw_arc(center, radius - 1.4, PI * 1.08, PI * 1.92, 20, Color("ff9475"), 1.5 * k, true)
	canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(0, -11) * k, center + Vector2(9, -1) * k, center + Vector2(-9, -1) * k]), Color.WHITE)
	canvas.draw_rect(Rect2(center + Vector2(-4, -2) * k, Vector2(8, 11) * k), Color.WHITE)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(RADIUS, RADIUS) * 2 + Vector2(4, 4)
	visible = false


## Place the badge so its centre sits on `point` (in the parent's coordinates).
func center_on(point: Vector2) -> void:
	position = point - size / 2.0


func _draw() -> void:
	draw_badge(self, size / 2.0)
